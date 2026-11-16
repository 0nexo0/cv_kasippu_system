---o[ Tasting - sample a bottle to learn what is really in it ]o---
-- Use a Tasting Cup (Config.Items.TastingCup) from the satchel, pick a bottle, and play the
-- nose-and-palate minigame. A good reading writes the bottle's true grade, its notes and its
-- flaws onto it for good. The bottle stays: it is only a sip.
Config.Tasting = {
    Enabled      = true,  -- false: no tasting; bottles show their grade as before
    HideUntasted = true,  -- true: new bottles read "untasted" (grade and taint hidden) until someone tastes them
    ConsumeCup   = false, -- true: the cup is used up by each tasting

    RetrySeconds = 20,    -- after a muddled reading, wait this long before the next try (sec)
    MinSeconds   = 5,     -- a result sooner than this is not a real tasting: it counts as muddled

    ---o[ How much a reading reveals (accuracy 0 - 1 from the minigame) ]o---
    MuddledBelow = 0.35,  -- below this: nothing learned, the bottle is untouched
    FullFrom     = 0.75,  -- from this: everything (grade, the heat score, every note and flaw)
                          -- in between: the grade, the main note and the worst flaw

    ---o[ What counts as a flaw ]o---
    MustyResidue = 25,    -- barrel fouling (FOUL) at bottling above this: "musty"
    StaleFrom    = 0.3,   -- fruit staleness (0 fresh - 1 stale) above this: "stale fruit"
    CleanFrom    = 80,    -- a heat score (0 - 100) of this or more, with a clean cut: "clean"

    PickerMax    = 12,    -- most bottles listed in the picker
    CardSeconds  = 10,    -- how long the tasting-notes card stays up (sec)

    ---o[ The minigame: nose (hold Space and let go in the band), then palate (3 keys in time) ]o---
    Minigame = {
        type = "taste", hint = "taste",
        time       = 16,   -- seconds for the whole tasting
        noseRise   = 0.45, -- breath meter rise per second while Space is held (0 - 1)
        noseBand   = 0.18, -- width of the sweet spot
        palateKeys = { "W", "A", "S", "D" }, -- letters the flavours light up
        palateWindow = 0.9, -- seconds each flavour can be caught
        nose       = 0.4,  -- share of the accuracy from the nose (the palate gives the rest)
        tint       = "#d9d0b4", -- colour of a fresh spirit in the glass
        agedTint   = "#b8742a", -- and of one aged in a crate
    },
}
