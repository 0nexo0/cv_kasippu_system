---o[ Animations ]o---
Config.AnimConf = {
    ---o[ The still ]o---
    AddWoodScenario     = "WORLD_HUMAN_FIRE_TEND_KNEEL", -- putting a log on: kneel and tend the fire (nil = use the dict below)
    AddWoodAnimDict     = "amb_work@prop_human_wood_chop@chop_front@male_a@stand_exit",
    AddWoodAnimName     = "exit_back",
    AddWoodAnimTime     = 3700,                          -- ms
    AddWoodProp         = nil, -- no log in hand. To bring one back:

    AddWaterScene       = "WORLD_HUMAN_BUCKET_POUR_LOW", -- pouring water (scenario)
    AddWaterSceneTime   = 4000,

    ---o[ Props a scenario hands the player and can leave stuck in the hand ]o---
    ScenarioProps = { "p_bucket01x", "p_bucket02x", "p_bucket03x", "p_bucket04x", "p_bucket06x", "p_bucket07x",
        "p_cs_bucket01x", "p_cs_bucket01bx", "p_cs_bucket03x", "p_waterbucket01x", "p_buckethin01x" },
    ScenarioPropRadius = 1.5, -- metres around the player
    ScenarioPropDelay  = 800, -- ms after the scenario ends (it puts the bucket down first)

    BrewProductAnimDict =                                -- bottling: reach down, bring a bottle up
    "amb_work@world_human_bartender@serve_beer@male_a@serve_bottle@under_bar@base",
    BrewProductAnimName = "under_trans_over_a",
    BrewProductAnimTime = 4000,

    ---o[ Setting things down / picking them up, and the still's chores ]o---
    Actions = {
        ---o[ Setting each thing down ]o---
        place       = { scenario = "WORLD_HUMAN_BOX_PUT_DOWN_1",       time = 2500 }, -- anything set down
        place_still = { scenario = "WORLD_HUMAN_BOX_PUT_DOWN_1",       time = 2800 }, -- the still (barrel kit)
        place_crate = { scenario = "WORLD_HUMAN_BOX_PUT_DOWN_1",       time = 2500 }, -- the aging crate
        place_water = { scenario = "WORLD_HUMAN_BUCKET_PUT_DOWN_FULL", time = 2500 }, -- the water barrel
        place_rack  = { scenario = "WORLD_HUMAN_SACK_PUT_DOWN_1",      time = 2500 }, -- the log rack (no log in hand)

        ---o[ Adding to things ]o---
        store   = { scenario = "WORLD_HUMAN_CROUCH_INSPECT", time = 2000 }, -- opening the barrel's storage (Store Ingredients)
        upgrade = { scenario = "WORLD_HUMAN_HAMMER_KNEEL",   time = 3500 }, -- fitting a copper coil / iron hoops / pressure gauge

        pickup = { scenario = "WORLD_HUMAN_BOX_PICKUP_1",    time = 2500 }, -- picking one up again, or taking the tarp down
        fill   = { scenario = "WORLD_HUMAN_BUCKET_POUR_LOW", time = 3500 }, -- a bucket into the water barrel
        stack  = { scenario = "WORLD_HUMAN_BOX_PUT_DOWN_1",  time = 2500 }, -- logs onto the log rack (no log in hand)
        scrub  = { scenario = "WORLD_HUMAN_CLEAN_TABLE",     time = 4000 }, -- scrubbing the barrel out
        repair = { scenario = "WORLD_HUMAN_HAMMER_KNEEL",    time = 4000 }, -- mending the staves with a barrel repair kit
        tarp   = { scenario = "WORLD_HUMAN_HAMMER_KNEEL",    time = 3500 }, -- staking the tarp over the still
        vent   = { scenario = "WORLD_HUMAN_CROUCH_INSPECT",  time = 1500 }, -- opening the vent
    },

    ---o[ Palm trees ]o---
    ClimbPrepareAnimDict    = "mech_inspection@mini_map@satchel", -- readying the rope before the climb
    ClimbPrepareAnimName    = "exit",
    ClimbPrepareAnimFlag    = 31,

    TreeClimbUpAnimDict     = "mech_ladders@base",                 -- climbing up
    TreeClimbUpAnimName     = "climb_up",
    TreeClimbUpAnimTime     = -1,                                  -- -1 = loop until stopped
    TreeClimbUpAnimFlag     = 1,

    TreeClimbDownAnimDict   = "mech_ladders@base",                 -- climbing down
    TreeClimbDownAnimName   = "slide_climb_down",
    TreeClimbDownAnimFlag   = 1,

    TreeCrouchAnimDict      = "amb_work@world_human_crouch_inspect@male_a@idle_a", -- crouched at the top
    TreeCrouchAnimName      = "idle_a",
    TreeCrouchAnimFlag      = 1,

    TreeItemSearchAnimDict  = "amb_work@world_human_crouch_inspect@male_a@idle_b", -- rummaging through the crown
    TreeItemSearchAnimName  = "idle_d",
    TreeItemsSearchAnimFlag = 31,

    CoconutCollectAnimDict  = "mech_inspection@mini_map@satchel", -- draining coconut water into the pot
    CoconutCollectAnimName  = "exit",
    CoconutCollectAnimFlag  = 31,

    ---o[ The aging crate ]o---
    CrateBottleAnimDict     = "amb_player@world_player_bottle_box_pickup@whiskey", -- putting a bottle in / taking one out
    CrateBottleAnimName     = "base",
    CrateBottleAnimFlag     = 31,
    CrateBottleAnimTime     = 1800,
    CrateBottleHandBone     = "PH_R_Hand",                         -- bone the bottle prop is held in
    CrateBottleHandOffset   = vector3(0.0, 0.0, 0.0),
    CrateBottleHandRotation = vector3(0.0, 0.0, 0.0),

    CrateActivities = {
        TURN  = { dict = "amb_player@world_player_bottle_box_pickup@whiskey", anim = "base", flag = 31, time = 4000, holdBottle = true }, -- lifting and turning a bottle
        AIR   = { scenario = "WORLD_HUMAN_FAN", time = 5000 },                -- fanning the crate
        STRAW = { scenario = "WORLD_HUMAN_CROUCH_INSPECT", time = 5000 },     -- packing straw by hand
        CORK  = { dict = "mech_inspection@mini_map@satchel", anim = "exit", flag = 31, time = 3000, holdBottle = true },
        RATS  = { scenario = "WORLD_HUMAN_BROOM_WORKING", time = 3500 },      -- sweeping the rats off
    },

    CrateLockAnim         = { dict = "mech_inspection@mini_map@satchel", anim = "exit", flag = 31, time = 1500 }, -- locking / unlocking
    CrateLockpickScenario = "WORLD_PLAYER_PICK_LOCK", -- held while the lockpick minigame runs (fallback: "WORLD_HUMAN_CROUCH_INSPECT")

    ---o[ Scenarios held during minigames (nil = none) ]o---
    MixStirScenario  = "WORLD_HUMAN_CAULDRON_STIR_NO_POT", -- stirring the mash with a paddle (alt: "PROP_HUMAN_MOONSHINE_STIR_MASH")
    JournalScenario  = "WORLD_HUMAN_WRITE_NOTEBOOK", -- while the recipe book is open
    IncidentScenario = "WORLD_HUMAN_CROUCH_INSPECT", -- fixing trouble at the still

    ---o[ Tasting ]o---
    TastingAnim = { dict = "mech_inspection@mini_map@satchel", anim = "exit", flag = 31, time = 1500 }, -- the cup out of the satchel (nil = none)
}
