Config = {}

---o[ General ]o---
Config.DevMode = false -- true: debug prints in F8 / server console
Config.LawJob  = "Sheriff" -- the job that counts as the law (dispatches, seizing stills)
Config.VersionCheck = true -- true: on start, the server console says if a newer version is out

---o[ Notifications - the script's own top-right paper notes ]o---
Config.Notify = {
    UseVorp    = true,  -- true:  VORP's game feed (NotifyAdvanced / right tip). The game shows ONE feed note at a
    Style      = "black", -- the script's notes: "black" = a black brush plate
    VorpStyle  = "advanced", -- with UseVorp: "advanced" = VORP NotifyAdvanced (an icon picked from VorpIcons below)
    DefaultMs  = 4000,  -- how long a note stays (ms) when the message gives no time
    MaxMs      = 8000,  -- no note stays longer than this (ms), whatever the message asks for
    MaxVisible = 4,     -- notes on screen at once; the oldest goes first
    Sound      = false, -- true: a soft click with each new note
    ReadingTime = true, -- true: a note stays at least 1.5 s + 45 ms per letter

    ---o[ With UseVorp ]o---
    BatchMs    = 100,   -- notes arriving within this many ms are joined into one
    MaxLines   = 3,     -- at most this many messages in one joined note (the newest win)

    ---o[ Placement notes ]o---
    PlacementObjective = true, -- true: VORP NotifyObjective (the objective line; a new one replaces the old)
    Fuse        = true, -- true: a burning fuse along the bottom shows how long the note stays

    ---o[ The wax seal on each note: picked by words in the message ]o---
    Icons = {
        { icon = "danger", kind = "warning", words = { "explod", "blew", "burst", "ruined", "spoil", "vinegar", "is lost",
            "data lost", "collaps", "critical", "destroy", "apart" } },
        { icon = "law",    words = { "sheriff", "lawman", "the law", "dispatch", "seize", "raid", "tip-off", "marshal" } },
        { icon = "guard",  words = { "guard", "trespass", "restricted", "noise", "back off", "yard" } },
        { icon = "wash",   words = { "wash", "ferment", "mash", "stir", "mix", "yeast", "ingredient", "lump" } },
        { icon = "fire",   words = { "fire", "wood", "smoke", "ember", "burn", "flame", "fuel" } },
        { icon = "tree",   words = { "tree", "coconut", "climb", "rope", "frond", "crown", "banana", "palm", "grip" } },
        { icon = "water",  words = { "water", "rain", "cool", "cold", "condenser", "bucket", "tarp" } },
        { icon = "crate",  words = { "crate", "aging", "cellar", "cork", "lock" } },
        { icon = "bottle", words = { "bottle", "batch", "spirit", "kasippu", "kassippu", "arrack", "brew", "distil", "jar", "proof" } },
        { icon = "crew",   words = { "crew", "invit", "helper", "join", "cook with" } },
        { icon = "still",  words = { "barrel", "still", "stave", "scrub", "repair", "pressure", "vent", "heat" } },
    },

    ---o[ VORP NotifyAdvanced ]o---
    VorpIcons = {
        danger = { dict = "menu_textures",   icon = "menu_icon_alert",          color = "COLOR_RED" },
        law    = { dict = "inventory_items", icon = "provision_sheriff_star",   color = "COLOR_WHITE" },
        guard  = { dict = "inventory_items", icon = "weapon_shotgun_doublebarrel", color = "COLOR_WHITE" },
        wash   = { dict = "inventory_items", icon = "kit_pouch_ingredients",    color = "COLOR_WHITE" },
        fire   = { dict = "blips",           icon = "blip_campfire",            color = "COLOR_WHITE" },
        tree   = { dict = "blips",           icon = "blip_plant",               color = "COLOR_WHITE" },
        water  = { dict = "blips",           icon = "blip_mg_fishing",          color = "COLOR_WHITE" },
        crate  = { dict = "blips",           icon = "blip_chest",               color = "COLOR_WHITE" },
        bottle = { dict = "inventory_items", icon = "consumable_moonshine",     color = "COLOR_WHITE" },
        crew   = { dict = "menu_textures",   icon = "menu_icon_invite_accepted", color = "COLOR_WHITE" },
        still  = { dict = "inventory_items", icon = "weapon_moonshinejug",      color = "COLOR_WHITE" },
        note   = { dict = "generic_textures", icon = "tick",                    color = "COLOR_WHITE" },
    },
    VorpColor     = nil, -- the colour every NotifyAdvanced is sent with, e.g
    VorpWarnColor = nil,           -- a warning / alert note's colour instead (e.g. "COLOR_RED"; nil = VorpColor)
}

---o[ Discord logs (webhook URLs go in config/webhooks.lua) ]o---
Config.Logs = {
    Enabled    = true,           -- false: no logs at all
    Console    = true,           -- true: every log line also goes to the server console
    ServerName = "",             -- shown under each Discord entry ("" = Kasippu)
    Username   = "Kasippu Logs", -- the webhook's name in Discord
    Avatar     = "",             -- an image URL for the webhook's picture ("" = Discord's default)
    Events = {                   -- false turns a group off
        explosion = true, -- a still blew up (pressure, heat, overfed fire)
        theft     = true, -- a bottle stolen from a still, a wash spiked, a bottle taken from someone else's crate
        law       = true, -- a still seized, a batch poured out before the law
        lockpick  = true, -- a crate lock picked, a pick broken or failed
        admin     = true, -- /kasippugive, trees added, deleted or cleared
        market    = true, -- bottles sold to a buyer (who, to whom, what, for how much)
    },
}

