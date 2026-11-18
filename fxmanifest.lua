fx_version 'cerulean'
games { 'rdr3' }
lua54 'yes'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author 'N3XO'
description 'Kassippu Custom Script'

---oo[ CronicalVerse layout - docs/ARCHITECTURE.md ]oo---

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
dependencies {
    'vorp_core',
    'vorp_inventory',
    'oxmysql',
}

client_scripts {
    'features/common/client/notify.lua',
    'features/common/client/minigame.lua',
    'features/common/client/radial.lua',

    'features/trees/client/trees.lua',      -- GSC.Trees      props + streaming
    'features/trees/client/tree_camera.lua',
    'features/trees/client/climb.lua',
    'features/trees/client/harvest.lua',

    'features/guards/client/zones.lua',     -- GSC.Zones      who is trespassing
    'features/guards/client/guards.lua',    -- GSC.Guards     the men, and their AI

    'features/still/client/barrels.lua',    -- GSC.Barrels    distilling + its UI
    'features/still/client/push_game.lua',
    'features/still/client/stations.lua',
    'features/crew/client/crew.lua',
    'features/crates/client/crates.lua',
    'features/market/client/buyers.lua',
    'features/still/client/tasting.lua',
    'features/common/client/ui_guard.lua',
}

server_scripts {
    'config/webhooks.lua', -- server only: holds the webhook URLs

    'features/common/server/admin.lua',
    'features/common/server/notify.lua',
    'features/common/server/logs.lua',
    'cv_core/server/version.lua',
    'features/trees/server/tree_store.lua', -- GSC.TreeStore  trees + bucket economy
    'features/guards/server/alarm.lua',     -- GSC.Alarm      is this trespass real?
    'features/guards/server/roster.lua',
    'features/still/server/distillery.lua', -- GSC.Distillery barrel state machine
    'features/still/server/stations.lua',
    'features/still/server/mash.lua',
    'features/crew/server/barrel_crew.lua',
    'features/crew/server/barrel_theft.lua',
    'features/law/server/law.lua',
    'features/crates/server/crates.lua',
    'features/market/server/market.lua',
    'features/common/server/upkeep.lua',
    'features/still/server/tasting.lua',
}

files {
    'nui/**',
}

---oo[ Version check - cv_core/server/version.lua, see CHANGELOG.md ]oo---
version '1.6.0'
cv_version_id 'cv_kasippu_system'
