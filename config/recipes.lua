---o[ Recipe Book ]o---
Config.DefaultRecipe = "kasippu" -- recipe the book opens on

Config.RecipeBook = {
    ItemImages = "nui://vorp_inventory/html/img/items/%s.png", -- item pictures in the book (%s = item name)
    CardsUsable = true, -- using a recipeItem from the satchel opens the book on that recipe (read-only)
}

---o[ Recipes ]o---
Config.Recipes = {
    ---o[ Kassippu ]o---
    ["kasippu"] = {
        label        = "Kassippu",
        title        = "කසිප්පු Recipe",
        titleImage   = "assets/img/new/kasippu_text.png",
        displayImage = "assets/img/new/kasiya.png",

        recipeItem = Config.Items.RecipeKasippu, -- card needed

        ingredients = {
            { item = "water",       label = "Water",       batch = true },   -- 1 per batch: the batch size
            { item = "yeast",       label = "Yeast",       amount = 1 },     -- every batch needs 1
            { item = "brown_sugar", label = "Brown Sugar", sugar = 2 },
            { item = "sugarcane",   label = "Sugarcane",   sugar = 1 },
            { item = "banana",      label = "Banana",      flavour = 1, perishable = true },
            { item = "apple",       label = "Apple",       flavour = 1 },
            { item = "orange",      label = "Orange",      flavour = 1 },
            { item = "grape",       label = "Grape",       flavour = 1 },
        },
        minSugar = 1,

        strengths = {
            { key = "STRONG",  label = "Strong",  sugar = 4, proof = 100 },
            { key = "REGULAR", label = "Regular", sugar = 2, proof = 80 },
            { key = "LIGHT",   label = "Light",   sugar = 1, proof = 60 },
        },

        instructions = "Water = how much you make. Sugar = how strong (2 for Regular, 4 for Strong, per batch). "
            .. "Fruit = better quality, up to 2 per batch. Fresh fruit is best.",

        rewards = {
            ["PERFECT"] = {
                item = Config.Items.KasippuBottle, count = 8, quality = "PERFECT",
                agedItems = {
                    RESTED = Config.Items.KasippuRested,
                    MELLOW = Config.Items.KasippuMellow,
                    FINE   = Config.Items.KasippuFine,
                },
            },
            ["GOOD"]    = {
                item = Config.Items.KasippuBottle, count = 5, quality = "GOOD",
                agedItems = {
                    MELLOW = Config.Items.KasippuRested,
                    FINE   = Config.Items.KasippuMellow,
                },
            },
            ["NORMAL"]  = { item = Config.Items.KasippuBottle, count = 3, quality = "NORMAL" }, -- no agedItems: ages only as a relabelled bottle
        },
    },

    ---o[ Raa ]o---
    ["raaa"] = {
        label        = "Raa",   -- shown to players; the key stays ["raaa"] (saved barrels and bottles use it)
        title        = "රා Recipe",
        titleImage   = "assets/img/new/Raa_text.png",
        displayImage = "assets/img/new/Raa.png",

        ingredients = { -- no yeast: coconut water ferments it
            { item = "water",       label = "Water",       batch = true }, -- the ONLY batch item: every batch = true item counts as a batch
            { item = "brown_sugar", label = "Brown Sugar", sugar = 2 },
        },
        minSugar     = 1,
        coconutMl    = 500, -- ml of coconut water per batch, carried in the satchel (half a full pot)
        coconutSugar = 2,   -- sugar the coconut water counts as

        strengths = {
            { key = "STRONG",  label = "Strong",  sugar = 4, proof = 100 },
            { key = "REGULAR", label = "Regular", sugar = 2, proof = 80 },
            { key = "LIGHT",   label = "Light",   sugar = 1, proof = 60 },
        },

        instructions = "Coconut water does the work - bring 500ml for every batch, as fresh as you can. "
            .. "Add 1 Brown Sugar per batch for a Strong Raa.",

        rewards = {
            ["PERFECT"] = { item = Config.Items.RaaBottle, count = 8, quality = "PERFECT" },
            ["GOOD"]    = { item = Config.Items.RaaBottle, count = 5, quality = "GOOD" },
            ["NORMAL"]  = { item = Config.Items.RaaBottle, count = 3, quality = "NORMAL" },
        },
    },

}

---o[ The Mash ]o---
Config.Mash = {
    MaxBatch          = 3,    -- most batches (water) a barrel holds
    BatchPressureStep = 0.35, -- pressure builds this much faster per batch over one

    FruitBonusPer     = 4,    -- score per fruit per batch...
    FruitBest         = 2,    -- ...up to this many per batch
    FruitMax          = 3,    -- more than this per batch clogs the barrel
    ClogResidue       = 12.0, -- fouling per fruit over FruitMax
}

---o[ Freshness ]o---
Config.Freshness = {
    Enabled      = true,
    FreshMinutes = 60,  -- perfectly fresh for this long
    StaleMinutes = 240, -- fully stale after this
    MaxPenalty   = 15,  -- score lost for a fully stale mash
    StampMinutes = 30,  -- picked times rounded to this, so items stack
}

---o[ Grades ]o---
Config.Product = {
    Qualities = { -- min / max only used with HeatSkill off
        PERFECT = { min = 75, max = 85, label = "Perfect" },
        GOOD    = { min = 60, max = 74, label = "Good" },
        NORMAL  = { min = 40, max = 59, label = "Normal" },
    },
    FillingItem = Config.Items.EmptyBottle, -- needed for every bottle drawn

    BottleAll = true -- one prompt hold bottles everything you have bottles for
}

---o[ Spent Mash ]o---
Config.SpentMash = {
    Enabled      = true,
    Item         = Config.Items.SpentMash,
    PerBatch     = 1,    -- given per batch to whoever draws the last bottle

    HorseFeed    = true, -- usable to feed your horse
    HorseHealth  = 15,   -- health core added
    HorseStamina = 25,   -- stamina core added
    HorseRange   = 4.0,  -- metres: how close the horse must be (or ride it)
}
