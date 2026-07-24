-- ACLassist v2 — deterministic analysis (runs entirely inside SQLite; no AI, no Azure).
-- Computes membership metrics via transitive closure of the containment graph, plus the behavioural
-- role/status, and appends one history snapshot. All numbers here are reproducible ground truth.

-- Indexes on the freshly imported raw tables (created after .import for load speed).
CREATE INDEX IF NOT EXISTS ix_mem_group  ON memberships(group_id);
CREATE INDEX IF NOT EXISTS ix_mem_member ON memberships(member_id, member_type);
CREATE INDEX IF NOT EXISTS ix_nest_parent ON nesting(parent_group_id);
CREATE INDEX IF NOT EXISTS ix_nest_child  ON nesting(child_group_id);
CREATE INDEX IF NOT EXISTS ix_aces_prin   ON aces(principal_id, principal_type);
CREATE INDEX IF NOT EXISTS ix_groups_id   ON groups(id);
CREATE INDEX IF NOT EXISTS ix_users_id    ON users(id);

-- Unified containment edges: parent CONTAINS child (child is a member of parent).
DROP TABLE IF EXISTS contains;
CREATE TABLE contains AS
  SELECT parent_group_id AS parent, child_group_id AS child FROM nesting
  UNION
  SELECT group_id AS parent, member_id AS child FROM memberships WHERE member_type = 'group';
CREATE INDEX ix_contains_parent ON contains(parent);
CREATE INDEX ix_contains_child  ON contains(child);

-- Direct user members per group.
DROP TABLE IF EXISTS group_direct_users;
CREATE TABLE group_direct_users AS
  SELECT group_id, member_id AS user_id FROM memberships WHERE member_type = 'user';
CREATE INDEX ix_gdu_group ON group_direct_users(group_id);

-- Transitive descendants: (root -> node) for every group reachable from root via containment.
-- UNION (not UNION ALL) makes it cycle-safe and de-duplicated.
DROP TABLE IF EXISTS descendants;
CREATE TABLE descendants AS
  WITH RECURSIVE d(root, node) AS (
    SELECT parent, child FROM contains
    UNION
    SELECT d.root, c.child FROM d JOIN contains c ON c.parent = d.node
  )
  SELECT DISTINCT root, node FROM d;
CREATE INDEX ix_desc_root ON descendants(root);
CREATE INDEX ix_desc_node ON descendants(node);

-- Effective users of a group = its direct users + direct users of all descendant groups.
DROP TABLE IF EXISTS group_effective_users;
CREATE TABLE group_effective_users AS
  SELECT group_id, user_id FROM group_direct_users
  UNION
  SELECT d.root AS group_id, gdu.user_id
  FROM descendants d JOIN group_direct_users gdu ON gdu.group_id = d.node;
CREATE INDEX ix_geu_group ON group_effective_users(group_id);

-- Per-group metrics + naming-independent behavioural role/status.
DROP TABLE IF EXISTS group_metrics;
CREATE TABLE group_metrics AS
WITH base AS (
  SELECT
    g.id AS group_id, g.display_name, g.kind,
    (SELECT COUNT(*) FROM memberships m WHERE m.group_id = g.id) AS member_count,
    (SELECT COUNT(*) FROM descendants d WHERE d.root = g.id) AS total_nested_groups,
    (SELECT COUNT(DISTINCT eu.user_id) FROM group_effective_users eu WHERE eu.group_id = g.id) AS effective_user_count,
    CASE WHEN EXISTS(SELECT 1 FROM aces a WHERE a.principal_id = g.id AND a.principal_type = 'group') THEN 1 ELSE 0 END AS on_ace,
    CASE WHEN EXISTS(SELECT 1 FROM contains c WHERE c.parent = g.id) THEN 1 ELSE 0 END AS is_parent
  FROM groups g
)
SELECT
  group_id, display_name, kind, member_count, total_nested_groups, effective_user_count, on_ace,
  CASE
    WHEN on_ace = 1 AND (member_count > 0 OR is_parent = 1) THEN 'hybrid'
    WHEN on_ace = 1 THEN 'access'
    WHEN (member_count > 0 OR is_parent = 1) THEN 'role'
    ELSE 'unused'
  END AS role,
  CASE
    WHEN on_ace = 0 AND member_count = 0 AND is_parent = 0 THEN 'unused'
    WHEN on_ace = 1 AND effective_user_count = 0 THEN 'dormant'
    ELSE 'active'
  END AS status
FROM base;
CREATE INDEX ix_gm_group ON group_metrics(group_id);

-- Effective groups per user = direct groups + all ancestors of those groups (the real reach).
DROP TABLE IF EXISTS user_effective_groups;
CREATE TABLE user_effective_groups AS
  SELECT member_id AS user_id, group_id FROM memberships WHERE member_type = 'user'
  UNION
  SELECT m.member_id AS user_id, d.root AS group_id
  FROM memberships m JOIN descendants d ON d.node = m.group_id
  WHERE m.member_type = 'user';
CREATE INDEX ix_ueg_user ON user_effective_groups(user_id);

-- Per-user metrics: direct vs effective (transitive) group counts.
DROP TABLE IF EXISTS user_metrics;
CREATE TABLE user_metrics AS
SELECT
  u.id AS user_id, u.upn, u.display_name, u.job_title, u.account_enabled,
  (SELECT COUNT(*) FROM memberships m WHERE m.member_id = u.id AND m.member_type = 'user') AS direct_group_count,
  (SELECT COUNT(DISTINCT eg.group_id) FROM user_effective_groups eg WHERE eg.user_id = u.id) AS effective_group_count
FROM users u;
CREATE INDEX ix_um_user ON user_metrics(user_id);

-- One history snapshot (scan id/time come from imported meta rows — never string-built into SQL).
INSERT INTO snapshots
SELECT
  (SELECT value FROM meta WHERE key = 'scanId'),
  (SELECT value FROM meta WHERE key = 'generatedUtc'),
  (SELECT COUNT(*) FROM folders),
  (SELECT COUNT(*) FROM aces),
  (SELECT COUNT(*) FROM groups),
  (SELECT COUNT(*) FROM users),
  (SELECT COUNT(*) FROM group_metrics WHERE role IN ('access', 'hybrid')),
  (SELECT COUNT(*) FROM group_metrics WHERE role = 'role'),
  (SELECT COUNT(*) FROM group_metrics WHERE status = 'dormant'),
  (SELECT COUNT(*) FROM group_metrics WHERE status = 'unused'),
  (SELECT COUNT(*) FROM contains),
  (SELECT AVG(direct_group_count) FROM user_metrics),
  (SELECT MAX(direct_group_count) FROM user_metrics),
  (SELECT AVG(effective_group_count) FROM user_metrics),
  (SELECT MAX(effective_group_count) FROM user_metrics);
