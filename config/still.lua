---o[ Barrel Kit ]o---
Config.KasiyaBarrelKitConf = {
    KasiyaBarrelItemName        = Config.Items.BarrelKit, -- usable item that places a still
    KasiyaBarrelPromptTitle     = "Goldstone Kasiya",     -- prompt group title at the barrel
    KasiyaBarrelPromptsHoldTime = 200,                    -- ms to hold every barrel / crate / crew prompt
    BarrelInteractRadius        = 2.5,                    -- metres: how close for the barrel prompts to show
    KasiyaBarrelDistance        = 0.5,                    -- metres: server range check is this + 5
    StreamDistance              = 80.0,                   -- metres: barrel and fire props only exist within this
    BarrelUsageTime             = 1,                      -- batches before the barrel breaks (only with BarrelCondition off)
    BarrelDestroyingTime        = 10000,                  -- ms between "falling apart" warning and the barrel vanishing
    SaveEverySeconds            = 60, -- a lit or working still is saved this often, so a restart keeps its heat and fuel
    MaxPerPlayer                = 1,                      -- most barrels one character can have set down at once (0 = no limit)
}

---o[ Picking Up A Barrel ]o---
Config.BarrelPickup = {
    Enabled = true,
    HoldMs  = 1500, -- ms to hold the pickup prompt
}

---o[ Barrel Stash ]o---
Config.BarrelStash = {
    StashName              = "Kassippu Barrel", -- inventory title
    StashItemsLimit        = 20,                -- slots
    StashWeight            = 5.0,              -- max weight
    StashCustomItemsStatus = true,              -- accept items with metadata
    StashSharedStatus      = true               -- everyone allowed sees the same stash
}

---o[ The Fire ]o---
Config.Fuel = {
    Logs = {
        wood     = { item = Config.Items.Wood,     label = "Wood",     burnSeconds = 60,  power = 1.0, icon = "fire" },              -- burnSeconds: how long one log lasts
        hardwood = { item = Config.Items.Hardwood, label = "Hardwood", burnSeconds = 120, power = 1.4, icon = "fire-flame-curved" }, -- power: how hot (1.0 = normal); icon: its wedge in the F2 menu
    },
    MaxBurnSeconds = 300, -- most burn time the fire box can hold (sec) 5 minutes

    ---o[ Heat ]o---
    WarmUpIncrement = 0.2, -- heat gained per second while a cold barrel warms to InitialHeat, x the fire's power
    HeatIncrement = 1.0, -- heat gained per second heating up after the ferment, x the fire's power
    ManualBoost   = 2.0,  -- instant heat a log adds in the final push, x its power
    CoolDownRate  = 1.0,  -- heat lost per second with the fire out (heating up after the ferment)
    PushCoolRate  = 0.6,  -- heat lost per second with the fire out (final push)

    ---o[ Cold stage: forgetting to feed the fire ]o---
    ColdGraceSeconds = 60,  -- seconds the barrel keeps its heat after the fire burns out (0 = cools at once)
    ColdCoolRate     = 0.3, -- heat lost per second once that grace is over (1.0 = the old speed)

    ---o[ Rain ]o---
    Rain = {
        Enabled       = true,
        OutSeconds    = 20, -- seconds of rain on an open fire before it goes out
        CheckSeconds  = 5,  -- how often a player at the barrel checks the sky (sec)
        ReportSeconds = 20, -- a sky check older than this counts as dry (sec)
        Weathers      = { "rain", "thunderstorm", "drizzle", "shower", "hurricane", "hail", "sleet", "thunder" }, -- weather that counts as rain

        TarpEnabled   = true, -- a rigged tarp keeps the fire safe from rain
    },
}

---o[ Water Bucket ]o---
Config.WaterBucket = {
    Item      = Config.Items.WaterBucket, -- a bucket of water
    EmptyItem = Config.Items.EmptyBucket, -- left after the last use (false = nothing)
    Uses      = 5,                        -- uses in a full bucket
}

---o[ Cooling ]o---
Config.CoolingSystem = {
    HeatReductionValue = 5.0, -- heat removed by one pour of water
}

