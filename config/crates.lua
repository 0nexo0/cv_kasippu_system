---o[ Aging Crate ]o---
Config.CrateAging = {
    Enabled = true, -- false: the crate item does nothing and placed crates are not loaded

    ---o[ The crate ]o---
    ItemName        = Config.Items.AgingCrate, -- usable item that places a crate
    Capacity        = 12,                      -- bottles it holds (the prop is built for 12)
    MaxPerPlayer    = 4,                       -- most crates one character can have set down at once (0 = no limit)
    InteractRadius  = 1.8,                     -- metres: how close for the crate prompts
    StreamDistance  = 60.0,                    -- metres: crate and bottle props only exist within this
    PickupOwnerOnly = true,                    -- only the owner can pick up an empty crate
    TakeOwnerOnly   = false,                   -- false: anyone can take bottles from an UNLOCKED crate
    TagFreshBottles = true,                    -- tag bottles with recipe + grade (keep true)

    ---o[ Bottle props in the crate ]o---
    ShowBottleProps = true,
    SlotColumns     = 4,
    SlotRows        = 3,
    SlotSpacingX    = 0.115,                   -- metres between columns
    SlotSpacingY    = 0.12,                    -- metres between rows
    SlotOffset      = vector3(0.0, 0.0, 0.05), -- grid offset from the crate centre
    SelectedLift    = 0.05,                    -- the selected bottle stands this much higher

    ---o[ Tiers - richest first, minutes of maturity ]o---
    -- key is looked up in a recipe's rewards[grade].agedItems
    Tiers = {
        { key = "FINE",   minutes = 120, label = "Fine" },   -- 2 h of maturity (1 h with good care)
        { key = "MELLOW", minutes = 60,  label = "Mellow" }, -- 1 h
        { key = "RESTED", minutes = 30,  label = "Rested" }, -- 30 min
    },

    ---o[ Climate - read where the crate is placed ]o---
    -- ageRate = how fast bottles mature, keepRate = how long before they turn. Also used by fermentation.
    Climate = {
        Enabled = true,
        Bands = { -- coldest first: the first band the temperature (C) is `below` wins
            { key = "FREEZING", label = "Freezing", below = 0,         ageRate = 0.6,  keepRate = 1.5 },
            { key = "COLD",     label = "Cold",     below = 10,        ageRate = 0.85, keepRate = 1.3 },
            { key = "COOL",     label = "Cool",     below = 18,        ageRate = 0.95, keepRate = 1.15 },
            { key = "MILD",     label = "Mild",     below = 26,        ageRate = 1.0,  keepRate = 1.0 },
            { key = "WARM",     label = "Warm",     below = 33,        ageRate = 1.25, keepRate = 0.75 },
            { key = "HOT",      label = "Hot",      below = math.huge, ageRate = 1.5,  keepRate = 0.5 },
        },
        ShelterKeepRate = 1.2,    -- indoors: bottles keep this much longer on top
        Fallback        = "MILD", -- band used when climate is off or unknown
    },

    ---o[ Care - the crate asks for an activity ]o---
    TendEverySeconds  = 300,   -- how often an activity comes due (sec)
    TendWindowSeconds = 60,    -- how long it can be answered (sec)
    TendMinSeconds    = 1.5,   -- a job won sooner than this after it started is not a real game: counted as failed (anti-cheat)
    PassBonus         = 6.0,   -- care every bottle gains for a pass
    FailPenalty       = 4.0,   -- care lost for a failed minigame
    MissPenalty       = 10.0,  -- care lost for ignoring it
    CareMax           = 40.0,
    CareMin           = -40.0,
    GoodCare          = 18.0,  -- at or above: bottle finishes one tier higher
    PoorCare          = -18.0, -- at or below: bottle finishes one tier lower

    ---o[ Rhythm - passes in a row are worth more ]o---
    RhythmStep        = 0.25,  -- extra per pass in a row (0.25 x 4 = double)
    RhythmMaxSteps    = 4,

    NotifyOwnerAway   = true,  -- tell the owner an activity is due wherever they are

    ---o[ Souring ]o---
    SpoilMinutes      = 180,   -- real minutes before a bottle turns (Mild cellar). Must be > Fine minutes / (ageRate x keepRate) in every band: Hot needs > 160

    ---o[ Minigames ]o---
    -- "builtin" = the script's own minigames, "syn_minigame" = syn's task bar
    MinigameProvider  = "builtin",

    ---o[ Activities ]o---
    -- weight = how often it comes up, bonus = overrides PassBonus, item = consumed if set
    -- Minigame types: dial, bar, pins, hold, sequence, reach. All take time (sec) and strikes (misses allowed).
    Activities = {
        {
            key      = "TURN",
            label    = "Turn The Bottles",
            due      = "The sediment has settled - the bottles want turning.",
            weight   = 3,
            minigame = { type = "dial", rounds = 4, zone = 0.16, speed = 0.7, shrink = 0.82, speedUp = 1.20,
                reverse = true, strikes = 1, time = 16 },
        },
        {
            key      = "AIR",
            label    = "Air The Crate",
            due      = "The crate is sweating - lift the lid and let her breathe.",
            weight   = 2,
            minigame = { type = "hold", hint = "lid", goal = 5.5, band = 0.24, rise = 0.95, fall = 0.7, drift = 0.26,
                period = 4.5, gusts = 0.5, time = 12 },
        },
        {
            key      = "STRAW",
            label    = "Pack Fresh Straw",
            due      = "The straw has gone damp - pack it fresh around the bottles.",
            weight   = 2,
            minigame = { type = "sequence", length = 7, keys = { "W", "A", "S", "D" }, strikes = 1, time = 7 },
            bonus    = 8.0, -- the most work, so the most worth
            item     = nil, -- e.g. Config.Items.X to make it cost one of that item (add it to config/items.lua first)
        },
    },

    ---o[ Hazards - sometimes replace an activity, target ONE bottle ]o---
    -- window = seconds to answer, targetBonus = extra care on a pass,
    -- failTarget / missTarget = care lost, breakOnMiss = bottle lost if ignored
    HazardChance = 0.35, -- chance a window is a hazard (0-1)
    Hazards = {
        {
            key         = "CORK",
            label       = "Reseal The Cork",
            due         = "A cork is weeping - one of the bottles is losing spirit!",
            weight      = 2,
            window      = 45,
            minigame    = { type = "bar", rounds = 2, zone = 0.12, speed = 1.25, shrink = 0.8, speedUp = 1.1,
                strikes = 0, time = 8 },
            targetBonus = 4.0,
            failTarget  = 12.0,
            missTarget  = 22.0,
        },
        {
            key         = "RATS",
            label       = "Drive Off The Rats",
            due         = "Rats are nosing about in the straw - they'll have a bottle over!",
            weight      = 1,
            window      = 35,
            minigame    = { type = "sequence", length = 5, keys = { "W", "A", "S", "D" }, strikes = 0, time = 3.5 },
            targetBonus = 2.0,
            failTarget  = 8.0,
            breakOnMiss = true,
        },
    },

    ---o[ Lock ]o---
    Lock = {
        Enabled              = true,
        LockOnPlace          = false,                -- a new crate starts locked
        PickItem             = Config.Items.Lockpick, -- needed to pick a lock (nil = bare hands)
        PickBreakChance      = 0.5,                  -- chance the pick breaks on a fail (0-1)
        PickConsumeOnSuccess = false,                -- use up the pick on success too
        PickCooldownSeconds  = 30,                   -- per player, between attempts (sec)
        PickMinSeconds       = 2,                    -- a lock picked sooner than this is not a real game: counted as failed (anti-cheat)
        PickMinigame         = { type = "pins", pins = 4, zone = 0.14, speed = 1.3, speedUp = 1.12, dropOnMiss = true,
            strikes = 2, time = 20 },
    },

    ---o[ Owner map blips ]o---
    Blips = {
        Enabled = true,
        Sprite  = nil,           -- nil = default marker, or a sprite name
        Scale   = 0.8,
        Name    = "Aging Crate",
        Colours = {
            idle    = "BLIP_MODIFIER_MP_COLOR_32", -- nothing to do
            ready   = "BLIP_MODIFIER_MP_COLOR_23", -- a bottle reached the richest tier
            due     = "BLIP_MODIFIER_MP_COLOR_2",  -- an activity is waiting
            turning = "BLIP_MODIFIER_MP_COLOR_8",  -- a bottle is close to turning
            hazard  = "BLIP_MODIFIER_MP_COLOR_8",  -- a hazard is waiting
        },
    },
}
