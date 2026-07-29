-- ACLassist v2 — deterministic proposition (runs entirely inside SQLite; no AI, no Azure).
-- Requires analyze.sql to have run first (group_metrics, group_effective_users, contains, user_metrics).
--
-- SAFETY MODEL — the whole point of this file:
--   Every number below is reproducible SQL. Nothing is inferred, guessed, or generated.
--   Actions are split into two tiers so a reviewer can tell them apart at a glance:
--     * access_safe = 1  -> provably NO change to any user's effective access (retire dead grants,
--                           merge groups with an identical grant footprint, drop pass-through nesting).
--     * access_safe = 0  -> a consolidation that may WIDEN access; every such row carries
--                           new_folder_count = exactly how many folders it would newly expose.
--   Nothing is ever applied. This is data for the customer to approve, modify or reject.

-------------------------------------------------------------------------------
-- 1. Grant footprint atoms — what each group actually confers on which folder.
-------------------------------------------------------------------------------
DROP TABLE IF EXISTS group_grants;
CREATE TABLE group_grants AS
SELECT DISTINCT
  a.principal_id AS group_id,
  a.folder_path,
  a.scope,
  a.permissions,
  CASE
    WHEN instr(a.permissions, 'w') > 0 THEN 'Contributor'
    WHEN instr(a.permissions, 'r') > 0 THEN 'Reader'
    ELSE 'Traverse'
  END AS access_level,
  COALESCE(f.level1, '/') AS base_dir
FROM aces a
LEFT JOIN folders f ON f.path = a.folder_path
WHERE a.principal_type = 'group' AND a.is_named = 1;
CREATE INDEX ix_gg_group ON group_grants(group_id);
CREATE INDEX ix_gg_scope ON group_grants(base_dir, access_level);

-- Canonical footprint per group: two groups with the same footprint are functionally interchangeable.
DROP TABLE IF EXISTS group_footprints;
CREATE TABLE group_footprints AS
SELECT
  group_id,
  COUNT(*) AS grant_count,
  group_concat(folder_path || '|' || scope || '|' || permissions, char(10)
               ORDER BY folder_path, scope, permissions) AS footprint
FROM group_grants
GROUP BY group_id;
CREATE INDEX ix_gf_fp ON group_footprints(footprint);

-------------------------------------------------------------------------------
-- 2. LEVER: merge duplicate groups (identical footprint -> access-neutral).
-------------------------------------------------------------------------------
DROP TABLE IF EXISTS duplicate_survivors;
CREATE TABLE duplicate_survivors AS
SELECT
  c.footprint,
  c.group_count,
  (SELECT gf.group_id
     FROM group_footprints gf
     JOIN group_metrics gm ON gm.group_id = gf.group_id
    WHERE gf.footprint = c.footprint
    ORDER BY gm.effective_user_count DESC, gf.group_id ASC
    LIMIT 1) AS survivor_group_id
FROM (SELECT footprint, COUNT(*) AS group_count
        FROM group_footprints GROUP BY footprint HAVING COUNT(*) > 1) c;
CREATE INDEX ix_ds_fp ON duplicate_survivors(footprint);

-------------------------------------------------------------------------------
-- 3. LEVER: flatten pass-through nesting.
--    A group with no ACE, no direct users, that both has a parent and has children, only forwards
--    membership. Re-pointing its edges to its parent leaves every user's effective access identical.
-------------------------------------------------------------------------------
DROP TABLE IF EXISTS flatten_candidates;
CREATE TABLE flatten_candidates AS
SELECT gm.group_id
FROM group_metrics gm
WHERE gm.on_ace = 0
  AND NOT EXISTS (SELECT 1 FROM group_direct_users du WHERE du.group_id = gm.group_id)
  AND EXISTS (SELECT 1 FROM contains c1 WHERE c1.parent = gm.group_id)
  AND EXISTS (SELECT 1 FROM contains c2 WHERE c2.child  = gm.group_id);
CREATE INDEX ix_fc_group ON flatten_candidates(group_id);

-------------------------------------------------------------------------------
-- 4. LEVER: RBAC-style role consolidation.
--    A role replaces the active groups granting the same access level within one base directory.
--    Its scope is the DEEPEST folder that is an ancestor-or-self of EVERY folder those groups grant on,
--    so the proposal widens access as little as the data allows — often not at all. Prefix tests use
--    substr(), not LIKE, so folder names containing % or _ cannot produce a false match.
-------------------------------------------------------------------------------
DROP TABLE IF EXISTS active_grants;
CREATE TABLE active_grants AS
SELECT gg.*
FROM group_grants gg
JOIN group_metrics gm ON gm.group_id = gg.group_id
WHERE gm.status = 'active';
CREATE INDEX ix_ag_scope ON active_grants(base_dir, access_level);

DROP TABLE IF EXISTS role_keys;
CREATE TABLE role_keys AS SELECT DISTINCT base_dir, access_level FROM active_grants;