---o[ Mixing ]o---
Config.Mixing = {
    Time        = 10000,         -- ms; only used when Stir.Enabled = false
    Sound       = "Mixing.ogg", -- sound file in nui/
    SoundVolume = 0.9,          -- 0.0 - 1.0

    ---o[ Stirring minigame ]o---
    Stir = {
        Enabled     = true, -- false: mixing is just a wait of Time
        GoodBonus   = 5,    -- score added for a good stir
        BadPenalty  = 4,    -- score lost for a bad or missed stir (once, after the last try)
        Tries       = 2,    -- goes at the stir: a failed one starts again (1 = no second chance)
        RetryDelay  = 3,    -- sec between a failed stir and the next try
        WaitSeconds = 45,   -- sec the stir may take before it counts as missed (keep it above Minigame.time)
        MinSeconds  = 4, -- a stir won sooner than this after it started is not a real game: counted as bad
        ---o[ The spoon ]o---
        Minigame    = {
            type = "spoon", hint = "spoon",
            mouse      = true,  -- the cursor shows for this game only
            time       = 40,    -- seconds to finish
            strikes    = 2,     -- misses allowed (boil-over, wrong ingredient, a call left too long)
            steps      = 3,     -- ingredients it calls for, one per stage of the mixing
            callTime   = 6,     -- seconds to add the called ingredient before it counts as a miss
            perTurn    = 0.16,  -- mixed per full turn of the spoon (about 6 turns in all; 0.08 = 12)
            minSpeed   = 0.3,   -- turns a second: slower than this mixes at half (lazy circles still count)
            maxSpeed   = 2.0,   -- turns a second: faster than this whips up froth
            frothRate  = 0.25,  -- froth per second for each turn-a-second over maxSpeed
            frothFall  = 0.30,  -- froth that settles per second
            reverse    = false,  -- true: halfway, the stir changes direction (harder)
            lumps      = 3,     -- lumps per ingredient (0 = none: it simply mixes in)
            lumpShare  = 0.04,  -- mixing each lump holds back until it is broken
            lumpBonus  = 0.02,  -- mixed for breaking one
            lumpSoften = 5,     -- seconds before an unbroken lump dissolves by itself (0 = never)
            streakMax   = 1.6,  -- mixing at a full Smooth streak
            streakBuild = 0.5, -- streak gained per second of steady stirring (2 s to the full x1.6)
            hintAfter  = 0.5,   -- the called dish glows after this share of callTime (false = never)
            sound      = true,  -- plop, crunch, fizz, chime and the swish (made in the UI, no files)
            volume     = 0.5,   -- 0.0 - 1.0
        },
    },
}

