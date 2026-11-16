fx_version 'cerulean'
games { 'rdr3' }
lua54 'yes'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author 'N3XO'
description 'Kassippu Custom Script'

---oo[ CronicalVerse layout - docs/ARCHITECTURE.md ]oo---
-- cv_core/    the same files in every CV script
-- config/     everything a server owner may edit
-- features/   one folder per feature, each with client/ server/ shared/
-- nui/        the in-game UI
-- database/   schema.sql (auto-run on start) + item rows (import by hand)

shared_scripts {
    'cv_core/shared/module.lua',

    'features/common/shared/helpers.lua',

    'config/main.lua',
    'config/items.lua',

    'config/controls.lua',
    'config/text.lua',
    'config/animations.lua',

    'config/trees.lua',
    'config/tree_locations.lua',
    'config/guards.lua',

    'config/recipes.lua',
    'config/still.lua',
    'config/crew.lua',
    'config/law.lua',
    'config/crates.lua',
    'config/tasting.lua',
    'config/market.lua',
}

ui_page 'nui/index.html'

escrow_ignore {
    'config/*.lua',
}

---oo[ Start after the framework and the database ]oo---
-- Optional minigame providers (syn_minigame, legends-keypress) are left out on purpose:
-- the script's own minigames are used when they are missing.
dependencies {
    'vorp_core',
    'vorp_inventory',
    'oxmysql',
}

-- PolyZone is no longer loaded: barrels, crates, trees and yards all use the script's own
-- distance checks (Shared.InZone / proximity threads), so nothing here calls PolyZone.

client_scripts {
    'features/common/client/notify.lua',    -- GSC.Notify     the script's own top-right notes
    'features/common/client/minigame.lua',  -- GSC.Minigame   the script's own minigames
    'features/common/client/radial.lua',    -- GSC.Radial     the Kasippu radial menu (F6): every action where you stand

    'features/trees/client/trees.lua',      -- GSC.Trees      props + streaming
    'features/trees/client/tree_camera.lua',-- GSC.TreeCamera climb cam + first person
    'features/trees/client/climb.lua',      -- GSC.Climb      up, down, and falling off
    'features/trees/client/harvest.lua',    -- GSC.Harvest    bucket fill + tree search

    'features/guards/client/zones.lua',     -- GSC.Zones      who is trespassing
    'features/guards/client/guards.lua',    -- GSC.Guards     the men, and their AI

    'features/still/client/barrels.lua',    -- GSC.Barrels    distilling + its UI
    'features/still/client/push_game.lua',  -- GSC.PushGame   Hold The Heat: stoke / cool / vent prompts in the final push
    'features/still/client/stations.lua',   -- GSC.Stations   the Water Barrel and Log Rack beside a still
    'features/crew/client/crew.lua',        -- GSC.Crew       answering an invite to someone's still
    'features/crates/client/crates.lua',    -- GSC.Crates     aging crate: bottles laid down to mature
    'features/market/client/buyers.lua',    -- GSC.Buyers     the buyers' NPCs, the Talk prompt, the ledger
    'features/still/client/tasting.lua',    -- GSC.Tasting    tasting cup: pick a bottle, nose + palate, the notes card
    'features/common/client/ui_guard.lua',  -- GSC.UiGuard    no Kasippu screen ever stays stuck (after every screen above)
}

server_scripts {
    'config/webhooks.lua',                  -- (no module)    Config.Webhooks - SERVER ONLY, never in shared_scripts

    'features/common/server/admin.lua',     -- GSC.Admin      who may use the admin commands
    'features/common/server/notify.lua',    -- GSC.Notify     sends a top-right note to one player
    'features/common/server/logs.lua',      -- GSC.Logs       Discord logs for staff (webhook from config/webhooks.lua or a convar)
    'cv_core/server/version.lua',           -- (no module)    version check, same file in every CV script
    'features/trees/server/tree_store.lua', -- GSC.TreeStore  trees + bucket economy
    'features/guards/server/alarm.lua',     -- GSC.Alarm      is this trespass real?
    'features/guards/server/roster.lua',    -- GSC.Roster     who is on duty, authoritative
    'features/still/server/distillery.lua', -- GSC.Distillery barrel state machine
    'features/still/server/stations.lua',   -- GSC.Stations   the Water Barrel and Log Rack: placing, filling, what the push draws
    'features/still/server/mash.lua',       -- GSC.Mash       what is in a barrel: batch, strength, fruit, freshness
    'features/crew/server/barrel_crew.lua', -- GSC.BarrelCrew co-op cooking: invites, crews, who may touch a barrel
    'features/crew/server/barrel_theft.lua',-- GSC.BarrelTheft strangers stealing bottles off a finished batch
    'features/law/server/law.lua',          -- GSC.Law        smoke tip-offs, lookouts, raids
    'features/crates/server/crates.lua',    -- GSC.Crates     aging crates, their bottles and activities
    'features/market/server/market.lua',    -- GSC.Market     buyers: prices, demand, trust, the sale
    'features/common/server/upkeep.lua',    -- GSC.Upkeep     clears the stills and crates of owners gone too long
    'features/still/server/tasting.lua',    -- GSC.Tasting    tasting cup: what a sip reveals (grade, notes, flaws)
}

files {
    'nui/**',
}

version '1.5.0'
gsc_version_id 'gsc_kasippu_system' 
