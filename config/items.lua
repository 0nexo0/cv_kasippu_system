---o[ Item Names ]o---
Config.Items = {
    ---o[ Tools and containers ]o---
    ClimbRope    = "climb_rope",           -- needed to climb a coconut tree
    EmptyPot     = "empty_pot",            -- catches coconut water at the top of a tree
    FilledPot    = "filled_pot",           -- a pot of coconut water; remembers how many ml
    CoconutWater = "coconut_water",        -- coconut water poured out of a pot; remembers ml
    BarrelKit    = "kassippu_barrel_kit",  -- sets down a still
    RepairKit    = "barrel_repair_kit",    -- repairs a worn still; several uses (Config.BarrelCondition.RepairKitUses)
    AgingCrate   = "kassippu_aging_crate", -- sets down an aging crate
    EmptyBottle  = "empty_bottle",         -- one for every bottle drawn off a still
    Lockpick     = "lockpick",             -- opens somebody else's locked aging crate
    Wood         = "wood",                 -- the still's fire: burns fast and ordinary
    Hardwood     = "hwood",                -- burns slow and hot
    StillTarp    = "still_tarp",           -- used at a still: rigs a tarp that keeps the rain off its fire
    WaterBucket  = "bucketwater",          -- cools the still, tops up the condenser, scrubs it; several uses
    EmptyBucket  = "bucket",               -- what a water bucket leaves when its last use is gone
    TastingCup   = "tasting_cup",          -- used from the satchel: sample a bottle to learn its grade, notes and flaws
    WaterBarrel  = "kassippu_water_barrel", -- set down beside a still: all its water comes from it
    LogRack      = "kassippu_log_rack",     -- set down beside a still: all its wood comes from it

    ---o[ Barrel upgrades ]o---
    CopperCoil    = "copper_coil",         -- a better condenser: higher score, Perfect from a more worn barrel
    IronHoops     = "iron_hoops",          -- the barrel wears slower
    PressureGauge = "pressure_gauge",      -- venting costs less heat, and the warning comes sooner

    ---o[ Recipe cards ]o---
    RecipeKasippu = "recipe_kasippu",      -- unlocks Kassippu in the recipe book

    ---o[ What a batch leaves behind ]o---
    SpentMash    = "spent_mash",           -- horse feed, or sold cheaply

    ---o[ Used outside the recipes ]o---
    Water        = "water",                -- found searching the coconut trees
    Banana       = "coconut",              -- found searching the coconut trees

    ---o[ What a still bottles ]o---
    KasippuBottle = "local_kasippu",       -- Kassippu, any grade and strength (config/recipes.lua rewards)
    RaaBottle     = "ra_packet",           -- Raa, any grade and strength

    ---o[ Aged Kassippu ]o---
    KasippuRested = "kasippu_rested",
    KasippuMellow = "kasippu_mellow",
    KasippuFine   = "kasippu_fine",
}
