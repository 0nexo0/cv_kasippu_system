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

### Added
- **Settings panel: change the config files in game (`/kasippuadmin`).** Every config file except `text.lua` and
  `webhooks.lua`, file by file, with each setting's own comment from the file as its hint. Covers on / off,
  numbers (control hashes shown as `0x...`), text, `vector2/3/4` and lists of values. Search within a file. Staged
  changes are saved together with **Save changes**. A setting changed in game shows its file value and a ↺ button
  to go back to it.
  - **Who:** only the players in the new server-only `config/admin_panel.lua` (`Config.AdminPanel.SteamIds`: steam
    hex or steam64, `CharIds`: VORP character ids). No ACE or VORP group opens it, and the panel can't edit that list.
    `Config.Admin`, `Config.TreeAdmin` and every `Ace` / `Groups` setting are hidden from the panel too.
  - **Saved** in the new `gsc_kasippu_config` table (created by `database/cv_kasippu_tables.sql`, one row per
    changed setting) and laid over the config files at every start. The files themselves are never written. Delete a
    row (or press ↺) to go back to the file's value. `database/config_overrides.json` is a copy the server reads at
    start, before the DB is up.
  - **Live:** a save is applied on the server and sent to every player at once (`gsc_kassippu:client:cfgSync`).
    Players who join later get it from `GlobalState` when the script starts. Config tables are changed in place, so
    scripts that keep a reference to one see the new value. Settings only read at start (item names, prompt keys, the
    menu command, tree stream distances, ...) are marked **RESTART** in the panel.
  - **Checks (server):** every event checks the access list again. A value must have the same kind as the file's
    value (whole numbers stay whole, text up to 256 characters, lists up to 200 items). Only settings that exist in
    the file can be changed; nothing can be added or set to nil. All changes are checked before any is saved. Each
    save goes to the `admin` log / webhook with who changed what.
  - **Lists of entries** (saloons, traveller camps, law tip-off towns, crate activities / hazards / tiers / climate
    bands, incidents, notify icons, recipe ingredients / strengths, tree search rewards, tree zones and their
    reinforce spawns, ...) can have entries **added, copied, moved and removed**, not only edited. A list is saved
    whole. Every entry is checked against the shape of the file's own entries: the same keys, the same kinds
    (nested lists and coordinates too), at least 1 and at most 100 entries. A new entry starts as a copy of the
    last one. `Market.Saloons` and `Market.Traveller.Camps` are marked RESTART (the client keeps its buyer list).
  - **New recipes from the panel.** `Config.Recipes` and `Config.Market.Base` (the price per recipe) are
    *named entries*: a new one is added as a copy of an existing one under a new name (letters, numbers, `_`, 32
    max), then changed. Each is saved whole and checked against the shape of the file's own recipes (ingredients,
    strengths, rewards, aged items...). Recipes the config file has can be changed but not removed. A recipe a still
    is brewing right now can't be removed, and neither can a reset that would remove it (new
    `GSC.Distillery.RecipeInUse`). `recipeItem` is shown again inside a recipe and is marked RESTART (the recipe card
    is made usable at start). A new recipe's bottle items must already exist in vorp_inventory. Without its own
    `Market.Base` price, it sells at `Market.DefaultBase`.
  - **Hidden from the panel by default** (`Config.AdminPanel.Hide` / `HideNamed` in `config/admin_panel.lua`):
    item names, control keys, command names, dev / log settings, and game names typed as text (models, props, anim
    dicts, scenarios, bones, sprites, sounds, icons). That's 285 of 1,096 settings; 811 stay. These are not shown,
    a save that touches one is refused, and a saved DB row for a setting hidden later is ignored (the file's value
    is used, and the console says how many were skipped). `HideNamed` only hides text settings, so numbers and
    on / off with those words stay (`CollectAnimSeconds`, `ShowBottleProps`), and it never applies inside a list of
    entries (a reward or an ingredient needs its item name). Remove a line from `Hide` to bring those settings
    back. A file with nothing left (items.lua, animations.lua, tree_locations.lua) drops out of the file list.
  - New: `features/admin_panel/{shared/config_live.lua, server/admin_panel.lua, client/admin_panel.lua}`,
    `Config.Text.AdminPanel`, and the `#cfg-panel` NUI (`nui/index.html`, `style.css`, `script.js`). The UI guard
    knows about the panel and closes it on death or lost focus.
