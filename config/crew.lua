---o[ Cooking Crew ]o---
Config.BarrelCrew = {
    Enabled               = true, -- false: no crew, every barrel open to everyone
    CrewOnly              = true, -- true: only owner + crew can work a barrel

    MaxCrew               = 3,    -- helpers, not counting the owner
    InviteRadius          = 6.0,  -- metres: invited player must be this close to the barrel
    InviteTimeoutSeconds  = 30,   -- seconds to answer an invite
    InviteCooldownSeconds = 5,    -- seconds between invites, per owner

    ---o[ What a crew member may do ]o---
    CrewCan = {
        fuel        = true, -- put wood on
        cool        = true, -- pour water
        vent        = true, -- vent pressure
        ingredients = true, -- open the barrel stash
        mix         = true, -- start mixing from the recipe book
        cuts        = true, -- start / stop keeping during the drip
        pour        = true, -- pour the batch out before the law arrives
        fix         = true, -- deal with trouble at the still
        bottle      = true, -- bottle the batch (bottles go to whoever draws them)
        scrub       = true, -- scrub the barrel
        repair      = true, -- repair the barrel
    },
}

---o[ Stealing From A Still ]o---
Config.BarrelTheft = {
    Enabled         = true,

    WatchedBlocks   = true, -- no stealing while the owner or crew is at the barrel
    CooldownSeconds = 30,   -- seconds between attempts, per thief
    AlertOwner      = true, -- tell owner + crew about attempts and thefts
    MinSeconds      = 2, -- a theft or spike won sooner than this after it started is not a real game: counted as failed

    Minigame        = { type = "bar", rounds = 3, zone = 0.14, speed = 1.1, shrink = 0.85, speedUp = 1.12,
        strikes = 1, time = 10 },
    Scenario        = "WORLD_HUMAN_CROUCH_INSPECT", -- played during the minigame (nil = none)

    ---o[ Spiking a fermenting wash ]o---
    SpikeEnabled    = true,
    SpikeMinutes    = 6,    -- minutes taken off the time before it turns and spoils
    SpikeMaxPerBatch = 1,   -- spikes one wash can take; after that it can't be spiked again (0 = no limit)
    SpikeMinigame   = { type = "sequence", length = 6, keys = { "W", "A", "S", "D" }, strikes = 1, time = 6 },
}
