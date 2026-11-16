---o[ Player Text ]o---
-- Every message a player reads. %s = text, %d = number, %% = a % sign. Keep the % codes when rewording.
-- Plain text only: VORP notifications show colour codes (~r~) and emoji literally.
Config.Text = {
    ---o[ Placing and losing a barrel ]o---
    KasiyaBarrelPlacementHint    = "Use E/R to rotate, ENTER to place, BACKSPACE to cancel",
    KasiyaBarrelPlacementSuccess = "Kasiya Barrel Placement Successfully",
    KasiyaBarrelPlacementCansel  = "Kasiya Barrel Placement Cansel",
    BarrelTooClose               = "Too close to another barrel - give her some room.",
    BarrelLimitReached           = "You already have %d still set down. Pick it up before you place another.", -- MaxPerPlayer
    BarrelExploideNotify         = "CRITICAL FAILURE",
    BarrelEmpty                  = "The barrel is empty!",
    BarrelCleanNotify            = "Barrel cleaned. It looks like it can handle one more batch.",
    BarrelDetroyWarning          = "The barrel is falling apart! It will vanish in 10 seconds.",
    BarrelDestroyedNotify        = "Barrel Destroyed",
    RecipeDataLost               = "Error: Recipe data lost!",

    ---o[ The fire ]o---
    FuelAdded     = "%s on the fire - about %ds of burn in it.",           -- log, seconds
    FuelBoxFull   = "The fire box is full - let it burn down a little.",
    FuelNone      = "You don't have any %s.",                              -- log
    FireOut       = "The fire has burned out - put more on.",
    FireRainWarn  = "Rain is hitting the fire - it won't last long out in this.",
    FireRainedOut = "The rain has put the fire out!",
    FireGauge     = { Label = "FIRE", Out = "OUT", Rain = "Rain on the fire - get her under cover!",
        Smoke = { "Light smoke", "Smoke rising", "Heavy smoke - seen for miles" }, -- light / rising / heavy
        Holding = "Embers holding the heat - cools in %ds",   -- Cold stage, fire out, grace left (seconds)
        Cooling = "Cooling down - put more wood on!" },       -- Cold stage, grace over
    ColdCooling   = "Your still has gone cold - the barrel is losing its heat. Put more wood on.",

    ---o[ The tarp ]o---
    TarpRigged     = "Tarp rigged over the still - the rain can't get at the fire now.",
    TarpAlready    = "There's already a tarp over this still.",
    TarpNotAtStill = "Stand at your still to rig the tarp over it.",
    TarpNone       = "You don't have a still tarp to rig.",
    TarpNoRoom     = "No room in your satchel for the tarp.",
    TarpTakenDown  = "Tarp taken down and folded into your satchel.",
    TarpBook       = { Label = "Tarp", Up = "Rigged", Down = "None", Rig = "Rig Tarp", TakeDown = "Take Down" },

    ---o[ Water and cooling ]o---
    CoolingSysAddedWater     = "Added water. Heat dropped to: ",
    CoolingSysAlreadyCold    = "The barrel is already cold!",
    CoolingSysNotEnoughWater = "You need a bucket of water, ",
    BucketDescription        = "Water left: %d/%d uses.",                 -- uses left, uses in a full bucket

    ---o[ The condenser ]o---
    CondenserTopped = "Cold water in the condenser - %d%% full.",         -- level
    CondenserFull   = "The condenser is already full.",
    CondenserHot    = "The condenser is running hot - steam's escaping! Top it up (R).",
    CondenserCool   = "The condenser's cold again - no more steam.",
    CondenserLost   = "Steam carried off %d%% of the batch.",             -- percent
    CondenserGauge  = { Label = "COOLER", Hot = "Steam escaping - top up the condenser (R)!" },

    ---o[ Mixing and the mash ]o---
    MixingNotReady      = "The barrel is not ready for mixing yet!",
    RecipeUnknown       = "You need that recipe's card in your satchel to brew it.",
    MixingItemsMatched  = "Mixing a %s batch of %s.",                       -- batch name, product
    MashEmpty           = "The barrel is empty - put the ingredients in first (Store Ingredients).",
    MashNotForRecipe    = "Take out the %s - it doesn't go in %s.",          -- item, recipe
    MashNoWater         = "Add %s - one for every batch.",                   -- the batch ingredient
    MashTooMuchWater    = "Too much %s - %d at most (one per batch).",       -- the batch ingredient, max
    MashNeedMore        = "Add %d more %s - a %s batch needs %d.",           -- missing, ingredient, batch name, needed
    MashNeedSugar       = "Add sugar - it needs at least %d sugar per batch (the book shows what each counts as).",
    MashNeedCoconut     = "Bring %dml of coconut water in your satchel - you have %dml.",
    MashTooMuchFruit    = "Too much fruit - it will clog the barrel.",
    MashIngredientBonus = "Your ingredients and stirring: %+d to the score.",
    MashSpiritTooRough  = "Take out the %s - only Good or Perfect spirit is worth running again.", -- the bottle's name
    MashSpiritAged      = "Take out the %s - aged or turned spirit doesn't go back in the still.",
    BatchNames          = { "single", "double", "triple", "quadruple" },

    ---o[ Stirring ]o---
    StirTitle  = "Stir The Mash",
    StirGood   = "A good even stir - that will tell in the spirit.",
    StirBad    = "Lumpy mash. The batch will suffer a little for it.",
    StirRetry  = "Lumpy mash - stir it again. (%d more try)",          -- tries left
    StirMissed = "Nobody stirred the mash. The batch will suffer a little for it.",

    ---o[ Fermentation ]o---
    FermentStarted  = "The wash is set to ferment (%s spot). Light the fire under it once it's ready.", -- climate
    FermentReady    = "The wash is ready - light the fire and distil it.",
    FermentTurning  = "The wash is starting to turn - distil it soon or lose it!",
    FermentSpoiled  = "The wash turned to vinegar. The batch is lost.",
    FermentTooYoung = "The wash has barely started (%d%%). Give it time.",
    FermentLit      = "Fire lit under the wash - %d%% strength.",
    FermentWeak     = "A weak wash - this batch will make fewer bottles.",

    ---o[ Tend The Wash (the pot minigame while it ferments) ]o---
    TendWashTitle   = "Tend The Wash",
    TendWashGood    = "The wash took it well - folded smooth and settled. (+%d to the batch)",  -- bonus
    TendWashBad     = "Froth over the rim and lumps in the pot. The batch will suffer a little. (-%d)", -- penalty
    TendWashAlready = "This wash has already been tended.",
    TendWashBusy    = "Someone is already tending this wash.",
    TendWashNotYet  = "The wash hasn't started working yet. Give it a moment.",
    TendWashReverse = "Now the other way!",                     -- called out halfway, when the stir flips
    TendWashIngredients = { "Jaggery", "Yeast", "Palm Sap", "Coconut Water", "Treacle" }, -- what floats up
    TendWashLabels  = { mixed = "Mixed", froth = "Froth", speed = "Stir" }, -- the bars, and the spoon's speed gauge
    TendWashCall     = "Add the %s",                            -- spoon game: the wash calls for an ingredient
    TendWashTooFast  = "Too fast - it's frothing!",
    TendWashWrongWay = "Other way round!",
    TendWashSpoiled  = "Not that one!",                         -- the wrong ingredient went in
    TendWashLumps    = "Break up the lumps!",                   -- the stage waits on the lumps
    TendWashSmooth   = "Smooth",                                -- the streak tag: "Smooth x1.4"

    ---o[ Heat and the final push ]o---
    MixingFuelAddAgain = "DISTILLATION",
    QualityTracked     = "Stabilized: ",
    PushStarted        = "Hold her steady - watch the mark on the gauge.",
    PushFlare          = "The fire catches! Heat is climbing.",
    PushDraught        = "A draught gets under the still - she's losing heat.",
    PushGraded         = "Run finished. Batch graded: ",
    PushGradedCuts     = "Heat held at %d%% - %s so far. Now catch the spirit!", -- score, grade

    ---o[ Hold The Heat - the game (Config.HeatSkill.Game) ]o---
    PushGame = {
        Group       = "Hold The Heat",                          -- the prompt group's title
        Stoke       = "Stoke",                                  -- [E]
        Cool        = "Cool (hold)",                            -- [R]
        Vent        = "Vent",                                   -- [V]
        WarnFlare   = "Smoke's thickening - she's about to flare!",
        WarnDraught = "Wind's picking up - she'll lose heat!",
        RackEmpty   = "The log rack is bare - stoking with a whole log from your satchel.",
        NoWood      = "No logs on the rack or in your satchel to stoke with.",
        WaterEmpty  = "The water barrel has run dry.",
        NoWater     = "No water barrel and no bucket of water to cool her with.",
        Rekindled   = "You coax the fire back to life.",
        Gauge       = { Water = "WATER", Logs = "SPLITS", TapOn = "TAP OPEN" }, -- the gauge's two cores
        Open        = "Work The Fire",                          -- F2 wedge / prompt that opens the panel again

        ---o[ The Firebox panel (Config.HeatSkill.Game.Panel) ]o---
        Panel = {
            Title     = "Hold The Heat",
            Heat      = "HEAT",
            Quality   = "QUALITY",
            Rack      = "LOG RACK",
            Firebox   = "FIREBOX",
            Barrel    = "WATER BARREL",
            Pressure  = "PRESSURE",
            Splits    = "%d splits",                             -- splits left on the rack
            Litres    = "%d L",                                  -- litres left in the barrel
            Drag      = "Drag a split into the fire",
            Valve     = "Hold the valve to cool",
            Lever     = "PULL TO VENT",
            RackEmpty = "Rack bare - stack logs",
            NoRack    = "No log rack by the still",
            BarrelDry = "Dry - fill it",
            NoBarrel  = "No water barrel by the still",
            FireOut   = "Fire's out - a split relights it",
            Trouble   = "TROUBLE: %s - click (T)",               -- the incident's name
            Keys      = "Drag or SPACE stoke  ·  hold valve or S cool  ·  V vent  ·  T trouble  ·  ESC step back",
            Grades    = { "Normal", "Good", "Perfect" },         -- the stars: one, two, three
        },
    },

    ---o[ The Water Barrel and the Log Rack (Config.Stations) ]o---
    Stations = {
        WaterBarrel  = "Water Barrel",
        LogRack      = "Log Rack",
        PlaceHint    = "E / R turn · ENTER set it down · BACKSPACE put it away",
        Cancelled    = "You put it away.",
        Wet          = "This ground is too wet! Find dry land.",
        NotAtStill   = "Stand at your still to set it down.",
        NotYours     = "Only the still's owner or crew can set that down here.",
        TooFar       = "Too far from the still - set it down within %.0f m.",  -- metres
        TooClose     = "Too close to the still - give the fire some room.",
        Already      = "This still already has a %s.",                        -- the station's name
        Placed       = "%s set down beside the still.",
        ModelMissing = "That prop couldn't be loaded - tell an admin (Config.Models).",
        Fill         = "Fill Water Barrel",
        Stack        = "Stack Logs",
        PickUp       = "Pick Up %s",                                          -- the station's name
        Filled       = "Water barrel: %d / %d L.",                            -- now, capacity
        Full         = "The water barrel is full.",
        NoBucket     = "You need a bucket of water.",
        PourCancelled = "You stopped pouring - no water went in.",
        Stacked      = "Stacked %d logs - the rack holds %d / %d.",           -- added, now, capacity
        RackFull     = "The log rack is full.",
        NoLogs       = "You have no logs to stack.",
        PickedUp     = "%s picked up.",
        NoRoom       = "No room in your satchel.",
        NotNow       = "Not while she's holding the heat.",
        SetDown      = "Set Down %s",                                          -- the still's F2 wedge (the station's name)
        NeedRack     = "Set a Log Rack down by your still - the fire burns from it.",
        RackNoKind   = "No %s on your Log Rack - stack some.",                 -- the log's name
        NeedWater    = "Set a Water Barrel down by your still - she draws her water from it.",
        WaterLow     = "Not enough water in the water barrel - fill it (%d L left).", -- litres left
        Radial       = "Water & Logs",                                        -- its wedge in the F2 menu
        Prompts      = "Still Supplies",                                      -- its prompt group (key mode)
    },

    ---o[ The cuts ]o---
    Cuts = {
        Smell = { -- on the gauge, and said once as the drip changes
            heads  = "Sharp, like lamp oil - the heads. Don't keep this.",
            hearts = "Sweet and clean - the hearts. Keep this!",
            tails  = "Oily, like wet sacking - the tails. Stop keeping.",
        },
        Soon = { -- a little before it changes
            hearts = "Getting sweeter... nearly the good stuff.",
            tails  = "Starting to turn oily...",
        },
        DoStart            = "Start Keeping (E) once it smells sweet.",
        DoStop             = "Stop Keeping (E) before it turns oily.",
        Keeping            = "KEEPING",
        NotKeeping         = "SET ASIDE",
        Started            = "Jar under the spout - keeping it.",
        Stopped            = "Jar off the spout. That's your batch.",
        Graded             = "The cut is made. Batch graded: %s (%d%%).", -- grade, score
        Clean              = "A clean cut - nothing but hearts in the jar.",
        Tainted            = "The jar smells sharp - some heads got in. These bottles will make a man sick.",
        Oily               = "Too much of the oily tail in there - it cost you quality.",
        Short              = "You lost a good part of the hearts - fewer bottles.",
        TaintedDescription = " It has a sharp, lamp-oil smell to it.",
    },

    ---o[ Pressure ]o---
    PressureWarning       = "She's building pressure - vent her before she goes!",
    PressureVented        = "Vented. Pressure: ",
    PressureNothingToVent = "There's no pressure to let out.",
    PressureBurst         = "SHE BLEW - too much pressure!",

    ---o[ Condition, scrubbing and repair ]o---
    ConditionWarning   = "The staves are giving out - she needs repairing.",
    ConditionCapped    = "Too worn to do better than ",
    ConditionCollapsed = "The barrel falls apart. She's finished.",
    ResidueWarning     = "She's filthy inside - this batch will suffer for it.",
    ScrubDone          = "Scrubbed her out. Residue: ",
    ScrubNothingToDo   = "She's already clean.",
    ScrubNoItem        = "You need a bucket of water to scrub her out.",
    ScrubWrongStage    = "Let her cool and empty before you scrub.",
    RepairDone         = "Patched her up. Condition: ",
    RepairNotNeeded    = "She's in good order - nothing to mend.",
    RepairNoItem       = "You need a spare barrel kit to mend her.",

    ---o[ Trouble at the still (each incident's own words are in still.lua) ]o---
    IncidentFailed = "You botched it - have another go.",
    IncidentBusy   = "Somebody's already seeing to it.",
    IncidentGauge  = "TROUBLE",

    ---o[ Bottling ]o---
    CollectProdNotReady = "This batch isn't ready for bottling!",
    RequiredFillingItem = "You need an empty bottle, ",
    RemainingBottles    = "Bottled 1x %s. (%s remaining)",
    BottledAll          = "Bottled %dx %s. (%d left)",                       -- count, product, remaining
    BottledSpilled      = "Bottled %dx %s - %d spilled. (%d left)",          -- count, product, spilled, remaining
    BottlingAllSpilled  = "Every pour went over - %d bottles' worth spilled. (%d left)", -- spilled, remaining
    BottlingBusy        = "Someone is already bottling this batch.",
    BottlingTitle       = "Bottle The Batch",
    BottlingLabels      = { -- the bottling minigame's words
        fill = "Fill to the mark", cork = "Cork it", perfect = "Perfect pour", clean = "Corked",
        spill = "Spilled!", short = "Too slow - it dribbled", crooked = "Crooked - again!",
        knocked = "Knocked it over!", froth = "Froth", clear = "Clean Run", spilled = "%d Spilled",
    },

    ---o[ Bottle labels and descriptions ]o---
    ProductLabel           = "%s %s",                                         -- strength, recipe: "Strong Kassippu"
    BottleProof            = " %d proof.",                                    -- added to the description
    FreshPickedDescription = "Picked fresh. Best used within the hour.",
    BottleFreshDescription = "%s, %s grade. Fresh off the still.",            -- recipe, grade
    BottleAgedLabel        = "%s (%s)",                                       -- bottle, maturity
    BottleAgedDescription  = "%s, %s grade. Aged %d minutes in the crate: %s.",
    BottleSourLabel        = "%s (Turned)",
    BottleSourDescription  = "%s left too long in the crate. It has turned.",
    BottleUntastedDescription = "%s, untasted. Fresh off the still - sample it to know its grade.", -- recipe (Config.Tasting.HideUntasted)
    BottleAgedUntasted     = "%s, untasted. Aged %d minutes in the crate: %s.", -- recipe, minutes, maturity

    ---o[ Tasting (Config.Tasting) ]o---
    ---o[ The market - buyers and the ledger (Config.Market) ]o---
    Market = {
        Title      = "The Buyer's Ledger",
        Trust      = "Trust",
        Each       = "each",
        Total      = "Total",
        Left       = "He'll take %d more",            -- bottles of demand left
        Sell       = "Shake On It",
        Close      = "Esc to walk away",
        Sealed     = "Sold",                          -- the stamp on a done deal
        Appetite   = "Appetite",                      -- meter: what his next bottle fetches of full price
        OfferAll   = "Offer Everything",              -- fills every line up to what he'll take
        Clear      = "Clear The Table",               -- the same button once everything is offered
        All        = "All",                           -- per line: the whole stack
        Bottles    = "%d bottles",                    -- under a line: how many of it are offered
        Keys = { -- the key strip along the foot of the ledger
            Select = "Select",
            Amount = "Amount",
            All    = "All / None",
            Sell   = "Hold: Shake On It",
            Leave  = "Walk Away",
            Shift  = "Shift",
            Enter  = "Enter",
            Esc    = "Esc",
        },
        Rumour     = "Word is the travelling buyer is camped near %s.", -- camp name
        NoRumour   = "Nobody has seen the travelling buyer lately.",
        None       = "He looks over your satchel: nothing he wants.",
        Full       = "He has bought all he can for now. Come back later.",
        NothingSold = "No deal - those bottles aren't in your satchel any more.",
        Refuse     = "He won't deal with you. Word is your bottles make people sick.",
        Closed     = "He isn't dealing now. Come back between %02d:00 and %02d:00.", -- from, to
        Sold       = "Sold %d bottles for $%.2f.",    -- bottles, money
        Sick       = "Word came back: someone fell sick on a bottle you sold. Buyers trust you less.",
        Moved      = "The travelling buyer moved to %s.",
        AdminUsage = "Use: /kasippubuyer move",
        LawTip     = "Moonshine is being sold out in the open. Marked on your map.",
        LawTipTown = "Moonshine is being sold near %s. Marked on your map.", -- town
        LawBlip    = "Moonshine Sale",
        Tags = {
            Untasted = "untasted - he can't be sure",
            Tasted   = "tasted",
            Tainted  = "tainted",
            Soured   = "turned",
            Proof    = "%d proof",
            Aged     = "aged: %s",
        },
    },

    Tasting = {
        PickerTitle  = "Which bottle?",
        PickerHint   = "Click a bottle to sample it - Esc to put the cup away",
        PickerAged   = "aged: %s",               -- maturity
        PickerTaste  = "Take A Sip",             -- the button under the cup
        PickerKeys   = {                         -- the key strip along the foot of the cup
            Select = "Choose",
            Taste  = "Sip",
            Leave  = "Put The Cup Away",
            Enter  = "Enter",
            Esc    = "Esc",
        },
        NoneToTaste  = "You have no untasted bottles to sample.",
        NotThere     = "That bottle isn't in your satchel any more.",
        NoCup        = "You need a tasting cup.",
        Wait         = "Your palate needs a moment. Try again in %ds.",
        Muddled      = "A muddled reading - you can't make it out. Rinse and try again.",
        Done         = "Tasted: %s, %s grade.",  -- product, grade
        GameTitle    = "Taste The Spirit",
        NoseTitle    = "Nose",
        PalateTitle  = "Palate",
        NoseHint     = "Hold SPACE to breathe in slowly - let go in the gold",
        PalateHint   = "Press each letter as the flavour comes",
        Cough        = "Too deep - you cough!",
        Zones        = { "Front", "Body", "Finish" },
        CardTitle    = "Tasting Notes",
        CardScore    = "Heat held at %d",
        CardNotes    = "Notes",
        CardFlaws    = "Flaws",
        CardNone     = "nothing to fault",
        CardPartial  = "A quick taste - there may be more to it.",
        GameClear    = "A Clear Reading",
        GameMuddled  = "Muddled",
        Described    = "%s, %s grade. Tasted: %s.", -- product, grade, what was found
        DescribedFlaw = " Flaw: %s.",
        DescribedAged = " Aged to %s.",            -- maturity, after the tasting
        TastedNote   = "Tasted: %s.",              -- kept on the bottle for the crate's aged description
        Notes = {
            fruity = "fruity", silky = "silky, well stirred", bold = "bold, full strength", clean = "a clean cut",
            plain = "plain and honest", rich = "rich", sharp = "rough",
        },
        Flaws = {
            spiked = "spiked - it tastes of rot", thin = "thin - a weak wash", stale = "stale fruit",
            musty = "musty - a dirty barrel", harsh = "harsh - heads or tails kept", lumpy = "lumpy - poorly stirred",
            scorched = "scorched",
        },
    },

    ---o[ Picking up a barrel, upgrades, spent mash ]o---
    PickupDone        = "You take the barrel down and pack it up.",
    PickupNotEmpty    = "Empty her first - she has to be cold, idle and the stash empty.",
    PickupStash       = "Take everything out of the stash first.",
    PickupNoRoom      = "You can't carry the barrel kit.",
    KitLabel          = "Kasiya Barrel Kit (%d%% sound)",                     -- condition
    KitDescription    = "A still, packed up. Condition %d%%%s.",              -- condition, fittings
    KitFittings       = ", fitted with %s",                                   -- list of fittings
    UpgradeFitted     = "%s fitted to the still.",
    UpgradeAlready    = "This still already has %s fitted.",
    UpgradeNotAtStill = "Stand at your still to fit that.",
    SpentMashGot      = "%dx spent mash left in the barrel - you scoop it out.",
    SpentMashNoHorse  = "Your horse needs to be right beside you.",
    SpentMashFed      = "Your horse wolfs down the mash.",

    ---o[ Barrel stages - label on the gauge / book, hint = what to do now ]o---
    Stages = {
        IDLE       = { label = "Cold",               hint = "Pick the fuel (Left / Right) and put it on (E) to warm her up." },
        FREEZE     = { label = "Add Ingredients",    hint = "Store ingredients (G), then open the book (Enter) and start mixing." },
        MIXING     = { label = "Mixing",             hint = "Stirring the mash - give it a moment." },
        FERMENTING = { label = "Fermenting",         hint = "Let the wash work. Light the fire (E) once it's ready." },
        MID_CLIMB  = { label = "Heating Up",         hint = "Keep the fire fed - she's climbing to full heat." },
        HEAT_PAUSE = { label = "Coming To Heat",     hint = "Get ready - keep the pressure down with V." },
        FINAL_PUSH = { label = "Hold The Heat",      hint = "Keep the needle on the mark: stoke (E) lands late, hold R to cool. Watch for the warnings." },
        BREWING    = { label = "Catch The Spirit",   hint = "Heads first: Start Keeping (E) when it smells sweet, Stop before it turns oily. Keep the condenser topped up (R)." },
        COMPLETED  = { label = "Ready To Bottle",    hint = "Bring empty bottles and bottle it (E)." },
    },

    ---o[ Recipe book - the mash slip ]o---
    MashSlip = {
        Title        = "IN THE BARREL",
        Spirit       = "Spirit",
        SpiritText   = "%d bottles, %s",       -- count, average grade
        Batch        = "Batch",
        Strength     = "Strength",
        Fruit        = "Fruit",
        Freshness    = "Freshness",
        Coconut      = "Coconut water",
        Outcome      = "You'll get",
        OutcomeText  = "%d-%d bottles of %s",  -- fewest, most, product
        OutcomeNote  = "How many depends on how well you hold the heat.",
        FixTitle     = "TO FIX",
        Legend       = "Water = how much. Sugar = how strong. Fruit = how good.",
        FruitNone    = "None",
        FruitSome    = "Some (%+d)",
        FruitBest    = "Just right (%+d)",
        FruitTooMuch = "Too much! (%+d, clogs)",
        Fresh        = "Fresh",
        Aging        = "Getting old (%d)",
        Stale        = "Stale (%d)",
        Ready        = "Ready to mix",
    },

    ---o[ Recipe book - the receipt ]o---
    Receipt = {
        PerBatch     = "%d a batch",
        MlPerBatch   = "%dml a batch",
        UpToPerBatch = "up to %d a batch",
        CoconutWater = "Coconut Water",
        InSatchel    = "carried in your satchel",
        Sugar        = "Sugar",
        SugarWorth   = "%s %d",        -- item, the sugar it counts as
        SugarFor     = "%d %s",        -- sugar a batch, strength: "4 Strong"
        SugarExtra   = "+%d %s",       -- on top of the coconut water's own sugar
        Fruit        = "Fruit",
        FruitNote    = "optional - fresh is best",
        Spirit       = "Bottles of %s", -- the first-run recipe
        SpiritNote   = "%s or better",  -- the worst grade it takes
        NeedSugar    = "counts as %d sugar",
        NeedFruit    = "counts as fruit",
        Optional     = "if you like",
    },

    ---o[ Recipe book - the crew slip (owner only) ]o---
    CrewSlip = {
        Title       = "THE CREW",
        Count       = "%d of %d",     -- helpers in, helpers allowed
        NoCrew      = "Cooking alone.",
        Nearby      = "Standing by",
        NoOneNearby = "Nobody close enough to ask - they need to be standing by the barrel.",
        Invite      = "Ask",
        Asked       = "Asked",
        Full        = "The crew is full.",
    },

    ---o[ Cooking crew (%s = a player's name) ]o---
    CrewNoAccess        = "This isn't your still. Ask the owner to invite you.",
    CrewNotAllowed      = "The owner keeps that job for themselves.",
    CrewInviteNotThere  = "They aren't standing by the barrel any more - or someone else asked them first.",
    CrewFull            = "The crew is full.",
    CrewInviteWait      = "Wait a moment before inviting again.",
    CrewInviteSent      = "You asked %s to cook with you.",
    CrewInviteReceived  = "%s wants a hand at their still. Join or decline from the prompt.",
    CrewInviteExpired   = "The invite ran out.",
    CrewInviteNoAnswer  = "%s didn't answer your invite.",
    CrewInviteGone      = "That still is gone.",
    CrewDeclined        = "%s turned down your invite.",
    CrewJoined          = "You joined %s's crew.",
    CrewMemberJoined    = "%s joined your crew.",
    CrewDismissed       = "You sent your crew home.",
    CrewDismissedMember = "%s sent the crew home.",
    CrewLeft            = "You left the crew.",
    CrewMemberLeft      = "%s left your crew.",

    ---o[ Stealing and spiking ]o---
    TheftTitle        = "Steal A Bottle",                                    -- minigame heading
    TheftWatched      = "Not with them standing right there.",
    TheftCooldown     = "Lie low a moment - try again in %ds.",
    TheftNothing      = "There's nothing in there worth taking.",
    TheftNeedsBottle  = "You need an empty bottle to steal into.",
    TheftFailed       = "You fumbled it. Nothing taken.",
    TheftAttemptAlert = "Someone is at your still, trying to steal from it!",
    TheftStolenAlert  = "A bottle was stolen from your still! (%d left)",
    SpikeTitle        = "Spike The Wash",                                    -- minigame heading
    SpikeDone         = "Done. That wash won't keep long now.",
    SpikeAttemptAlert = "Someone is tampering with your wash!",
    SpikedAlert       = "Someone spiked your wash - it will turn sooner!",
    SpikeAlready      = "Someone's already been at this wash. It can't be spiked again.", -- SpikeMaxPerBatch

    ---o[ The law and the still ]o---
    LawTipTitle      = "DISPATCH",
    LawTipNotify     = "Smoke from a still has been reported. Marked on your map - search the area.",
    LawTipNotifyTown = "Smoke from a still has been reported near %s. Marked on your map.", -- town
    LookoutWarn      = "Lookout: the law is %dm from the still!",            -- metres
    LookoutNotice    = "Riders coming - looks like the law!",
    SeizeDone        = "Still seized. The batch is evidence now.",
    SeizeOwner       = "The law has seized your still!",
    SeizeNothing     = "Just an empty barrel - nothing here to take.",
    PourDone         = "Poured it all out - nothing left for the law to find.",
    PourNothing      = "There's nothing in her to pour out.",

    ---o[ Aging crate - placing and storing ]o---
    CratePlacementHint   = "Use E/R to rotate, ENTER to place, BACKSPACE to cancel",
    CratePlaced          = "Aging crate set down.",
    CratePlacementCancel = "Crate placement cancelled.",
    CratePlacementWet    = "This ground is too wet! Find dry land.",
    CrateTooClose        = "There's already a crate here.",
    CrateLimitReached    = "You already have %d aging crates set down. Pick one up before you place another.", -- MaxPerPlayer
    CrateStored          = "Laid down %s. (%d/%d in the crate)",
    CrateFull            = "The crate is full.",
    CrateNoBottle        = "You have no fresh bottles to lay down.",
    CrateEmpty           = "The crate is empty.",
    CrateTakenRaw        = "Took out %s - it hadn't aged yet.",
    CrateTakenAged       = "Took out %s.",
    CrateTakenSour       = "Took out %s - it has turned.",
    CrateNotYours        = "This isn't your crate.",
    CratePickupNotEmpty  = "Empty the crate before you pick it up.",
    CratePickedUp        = "Picked up the aging crate.",
    CratePocketsFull     = "You can't carry any more.",
    CrateBottleGone      = "That bottle isn't there any more.",

    ---o[ Aging crate - tending ]o---
    CrateTendDueAway   = "Your aging crate needs seeing to: %s",
    CrateTendNotDue    = "The bottles are settled. Leave them be for now.",
    CrateTendPassed    = "%s - the bottles are the better for it.",
    CrateTendFailed    = "You fumbled it. The bottles are none the better.",
    CrateTendMissed    = "Nobody saw to the crate - the bottles suffered for it.",
    CrateTendNeedsItem = "You need %s for that.",
    CrateTierReached   = "%d bottle(s) in the crate have come on to %s.",
    CrateSoured        = "%d bottle(s) in the crate have turned.",
    CrateRhythm        = " Rhythm x%.2f.",                                   -- added after a pass once a run is going

    ---o[ Aging crate - hazards ]o---
    CrateHazardAway   = "Trouble at your aging crate: %s",
    CrateHazardPassed = "%s - you saved the bottle.",
    CrateHazardFailed = "You botched it. The bottle took the worst of it.",
    CrateHazardBroke  = "The rats had a bottle over - a %s is lost.",

    ---o[ Aging crate - climate ]o---
    CrateClimate        = "%s cellar (%dC%s): ages x%.2f, keeps x%.2f.",    -- band, degrees, indoors, age rate, keep rate
    CrateClimateIndoors = ", indoors",

    ---o[ Aging crate - lock ]o---
    CrateIsLocked      = "The crate is locked.",
    CrateLocked        = "You lock the crate.",
    CrateUnlocked      = "You unlock the crate.",
    CratePickNeedsItem = "You need a %s to work this lock.",
    CratePickCooldown  = "Your hands are shaking. Try again in %ds.",
    CratePickSuccess   = "The lock gives. The crate is open.",
    CratePickFailed    = "The lock holds.",
    CratePickBroke     = "The lock holds - and your pick snaps.",
    CrateLockTampered  = "Someone is working the lock on your aging crate!",
    CrateLockPicked    = "The lock on your aging crate has been picked!",

    ---o[ Aging crate - owner map blip state ]o---
    CrateBlipStates = {
        ready   = "Ready",
        due     = "Needs Tending",
        turning = "Turning Soon",
        hazard  = "Trouble!",
    },

    ---o[ Aging crate - the card at the crate (nui) ]o---
    CrateGauge = {
        Title      = "AGING CRATE",
        Locked     = "LOCKED",
        Best       = "BEST",             -- over the richest tier in the crate
        Empty      = "EMPTY",
        EmptyHint  = "Lay a fresh bottle down and let the crate do its work.",
        Raw        = "Raw",              -- a bottle before its first tier
        Turned     = "Turned",
        Peak       = "At its best - take it before it turns",
        NextIn     = "%s in %s",         -- next tier, time
        NoFurther  = "Won't come on further",
        TurnsIn    = "Turns in %s",      -- time
        Turning    = "Turning! %s",      -- time
        Sour       = "Comes out as plain spirit",
        Aged       = "Down %d min",      -- minutes in the crate
        Care       = "Care %s",          -- the bottle's care, signed
        Cellar     = "%s cellar",        -- climate band
        Indoors    = "indoors",
        CareCore   = "CARE",             -- the four rings
        AgesCore   = "AGES",
        KeepsCore  = "KEEPS",
        RhythmCore = "RHYTHM",
        Shelf      = "SHELF LIFE",
        NextCheck  = "NEXT CHECK",
    },

    ---o[ Minigames ]o---
    MinigameHints = { -- line under the title, by minigame type or `hint`
        dial     = "SPACE as the mark passes the gilt arc",
        bar      = "SPACE as the mark crosses the gilt",
        pins     = "SPACE as each pin reaches the line",
        hold     = "Hold SPACE to raise it - keep it in the band",
        sequence = "Press the keys in order",
        reach    = "A / D to grab each hold as your hand swings over it",
        lid      = "Hold SPACE to lift - keep the lid in the band",
        pour     = "Hold SPACE to tip the bucket - keep the pour steady",
        fronds   = "Part the fronds - follow the arrows",
        stir     = "Hold SPACE to work the paddle - keep the stir even",
        pot      = "W A S D round the pot - fold in what floats up, don't let it froth over",
        spoon    = "Circle the spoon to stir - drag in each ingredient as it's called",
        taste    = "Nose it, then taste it - read the spirit",
        bottle   = "Hold SPACE to pour to the chalk - SPACE to cork",
    },
    MinigameBanners = {
        ready  = "Steady...",
        win    = "Well Done",
        lose   = "Botched",
        quit   = "Gave Up",
        giveUp = "ESC to give up",
        misses = "Misses",
    },
    ClimbGripTitle      = "Grip %d/%d",
    TreeSearchGameTitle = "Search The Crown",
    CoconutGameTitle    = "Pour Off The Water",

    ---o[ Climbing trees ]o---
    ClimbRopeRequiredNotify     = "You need a climbing rope to climb this tree!",
    ClimbPreparingNotify        = "Readying your rope...",
    ClimbCancelledNotify        = "You stepped away from the tree.",
    ClimbingUpNotify            = "Climbing: ",
    ReachedTopOfTreeNotify      = "You made it to the top!",
    ClimbCheckUnavailableNotify = "Could not get a grip. Climbing back down.",
    TreeFallNotify              = "You lost your grip!",
    TreeClimbingDownNotify      = "Descending...",
    TreeClimbDownSafeNotify     = "Safe on the ground.",

    ---o[ Searching the crown ]o---
    TreeItemsSearchSuccessNotify     = "You've got a good grip. Searching...",
    TreeItemsSearchStartNotify       = "Search the fronds carefully...",
    TreeItemsSearchFailNotify        = "You fumbled the branches and found nothing.",
    TreeItemsSearchPocketHeavyNotify = "Your pockets are too heavy!",
    TreeReGrowingNotify              = "This tree is bare... wait for it to regrow.",
    TreeLootCardTitle                = "FOUND",
    TreeLootCardEmpty                = "Nothing but leaves",

    ---o[ Coconut water ]o---
    CoconutBucketEmptyNotify          = "The bucket isn't full enough yet. Come back later.",
    CoconutPotRequiredNotify          = "You need an empty pot to collect coconut water!",
    CoconutCollectedNotify            = "You collected coconut water from the bucket!",
    CoconutCollectMinigameStartNotify = "Carefully collect the coconut water...",
    CoconutCollectFailNotify          = "You spilled the coconut water!",
    CoconutFillHudLabel               = "Coconut Water",
    CoconutFillHudReady               = "FULL",
    CoconutFillHudWaiting             = "checking bucket...",
    CoconutFillHudRegrowing           = "Regrowing",

    ---o[ Restricted yard ]o---
    ZoneEnterNotify         = "Restricted area: %s. Move quietly.",           -- yard name
    ZoneNoiseNotify         = "You are making noise.",
    ZoneNoiseNoGuardsNotify = "Keep it down. This is a restricted area.",

    ---o[ Guard reactions ]o---
    GuardAlarmNotify        = "The alarm is up at %s. The guards are hunting you.", -- yard name
    GuardBodyFoundNotify    = "A guard found a body. The yard is searching.",
    GuardHostileNotify      = "You have been spotted. The guards are opening fire!",
    GuardSpottedNotify      = "A guard has noticed you.",
    GuardSearchingNotify    = "The guards are searching for you.",
    GuardLostYouNotify      = "You have lost the guards.",
    GuardZoneClearedNotify  = "The yard is cleared. Every guard is down.",
    GuardWaveNotify         = "A fresh shift of guards has arrived.",
    GuardWarnNotify         = "A guard has his gun on you: \"Back off. You have %d seconds.\"", -- seconds
    GuardWarnCompliedNotify = "The guard lowers his gun and watches you go.",
    GuardWarnIgnoredNotify  = "You ignored the warning. The guards are opening fire!",
    GuardRewarnNotify       = "\"I warned you!\" The guards are opening fire!",
    GuardAimedNotify        = "You drew on a guard. The guards are opening fire!",

    ---o[ Admin commands (main.lua Config.Admin) ]o---
    AdminNoAccess     = "You can't use that command.",

    ---o[ Tree admin commands (tree_locations.lua) ]o---
    TreeAdminNoAccess = "You can't use that command.",
    TreeAddInGame     = "Use /addtree in game, standing where the tree should go.",
    TreeAddTooClose   = "There's already a tree %.1fm from here.",           -- distance
    TreeAddDone       = "Tree saved to the database: %s",                    -- tree uid

    ---o[ Admin give command (main.lua) ]o---
    GiveUsage       = "Usage: /%s <playerId> <recipe> <grade> [strength] [amount] [fresh|rested|mellow|fine|turned] [tainted]",
    GiveNoAccess    = "You can't use that command.",
    GiveBadPlayer   = "No player with id %s on a character.",
    GiveBadRecipe   = "Unknown recipe %s. Recipes: %s",
    GiveBadGrade    = "Unknown grade %s. Grades: %s",
    GiveBadStrength = "Unknown strength %s. Strengths: %s",
    GiveBadState    = "Unknown option %s. Use fresh, rested, mellow, fine, turned or tainted.",
    GiveNoCrate     = "Aged and turned bottles need the aging crate switched on (and a valid tier).",
    GiveCantCarry   = "They can't carry that many.",
    GiveDone        = "Gave %dx %s (%s) to player %s.",          -- amount, label, item, player id

    ---o[ Sheriff dispatch (yard trespass) ]o---
    LawDispatchTitle        = "DISPATCH",
    LawDispatchNotify       = "Trespasser at %s. Marked on your map.",         -- yard name
    LawDispatchUpdateNotify = "Trespasser still on the move at %s. Marker updated.",

    ---o[ Discord logs (staff only - Config.Logs) ]o---
    Logs = {
        Console      = "Server console",
        Offline      = "offline",
        Explosion    = "Still exploded",
        Abandoned    = "Abandoned stills / crates cleared",
        BottleStolen = "Bottle stolen from a still",
        WashSpiked   = "Wash spiked",
        CrateTaken   = "Bottle taken from someone else's crate",
        Seized       = "Still seized by the law",
        PouredOut    = "Batch poured out",
        LockPicked   = "Crate lock picked",
        LockBroke    = "Lock pick broke",
        LockFailed   = "Lock pick failed",
        Give         = "Admin give",
        TreeAdded    = "Tree added",
        TreeDeleted  = "Tree deleted",
        TreesCleared = "All trees cleared",
        Sale         = "Bottles sold to a buyer",
        Fields = {
            Who = "Who", Thief = "Thief", Lawman = "Lawman", Admin = "Admin", Target = "Given to",
            Still = "Still", Crate = "Crate", Owner = "Owner", Where = "Where", Cause = "Cause",
            Crew = "Crew", Left = "Bottles left", Item = "Item", Amount = "Amount", Details = "Details",
            Tree = "Tree", Count = "Trees removed", Told = "Keepers told",
            Buyer = "Buyer", Paid = "Paid", Bottles = "Bottles",
        },
        Causes = { pressure = "Pressure burst", heat = "Overheated", overfed = "Overfed fire in the final push" },
    },

    ---o[ The Kasippu radial menu (GSC.Radial) - the actions reuse the prompt labels below ]o---
    Radial = {
        Barrel    = "Still",                          -- wedge titles, when more than one place offers something
        Crate     = "Crate",
        Tree      = "Tree",
        Buyer     = "Buyer",
        Crew      = "Invite",
        TakeAll   = "Take Bottle",                    -- the crate's ring of bottles
        BottleTag = "%s (%s)",                        -- bottle name, its level ("Kassippu (Fine)")
        Gone      = "That can't be done now.",        -- picked, but the still / crate moved on while the menu was open
        Cancelled = "Stopped - you moved.",           -- a timed pick (seize, pour, pick up) broken off
        KeyBinding = "Kasippu: open the menu",          -- its name in Settings > Key Bindings (Config.Radial.KeyMapping)
        HintLabel = "Kasippu Menu",                     -- the tag beside the key, shown only at a still / crate / buyer
        MenuTitle = "Kasippu",                          -- the centre's top line when the wheel holds several places
        UiReset   = "Kasippu screens closed.",          -- after the reset command (Config.UiGuard.ResetCommand)
        MenuHint  = "Click · 1-9 · Scroll · Esc",       -- the centre's bottom line: how to use it
    },
}

---o[ Prompt Labels ]o---
Config.PromptsTxt = {
    ---o[ At the barrel ]o---
    BarrelUIPrompt           = "Open Kasiya Menu",
    WoodFuelAddingPrompt     = "Add Wood",
    FuelSelectPrompt         = "Fuel: %s",             -- the selected log
    WaterAddingPrompt        = "Pour Water",
    IngredientsAddingPrompt  = "Store Ingredients",
    CollectingProductsPrompt = "Brew Into The Bottle",
    BarrelVentPrompt         = "Vent Pressure",
    BarrelScrubPrompt        = "Scrub Barrel",
    BarrelRepairPrompt       = "Repair Barrel",
    BarrelCrewDismissPrompt  = "Dismiss Crew",
    BarrelCrewLeavePrompt    = "Leave Crew",
    BarrelStealPrompt        = "Steal A Bottle",
    BarrelSpikePrompt        = "Spike The Wash",       -- same prompt, at a fermenting barrel
    FermentLightPrompt       = "Light The Fire",       -- wood prompt at a fermenting barrel
    TendWashPrompt           = "Tend The Wash",        -- ingredients prompt [G] at a fermenting barrel
    CutStartPrompt           = "Start Keeping",        -- wood prompt during the drip
    CutStopPrompt            = "Stop Keeping",
    CondenserPrompt          = "Top Up Condenser",     -- water prompt during the drip
    SeizePrompt              = "Seize The Still",      -- lawman
    BarrelPickupPrompt       = "Pick Up Barrel",
    TarpRigPrompt            = "Rig Tarp",
    TarpTakeDownPrompt       = "Take Down Tarp",
    PourPrompt               = "Pour It Out",
    IncidentPrompt           = "Deal With It",         -- renamed to the incident's label

    ---o[ Crew invite ]o---
    CrewInviteTitle          = "Still Invite",         -- inviter's name and seconds left follow it
    CrewInviteAcceptPrompt   = "Join",
    CrewInviteDeclinePrompt  = "Decline",

    ---o[ At the aging crate (the tend prompt uses the activity's label) ]o---
    CratePromptTitle         = "Aging Crate",
    CrateStorePrompt         = "Lay Down A Bottle",
    CrateTakePrompt          = "Take Out A Bottle",
    CratePickupPrompt        = "Pick Up Crate",
    CrateSelectPrompt        = "Choose Bottle",
    BuyerTalkPrompt          = "Talk To The Buyer",
    CrateLockPrompt          = "Lock Crate",
    CrateUnlockPrompt        = "Unlock Crate",
    CratePickLockPrompt      = "Pick The Lock",
    CrateLockedTag           = " - Locked",            -- after the title while locked

    ---o[ Palm trees ]o---
    PlamTreeClimbPrompt      = "Climb Tree",
    TreeSearchPrompt         = "Search",
    TreeCollectPrompt        = "Collect Coconut Water",
    TreeClimbDownPrompt      = "Climb Down",
}
