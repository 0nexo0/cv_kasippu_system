Config = {}

---o[ General ]o---
Config.DevMode = false     -- true: debug prints in F8 / server console (costs resmon: keep false unless reading logs)
Config.LawJob  = "Sheriff" -- the job that counts as the law (dispatches, seizing stills)
Config.VersionCheck = true -- true: on start, the server console says if a newer version is out

---o[ Notifications - the script's own top-right paper notes ]o---
-- Every message this script shows a player goes through GSC.Notify (features/common/*/notify.lua).
Config.Notify = {
    UseVorp    = true,  -- true:  VORP's game feed (NotifyAdvanced / right tip). The game shows ONE feed note at a
                        --        time, so a new note replaces the one up (no queue behind it).
                        -- false: the script's own notes - they stack (newest at the bottom, older slide up).
    Style      = "black", -- the script's notes: "black" = a black brush plate (like the gauge card), "paper" = scorched paper
    VorpStyle  = "advanced", -- with UseVorp: "advanced" = VORP NotifyAdvanced (an icon picked from VorpIcons below)
                             --               "tip"      = VORP NotifyRightTip (text only, the old way)
    DefaultMs  = 4000,  -- how long a note stays (ms) when the message gives no time
    MaxMs      = 8000,  -- no note stays longer than this (ms), whatever the message asks for
    MaxVisible = 4,     -- notes on screen at once; the oldest goes first
    Sound      = false, -- true: a soft click with each new note
    ReadingTime = true, -- true: a note stays at least 1.5 s + 45 ms per letter (still capped by MaxMs), so long ones can be read

    ---o[ With UseVorp: the game feed shows one note at a time, so notes are kept in step with the action ]o---
    -- A new note replaces the one still showing (it never waits in a queue behind it), and notes
    -- that land together (one action) are joined into one, " | " between them.
    BatchMs    = 100,   -- notes arriving within this many ms are joined into one
    MaxLines   = 3,     -- at most this many messages in one joined note (the newest win)

    ---o[ Placement notes: setting down a still, an aging crate, a Water Barrel or Log Rack ]o---
    -- The hint, wet ground, too close / too far, cancelled, the limit and the result.
    PlacementObjective = true, -- true: VORP NotifyObjective (the objective line; a new one replaces the old)
                               -- false: shown like every other note above
    Fuse        = true, -- true: a burning fuse along the bottom shows how long the note stays

    ---o[ The wax seal on each note: picked by words in the message ]o---
    -- Checked top to bottom; the first group with a word found in the message (any case) gives
    -- the seal. kind = "warning" makes those notes warnings too. Translating config/text.lua?
    -- Translate these words with it. No match = a plain quill seal.
    -- Seals: danger, law, guard, wash, fire, tree, water, crate, bottle, crew, still (and note).
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

    ---o[ VORP NotifyAdvanced (VorpStyle = "advanced"): the game icon for each seal above ]o---
    -- dict = texture dictionary, icon = texture in it, color = text colour. Names from the RDR3 texture lists
    -- (github.com/femga/rdr3_discoveries useful_info_from_rpfs/textures). A missing seal uses `note`.
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
    VorpColor     = nil,           -- the colour every NotifyAdvanced is sent with, e.g. "COLOR_BLACK" (nil = each icon's own colour above)
    VorpWarnColor = nil,           -- a warning / alert note's colour instead (e.g. "COLOR_RED"; nil = VorpColor)
}

---o[ Discord logs - for staff: explosions, thefts, the law, lock-picks, admin actions ]o---
-- The webhook URL is NOT set here: this file is sent to every player, so a URL here could be
-- read and abused. Paste it into config/webhooks.lua instead - that file loads on the server
-- only. (A server.cfg convar  set gsc_kasippu_webhook "..."  also works and wins over it.)
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

---o[ Abandoned stills and crates - cleared when their owner stays away ]o---
-- Keeps the database and the server tick from filling with the stills and crates of people who left.
Config.Upkeep = {
    Enabled       = true,
    OwnerAwayDays = 14, -- an owner not online for this many days loses his stills and crates (and what is in them)
    CheckHours    = 6,  -- how often it looks (the first look is about 15 min after a start)
}

---o[ Admins - who may use the script's admin commands ]o---
-- Every admin command checks this on the server. /addtree, tree delete and /kasippugive
-- also accept their own Ace / Groups (Config.TreeAdmin, Config.GiveCommand).
Config.Admin = {
    Ace    = "gsc_kasippu.admin", -- server.cfg: add_ace group.admin gsc_kasippu.admin allow
    Groups = { "admin" },         -- VORP account or character groups
}

---o[ Admin Give Command ]o---
-- /kasippugive <playerId> <recipe> <grade> [strength] [amount] [fresh|rested|mellow|fine|turned] [tainted]
-- e.g. /kasippugive 1 kasippu GOOD STRONG 2      /kasippugive 1 kasippu PERFECT - 1 fine
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
    LogRackModel         = "p_cordwood01x",             -- the Log Rack beside a still (in the RDR3 object list; also p_cordwood02x / 03x, p_woodpile01x)
}

---o[ Still Dressing - props around every still ]o---
-- offset / rotation are in the barrel's own axes, so they turn with it
Config.StillDressing = {
    Enabled = true, -- false: no dressing props at all

    Logs     = { model = "",                       offset = vector3(-0.4, 0.105, -0.5), rotation = vector3(0.0, 0.0, 0.0) }, -- cold firewood while the fire is out ("" = none)
    JarEmpty = { model = "p_masonjar_empty01x",    offset = vector3(0.55, 0.0, -0.45),  rotation = vector3(0.0, 0.0, 0.0) }, -- catch jar while heads are set aside
    JarFull  = { model = "p_masonjarmoonshine01x", offset = vector3(0.55, 0.0, -0.45),  rotation = vector3(0.0, 0.0, 0.0) }, -- catch jar while keeping

    Jugs = nil, -- one jug per waiting bottle; nil = off. Example:
    -- Jugs = {
    --     model = "mp006_s_mnshn_product01x_full",
    --     offset = vector3(-0.45, 0.6, -0.5),
    --     step = vector3(0.2, 0.0, 0.0),
    --     rotation = vector3(0.0, 0.0, 0.0),
    --     max = 6,
    -- },

    Tarp  = { model = "p_tent_leento02x", offset = vector3(0.0, -0.2, -0.5), rotation = vector3(0.0, 0.0, 0.0) }, -- over a still with a tarp rigged
    Wreck = { model = "mp006_p_mnshn_debris03x", seconds = 600 },                                                -- left where a still blew up (sec)

    ---o[ Particle effects ]o---
    Steam = { asset = "core", name = "ent_amb_smoke_chimney", scale = 0.6, offset = vector3(0.0, 0.0, 0.9) }, -- condenser running hot
    Smoke = { asset = "core", name = "ent_amb_smoke_chimney", scales = { 0.6, 1.0, 1.6 },                     -- fire smoke: light / rising / heavy
        offset = vector3(-0.4, 0.105, 0.2) },
}
