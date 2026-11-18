---o[ Tree Minigames ]o---
Config.TreeMinigameProvider = "builtin" -- "builtin" = script's own, "legacy" = legends-keypress + syn_minigame

---o[ Tree Climbing ]o---
Config.TreeClimbConf = {
    ---o[ General ]o---
    TreeName          = "Coconut Tree",           -- prompt group name
    ClimbRequiredItem = Config.Items.ClimbRope,   -- needed to climb
    InteractRadius    = 3.0,                      -- metres: how close for the climb prompt
    PromptHoldMs      = 1000,                     -- ms to hold every tree prompt
    TreeGrowingTime   = 60,                       -- seconds before a searched tree can be searched again
    PrepareSeconds    = 3,                        -- readying the rope before the climb (sec)
    MinClimbSeconds   = 20,                       -- anti-cheat: search / collect only this long after the server let him start up
    MaxTopMinutes     = 30,                       -- ...and no longer than this after (then he must climb again)
    SearchMaxDistance = 6.0,                      -- metres (flat) from the trunk the server accepts a crown search from

    ---o[ Grip check on each rung ]o---
    ClimbMaxSteps     = 8,                        -- rungs to the top
    GripMinigame      = { type = "reach", reaches = 2, zone = 0.24, speed = 0.75, speedUp = 1.08,
        strikes = 0, time = 4.5, compact = true, minimal = true },
    GripHarderPerRung = 0.05,                     -- each rung up is this much harder (0 = all alike)
    HealthReduceCount = 20,                       -- health lost on a fall

    ---o[ Position on the trunk ]o---
    ClimbStepHeight    = 1.5,  -- metres per rung
    ClimbBaseOffset    = 1.0,  -- attach height at ground level (metres)
    ClimbForwardOffset = 0.45, -- how far out from the trunk (metres)
    ClimbUpSyncMs      = 100,  -- ms between height updates to other players going up (false = per rung)
    ClimbDownSyncMs    = 100,  -- ...and coming down

    ---o[ Going up ]o---
    ClimbSpeed          = 0.28, -- rungs per second
    ClimbEaseDistance   = 0.4,  -- slows over the last of a rung while waiting on a check
    ClimbMinSpeedFactor = 0.12, -- never slower than this share of ClimbSpeed
    FinishRungSpeed     = 6.0,  -- rungs per second for the last rung (0 = snap)
    TopSettleSeconds    = 0,    -- pause at the top before crouching (sec)

    ---o[ Coming down ]o---
    DescendSpeed        = 2.4,  -- metres per second
    DescendEaseDistance = 1.5,  -- metres: slows over this last stretch

    ---o[ Falling off ]o---
    FallRagdollSeconds       = 5.0,   -- ragdoll length (sec)
    FallPushSpeed            = 1.5,   -- m/s pushed away from the trunk (0 = straight down)
    FallGameDamage           = false, -- false: only HealthReduceCount is lost; true: game fall damage too
    FallClearDistance        = 1.2,   -- metres: trunk collision ignored until this far away
    FallClimbCooldownSeconds = 1,     -- climb prompt hidden this long after getting up (sec)

    ---o[ First person at the top ]o---
    FirstPersonAtTop       = false,
    FirstPersonEyeOffset   = vector3(0.0, 0.22, 0.60), -- right / forward / up from the ped
    FirstPersonFov         = 55.0,
    FirstPersonSensitivity = 8.0,  -- degrees per unit of look input
    FirstPersonPitchLimit  = 80.0, -- degrees up / down
}

---o[ Tree Streaming ]o---
Config.TreeClimbConf.StreamDistance   = 50.0 -- metres: trees spawn within this
Config.TreeClimbConf.DespawnDistance  = 90.0 -- metres: removed past this (keep 20+ above StreamDistance)
Config.TreeClimbConf.MaxSpawnsPerPass = 2    -- trees created per pass

