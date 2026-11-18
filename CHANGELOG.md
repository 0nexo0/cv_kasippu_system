# Changelog — cv_kasippu_system

All notable changes to the Kasippu script.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) · Versioning: [SemVer](https://semver.org/).

## How to release a version

1. Move everything under **[Unreleased]** into a new `## [x.y.z] - YYYY-MM-DD` section.
2. Bump `version` in `fxmanifest.lua` to the same number.
3. Write 3–6 short lines for server owners in `version.json` (same number).
4. Upload the build to keymaster.
5. **Last:** copy `version.json` over **both** `cv_kasippu_system.json` and `gsc_kasippu_system.json` in
   [0nexo0/CronicalVerse-Versions](https://github.com/0nexo0/CronicalVerse-Versions), commit, push.
   (`cv_kasippu_system.json` is what 1.6.0+ reads; `gsc_kasippu_system.json` is what 1.5.x servers still read.)
   Pushing tells every server to update, so only do it once the build is on keymaster.

The server console shows the result on start (`cv_core/server/version.lua`):
up to date (green), outdated with the changelog lines from that JSON (red), or a dev build (yellow, local version newer than the release).

## [Unreleased]

### Changed
- **Code clean-up for release.** Long explanation comments removed; every section keeps one short
  `---o[ Title ]o---` line. Config files keep their one-line setting notes. No setting or behaviour changed.
- **`/removetree` always works for tree admins.** The dev tree commands (`spawntree`, `listtreesdb`,
  `cleartreesdb`, `fixduplicates`) stay behind `Config.DebugTreeCommands`, now **false** by default.

- **Coconut water stays in the pot.** Collecting at a tree now fills the pots you carry: part-filled
  `filled_pot`s are topped up first (fullest first), then `empty_pot`s are filled, each up to the new
  `Config.CoconutBucketConf.PotCapacityMl` (1000). Whatever does not fit stays in the tree's pot and can be
  collected later. The tree's regrow cooldown starts only when its pot is drained. A topped-up pot keeps the
  older `picked` stamp, so mixing in fresh water does not make old water fresh again. The still takes water
  from `filled_pot`s only. A pot drained at the still becomes an `empty_pot` again.
  - Texts: `CoconutCollectedNotify` now shows the ml taken (`%d`), new `CoconutLeftInTreeNotify`,
    and `CoconutPotRequiredNotify` reworded.
  - One collect at a time per player and per tree.

### Removed
- Unused items in `config/items.lua`: `RecipeArrack`, `SpiritPerfect`, `SpiritGood`, `SpiritNormal`,
  and the commented-out Arrack recipe in `config/recipes.lua`.
- **`coconut_water` item** (`Config.Items.CoconutWater`, `Config.CoconutBucketConf.CoconutWaterItem`) and
  using a `filled_pot` to pour it out. Remove `coconut_water` from the `items` table on the server;
  any `coconut_water` players still carry no longer counts at the still.

### Fixed
- Hidden barrel and crate gauges no longer keep a warning animation running behind them (FPS).

### Added
- **Fittings slip beside the still's book.** Opening the book at your still (owner and crew) now shows a slip
  on the right with the Copper coil, Iron hoops and Pressure gauge: what each one does, whether it is fitted,
  and a **Fit** button. Fit takes the part from your satchel. Using the part from the satchel at the still still works.
  - Each upgrade has `order`, `desc` (the text players read) and optional `requires` in `Config.Upgrades.List`.
  - `requires` = a Config section that must be on. The Pressure gauge needs `Config.Pressure.Enabled`,
    the Iron hoops need `Config.BarrelCondition.Enabled`. When it is off, the upgrade is left off the slip and can't be fitted
    (before, the part was taken and did nothing).
  - Slip words: `Config.Text.FittingsBook`. New notes: `UpgradeNoItem`, `UpgradeNotUsed`.

### Changed
- **A still has a set life: at most 2 repairs and 3 batches, then it falls apart.**
  `Config.BarrelCondition.MaxRepairs` (2) and `MaxBatches` (3) in `config/still.lua`; 0 = no limit.
  The repair note shows repairs and batches left. Picking the still up and setting it down again does not reset them.
- **Repairs now take a Barrel Repair Kit (`barrel_repair_kit`), not a spare Kasiya Barrel Kit.**
  A kit has 5 uses (`Config.BarrelCondition.RepairKitUses`); one repair takes 1 (`RepairCost`).
  Uses left are kept in the item's metadata and shown in its description. The kit is removed after its last use.
  **Add the item to your database** (see below) and give players a way to get it (shop, crafting, loot).
  ```sql
  INSERT IGNORE INTO `items` (`item`, `label`, `limit`, `can_remove`, `type`, `usable`, `desc`) VALUES
    ('barrel_repair_kit', 'Barrel Repair Kit', 3, 1, 'item_standard', 0, 'Mends a worn still. Several uses.');
  ```

## [1.6.0] - 2026-11-16

### Added
- **Kasippu radial menu (F6)** — every action available where you stand, in one wheel.
- **Version check, CronicalVerse edition** — `cv_core/server/version.lua` is now the shared
  `versioncheck.lua` from CronicalVerse-Versions.
  - Says so in the console when `version` or `cv_version_id` is missing from `fxmanifest.lua`.
  - This file (`CHANGELOG.md`) and `version.json` (the release notes to publish).

### Changed
- **Resource folder is now `cv_kasippu_system`** (was `gsc_kasippu_system`). Event names are unchanged.
  - `fxmanifest.lua`: `gsc_version_id 'gsc_kasippu_system'` → `cv_version_id 'cv_kasippu_system'`.
  - 1.6.0+ reads `cv_kasippu_system.json`. `gsc_kasippu_system.json` stays for 1.5.x servers.
- **Turning the version check off:** `set cv_versioncheck false` in `server.cfg` (was `gsc_versioncheck`).
  A server that only has `set gsc_versioncheck false` will see the check again; add the `cv_` line too.
  `Config.VersionCheck = false` in `config/main.lua` still works.
- **Placement notes use VORP `NotifyObjective`.** Setting down a still, an aging crate, a Water Barrel or a Log Rack.
  A new placement note always replaces the old one. `Config.Notify.PlacementObjective` (true; false = show them like any other note).

### Fixed
- **Fill Water Barrel could be spammed, and X cancelled the pour but kept the water.**
  The barrel now fills only when the pour animation plays out. Breaking it off (X, moving, ragdoll, death) fills nothing.
- **A new VORP note waited behind the previous action's note.** The old note is now cleared from the game feed first.

## [1.5.1] - 2026-11-10
### Added
- New notify system.
- New minigames.
### Changed
- Improved performance.
### Fixed
- Bug fixes.

## [1.5.0] - 2026-10-26
### Added
- First release as `gsc_kasippu_system`.
