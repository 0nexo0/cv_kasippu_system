-- cv_kasippu_system tables.
-- Runs automatically on every resource start (features/still/server/distillery.lua),
-- so every statement must be safe to run again.
-- The loader strips comments and splits on semicolons: never put one inside a string or a default.

-- ---------------------------------------------------------------------------
-- Climbable coconut trees and each tree's sap pot (features/trees/server/tree_store.lua)
--   fill_percent : how full the tree's pot is (0-100, 1% = Config.CoconutBucketConf.MlPerPercent ml)
--   last_update  : unix time the fill was last worked out, or when the regrow cooldown ends
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `gsc_kasippu_trees` (
  `uid`          VARCHAR(100) NOT NULL,
  `x`            FLOAT        NOT NULL,
  `y`            FLOAT        NOT NULL,
  `z`            FLOAT        NOT NULL,
  `heading`      FLOAT        NOT NULL DEFAULT 0,
  `fill_percent` DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  `last_update`  INT(11)      NOT NULL DEFAULT 0,
  PRIMARY KEY (`uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Stills (features/still/server/distillery.lua)
--   crew / ferment / mix / fire / upgrades / stations are JSON, NULL when empty.
--   aging_started / cask_score / aged_tier are no longer read, but every save still writes them.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `gsc_kassippu_barrels` (
  `uid`               VARCHAR(100) NOT NULL,
  `owner`             VARCHAR(100) DEFAULT NULL,
  `coords`            LONGTEXT     NOT NULL,
  `heading`           FLOAT        NOT NULL DEFAULT 0,
  `stage`             VARCHAR(50)  NOT NULL DEFAULT 'IDLE',
  `stage_deadline`    INT(11)      NOT NULL DEFAULT 0,
  `heat`              DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  `fuel`              TINYINT(3)   NOT NULL DEFAULT 0,
  `progress`          TINYINT(3)   NOT NULL DEFAULT 0,
  `recipe`            VARCHAR(50)  DEFAULT NULL,
  `quality`           VARCHAR(20)  DEFAULT NULL,
  `remaining_bottles` TINYINT(3)   DEFAULT 0,
  `usage_count`       INT(11)      NOT NULL DEFAULT 0,
  `condition_pct`     DECIMAL(5,2) NOT NULL DEFAULT 100.00,
  `residue`           DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  `crew`              LONGTEXT     DEFAULT NULL,
  `ferment`           LONGTEXT     DEFAULT NULL,
  `mix`               LONGTEXT     DEFAULT NULL,
  `fire`              LONGTEXT     DEFAULT NULL,
  `upgrades`          LONGTEXT     DEFAULT NULL,
  `stations`          LONGTEXT     DEFAULT NULL,
  `aging_started`     INT(11)      NOT NULL DEFAULT 0,
  `cask_score`        DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  `aged_tier`         VARCHAR(20)  DEFAULT NULL,
  PRIMARY KEY (`uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Aging crates (features/crates/server/crates.lua)
--   bottles : JSON array, one entry per bottle
--   climate : JSON { temp, sheltered }, empty for crates older than climate
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `gsc_kassippu_crates` (
  `uid`         VARCHAR(100) NOT NULL,
  `owner`       VARCHAR(100) DEFAULT NULL,
  `coords`      LONGTEXT     NOT NULL,
  `heading`     FLOAT        NOT NULL DEFAULT 0,
  `bottles`     LONGTEXT     DEFAULT NULL,
  `tend_anchor` INT(11)      NOT NULL DEFAULT 0,
  `locked`      TINYINT(1)   NOT NULL DEFAULT 0,
  `climate`     LONGTEXT     DEFAULT NULL,
  `streak`      INT(11)      NOT NULL DEFAULT 0,
  PRIMARY KEY (`uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Buyers' trust in each character (features/market/server/market.lua)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `gsc_kassippu_trust` (
  `charid`  VARCHAR(64) NOT NULL,
  `trust`   INT(11)     NOT NULL DEFAULT 50,
  `sold`    INT(11)     NOT NULL DEFAULT 0,
  `updated` INT(11)     NOT NULL DEFAULT 0,
  PRIMARY KEY (`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- When each character / account was last online (features/common/server/upkeep.lua).
-- Stills and crates of an owner away longer than Config.Upkeep.OwnerAwayDays are removed.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `gsc_kassippu_seen` (
  `owner`     VARCHAR(100) NOT NULL,
  `last_seen` INT(11)      NOT NULL DEFAULT 0,
  PRIMARY KEY (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Upgrades from older versions: adds columns an older table may be missing.
-- Each line does nothing where the column already exists. MariaDB syntax
-- (MySQL 8 has no ADD COLUMN IF NOT EXISTS - run the needed lines by hand there).
-- gsc_kasippu_trees needs nothing here: tree_store.lua adds fill_percent / last_update itself.
-- ---------------------------------------------------------------------------
ALTER TABLE `gsc_kassippu_barrels`
  ADD COLUMN IF NOT EXISTS `heading`        FLOAT        NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `stage_deadline` INT(11)      NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `quality`        VARCHAR(20)  DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `usage_count`    INT(11)      NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `condition_pct`  DECIMAL(5,2) NOT NULL DEFAULT 100.00,
  ADD COLUMN IF NOT EXISTS `residue`        DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS `crew`           LONGTEXT     DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `ferment`        LONGTEXT     DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `mix`            LONGTEXT     DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `fire`           LONGTEXT     DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `upgrades`       LONGTEXT     DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `stations`       LONGTEXT     DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `aging_started`  INT(11)      NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `cask_score`     DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS `aged_tier`      VARCHAR(20)  DEFAULT NULL;

ALTER TABLE `gsc_kassippu_crates`
  ADD COLUMN IF NOT EXISTS `locked`  TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `climate` LONGTEXT   DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `streak`  INT(11)    NOT NULL DEFAULT 0;
