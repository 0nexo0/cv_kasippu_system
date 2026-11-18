---o[ Interaction Keys ]o---
Config.InteractKeys = {
    ---o[ At the barrel ]o---
    BarrelUIInteractingKey = 0xC7B5340A,         -- [Enter]       open the recipe book (invite crew from there)
    WoodFuelAddingKey      = 0xCEFD9220,         -- [E]           add wood | light fire | start / stop keeping | bottle
    FuelSelectLeftKey      = 0xA65EBAB4,         -- [Left Arrow]  pick which log E puts on
    FuelSelectRightKey     = 0xDEB34313,         -- [Right Arrow]
    WaterPouringKey        = 0x27D1C284,         -- [R]           pour water | top up the condenser
    IngredientsAddingKey   = 0x760A9C6F,         -- [G]           store ingredients
    BarrelVentKey          = 0x7F8D09B8,         -- [V]           vent pressure
    BarrelScrubKey         = 0x9959A6F0,         -- [C]           scrub the barrel
    BarrelRepairKey        = 0x8CC9CD42,         -- [X]           repair the barrel
    BarrelCrewLeaveKey     = 0xD8F73058,         -- [U]           owner: dismiss crew | crew: leave
    BarrelIncidentKey      = 0x9720FCEE,         -- [T]           deal with trouble at the still
    BarrelPourKey          = 0x05CA7C52,         -- [Down Arrow]  pour it all out before the law arrives
    BarrelSeizeKey         = 0x6319DB71,         -- [Up Arrow]    lawman: seize the still
    BarrelStealKey         = 0x4CC0E2FE,         -- [B]           stranger: steal a bottle | spike the wash
    BarrelPickupKey        = 0x156F7119,         -- [Backspace]   owner: pick up an idle, cold, empty barrel
    BarrelTarpKey          = 0x24978A28,         -- [H]           rig / take down the tarp

    ---o[ Answering a crew invite ]o---
    CrewInviteAcceptKey    = 0x760A9C6F,         -- [G]
    CrewInviteDeclineKey   = 0x156F7119,         -- [Backspace]

    ---o[ At the aging crate ]o---
    CrateStoreKey          = 0x760A9C6F,         -- [G]           lay down a bottle
    CrateTakeKey           = 0xCEFD9220,         -- [E]           take a bottle out
    CrateTendKey           = 0x9720FCEE,         -- [T]           tend / answer a hazard
    CratePickupKey         = 0x4CC0E2FE,         -- [B]           pick up the crate
    CrateLockKey           = 0xD8F73058,         -- [U]           lock / unlock, or pick the lock
    CrateSelectLeftKey     = 0xA65EBAB4,         -- [Left Arrow]  choose which bottle
    CrateSelectRightKey    = 0xDEB34313,         -- [Right Arrow]

    ---o[ At a buyer ]o---
    BuyerTalkKey           = 0x760A9C6F,         -- [G]           talk to the buyer: open his ledger

    ---o[ Placing a barrel ]o---
    KasiyaBarrelPlacmenteKey       = 0xC7B5340A, -- [Enter]       place
    KasiyaBarrelPlacementCanselKey = 0x156F7119, -- [Backspace]   cancel
    KasiyaBarrelRotateRightKey     = 0x27D1C284, -- [R]           rotate right
    KasiyaBarrelRotateLeftKey      = 0xCEFD9220, -- [E]           rotate left

    ---o[ Palm trees ]o---
    TreeClimbKey           = 0xD9D0E1C0,         -- [Space]       hold to climb up / climb down
    TreeSearchKey          = 0x760A9C6F,         -- [G]           search the crown
    TreeCoconutCollectKey  = 0xE30CD707,         -- [R]           collect coconut flower sap

    ---o[ The Kasippu radial menu ]o---
    RadialMenuKey          = 0x3C0A40F2,         -- [F6]          opens the menu only with Config.Radial.KeyMapping = nil (else F2 does)
}

---o[ The Kasippu radial menu ]o---
Config.Radial = {
    Enabled        = true,
    KeyMapping     = "F2", -- keyboard key that opens it at a still / crate / buyer
    Command        = "kasippu", -- chat command that opens it too (the key mapping needs a command: "kasippu" if nil)
    Size           = 375,       -- menu size on screen (px)
    CancelDistance = 1.0,       -- metres: moving this far breaks off a timed pick (seize, pour, pick up)
    HoldScenario   = "WORLD_HUMAN_CROUCH_INSPECT", -- played during a timed pick (nil = none)
    Sound          = false,      -- a soft tick as the pick moves from wedge to wedge
    ShowHint       = true,      -- the "F2  Kasippu Menu" tag, shown only while at a still / crate / buyer (false = none)

    ---o[ Where the menu is used ]o---
    Places = {
        barrel = true,  -- the still
        crate  = true,  -- the aging crate (the arrows to look at a bottle stay)
        buyer  = true,  -- the buyers
        station = true, -- the Water Barrel / Log Rack beside a still
        tree   = false, -- the coconut tree: climb, search, collect stay on their keys
    },
}

---o[ UI guard ]o---
Config.UiGuard = {
    Enabled      = true,
    ResetCommand = "kasippuui", -- chat command: closes every Kasippu screen and frees the mouse / keys (nil = none)
    LostFocusMs  = 1000,        -- ms a screen may stay up without the keys (another UI took them) before it is closed
}