-- Deepest common ancestor folder per role.
DROP TABLE IF EXISTS role_scopes;
CREATE TABLE role_scopes AS
SELECT
  k.base_dir,
  k.access_level,
  COALESCE((
    SELECT f.path
      FROM folders f
     WHERE NOT EXISTS (
             SELECT 1 FROM active_grants ag
              WHERE ag.base_dir = k.base_dir
                AND ag.access_level = k.access_level
                AND NOT (f.path = '/'
                         OR ag.folder_path = f.path
                         OR substr(ag.folder_path, 1, LENGTH(f.path) + 1) = f.path || '/')
           )
     ORDER BY LENGTH(f.path) DESC, f.path ASC
     LIMIT 1), '/') AS scope_path
FROM role_keys k;

-- How many folders that scope actually exposes (the widening denominator).
DROP TABLE IF EXISTS scope_sizes;
CREATE TABLE scope_sizes AS
SELECT
  rs.base_dir, rs.access_level, rs.scope_path,
  (SELECT COUNT(*) FROM folders f
    WHERE rs.scope_path = '/'
       OR f.path = rs.scope_path
       OR substr(f.path, 1, LENGTH(rs.scope_path) + 1) = rs.scope_path || '/') AS scope_folder_count
FROM role_scopes rs;

-- Distinct users who would land in each proposed role (union of the replaced groups' effective users).
DROP TABLE IF EXISTS role_users;
CREATE TABLE role_users AS
SELECT DISTINCT ag.base_dir, ag.access_level, eu.user_id
FROM active_grants ag
JOIN group_effective_users eu ON eu.group_id = ag.group_id;

DROP TABLE IF EXISTS proposed_roles;
CREATE TABLE proposed_roles AS
SELECT
  'ROLE_' || replace(a.base_dir, ' ', '') || '_' || a.access_level      AS role_id,
  a.base_dir,
  a.access_level,
  CASE a.access_level
    WHEN 'Contributor' THEN 'Storage Blob Data Contributor'
    ELSE 'Storage Blob Data Reader'
  END                                                                    AS azure_role,
  s.scope_path                                                           AS folder_scope,
  a.replaces_group_count,
  COALESCE(u.member_user_count, 0)                                       AS member_user_count,
  a.covered_folder_count,
  s.scope_folder_count,
  MAX(s.scope_folder_count - a.covered_folder_count, 0)                  AS new_folder_count,
  CASE WHEN s.scope_folder_count > a.covered_folder_count THEN 0 ELSE 1 END AS access_safe,
  a.base_dir || ' — ' || a.access_level                                  AS display_name,
  'Replaces ' || a.replaces_group_count || ' group(s) granting ' || a.access_level ||
  ' across ' || a.covered_folder_count || ' folder(s) under ' || s.scope_path || '.' AS rationale,
  CASE WHEN s.scope_folder_count > a.covered_folder_count THEN 'review' ELSE 'high' END AS confidence,
  'deterministic'                                                        AS named_by,
  ''                                                                     AS decision
FROM (
  SELECT base_dir, access_level,
         COUNT(DISTINCT group_id)    AS replaces_group_count,
         COUNT(DISTINCT folder_path) AS covered_folder_count
  FROM active_grants
  GROUP BY base_dir, access_level
) a
JOIN scope_sizes s ON s.base_dir = a.base_dir AND s.access_level = a.access_level
LEFT JOIN (SELECT base_dir, access_level, COUNT(*) AS member_user_count
             FROM role_users GROUP BY base_dir, access_level) u
       ON u.base_dir = a.base_dir AND u.access_level = a.access_level;

-------------------------------------------------------------------------------
-- 5. Per-group disposition. First matching rule wins (most conservative first).
-------------------------------------------------------------------------------
DROP TABLE IF EXISTS proposed_group_actions;
CREATE TABLE proposed_group_actions AS
SELECT
  gm.group_id,
  gm.display_name,
  gm.role   AS observed_role,
  gm.status,
  gm.member_count,
  gm.effective_user_count,
  CASE
    WHEN gm.status = 'unused'  THEN 'retire_unused'
    WHEN gm.status = 'dormant' THEN 'retire_dormant'
    WHEN ds.survivor_group_id IS NOT NULL AND ds.survivor_group_id <> gm.group_id THEN 'merge_duplicate'
    WHEN fc.group_id IS NOT NULL THEN 'flatten_nesting'
    WHEN EXISTS (SELECT 1 FROM active_grants ag WHERE ag.group_id = gm.group_id) THEN 'map_to_role'
    ELSE 'keep'
  END AS action,
  CASE
    WHEN gm.status IN ('unused', 'dormant') THEN ''
    WHEN ds.survivor_group_id IS NOT NULL AND ds.survivor_group_id <> gm.group_id THEN ds.survivor_group_id
    WHEN fc.group_id IS NOT NULL THEN ''
    ELSE COALESCE((SELECT 'ROLE_' || replace(ag.base_dir, ' ', '') || '_' || ag.access_level
                     FROM active_grants ag WHERE ag.group_id = gm.group_id
                    ORDER BY ag.base_dir, ag.access_level LIMIT 1), '')
  END AS target,
  CASE
    WHEN gm.status = 'unused'  THEN 'Not on any ACL and has no members - grants nothing to anyone.'
    WHEN gm.status = 'dormant' THEN 'On a folder ACL but no user is an effective member - a dead grant.'
    WHEN ds.survivor_group_id IS NOT NULL AND ds.survivor_group_id <> gm.group_id
      THEN 'Grant footprint is identical to the surviving group - functionally a duplicate.'
    WHEN fc.group_id IS NOT NULL
      THEN 'Pass-through only: no ACL, no direct users - it just forwards membership.'
    WHEN EXISTS (SELECT 1 FROM active_grants ag WHERE ag.group_id = gm.group_id)
      THEN 'Its grants are covered by the proposed role for this scope and access level.'
    ELSE 'No change proposed - it carries no folder grants of its own.'
  END AS reason,
  -- 1 = provably no change to anyone's effective access.
  CASE
    WHEN gm.status IN ('unused', 'dormant') THEN 1
    WHEN ds.survivor_group_id IS NOT NULL AND ds.survivor_group_id <> gm.group_id THEN 1
    WHEN fc.group_id IS NOT NULL THEN 1
    WHEN EXISTS (SELECT 1 FROM active_grants ag WHERE ag.group_id = gm.group_id) THEN 0
    ELSE 1
  END AS access_safe,
  '' AS decision
FROM group_metrics gm
LEFT JOIN group_footprints  gf ON gf.group_id = gm.group_id
LEFT JOIN duplicate_survivors ds ON ds.footprint = gf.footprint
LEFT JOIN flatten_candidates fc ON fc.group_id = gm.group_id;
CREATE INDEX ix_pga_group  ON proposed_group_actions(group_id);
CREATE INDEX ix_pga_action ON proposed_group_actions(action);

-------------------------------------------------------------------------------
-- 6. LEVER: flag users carrying too many groups (the metric the customer cares about).
-------------------------------------------------------------------------------
DROP TABLE IF EXISTS proposed_user_flags;
CREATE TABLE proposed_user_flags AS
SELECT
  um.user_id, um.upn, um.display_name, um.job_title,
  um.direct_group_count, um.effective_group_count,
  (SELECT CAST(value AS INTEGER) FROM proposal_config WHERE key = 'overMembershipThreshold') AS threshold,
  CASE WHEN um.effective_group_count >=
            (SELECT CAST(value AS INTEGER) FROM proposal_config WHERE key = 'overMembershipThreshold')
       THEN 1 ELSE 0 END AS over_threshold
FROM user_metrics um;
CREATE INDEX ix_puf_user ON proposed_user_flags(user_id);

-------------------------------------------------------------------------------
-- 7. Headline summary — two honest figures: access-safe reduction, and full consolidation.
-------------------------------------------------------------------------------
DROP TABLE IF EXISTS proposal_summary;
CREATE TABLE proposal_summary AS
WITH c AS (
  SELECT
    (SELECT COUNT(*) FROM groups) AS current_groups,
    (SELECT COUNT(*) FROM proposed_roles) AS proposed_role_count,
    (SELECT COUNT(*) FROM proposed_group_actions WHERE action = 'retire_dormant')  AS retire_dormant,
    (SELECT COUNT(*) FROM proposed_group_actions WHERE action = 'retire_unused')   AS retire_unused,
    (SELECT COUNT(*) FROM proposed_group_actions WHERE action = 'merge_duplicate') AS merge_duplicate,
    (SELECT COUNT(*) FROM proposed_group_actions WHERE action = 'flatten_nesting') AS flatten_nesting,
    (SELECT COUNT(*) FROM proposed_group_actions WHERE action = 'map_to_role')     AS map_to_role,
    (SELECT COUNT(*) FROM proposed_group_actions WHERE action = 'keep')            AS keep_group,
    (SELECT COUNT(*) FROM proposed_user_flags WHERE over_threshold = 1)            AS users_over_threshold,
    (SELECT COUNT(*) FROM proposed_roles WHERE access_safe = 0)                    AS roles_needing_review
)
SELECT
  (SELECT value FROM meta WHERE key = 'scanId')            AS scan_id,
  (SELECT value FROM proposal_config WHERE key = 'generatedUtc') AS generated_utc,
  c.current_groups, c.proposed_role_count,
  c.retire_dormant, c.retire_unused, c.merge_duplicate, c.flatten_nesting, c.map_to_role, c.keep_group,
  c.users_over_threshold, c.roles_needing_review,
  (c.retire_dormant + c.retire_unused + c.merge_duplicate + c.flatten_nesting) AS safe_removable,
  c.current_groups - (c.retire_dormant + c.retire_unused + c.merge_duplicate + c.flatten_nesting) AS groups_after_safe,
  c.proposed_role_count + c.keep_group AS groups_after_full,
  ROUND(100.0 * (c.retire_dormant + c.retire_unused + c.merge_duplicate + c.flatten_nesting)
        / MAX(c.current_groups, 1), 1) AS safe_reduction_pct,
  ROUND(100.0 * (c.current_groups - (c.proposed_role_count + c.keep_group))
        / MAX(c.current_groups, 1), 1) AS full_reduction_pct
FROM c;