- **Carrying the still, water barrel, log rack and aging crate while placing them.** While a placement ghost is out,
  the player holds a prop in a carry pose (`mech_carry_box` / `idle`, flag 31, so they can still walk and turn): a
  small barrel (`p_barrel010x`) for the still and the water barrel, a small wooden crate (`p_chair_crate02x`) for the
  log rack, a bottle crate (`p_bottlecrate_mil`) for the aging crate. Placing or cancelling drops the pose and the
  prop; the server's existing `place_still` / `place_water` / `place_rack` / `place_crate` put-down then plays. The
  pose comes back if something interrupts it, and is cleared on resource stop.
  New `Config.AnimConf.PlacementCarry.still / .water / .rack / .crate` (dict, anim, flag, prop
  model/bone/offset/rotation); setting a kind to `nil` turns its carry pose off, `prop = nil` keeps empty hands.
  - `stations.lua` and `crates.lua` use the same helper through `GSC.Barrels.StartCarry / KeepCarry / StopCarry`.

### Changed
- **The Log Rack is stacked one log at a time, like filling the Water Barrel.** Each hold of the Stack prompt (or
  the F2 wedge) plays `Config.AnimConf.Actions.stack` (2.5 s). Only when it runs to the end does the server take
  **one** log (the first the player carries, in `Config.Stations.LogRack.BurnOrder`) and put it on the rack. Before,
  it took every log in the satchel at once. Walking off (more than 1 m), falling, or the scenario breaking cancels it,
  and the log stays in the satchel.
  - Server: `gsc_kassippu:server:stockStation` now only starts the job and sends the new
    `gsc_kassippu:client:stationStack`. The client answers with the new `gsc_kassippu:server:stockStationDone`, which
    checks the time, distance, crew right, room and log count again before taking anything. The water barrel and the
    rack share one job per player, so a player can't pour and stack at the same time.
  - Text: `Stations.Stack` "Stack Logs" → "Stack a Log". New `Stations.StackedOne` (log name, now, capacity) and
    `Stations.StackCancelled`. Without `StackedOne` (an older `config/text.lua`), the old `Stacked` line is used.

### Removed
- Unused items in `config/items.lua`: `RecipeArrack`, `SpiritPerfect`, `SpiritGood`, `SpiritNormal`,
  and the commented-out Arrack recipe in `config/recipes.lua`.
- **`coconut_water` item** (`Config.Items.CoconutWater`, `Config.CoconutBucketConf.CoconutWaterItem`) and
  using a `filled_pot` to pour it out. Remove `coconut_water` from the `items` table on the server;
  any `coconut_water` players still carry no longer counts at the still.

### Fixed
- **The Water Barrel / Log Rack F2 menu (and key prompts) show up as soon as you walk up.** Before, you often had to
  shuffle around them first. Two causes:
  - The "at a station" check measured in 3D from the ped (about 1 m above the ground) to the station's ground point,
    so 1.5 m only reached about 1.1 m across the ground. A freshly placed station sits 1.5 m in front of you, so you
    started outside it. It now measures across the ground (with up to 2.5 m height difference allowed), and
    `Config.Stations.InteractRadius` defaults to 2.0 (was 1.5). The "closer to the station than to the still" choice
    for the key prompts is measured across the ground too. The server's own range check is unchanged and still covers it.
  - The prop / range sweep could sleep 3 s when no station was near. It now also runs as soon as the server sends
    station data (a new, moved or removed station), and the "which one am I at" check runs every 0.5 s with none in
    range (was 1 s).
- **Coconut tree roots are hidden.** New `Config.TreeClimbConf.SinkDepth` (2.0): the tree model is pushed this many
  metres into the ground on spawn. The climb now starts `SinkDepth` higher up the trunk and still ends at the crown
  (which sank with it), so the rung count is the same and each rung is a little shorter. `SinkDepth = 0` gives the
  old placement.
  - The climb prompt (`Trees.GetNearest`) now uses the flat distance to the trunk, and accepts the player up to
    `SinkDepth + 3` m above or below the tree's stored z, so it shows whether the z is at ground level or lowered.
    The "walked off before climbing" check is flat too. The server's reach checks are already flat.
- **Climber sits tighter on the trunk.** `Config.TreeClimbConf.ClimbForwardOffset` 0.45 → 0.32, and a new
  `ClimbSideOffset` (default 0.0) moves him left / right of the trunk centre. Both are used for the attach, the
  pin other players see, and the climb camera. With `Config.DebugTreeCommands = true`,
  `/climboffset <forward> [side]` changes them live while climbing (console prints the values to copy into config).
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
- **Pol Raa could not be previewed or mixed (`mash.lua:504: bad argument #2 to 'insert' (position out of
  bounds)`).** The mix slip put the freshness line at position 4, but a recipe with no fruit and no spirit line
  (Pol Raa, now that its sap comes from the pot) only has 2 lines, so the insert threw inside the
  `getCustomInventoryItems` callback and the recipe book / mix never answered. The line now goes at position 4 or the
  end, whichever comes first.
