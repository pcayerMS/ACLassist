-- ACLassist v2 — SQLite schema (raw inventory tables + persistent history snapshots).
-- Loaded once per assessment. Raw tables hold the LATEST scan; `snapshots` accumulates across scans.
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

DROP TABLE IF EXISTS folders;
CREATE TABLE folders (
  id               TEXT,
  path             TEXT,
  name             TEXT,
  depth            INTEGER,
  level1           TEXT,
  level2           TEXT,
  level3           TEXT,
  level4           TEXT,
  base_permissions TEXT
);

DROP TABLE IF EXISTS groups;
CREATE TABLE groups (
  id               TEXT,
  display_name     TEXT,
  description      TEXT,
  kind             TEXT,      -- naming-prefix label only (ADLS/PRD/other); NOT the behavioural role
  security_enabled INTEGER,
  mail             TEXT
);

DROP TABLE IF EXISTS users;
CREATE TABLE users (
  id              TEXT,
  upn             TEXT,
  display_name    TEXT,
  job_title       TEXT,
  account_enabled INTEGER
);

DROP TABLE IF EXISTS memberships;
CREATE TABLE memberships (
  group_id    TEXT,
  member_id   TEXT,
  member_type TEXT           -- 'user' | 'group'
);

DROP TABLE IF EXISTS nesting;
CREATE TABLE nesting (
  parent_group_id TEXT,      -- parent CONTAINS child (child is a member of parent)
  child_group_id  TEXT
);

DROP TABLE IF EXISTS aces;
CREATE TABLE aces (
  folder_id      TEXT,
  folder_path    TEXT,
  principal_id   TEXT,
  principal_type TEXT,       -- 'user' | 'group'
  scope          TEXT,       -- 'access' | 'default'
  permissions    TEXT,       -- symbolic, e.g. r-x
  is_named       INTEGER
);

DROP TABLE IF EXISTS rbac;
CREATE TABLE rbac (
  principal_id         TEXT,
  principal_type       TEXT,
  role_definition_name TEXT,
  scope                TEXT
);

DROP TABLE IF EXISTS meta;
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);

-- Persistent, one row per scan run — feeds the future history/trend tab (Tab 3).
CREATE TABLE IF NOT EXISTS snapshots (
  scan_id              TEXT,
  generated_utc        TEXT,
  total_folders        INTEGER,
  total_aces           INTEGER,
  total_groups         INTEGER,
  total_users          INTEGER,
  access_groups        INTEGER,
  role_groups          INTEGER,
  dormant_groups       INTEGER,
  unused_groups        INTEGER,
  total_nested_edges   INTEGER,
  avg_direct_per_user  REAL,
  max_direct_per_user  INTEGER,
  avg_groups_per_user  REAL,
  max_groups_per_user  INTEGER
);
