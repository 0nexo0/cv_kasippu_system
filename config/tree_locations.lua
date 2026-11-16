---o[ Climbable Trees ]o---
-- One line per tree. heading = which way it faces, persist = saved to the database
Config.ClimbTrees = {
    -- { coords = vector3(-3122.78, -3591.33, 8.85),  heading = 45.0, persist = true },
    -- { coords = vector3(-3109.33, -3575.69, 8.25),  heading = 45.0, persist = true },
    -- { coords = vector3(-3114.8, -3553.09, 8.9),    heading = 45.0, persist = true },
    -- { coords = vector3(-3129.34, -3563.01, 9.68),  heading = 45.0, persist = true },
    -- { coords = vector3(-3151.1, -3576.39, 9.48),   heading = 45.0, persist = true },
    -- { coords = vector3(-3167.94, -3577.89, 7.88),  heading = 45.0, persist = true },
    -- { coords = vector3(-3173.32, -3559.69, 9.12),  heading = 45.0, persist = true },
    -- { coords = vector3(-3170.48, -3547.58, 9.84),  heading = 45.0, persist = true },
    -- { coords = vector3(-3158.36, -3551.5, 8.98),   heading = 45.0, persist = true },
    -- { coords = vector3(-3144.78, -3556.07, 8.77),  heading = 45.0, persist = true },
    -- { coords = vector3(-3125.35, -3576.12, 10.81), heading = 45.0, persist = true },
    -- { coords = vector3(-3137.35, -3569.24, 9.98),  heading = 45.0, persist = true },
    -- { coords = vector3(-3131.55, -3548.19, 8.33),  heading = 45.0, persist = true },
    -- { coords = vector3(-3146.69, -3535.05, 7.6),   heading = 45.0, persist = true },
    -- { coords = vector3(-3125.82, -3534.29, 6.26),  heading = 45.0, persist = true },
    -- { coords = vector3(-3104.31, -3549.07, 6.34),  heading = 45.0, persist = true },
    -- { coords = vector3(-3144.1, -3589.84, 8.09),   heading = 45.0, persist = true },
    -- { coords = vector3(-3155.29, -3565.91, 8.98),  heading = 45.0, persist = true },
    -- { coords = vector3(-3164.48, -3535.38, 7.58),  heading = 45.0, persist = true },
    -- { coords = vector3(-3103.06, -3563.58, 7.28),  heading = 45.0, persist = true },
    -- { coords = vector3(-3118.33, -3565.37, 8.92),  heading = 45.0, persist = true },
}

---o[ Tree Settings ]o---
Config.AutoSaveConfigTrees = true -- save the trees above to the database on first run
Config.DebugTreeCommands   = true -- tree admin commands on (false before launch)

---o[ Tree Admins - who may delete trees ]o---
Config.TreeAdmin = {
    Ace               = "gsc_kasippu.treeadmin", -- server.cfg: add_ace group.admin gsc_kasippu.treeadmin allow
    Groups            = { "admin" },             -- VORP account or character groups
    MaxDeleteDistance = 10.0,                    -- metres from the tree; /removetree looks within 5
    AddCommand        = "addtree",               -- /addtree [heading]: saves a tree where you stand, straight to gsc_climb_trees
    MinTreeSpacing    = 2.0,                     -- metres: /addtree refuses a spot this close to another tree
}