---o[ Abandoned stills and crates ]o---
Config.Upkeep = {
    Enabled       = true,
    OwnerAwayDays = 14, -- an owner not online for this many days loses his stills and crates
    CheckHours    = 6,  -- how often it looks (the first look is about 15 min after a start)
}

---o[ Admins - who may use the script's admin commands ]o---
Config.Admin = {
    Ace    = "gsc_kasippu.admin", -- server.cfg: add_ace group.admin gsc_kasippu.admin allow
    Groups = { "admin" },         -- VORP account or character groups
}

---o[ Admin Give Command ]o---
Config.GiveCommand = {
    Enabled   = true,               -- false before launch if you don't want it
    Name      = "kasippugive",      -- the chat / console command
    Ace       = "gsc_kasippu.give", -- server.cfg: add_ace group.admin gsc_kasippu.give allow
    Groups    = { "admin" },        -- VORP account or character groups that may use it
    MaxAmount = 20,                 -- most bottles per use
}

---o[ Prop Models ]o---
Config.Models = {
    PlamTreeModel        = "chiku9931",                 -- climbable coconut tree
    KasiyaBarrelKitModel = "kasiya_prop",               -- the still / barrel
    WoodFireModel        = "s_racefinish01x",           -- flame under a lit still
    AgingCrateModel      = "mp006_p_mnshn_crate12_01x", -- aging crate (built for 12 bottles)
    AgingBottleModel     = "p_bottlemedicine27x",       -- bottle shown in the crate / in hand
    WaterBarrelModel     = "p_watertrough01x",          -- the Water Barrel beside a still (in the RDR3 object list)
    LogRackModel         = "p_cordwood01x", -- the Log Rack beside a still
}

---o[ Still Dressing - props around every still ]o---
Config.StillDressing = {
    Enabled = true, -- false: no dressing props at all

    Logs     = { model = "",                       offset = vector3(-0.4, 0.105, -0.5), rotation = vector3(0.0, 0.0, 0.0) }, -- cold firewood while the fire is out ("" = none)
    JarEmpty = { model = "p_masonjar_empty01x",    offset = vector3(0.55, 0.0, -0.45),  rotation = vector3(0.0, 0.0, 0.0) }, -- catch jar while heads are set aside
    JarFull  = { model = "p_masonjarmoonshine01x", offset = vector3(0.55, 0.0, -0.45),  rotation = vector3(0.0, 0.0, 0.0) }, -- catch jar while keeping

    Jugs = nil, -- one jug per waiting bottle; nil = off. Example:

    Tarp  = { model = "p_tent_leento02x", offset = vector3(0.0, -0.2, -0.5), rotation = vector3(0.0, 0.0, 0.0) }, -- over a still with a tarp rigged
    Wreck = { model = "mp006_p_mnshn_debris03x", seconds = 600 },                                                -- left where a still blew up (sec)

    ---o[ Particle effects ]o---
    Steam = { asset = "core", name = "ent_amb_smoke_chimney", scale = 0.6, offset = vector3(0.0, 0.0, 0.9) }, -- condenser running hot
    Smoke = { asset = "core", name = "ent_amb_smoke_chimney", scales = { 0.6, 1.0, 1.6 },                     -- fire smoke: light / rising / heavy
        offset = vector3(-0.4, 0.105, 0.2) },
}