---o[ Fermentation ]o---
Config.Fermentation = {
    Enabled      = true, -- false: straight from mixing to heating

    ReadyMinutes = 2,   -- minutes to reach full strength (Mild; climate ageRate speeds / slows it)
    TurnMinutes  = 45,   -- minutes before it starts turning (warning) - 20 min to light the fire once ready
    SpoilMinutes = 55,   -- minutes before the batch is lost (keepRate and spikes shorten both)

    MinStrength  = 25,   -- % strength needed before the fire will light
    CoolRate     = 0.1,  -- heat lost per second while fermenting
    SpoilResidue = 30.0, -- fouling a ruined wash leaves in the barrel

    ---o[ Tend The Wash ]o---
    Tend = {
        Enabled    = true, -- false: no tending, fermenting is just a wait
        GoodBonus  = 5,    -- score added for a good tend
        BadPenalty = 3,    -- score lost for a botched tend (or giving up)
        MinSeconds = 4,    -- a result sooner than this is not a real game: it counts as botched
        ---o[ The spoon ]o---
        Minigame   = {
            type = "spoon", hint = "spoon",
            mouse     = true,  -- the cursor shows for this game only (it is played with the mouse)
            time      = 32,    -- seconds to finish
            strikes   = 2,     -- misses allowed (boil-over, wrong ingredient, a call left too long)
            steps     = 3,     -- ingredients the wash calls for, one per stage of the mixing
            callTime  = 6,     -- seconds to add the called ingredient before it counts as a miss
            perTurn   = 0.16,  -- mixed per full turn of the spoon (about 6 turns in all; 0.08 = 12)
            minSpeed  = 0.3,   -- turns a second: slower than this mixes at half (lazy circles still count)
            maxSpeed  = 2.0,   -- turns a second: faster than this whips up froth
            frothRate = 0.25,  -- froth per second for each turn-a-second over maxSpeed
            frothFall = 0.30,  -- froth that settles per second
            reverse   = false,  -- true: halfway, the stir changes direction (harder)

            ---o[ Lumps ]o---
            lumps     = 2,     -- lumps per ingredient (0 = none: it simply mixes in)
            lumpShare = 0.04,  -- mixing each lump holds back until it is broken
            lumpBonus = 0.02,  -- mixed for breaking one
            lumpSoften = 5,    -- seconds before an unbroken lump dissolves by itself, no bonus (0 = never)

            ---o[ Smooth streak: steady stirring in the gold band mixes faster ]o---
            streakMax   = 1.6,  -- mixing at a full streak (1.0 = no streak bonus)
            streakBuild = 0.5, -- streak gained per second of steady stirring (2 s to the full x1.6)

            hintAfter = 0.5,   -- the called dish glows after this share of callTime (false = never)
            sound     = true,  -- plop, crunch, fizz, chime and the stir's swish (made in the UI, no files)
            volume    = 0.5,   -- 0.0 - 1.0
        },

        ---o[ The colour each ingredient gives the wash ]o---
        Tints = {
            water       = "#9fc3cf",
            yeast       = "#efe3c4",
            brown_sugar = "#6b3a17",
            sugarcane   = "#c4c46a",
            banana      = "#ecd06a",
            apple       = "#c8463a",
            orange      = "#f0902e",
            grape       = "#6e3a72",
            coconut     = "#e8dfc8",
        },
    },
}

---o[ Heat Stages ]o---
Config.HeatManagement = {
    InitialHeat            = 40.0,  -- a cold barrel warms to this before ingredients can be mixed
    CommonHeat             = 100.0, -- heating up climbs to this, then the pause before the final push
    MaxHeat                = 105.0, -- reaching this blows the barrel
    HeatInterval           = 60000, -- ms pause at full heat before the final push
    HeatIncrementDivide    = 2,     -- final push heat per second = Fuel.HeatIncrement / this (1 / 2 = 0.5, keep it there)
    QualityTrackingTime    = 10,    -- seconds to hold a bracket (only with HeatSkill off)
    BrewgProgress          = 100,   -- progress to finish brewing (only with Cuts off)
    BrewProgressIncreValue = 10,    -- progress per tick (only with Cuts off)
}

---o[ Final Push - hold the heat on the mark ]o---
Config.HeatSkill = {
    Enabled            = true, -- false: old "sit in a bracket" grading

    PushSeconds        = 90,   -- length of the graded run (sec)

    ---o[ Target line ]o---
    TargetCentre       = 80.0, -- heat to hold
    TargetHalfWidth    = 5.0,  -- full marks within this of the centre
    ToleranceFalloff   = 12.0, -- marks fall to zero this far beyond it
    DriftAmplitude     = 6.0,  -- how far the target wanders (0 = fixed target)
    DriftPeriodSeconds = 24,   -- seconds for one full wander

    ---o[ Grades (0-100 average, highest first) ]o---
    Grades = {
        PERFECT = 82,
        GOOD    = 60,
        NORMAL  = 40,
        POOR    = 0,
    },

    ---o[ Random flare-ups and draughts ]o---
    EventsEnabled   = true,
    EventMinSeconds = 8,    -- shortest gap between events (sec)
    EventMaxSeconds = 18,   -- longest gap between events (sec)
    FlareHeat       = 7.0,  -- heat jump when the fire flares
    DraughtHeat     = -6.0, -- heat drop when a draught hits

    ---o[ The game ]o---
    Game = {
        Enabled       = true,
        Sag           = 0.4, -- heat lost per second on its own (a stoke every ~7 s holds the mark)
        StokeHeat     = 3.0, -- heat one split adds in all, x the log's power (hardwood 1.4)
        StokeSeconds  = 3,   -- ...spread over this many seconds: act before the needle moves
        StokeCooldown = 1.0, -- seconds between two stokes
        SplitsPerLog  = 6,   -- splits one log on the rack makes (without a rack, one stoke = one whole log)
        TapCool       = 1.5, -- heat the open tap takes off per second
        TapWater      = 1.0, -- litres the open tap uses per second
        WarnSeconds   = 3,   -- a flare-up / draught is warned this long before it hits (0 = no warning)

        ---o[ The Firebox ]o---
        Panel         = true, -- false: world prompts instead (E stoke, hold R cool, V vent, T trouble)
        AutoOpen      = true, -- opens by itself when the push starts for owner / crew at the still (else F2 / E)
        Sound         = true, -- crackle, hiss and clank, made in the UI (no files)
        Volume        = 0.3,  -- 0.0 - 1.0
    },
}

