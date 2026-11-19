---o[ Settings panel - change these config files in game (/kasippuadmin) ]o---
-- Server only: never sent to players. Nobody can change this file from the panel.
-- No ACE / VORP group is used: ONLY the players listed here can open the panel.
Config.AdminPanel = {
    Enabled = true,
    Command = "kasippuadmin", -- chat command that opens the panel

    ---o[ Who may open it - either list matching lets the player in ]o---
    SteamIds = {              -- steam hex ("steam:110000112345678") or steam64 ("76561198012345678")
        -- "steam:110000112345678",
    },
    CharIds  = {              -- VORP character ids (charIdentifier) - only that one character
        -- 1,
    },

    ---o[ Never shown or changed in the panel - they stay as the config files have them ]o---
    -- A setting and everything under it. "*" = any one key. Remove a line to bring those settings into the panel.
    Hide = {
        -- item names: must match the vorp_inventory items exactly, and are read at start
        "Items", "CrateAging.ItemName", "KasiyaBarrelKitConf.KasiyaBarrelItemName", "SpentMash.Item",
        "Upgrades.*.item",
        -- control keys and commands: read at start
        "InteractKeys", "GiveCommand.Name", "Radial.Command", "Radial.KeyMapping", "UiGuard.ResetCommand",
        -- dev and maintenance
        "DevMode", "VersionCheck", "DebugTreeCommands", "AutoSaveConfigTrees", "Logs",
        -- game names: a typo means an invisible prop or no animation
        "Models", "AnimConf", "StillDressing", "Notify.Icons",
    },
    -- Any TEXT setting whose name (or a group above it) contains one of these words, any case. Numbers and
    -- on / off stay (CollectAnimSeconds, ShowBottleProps...). Not used inside a list of entries (saloons, rewards,
    -- ingredients...): an entry needs every one of its fields.
    HideNamed = { "model", "prop", "dict", "anim", "scenario", "bone", "sprite", "sound", "icon" },
}
