---o[ The Law ]o---
Config.Law = {
    Enabled = true, -- false: no tip-offs, lookouts, raids or market sale reports (guard yards still call the Sheriff: GuardSpawnConf.LawDispatch)

    ---o[ Tip-offs - somebody reports the smoke ]o---
    TipOff = {
        Enabled         = true,
        ChancePerMinute = 0.05, -- base chance per minute a lit still is reported
        MaxChance       = 0.9,  -- cap after all factors (the worst case today, heavy smoke in town, is 0.05 x 1.6 x 3 = 0.24)
        NeedLawOnline   = true, -- no reports while no lawman is on duty
        CooldownMinutes = 10,   -- a still is not reported again within this

        ---o[ Chance multipliers ]o---
        SmokeFactor     = { 0.6, 1.0, 1.6 }, -- light / rising / heavy smoke
        TownFactor      = 3.0,    -- inside a town's radius
        WildsFactor     = 0.5,    -- further than WildsDistance from every town
        WildsDistance   = 1500.0, -- metres
        NightFactor     = 0.4,    -- between NightFrom and NightTo
        NightFrom       = 20,     -- game hour (same night as the yard guards: GuardSpawnConf.Detection.NightStartHour)
        NightTo         = 6,      -- game hour (GuardSpawnConf.Detection.NightEndHour)
        CoveredFactor   = 0.5,    -- indoors or under cover

        MarkerFuzz      = 60.0,   -- metres: the map marker lands up to this far from the still
        BlipName        = "Smoke Reported",

        Towns = {
            { name = "Saint Denis", coords = vector3(2632.0, -1312.0, 51.0),   radius = 450.0 },
            { name = "Valentine",   coords = vector3(-281.0, 793.0, 118.0),    radius = 300.0 },
            { name = "Rhodes",      coords = vector3(1346.0, -1312.0, 76.0),   radius = 300.0 },
            { name = "Blackwater",  coords = vector3(-813.0, -1324.0, 43.0),   radius = 350.0 },
            { name = "Strawberry",  coords = vector3(-1791.0, -386.0, 160.0),  radius = 250.0 },
            { name = "Annesburg",   coords = vector3(2929.0, 1355.0, 44.0),    radius = 250.0 },
            { name = "Van Horn",    coords = vector3(2985.0, 568.0, 44.0),     radius = 200.0 },
            { name = "Armadillo",   coords = vector3(-3685.0, -2623.0, -14.0), radius = 250.0 },
            { name = "Tumbleweed",  coords = vector3(-5512.0, -2937.0, -2.0),  radius = 200.0 },
        },
    },

    ---o[ Lookout - a crew member posted away from the still ]o---
    Lookout = {
        Enabled         = true,
        WarnRadius      = 150.0, -- metres: lookout spots a lawman this close
        LookoutRadius   = 250.0, -- metres: furthest a lookout can be from the still
        PostedOutside   = 15.0,  -- metres: must be at least this far out to count as a lookout
        NoticeRadius    = 35.0,  -- metres: without a lookout, people at the still notice this close
        CheckSeconds    = 3,     -- how often it checks (sec)
        CooldownSeconds = 45,    -- seconds between warnings, per still
    },

    ---o[ The raid ]o---
    Seize = { -- lawman seizes a still with a batch or lit fire
        Enabled = true,
        HoldMs  = 5000, -- ms to hold the prompt
    },

    Pour = { -- owner / crew destroy the evidence
        Enabled = true,
        HoldMs  = 3000, -- ms to hold the prompt
    },
}