---o[ The Water Barrel and the Log Rack ]o---
Config.Stations = {
    Enabled        = true,
    MaxDistance    = 6.0, -- metres from the still they may stand
    MinDistance    = 0.8, -- ...and no nearer than this (room for the fire)
    InteractRadius = 1.5, -- metres: how close for its prompts / its F2 menu wedges
    StreamDistance = 80.0, -- metres: the prop only exists within this
    StillUsesStock = true, -- every log and drop of water the still uses comes off these two, never the satchel

    WaterBarrel = {
        Capacity     = 100, -- litres it holds (a whole batch takes about 60-80)
        PerBucketUse = 4,  -- litres one use of a water bucket pours in
        PerUse       = 4,  -- litres the still takes for what used to cost one bucket use (pour, condenser, scrub)
    },
    LogRack = {
        Capacity  = 12,                      -- logs it holds (all kinds together)
        BurnOrder = { "wood", "hardwood" },  -- which log a stoke splits first (keys of Config.Fuel.Logs)
    },

    ---o[ When the still blows up, these two go up with it ]o---
    Explosion = {
        Delay  = 0.35, -- seconds after the still (and between the two): a chain, not one bang
        Size   = 1.0,  -- the blast's size (the still's own is 1.5)
        Radius = 3.0,  -- metres: a player this close is hurt
        Damage = 25,   -- health it takes (the still's own takes 50)
    },
}

---o[ The Cuts - catching the spirit ]o---
Config.Cuts = {
    Enabled        = true, -- false: plain progress bar, nothing to do
    RunSeconds     = 90,   -- how long the drip runs (sec)
    HeadsEnd       = 20,   -- where the heads usually end (0-100)
    TailsStart     = 75,   -- where the tails usually start (0-100)
    Jitter         = 5,    -- both move by up to this much each batch
    WarnAhead      = 7,    -- smell warning this far before each change

    HeadsTolerance = 4,    -- this much heads kept = the batch is tainted
    TailsPenalty   = 15,   -- score lost for keeping ALL of the tails
    MinYield       = 0.25, -- least share of hearts a jar counts as holding

    ---o[ Clean cut bonus ]o---
    CleanHearts    = 0.8,  -- keep at least this share of the hearts...
    CleanTails     = 0.15, -- ...and at most this share of the tails
    CleanBonus     = 5,    -- score for a clean cut

    TaintedLabel   = nil,  -- nil = normal label; e.g. "Bad %s" to label tainted bottles openly
}

---o[ Bottling ]o---
Config.Bottling = {
    Enabled       = true,
    HandPour      = 4,    -- bottles poured by hand per hold; the rest of the draw follows your pour
    RestFactor    = 0.5,  -- the rest spill at this share of your hand spill rate (0 = only hand spills count)
    MaxSpillShare = 0.25, -- the rest never take the loss past this share of the bottles drawn
    MinPerBottle  = 1.5,  -- a result sooner than this many seconds per hand bottle counts as all spilled

    Minigame = {
        type = "bottle", hint = "bottle",
        bottleTime = 7,     -- seconds to fill each bottle; run out short and it dribbles (a spill)
        corkTime   = 3,     -- seconds to cork it
        flowRise   = 2.2,   -- how fast the jug tips while SPACE is held (flow 0 - 1 per second)
        flowFall   = 3.0,   -- and rights itself once let go: the pour tapers off, let go a beat early
        fillRate   = 0.42,  -- bottle filled per second at full flow (0 - 1)
        frothRate  = 0.12,  -- froth raised per second at full flow (a fast pour foams; twice as fast in the neck)
        frothFall  = 0.9,   -- share of the froth that settles per second (also while pouring)
        glug       = 0.02,  -- froth kicked up each time you start pouring again (a top-up)
        band       = 0.09,  -- height of the chalk fill mark (share of the bottle)
        corkSpeed  = 1.3,   -- the mallet's swing
        corkZone   = 0.22,  -- width of the gold on the swing
        corkTries  = 2,     -- presses at the cork; miss them all and the bottle goes over
        sound      = true,  -- the pour and the cork, made in the page (no audio files)
        volume     = 0.5,
        tint       = "#d9d0b4", -- colour of the spirit in the jug and the bottles
    },
}

