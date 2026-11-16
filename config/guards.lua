---o[ Coconut Yards ]o---
-- Restricted ground the trees stand in. Copy a block to add a yard (restart after changing).
-- A yard only needs name, label, coords and size: without guardPosts the guards are spread over it for you
-- (AutoPostLayout round the fence + an AutoPostInner grid inside, see "Auto posts" below).
Config.TreeZones = {
    {
        name   = "armadillo_coconut_zone",
        label  = "Armadillo Coconut Yard",          -- shown to players
        coords = vector3(-3139.03, -3560.37, 5.94), -- centre
        size   = { x = 70.0, y = 70.0 },            -- HALF the width / depth in metres (70 = a 140 m yard)

        ---o[ When this yard's guards are on the map ]o---
        -- Keep spawnDistance above the furthest post: corner fence posts sit at about (size + AutoPostMargin) x 1.41
        -- from the centre (here (70 + 4) x 1.41 = 105 m), or guards pop in where the player can see them.
        spawnDistance   = 200.0, -- metres from the centre: every guard appears (nil = GuardSpawnConf.SpawnDistance)
        despawnDistance = 230.0, -- metres: removed again; at least spawnDistance + 20, or the code forces that (nil = GuardSpawnConf.DespawnDistance)

        -- innerPosts = 3,       -- optional: this yard's own inner grid (3 = 9 posts inside); nil = AutoPostInner

        ---o[ Hand-placed posts (optional) - uncomment to place guards yourself instead of the auto layout ]o---
        -- heading 0 = N, 90 = W, 180 = S, 270 = E. range = his fire range (nil = DefaultGuardRange).
        -- Optional per post: scenario = "WORLD_HUMAN_..." (always that), patrolPoints = { vector3, ... } (walks them).
        -- guardPosts = {
        --     { coords = vector3(-3111.24, -3553.12, 9.67), heading = 180.0, range = 22.0 },
        --     { coords = vector3(-3117.69, -3568.91, 11.07), heading =  90.0, range = 22.0 },
        --     { coords = vector3(-3137.49, -3580.61, 11.44), heading =   0.0, range = 22.0 },
        --     { coords = vector3(-3152.13, -3558.73, 11.98), heading = 270.0, range = 22.0 },
        -- },

        reinforceSpawns = { -- only with AtPostsOnly = false: where replacements walk in from
            vector3(-3180.15, -3546.72, 12.30),
            vector3(-3106.88, -3549.41, 9.40),
        },
    },
}

---o[ Yard Guards ]o---
Config.GuardSpawnConf = {
    Enabled = true, -- false: no guards anywhere (restart after changing)

    ---o[ The guard ]o---
    PedModel          = "re_fleeingfamily_males_01",
    Weapons           = "weapon_rifle_springfield",
    AmmoCount         = 200,                  -- rounds each guard carries (0 = can never fire back)
    Accuracy          = 90,                   -- 0-100, never above MaxAccuracy
    MaxAccuracy       = 90,                   -- cap on Accuracy and on every wave's bonus (always applies)
    RelationshipGroup = "REL_GANG_ODRISCOLL",
    AlertBlipName     = "blip_ambient_bounty_hunter",
    AlertCoolDown     = 10000,                -- ms between alarms

    ---o[ Spawning - a yard's own spawnDistance / despawnDistance win over these ]o---
    SpawnDistance       = 200.0, -- metres from the yard centre: guards appear
    DespawnDistance     = 260.0, -- metres: guards removed (keep 20+ above SpawnDistance)
    DespawnGraceSeconds = 10,    -- player must stay out this long first (sec)
    AtPostsOnly         = true,  -- every guard appears on his own post, all at once, and stands there
    AlwaysStaffed       = true,  -- no empty yard: a killed guard is back after RespawnSeconds, and once
                                 -- nobody is within despawnDistance the whole shift is back on duty
    RespawnSeconds      = 120,   -- a killed guard is back on his post after this (sec)
    BodyCleanupSeconds  = 45,    -- a body is removed after this (sec)

    ---o[ Auto posts - every yard that has no guardPosts of its own ]o---
    AutoPosts       = true, -- false: a yard without guardPosts gets no guards
    AutoPostLayout  = 8,    -- fence posts: 4 = middle of each side, 8 = sides + corners (all face the middle)
    AutoPostMargin  = 4.0,  -- metres outside the boundary for the fence posts
    AutoPostInner   = 2,    -- inside the yard: an N x N grid facing the middle (2 = 4 posts, 3 = 9, 0 = none).
                            -- Keep the gap between posts under Detection.SightRange: gap = size x 2 / N
    GuardsPerZone   = 0,    -- auto posts only: men on duty (0 = every post manned; fewer = random posts each shift)

    ---o[ What makes them open fire - as soon as a guard sees or hears it ]o---
    -- false = it only makes the yard suspicious (Suspicion below). Shooting a guard always starts a fight.
    FireOn = {
        Running      = true,   -- running or sprinting (Shift) in the yard
        Jumping      = true,   -- jumping in the yard
        Gunshot      = true,   -- a shot fired in the yard
        AimAtGuard   = true,   -- a gun pointed at a guard for AimAtGuardSeconds
        SeenClimbing = true,   -- seen on a tree trunk (not once he is up in the canopy)
        SeenArmed    = true,   -- seen with a gun drawn
        SeenUpright  = true,   -- seen in the yard NOT crouched (walking or standing): only sneaking is safe
        Falling      = true,   -- coming out of a tree
        TooClose     = "fire", -- inside a guard's range: "fire" = shoot, "warn" = gunpoint first (Warning), false = ignore
    },

    AimAtGuardSeconds        = 0.5,  -- how long a gun must be on a guard
    DefaultGuardRange        = 25.0, -- metres: a post's range when it sets none (every auto post uses this)
    RangeGraceSeconds        = 1,    -- seconds inside a range before he fires
    RangeCrouchMultiplier    = 0.5,  -- [crouch] a crouched player must get this much closer
    RangeRequiresLineOfSight = true, -- false = fires through walls. Leave true.
    LoudMovementNeedsWitness = true, -- running / jumping only count if a guard saw or heard it
    SprintKeyIsLoud          = true, -- false: only the actual running gait counts, not Shift
    CrouchWalkUndetected     = true, -- crouched, no sprint, no jump: not seen, heard or "too close" - the one safe way in.
                                     -- While true, the settings marked [crouch] only matter for a crouched player who
                                     -- is also noisy (running, jumping, falling, shooting) or already in a fight.
    LawmenIgnored            = true, -- lawmen are never treated as trespassers
    CalmDownTime             = 30000, -- ms guards keep fighting after the last trespass

    ---o[ Falling out of a tree ]o---
    FallingIsLoud   = true, -- false: a fall is not noticed at all
    FallMinHeight   = 2.5,  -- metres above ground before it counts as a fall
    FallLoudSeconds = 5,    -- how long a fall keeps the yard alert (sec)

    ---o[ Standing guard ]o---
    Duty = {
        IdleScenarios     = {         -- what a guard does on his post (one picked at random)
            "WORLD_HUMAN_GUARD_LAZY",
            "WORLD_HUMAN_GUARD_SCOUT",
            "WORLD_HUMAN_GUARD_MILITARY",
            "WORLD_HUMAN_SMOKE",
            "WORLD_HUMAN_WAITING_IMPATIENT",
            "WORLD_HUMAN_WRITE_NOTEBOOK",
        },
        IdleChangeSeconds = { 30, 60 }, -- min, max seconds before changing what he does
        IdleLookSwing     = 50.0,       -- degrees either side of the post heading he may face
        IdleLeashDistance = 4.0,        -- metres: pushed further off his post, he walks back
        IdleShare         = 0.5,        -- only with AtPostsOnly = false: share that stands (rest patrol)
    },

    ---o[ Notifications ]o---
    Notify = {
        EnterCooldownSeconds = 60, -- "you are in the yard" not repeated within this (sec)
        NoiseCooldownSeconds = 10, -- "you are making noise" not repeated within this (sec)
    },

    ---o[ Sheriff dispatch ]o---
    LawDispatch = {
        OnLoudMovement = true,   -- loud movement in a yard alerts the Sheriff job
        RepeatSeconds  = 30,     -- marker moves to the player at most this often (sec)
        UpdateNotify   = false,  -- false: marker moves silently after the first alert
        MarkerSeconds  = 90,     -- how long the blip stays (sec)
        ClearWithin    = 15.0,   -- metres: ...or until the lawman gets this close
        Waypoint       = true,   -- false: blip only, no GPS route
        RouteColour    = "COLOR_RED",
        BlipName       = "Trespasser",
        BlipColour     = "BLIP_MODIFIER_MP_COLOR_8", -- red
    },

    ---o[ ADVANCED - suspicion: what is not in FireOn makes the yard look and search ]o---
    Suspicion = {
        Enabled        = true,
        Max            = 100.0,
        DecayPerSecond = 3.0,   -- falls by this per second when nothing feeds it

        ---o[ Gained per second ]o---
        SeenWalking     = 10.0, -- only matters with FireOn.SeenUpright = false
        SeenRunning     = 18.0,
        HeardRunning    = 9.0,
        Jumping         = 12.0,
        Falling         = 7.0,
        SeenArmed       = 10.0,
        SeenClimbing    = 20.0,
        DistantNoise    = 3.0,  -- noise no guard saw or heard
        PerExtraWitness = 0.45, -- each extra guard watching adds this share

        ---o[ Levels ]o---
        Notice              = 25.0, -- nearest guard comes to look
        Investigate         = 50.0, -- the yard searches
        Hostile             = 75.0, -- guns out, Sheriff called
        PassiveCeiling      = 62.0, -- just being seen can't push it past this
        HostileGraceSeconds = 20,   -- stays hostile until below Hostile this long (sec)
        CrouchMultiplier    = 0.5,  -- [crouch] crouching slows the build-up

        ---o[ Settling down ]o---
        LevelDropMargin     = 8.0,  -- must fall this far below a level to drop it
        LevelMinSeconds     = 3,    -- a level is held at least this long (sec)
        NoticeInvestigators = 1,    -- men who come to look at Notice
    },

    ---o[ ADVANCED - warning (only with FireOn.TooClose = "warn") ]o---
    Warning = {
        Enabled              = true,
        Seconds              = 5,    -- seconds to back off
        ComplyDistanceFactor = 1.25, -- back off past range x this to comply
        MemorySeconds        = 90,   -- caught again within this = no second warning
        AdvanceTolerance     = 2.5,  -- metres closer that still is not "advancing"
        DeeperTolerance      = 3.0,  -- metres deeper into the yard that still is not "pushing in"
    },

    ---o[ ADVANCED - stealth: the quiet way through ]o---
    Stealth = {
        Enabled = true,

        ---o[ Freezing (crouched and still) ]o---
        StillRangeMultiplier = 0.55, -- [crouch] detection ranges x this
        StillDecayMultiplier = 2.0,  -- suspicion falls this much faster
        StillSpeed           = 0.15, -- m/s that counts as still

        ---o[ Up in the canopy ]o---
        ConcealHeightSteps     = 1.5, -- above this many climb steps guards can't see you...
        ConcealLookUpRange     = 8.0, -- ...unless one is this close (metres)
        ConcealDecayMultiplier = 2.5, -- suspicion falls this much faster up there

        ---o[ Patience ]o---
        RangeSparesCrouched     = true, -- [crouch] crouched players in range build suspicion instead of being shot
        RangeSuspicionPerSecond = 22.0, -- [crouch] suspicion per second while spared
    },

    ---o[ ADVANCED - detection: sight and hearing ]o---
    Detection = {
        SightRange         = 50.0,  -- metres
        FOV                = 140.0, -- field of view (degrees)
        HearRangeWalking   = 14.0,  -- metres
        HearRangeRunning   = 35.0,  -- metres (jumping and falling too)
        HearRangeGunshot   = 120.0, -- metres
        CrouchMultiplier   = 0.45,  -- [crouch] crouching cuts sight and hearing ranges
        NightMultiplier    = 0.7,   -- ranges at night
        NightStartHour     = 20,
        NightEndHour       = 6,
        InvestigateSeconds = 15,    -- how long he checks out what he noticed
        SearchSeconds      = 25,    -- how long he searches after losing you
        LoseTargetSeconds  = 10,    -- out of sight this long in combat -> search
        BodyDiscoveryRange = 20.0,  -- metres: finding a body puts the yard on edge
        WarnCooldown       = 8000,  -- ms before the same guard message shows again
    },

    ---o[ ADVANCED - territory: guards stay at the yard in a fight ]o---
    Territory = {
        Enabled              = true,
        LeashMargin          = 30.0, -- metres outside the boundary a guard may go
        HoldShare            = 0.5,  -- share who hold their posts in a fight (the yard stays covered)
        HoldRadius           = 10.0, -- metres a holder may move off his post
        HoldFireRange        = 60.0, -- metres: holders still fire at players within this
        SearchParty          = 3,    -- men sent to search
        StrayTeleportSeconds = 20,   -- lost and unseen this long -> back on his post

        ---o[ Only with AtPostsOnly = false ]o---
        SpawnUnnoticedDistance = 90.0, -- metres: further than this he can appear on his post
        SpawnMinPlayerDistance = 25.0, -- metres: never closer than this to a player
        MaxSpawnWaitSeconds    = 10,   -- after this he walks in from the furthest point
    },

    ---o[ ONLY WITH AtPostsOnly = false - patrols and walking in ]o---
    SpawnPerPass    = 1,     -- guards created per pass
    SpawnOutOfSight = true,  -- never create a guard in view: wait, or walk him in
    PatrolMargin             = 8.0,   -- metres outside the yard boundary
    PatrolPointsPerSide      = 3,     -- stops along each side
    PatrolSpeed              = 1.0,   -- 1.0 = walk, 2.0 = run
    PatrolPauseSeconds       = 6,     -- pause at each stop (sec)
    PatrolReachDistance      = 4.0,   -- metres: counts as arrived
    PatrolStuckSeconds       = 35,    -- give up on an unreachable stop (sec)
    PatrolAlternateDirection = false, -- true: every other man walks the other way

    ---o[ ONLY WITH AlwaysStaffed = false - waves and empty yards ]o---
    WaveDelaySeconds       = 300, -- whole yard wiped: next shift after this (sec)
    BrokenAlarmRushSeconds = 60,  -- alarm in an empty yard pulls the next shift in to this (0 = off)
    MaxWaves               = 3,   -- shifts sent before the yard is left alone
    ClearedMinutes         = 30,  -- how long a fully cleared yard stays empty
    WaveAccuracyBonus      = 8,   -- each new shift shoots this much better (up to MaxAccuracy, set with Accuracy above)
    WaveExtraGuards        = 0,   -- extra men each new shift brings
    MaxExtraGuards         = 3,
}
