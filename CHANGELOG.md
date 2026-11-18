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
- **Coconut trees fill slower, sized for a ~100-player server.** `FillIntervalMinutes` 1 → 2 and
  `FillPercentPerInterval` 10 → 5, so a pot fills in 40 min instead of 10. `RegrowCooldownSeconds` is now its
  own number, 300 (it was `TreeGrowingTime`, 60, which is also the tree search cooldown). A drained tree takes
  about 45 min to be full again. All 21 trees together now give about 28,000 ml an hour (was about 114,500).
- **A filled pot now reads "Coconut Flower Sap (600ml)"** instead of "Coconut Water (600ml)". The label and
  description come from the new `Config.Text.CoconutPotLabel` / `CoconutPotDescription` (they were hard-coded in
  `mash.lua`). Pots already in satchels keep the old label until they are next topped up or drawn from.
  Every other text players see now says "coconut flower sap" too: the tree prompt, fill HUD, collect / spill /
  pot notes, collect minigame title ("Pour Off The Sap"), the still's "bring Xml" note, the recipe book line, the
  mash slip and the Raa instructions (`config/text.lua`, `config/recipes.lua`). Event and function names
  (`collectCoconutWater`, `Config.Text.Receipt.CoconutWater`, ...) are unchanged.
- **Pol Raa: one full pot of sap is one batch, put in the barrel.** No water any more. The `filled_pot` is
  the recipe's batch ingredient, so the barrel stash takes whole pots (1 to 3). A pot only counts when it holds
  `Config.CoconutBucketConf.PotCapacityMl` (1000ml). A part-filled pot is refused with `MashPotNotFull`
  ("top it up at a tree"). Each pot used comes back as an `empty_pot` to whoever mixes, and the mix waits until
  they have room (`MashNoRoomForReturns`). Sap freshness comes from the pot's `picked` stamp. Each pot counts as
  2 sugar, so a pot alone makes Regular and +1 Brown Sugar per pot makes Strong. `coconutMl` / `coconutSugar`
  are gone from the recipe (the satchel route still works for any recipe that sets them).
  - New ingredient fields, usable on any recipe: `fullMl` (the stack only counts at this ml or more) and
    `returnItem` (handed back per item once mixed).
  - Recipe book: the batch line shows "a full pot (1000ml)", and the sugar line counts the pot's own sugar.
  - A batch poured out or seized while pots are still in the stash loses those pots.
  - Pol Raa now also needs 2 Water and at least 1 Brown Sugar per pot (`amount`). Brown Sugar counts as 1 sugar,
    so per pot 1 makes Light, 2 Regular and 4 Strong. The instructions text says this.
- **"Palm Sap" removed from `Config.Text.TendWashIngredients`.** The tend minigame's fallback tray is now
  Jaggery, Yeast, Coconut Flower Sap, Treacle (still 4, the most the tray shows).

### Removed
- Unused items in `config/items.lua`: `RecipeArrack`, `SpiritPerfect`, `SpiritGood`, `SpiritNormal`,
  and the commented-out Arrack recipe in `config/recipes.lua`.
- **`coconut_water` item** (`Config.Items.CoconutWater`, `Config.CoconutBucketConf.CoconutWaterItem`) and
  using a `filled_pot` to pour it out. Remove `coconut_water` from the `items` table on the server;
  any `coconut_water` players still carry no longer counts at the still.

### Fixed
- Hidden barrel and crate gauges no longer keep a warning animation running behind them (FPS).
- **Pol Raa sold at the $4 fallback price.** `Config.Market.Base` still used the old key `raaa`; it is now
  `pol_raa`, so Raa sells at its $5 base again.
- **Stills, bottles and crates saved under the old recipe key `raaa` work again.** New
  `Config.RecipeAliases = { raaa = "pol_raa" }` (`config/recipes.lua`) and `Shared.RecipeKey()`. They are used where a
  saved key is read back: a still loaded from the database, a fresh or aged bottle, a bottle in a crate, a soured
  bottle at the buyer, and a first-run spirit in the mash. Before, an aged or soured Raa bottle from before the
  rename was refused by every buyer, and a still mid-brew on `raaa` lost its recipe.

- **Guard news no longer goes to the whole server.** Every guard death, respawn and spawn check sent the yard's
  roster to all players, and every alarm went to all players too, even ones nowhere near the yard. Both now go only
  to players within the yard's despawn distance + 100 m (`GSC.Roster.SendNear`, `features/guards/server/roster.lua`).
  A player who leaves drops their copy of the roster (`GSC.Guards.ForgetRoster`) and asks for a fresh one on the way
  back, as they already did on first arrival. Guard AI, detection and ownership are unchanged. The audit found them
  already distributed: each client only senses its own player, the AI only runs on the client that owns the ped,
  raycasts only run while the player is in the yard, and kill and spawn reports are checked by the server.

### Removed
- **Unused NUI files (about 5.2 MB less for every player to download on first join):** `arakku.png`,
  `arakku_text.png`, `book.png`, `boxnew.png`, `kasippu.png`, `recipie_paper.png`, and the fonts
  `WesternBangBang-Regular.woff`, `crock.ttf` and `OldStandard-*` (with its licence). Nothing in the HTML, CSS, JS or
  config pointed at them. The book only uses PT Serif.

### Added
- **`Items/items.sql`**: every item the script uses (27), as one `INSERT IGNORE INTO items` for vorp_inventory.
  Safe to run again; `id` is left to the database. Item pictures are in `Items/Images/`.
- **A lit still now sounds alive between the bubbling.** New `Config.StillAmbience` (`config/still.lua`) plays the
  game's own `Cauldron_Boil` sound (`RPRSN_Sounds`) from the still while its fire burns, in the stages where the
  bubbling `.ogg` is quiet (IDLE, FREEZE, MID_CLIMB, HEAT_PAUSE, FINAL_PUSH, COMPLETED). Only the nearest still
  within `Range` (12 m) plays it. The sound comes from the still prop, so it fades as you walk away, and each
  player hears it only on their own client. A one-shot sound is started again when it ends.
  `Enabled = false` turns it off, and `SoundSet` / `SoundName` take any other game sound.
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