- **Coconut trees stand straight on slopes.** `PlaceObjectOnGroundProperly` also tilted the tree to the ground's
  slope, but only on its first spawn (later spawns reused the cached ground height and stood upright). The tree is
  now set upright (`SetEntityRotation` 0, 0, heading) every spawn, so the climber, the pot and the camera, which all
  follow the tree's axes, are straight too.
- **Database tables file is back: `database/cv_kasippu_tables.sql`.** The resource ran `database/schema.sql` on
  start, but that file was missing from the build, so a new server got no tables. The new file creates only the
  5 tables the code uses (`gsc_kasippu_trees`, `gsc_kassippu_barrels`, `gsc_kassippu_crates`, `gsc_kassippu_trust`,
  `gsc_kassippu_seen`), with only the columns it reads or writes. `gsc_kasippu_trees` now has `fill_percent` /
  `last_update` in the `CREATE`. Unused `owner_name`, `created_at`, `last_used` and the `id` key on barrels are
  gone from new installs (existing tables are not changed). The MariaDB `ADD COLUMN IF NOT EXISTS` upgrade lines are
  kept for older databases. The tree loader now waits for this file to run first, so trees load on the very first
  start of a fresh database.
- **Tree table renamed `gsc_climb_trees` → `gsc_kasippu_trees`.** Every query uses the new name. On start, before
  the tables file runs, an existing `gsc_climb_trees` is renamed in place (`RENAME TABLE`), so trees and their pot
  fill carry over. If both tables already exist, the new one is used and a yellow note says to drop the old one by
  hand.
- **Some coconut trees stuck on "checking bucket..." and could not be collected.** The client rebuilt each
  tree's uid from its x/y/z instead of using the uid the server sent. When the stored coords round differently
  from the uid (e.g. uid `..._-1062.80_..._55.44`, x `-1062.79`, z `55.43`), the client asked about a tree the
  server did not know, and the server silently ignored the bucket sync, collect and delete. The client now keeps
  the database uid (`features/trees/client/trees.lua`).
- **Garbled text under prompt groups (e.g. "er Sap" under the coconut tree prompts).** Group labels were built
  once with `VarString` and reused every frame, but a VarString points into a scratch buffer the game reuses,
  so other text overwrote it. Labels now keep the plain text and build the VarString on the frame it is shown
  (trees, buyers, crew invite, still push game, still stations, barrels, crates).
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

- **A crate's bottle count no longer goes to the whole server.** Every bottle stored, taken or broken in a crate sent
  the new count to all players. It now goes only to players within the crate's `StreamDistance` + 40 m (100 m by
  default), the ones who can see its bottle props. A crate that streams in on a client asks for its current count once
  (new server event `gsc_kassippu:server:crateCountAsk`, at most once per crate every 5 s per player), so a player
  coming from further away never sees an old number of bottles.

- **Security: a mix could be run twice from one stash (empty pots duplicated).** `startMixing` checked for FREEZE but only
  set MIXING after the stash read and `addItem` had yielded, so two requests close together (a cheater firing it twice,
  or two crew at once) both passed and both got the `returnItem` pots. The still is now claimed (`MixClaim`) before
  anything waits, a second request is turned away, and the claim is released on every refusal or once the stage is
  MIXING (it also lapses after 15 s if the stash read never answers).
- **Security: the stash can't be emptied while a mix reads it.** Starting a mix closes the inventory of everyone else
  within 10 m of the still, and the stash refuses to open while a mix is claimed (new text
  `Config.Text.StashBusyMixing`). Before, a crew member with the stash open could take the full pots out after they
  were counted, and the mix still went ahead.
- **`requestZoneRoster` throttled** to once a second per player (it only answers the sender, so this stops spam).
- **A trespasser always hears their own alarm.** If the yard is big enough that the player who set it off is outside
  `GSC.Roster.SendNear`'s range, they now get `AlertGuards` directly. `Roster.SendNear` now returns the set of
  players it sent to.
- **Still ambience keeps its soundset loaded while you move between stills**, and only releases it when no lit still
  is in range. Before, it released and reloaded it every time the nearest still changed.

### Removed
- **Radial menu icons trimmed: `nui/vendor/radialmenu.js` 1.1 MB → 66 KB.** Its `icos` table carried every Font
  Awesome Free icon (1,385); it now keeps the 71 whose names appear in the resource's Lua or `nui/script.js`
  (every wedge icon, the `circle-question` fallback, and a few harmless extra matches). The page now has far less JS
  to parse when it loads. To use a new icon, copy its line from the original ez_radialmenu `RadialMenu.js`
  (see the file header). An unknown name still shows the question-mark icon, as before.
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
