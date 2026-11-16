---o[ The Market - buyers who pay for what you brew ]o---
-- Saloon back doors pay a steady, lower price. The travelling buyer pays more, but he moves
-- between hidden camps: ask at a saloon where he was last seen. Talk to either to open the
-- buyer's ledger, choose what to sell and how many, and shake on it.
--
-- Price of one bottle:
--   Base[recipe] x Strength x Grade x Aged x tasting x trust x the buyer's Rate x demand
-- Everything is worked out on the server; the ledger only shows it.
--
-- !! The coordinates below are PLACEHOLDERS near each town. Stand where you want a buyer, read
-- !! your position (e.g. a /coords command) and put it here before you go live.
Config.Market = {
    Enabled = true, -- false: no buyers anywhere

    ---o[ The buyers' NPC ]o---
    Model         = "re_fleeingfamily_males_01", -- ped model for every buyer (a buyer can set his own `model`)
    Scenario      = "WORLD_HUMAN_WRITE_NOTEBOOK", -- what he does while he waits (nil = just stands)
    SpawnDistance = 60.0, -- metres: he is only there for players this close
    TalkDistance  = 2.5,  -- metres: the Talk prompt shows this close
    SellDistance  = 4.0,  -- metres: the server only deals this close (a little slack over TalkDistance)
    SessionSeconds = 180, -- the ledger stays valid this long after it opens

    ---o[ Saloon back doors - always in the same place, a steady lower price ]o---
    -- hours = nil: any time; { from = 20, to = 4 } = only between those game hours
    Saloons = {
        { id = "valentine",   name = "Smithfield's back door", coords = vector3(-313.0, 812.0, 118.98), heading = 100.0 },
        { id = "rhodes",      name = "Rhodes saloon cellar",    coords = vector3(1340.0, -1374.0, 80.5),   heading = 350.0 },
        { id = "saintdenis",  name = "Bastille back alley",     coords = vector3(2633.0, -1225.0, 53.38),  heading = 180.0 },
        { id = "blackwater",  name = "Blackwater saloon yard",  coords = vector3(-814.0, -1318.0, 43.68),  heading = 90.0 },
    },
    SaloonRate = 0.8, -- saloons pay this share of the price

    ---o[ The travelling buyer - pays more, moves camp ]o---
    Traveller = {
        Enabled     = true,
        Name        = "The travelling buyer",
        Rate        = 1.15,             -- he pays this share of the price
        MoveMinutes = 45,               -- he moves to another camp this often (never the same one twice running)
        Hours       = { from = 18, to = 6 }, -- he only deals between these game hours (nil = any time)
        Camps = {                       -- name is what the saloons' rumour says
            { name = "Flatneck Station", coords = vector3(-337.0, -360.0, 88.0),  heading = 45.0 },
            { name = "Lagras",           coords = vector3(2120.0, -600.0, 42.0),  heading = 270.0 },
            { name = "Emerald Ranch",    coords = vector3(1420.0, 300.0, 89.0),   heading = 180.0 },
            { name = "Hanging Dog Ranch", coords = vector3(-2190.0, 720.0, 122.0), heading = 0.0 },
            { name = "Thieves Landing",  coords = vector3(-1400.0, -2300.0, 43.0), heading = 90.0 },
        },
    },

    ---o[ Map markers - saloons only (the traveller has to be found) ]o---
    Blips = { Enabled = true, Sprite = nil, Scale = 0.7, Name = "Moonshine Buyer" },

    ---o[ The price ]o---
    Base        = { kasippu = 6.0, raaa = 5.0 }, -- $ for one Regular, Good, fresh, tasted bottle (trust 50, Rate 1, first of the day). Keys = Config.Recipes keys
    DefaultBase = 4.0,  -- a recipe not listed above
    Strength    = { LIGHT = 0.8, REGULAR = 1.0, STRONG = 1.25 },   -- by strength key (the proof)
    Grade       = { NORMAL = 0.75, GOOD = 1.0, PERFECT = 1.4 },    -- by grade
    Aged        = { RESTED = 1.25, MELLOW = 1.5, FINE = 1.85 },    -- by aging tier (fresh = 1)

    ---o[ Tasting: a buyer pays for what he can be sure of ]o---
    UntastedAs       = "GOOD", -- an untasted bottle is priced as this grade, whatever it really is...
    UntastedRate     = 0.85,   -- ...and at this share, for the risk he takes
    TaintedKnownRate = 0.4,    -- a tasted bottle known to be tainted: he pays this share, no hard feelings
    SouredRate       = 0.15,   -- a bottle that turned in a crate (0 = he won't take them)

    ---o[ Demand - each buyer only takes so much; every bottle sold lowers his price a little ]o---
    Demand         = 48,   -- bottles each buyer takes per restock (all players together; 5 buyers = 480 an hour)
    RestockMinutes = 30,   -- his demand comes back after this long
    DemandDrop     = 0.01, -- each bottle he already bought this period lowers the price this share (floor at bottle 40)
    DemandFloor    = 0.6,  -- never below this share

    ---o[ Trust - one per character, kept in the database (gsc_kassippu_trust) ]o---
    Trust = {
        Start       = 50,  -- a new character's trust (0 - 100)
        RefuseBelow = 15,  -- below this, buyers won't deal with you
        LowRate     = 0.8, -- price share at trust 0...
        HighRate    = 1.2, -- ...and at trust 100 (in between: a straight line)
        PerSale     = 2,   -- an honest sale earns this
        DailyGain   = 10,  -- most trust honest sales can earn in one real day
        TaintedHit  = 8,   -- lost per untasted tainted bottle sold (the buyer finds out)
        SickDelay   = 180, -- seconds before word comes back that someone fell sick
        RecoverPerHour = 1, -- below Start, trust creeps back this much per real hour (so nobody is shut out for good)
    },

    ---o[ The law - a sale can be reported ]o---
    Law = {
        Enabled         = true, -- needs Config.Law.Enabled too, and a lawman on duty
        Chance          = 0.06, -- per sale, before the town / wilds / night factors of Config.Law.TipOff
        CooldownMinutes = 10,   -- one player's sales are not reported again within this
    },

    MaxLines = 20, -- most stacks one ledger lists and one sale takes
}