---o[ Condenser - cooling water during the drip ]o---
Config.Condenser = {
    Enabled        = true,

    StartLevel     = 60,   -- % full when the drip starts
    DrainPerSecond = 1.2,  -- % lost per second (90 s drip = 108%: about 2 pours of water)
    TopUp          = 35,   -- % one pour of water adds
    HotBelow       = 25,   -- below this % it runs hot and loses spirit

    LossPerSecond  = 0.02, -- share of the batch lost per second while hot
    MaxLoss        = 0.6,  -- most of the batch it can cost
}

---o[ Trouble At The Still - random incidents ]o---
Config.Incidents = {
    Enabled           = true,

    ChancePerMinute   = 0.08, -- chance per minute of an incident (about 1-2 in a 25 min ferment, 0-1 in the cook)
    MinGapSeconds     = 240,  -- least time between incidents (sec)
    FirstAfterSeconds = 60,   -- none in a still's first seconds
    RetrySeconds      = 3,    -- wait after a botched fix (sec)
    MinSeconds        = 1.0, -- a fix won sooner than this after it started is not a real game: counted as botched

    List = {
        {
            key           = "LID",
            label         = "Reseal The Lid",
            due           = "The lid seal is leaking - spirit's escaping! Reseal it (T).",
            fixed         = "Lid resealed. Not another drop lost.",
            missed        = "The seal took on its own in the end - but a good share went up first.",
            stages        = { "FINAL_PUSH", "BREWING" },
            weight        = 3,
            window        = 40,
            leakPerSecond = 0.01,
            missLoss      = 0.1,
            minigame      = { type = "bar", rounds = 2, zone = 0.16, speed = 0.9, shrink = 0.85, speedUp = 1.1, strikes = 1, time = 9 },
        },
        {
            key             = "ASH",
            label           = "Rake The Ash",
            due             = "Ash is choking the fire - it's burning fast and cold. Rake it out (T).",
            fixed           = "Ash raked out. She's drawing clean again.",
            missed          = "The ash smothered the fire. It's out.",
            stages          = { "IDLE", "MID_CLIMB", "HEAT_PAUSE", "FINAL_PUSH" },
            needsFire       = true,
            weight          = 3,
            window          = 30,
            burnMultiplier  = 2.0,
            powerMultiplier = 0.5,
            missPutsOut     = true,
            minigame        = { type = "sequence", length = 6, keys = { "W", "A", "S", "D" }, strikes = 1, time = 7 },
        },
        {
            key              = "ANIMAL",
            label            = "Chase It Off",
            due              = "Something's sniffing round the still - drawn by the smell. Chase it off (T)!",
            fixed            = "Chased it off into the brush.",
            missed           = "A boar barged into the still before anyone stopped it.",
            stages           = { "FERMENTING", "BREWING" },
            weight           = 2,
            window           = 60,   -- the owner is told wherever he is: time to come back from the trees or a crate
            missWear         = 8,
            missPutsOut      = true,
            missSpikeMinutes = 3,  -- minutes off the wash's keeping time (does not count toward thieves' SpikeMaxPerBatch)
            minigame         = { type = "sequence", length = 5, keys = { "W", "A", "S", "D" }, strikes = 0, time = 4 },
        },
        {
            key                = "CRACK",
            label              = "Patch The Stave",
            due                = "A stave has cracked - she's straining. Patch it (T)!",
            fixed              = "Stave patched. She'll hold.",
            missed             = "The crack opened up - she took a beating and the pressure jumped.",
            stages             = { "HEAT_PAUSE", "FINAL_PUSH" },
            weight             = 2,
            window             = 35,
            pressureMultiplier = 1.5,
            wearPerSecond      = 0.15,
            missWear           = 15,
            missPressure       = 25,
            minigame           = { type = "dial", rounds = 3, zone = 0.18, speed = 0.55, shrink = 0.85, speedUp = 1.15, strikes = 1, time = 12 },
        },
    },
}