---o[ Coconut Water Pots ]o---
Config.CoconutBucketConf = {
    ---o[ The pot prop ]o---
    BucketModel    = "p_potclay04x",
    AttachOffset   = vector3(0.0, 0.0, 13.2), -- position on the tree
    AttachRotation = vector3(0.0, 0.0, 0.0),
    AttachBone     = 0,

    ---o[ Items ]o---
    CoconutWaterItem = Config.Items.CoconutWater,
    RequiredPotItem  = Config.Items.EmptyPot,  -- needed to collect
    FilledPotItem    = Config.Items.FilledPot, -- what the empty pot becomes (carries the ml)

    ---o[ Filling ]o---
    FillIntervalMinutes    = 1,   -- minutes between fills
    FillPercentPerInterval = 10,  -- % added each interval (a full 1000 ml pot in 10 min = 2 Raa batches)
    MaxFillPercent         = 100,
    MlPerPercent           = 10,  -- 1% = 10ml, 100% = 1000ml

    ---o[ Fill bar at the top of the tree ]o---
    ShowFillHud       = true,
    HudPosX           = 0.5,   -- screen position 0.0 - 1.0
    HudPosY           = 0.88,
    HudBarWidth       = 0.14,
    HudBarHeight      = 0.013,
    HudFont           = 1,     -- RedM font id (1 = western serif)
    HudRefreshSeconds = 15,    -- how often the % is re-read from the server (sec)
    HudEaseSeconds    = 2.5,   -- bar animation time (sec)

    ---o[ After collecting ]o---
    CollectAnimSeconds    = 6,                                       -- collecting animation (sec)
    RegrowCooldownSeconds = Config.TreeClimbConf.TreeGrowingTime,    -- pot stays empty this long (sec)

    ---o[ Database ]o---
    DbSnapshotMinutes = 0, -- 0 = save only on change (recommended)
}

---o[ Coconut Collect Minigame ]o---
Config.CoconutCollectMinigameConf = {
    Game     = { type = "hold", hint = "pour", goal = 3.0, band = 0.26, rise = 0.8, fall = 0.6, drift = 0.22,
        period = 5.0, gusts = 0.3, time = 10, anchor = "high" },
    Duration = 4000, -- legacy only (ms)
    Size     = 6,    -- legacy only
}

---o[ Tree Search Minigame ]o---
Config.TreeItemsSearchMinigameConf = {
    Game              = { type = "sequence", hint = "fronds", length = 5, keys = { "W", "A", "S", "D" }, arrows = true,
        strikes = 1, time = 6, anchor = "high" },
    Duration          = 4500, -- legacy only (ms)
    Size              = 7,    -- legacy only
    SearchAnimSeconds = 4,    -- searching animation before the loot (sec)
    LootCardSeconds   = 4,    -- loot card on screen (sec)
}

---o[ Tree Search Rewards ]o---
Config.TreeItemsSearchRewards = {
    { item = Config.Items.Banana,     label = "Banana",            chance = 60, amount = { min = 1, max = 3 } },
    { item = Config.Items.Water,      label = "Water",             chance = 30, amount = { min = 1, max = 1 } },
    { item = Config.Items.BarrelKit,  label = "Kasiya Barrel Kit", chance = 10, amount = { min = 1, max = 1 } },
}

---o[ Climb Camera ]o---
Config.StartClimbTreeCamConf = {
    CameraType    = "DEFAULT_SCRIPTED_CAMERA",
    RotX          = -3.0,
    RotY          = 0.0,
    FOV           = 60.0,
    BlendMs       = 800,   -- ms to blend into / out of the climb camera
}

Config.UpdateCamHeightConf = {
    Distance     = 3.2,  -- metres out from the trunk
    HieghtOffSet = 0.7,  -- metres above the hands (negative = below)
    SideOffset   = 1.1,  -- metres to the side
    LookAtRaise  = 0.45, -- aims this much above the attach point
}

---o[ Legacy Grip Minigame (legends-keypress) ]o---
Config.LegendKeyPressConf = {
    TotalTime     = 1,
    NumOfKeys     = 1,
    KeyPressGapMs = 2000, -- ms between checks (keep above 2000)
}