---o[ Barrel Upgrades ]o---
Config.Upgrades = {
    Enabled = true,
    List = {
        COPPER = {
            item = Config.Items.CopperCoil, label = "Copper coil", order = 1,
            scoreBonus = 4, capBonus = 15,
            desc = "A better condenser. Every batch scores higher, and Perfect / Good still come out of a more worn barrel.",
        },
        HOOPS = {
            item = Config.Items.IronHoops, label = "Iron hoops", order = 2, requires = "BarrelCondition",
            wearMultiplier = 0.6,
            desc = "Holds the staves tight. The barrel wears 40% slower, so it keeps its condition and top grades longer.",
        },
        GAUGE = {
            item = Config.Items.PressureGauge, label = "Pressure gauge", order = 3, requires = "Pressure",
            ventHeatMultiplier = 0.5, warnAt = 55,
            desc = "Warns you of pressure sooner, and venting it off costs only half the heat.",
        },
    },
}

---o[ Pressure ]o---
Config.Pressure = {
    Enabled        = false,

    Max            = 100.0, -- pressure that bursts the barrel
    BuildAboveHeat = 70.0,  -- builds above this heat, bleeds off below it
    BuildRate      = 3.5,   -- build per second, at MaxHeat
    BleedRate      = 1.5,   -- bleed per second, below BuildAboveHeat

    VentAmount     = 35.0,  -- pressure one vent removes
    VentHeatCost   = 4.0,   -- heat one vent costs
    WarnAt         = 70.0,  -- owner is warned past this
}

---o[ Barrel Condition, Fouling and Repair ]o---
Config.BarrelCondition = {
    Enabled = true, -- false: barrels break after KasiyaBarrelKitConf.BarrelUsageTime batches

    Max = 100.0,    -- condition of a new barrel

    ---o[ Wear ]o---
    WearPerBatch      = 6.0,  -- lost when the last bottle is drawn
    HotWearAbove      = 95.0, -- heat above this wears the barrel...
    HotWearRate       = 0.35, -- ...by this per second, at MaxHeat
    PressureWearAbove = 80.0, -- pressure above this wears the barrel...
    PressureWearRate  = 0.25, -- ...by this per second, at full pressure

    ---o[ What a worn barrel costs you ]o---
    QualityCaps = {           -- least condition needed to bottle each grade
        PERFECT = 75.0,
        GOOD    = 45.0,
    },
    WornPressureMultiplier = 1.9, -- pressure builds this much faster at 0 condition (1.0 = off)

    ---o[ Fouling ]o---
    ResiduePerBatch        = 25.0, -- residue left after each batch (one scrub clears one batch)
    ResidueMax             = 100.0,
    ScorePenaltyPerResidue = 0.28, -- score lost per point of residue
    ScrubUses              = 1,    -- bucket uses one scrub costs
    ScrubRemoves           = 25.0, -- residue removed per scrub

    ---o[ Repair ]o---
    RepairItem     = Config.Items.RepairKit, -- the barrel repair kit
    RepairKitUses  = 5,                      -- uses in a new repair kit (kept in its metadata; gone after the last)
    RepairCost     = 1,                      -- kit uses one repair takes
    RepairRestores = 60.0,                   -- condition restored by one repair

    ---o[ Lifetime (stops one still being farmed forever) ]o---
    MaxRepairs     = 2, -- repairs a still takes in its life, then no more (0 = no limit)
    MaxBatches     = 3, -- batches a still makes before it falls apart

    ---o[ Warnings ]o---
    WarnConditionAt = 30.0, -- owner is warned when condition drops below this
}
