local Distillery = GSC.module('Distillery')

---oo[ The Fire ]oo---
local BarrelFuelCount = {} -- [uid] = seconds of burn left
local BarrelFirePower = {}
local BarrelSoak = {}
local BarrelExposure = {}
local BarrelTarp = {}
local BarrelSmokeShown = {}
local BarrelFireOut = {}
local ColdGraceLeft

local DressingOf
local BarrelHeat = {}
local BarrelStage = {}
local BarrelLoaded = {}
local BarrelGracePeriodDone = {}
local BarrelQualityTrack = {}
local BarrelTargetQuality = {}
local BarrelOwner = {}
local BarrelBrewProgress = {}
local BarrelRemainingBottles = {}
local BarrelPositions = {}
local BarrelHeadings = {}
local BarrelUsageCount = {} -- Persistent during server session

---o[ Timed stages ]o---
local BarrelStageDeadline = {}

---oo[ The Graded Final Push ]oo---
local BarrelPushStart = {}
local BarrelScoreSum = {}
local BarrelScoreTicks = {}
local BarrelTargetHeat = {}
local BarrelNextEvent = {}
local BarrelPressure = {}      -- [uid] = 0..Config.Pressure.Max
local BarrelPressureWarned = {}

---oo[ Fermentation ]oo---
local BarrelFerment = {}
local FermentState

---oo[ The Batch ]oo---
local BarrelMix = {}

---oo[ Stirring and the Cuts ]oo---
local BarrelStirPending = {}
local BarrelStirSentAt = {}
local BarrelStirTries = {}
local BarrelTendPending = {}
local BarrelBottlePending = {}
local PushGame = {}
local TickPushGame

---o[ Hold The Heat as a game ]o---
local function PushGameOn()
    local game = Config.HeatSkill and Config.HeatSkill.Enabled and Config.HeatSkill.Game
    return (game and game.Enabled) and game or nil
end

local function PushState(uid)
    local st = PushGame[uid]
    if not st then
        st = { stokes = {}, taps = {}, stokeAt = {} }
        PushGame[uid] = st
    end
    return st
end
local BarrelsLoaded = false
local LastBarrelRequest = {}
local BarrelCut = {}
local BarrelCondenser = {}
local BarrelCondenserHot = {}

---oo[ Trouble At The Still ]oo---
local BarrelIncident = {}
local BarrelIncidentNext = {}

local function ActiveIncident(uid)
    local incident = BarrelIncident[uid]
    if not incident then return nil end
    for _, conf in ipairs((Config.Incidents or {}).List or {}) do
        if conf.key == incident.key then return conf end
    end
    return nil
end

---oo[ Second Runs ]oo---

local function RecipeOf(uid)
    return Config.Recipes[BarrelLoaded[uid] or ""]
end

local function IsSecondRun(uid)
    local recipe = RecipeOf(uid)
    return recipe ~= nil and recipe.secondRun == true
end

local function PushBand(uid)
    local recipe = RecipeOf(uid)
    return recipe and tonumber(recipe.pushBand) or 1.0
end

local function IncidentFactor(uid, field)
    local conf = ActiveIncident(uid)
    return conf and tonumber(conf[field]) or 1.0
end
local CutReading

---oo[ Condition and Fouling ]oo---
local BarrelCondition = {}       -- [uid] = 0..Config.BarrelCondition.Max
local BarrelResidue = {}
local BarrelConditionWarned = {}
local BarrelDoomed = {}
local BarrelRepairCount = {}

---o[ How many more repairs / batches a still has in her ]o---
local function RepairsLeft(uid)
    local max = tonumber(Config.BarrelCondition.MaxRepairs) or 0
    if max <= 0 then return nil end
    return math.max(0, max - (BarrelRepairCount[uid] or 0))
end

local function BatchesLeft(uid)
    local max = tonumber(Config.BarrelCondition.MaxBatches) or 0
    if max <= 0 then return nil end
    return math.max(0, max - (BarrelUsageCount[uid] or 0))
end

---oo[ Upgrades ]oo---
local BarrelUpgrades = {} -- [uid] = { [upgradeKey] = true }

local function UpgradeList()
    local conf = Config.Upgrades
    return (conf and conf.Enabled and conf.List) or {}
end

local function FittedUpgrades(uid)
    local fitted, list = {}, UpgradeList()
    for key in pairs(BarrelUpgrades[uid] or {}) do
        if list[key] then fitted[#fitted + 1] = list[key] end
    end
    return fitted
end

local function UpgradeSum(uid, field)
    local total = 0
    for _, up in ipairs(FittedUpgrades(uid)) do total = total + (tonumber(up[field]) or 0) end
    return total
end

local function UpgradeProduct(uid, field)
    local total = 1.0
    for _, up in ipairs(FittedUpgrades(uid)) do total = total * (tonumber(up[field]) or 1.0) end
    return total
end

local function UpgradeMin(uid, field, default)
    local best = default
    for _, up in ipairs(FittedUpgrades(uid)) do
        local v = tonumber(up[field])
        if v and v < best then best = v end
    end
    return best
end

local function UpgradeKeys(uid)
    local keys, list = {}, UpgradeList()
    for key in pairs(BarrelUpgrades[uid] or {}) do
        if list[key] then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

local function SetUpgrades(uid, keys)
    local list, set = UpgradeList(), {}
    for _, key in ipairs(type(keys) == 'table' and keys or {}) do
        if list[key] then set[key] = true end
    end
    BarrelUpgrades[uid] = next(set) and set or nil
end

---oo[ Heat Sync Subscriptions ]oo---
local BarrelWatchers = {} -- [uid] = { [src] = true }
local WatchedBarrel = {}

local function SetBarrelWatcher(src, uid)
    local previous = WatchedBarrel[src]

    if previous and BarrelWatchers[previous] then
        BarrelWatchers[previous][src] = nil
        if next(BarrelWatchers[previous]) == nil then
            BarrelWatchers[previous] = nil
        end
    end

    WatchedBarrel[src] = uid

    if uid then
        BarrelWatchers[uid] = BarrelWatchers[uid] or {}
        BarrelWatchers[uid][src] = true
    end
end

local function SyncBarrelHeat(uid, heat, progress, bottles)
    local watchers = BarrelWatchers[uid]
    if not watchers then return end

    local ticks = BarrelScoreTicks[uid] or 0
    local pushStart = BarrelPushStart[uid]

    local gauge = {
        pressure = BarrelPressure[uid] or 0.0,
        pressureWarn = UpgradeMin(uid, "warnAt", Config.Pressure.WarnAt),
        target = BarrelTargetHeat[uid],
        band = Config.HeatSkill.TargetHalfWidth * PushBand(uid),
        score = ticks > 0 and ((BarrelScoreSum[uid] or 0.0) / ticks) * 100.0 or nil,
        pushLeft = pushStart and math.max(0, Config.HeatSkill.PushSeconds - (os.time() - pushStart)) or nil,
    }

    if Config.BarrelCondition.Enabled then
        gauge.condition = BarrelCondition[uid] or Config.BarrelCondition.Max
        gauge.residue = BarrelResidue[uid] or 0.0
        gauge.conditionWarn = Config.BarrelCondition.WarnConditionAt
        gauge.repairsLeft = RepairsLeft(uid)
    end

    local fitted = UpgradeKeys(uid)
    gauge.fitted = fitted
    if #fitted > 0 then
        local names = {}
        for i, key in ipairs(fitted) do names[i] = UpgradeList()[key].label or key end
        gauge.upgrades = names
    end

    local trouble = ActiveIncident(uid)
    if trouble then
        gauge.incident = {
            key = trouble.key,
            label = trouble.label,
            due = trouble.due,
            left = math.max(0, BarrelIncident[uid].deadline - os.time()),
        }
    end

    ---o[ Hold The Heat ]o---
    local game = PushGameOn()
    if game and BarrelStage[uid] == Shared.BarrelStage.FINAL_PUSH then
        local st = PushGame[uid] or {}
        local stations = Config.Stations or {}
        local hasWater, hasRack = GSC.Stations.Has(uid, "water"), GSC.Stations.Has(uid, "rack")
        gauge.game = {
            water = hasWater and GSC.Stations.WaterLeft(uid) or nil,
            waterMax = hasWater and ((stations.WaterBarrel or {}).Capacity or 60) or nil,
            splits = hasRack and GSC.Stations.SplitsLeft(uid) or nil,
            splitsMax = hasRack and ((stations.LogRack or {}).Capacity or 12) * math.max(1, game.SplitsPerLog or 1) or nil,
            tap = st.taps ~= nil and next(st.taps) ~= nil,
            warn = st.warn,
        }
    end

    gauge.fire = {
        fuel = BarrelFuelCount[uid] or 0,
        max = Config.Fuel.MaxBurnSeconds,
        rain = (BarrelSoak[uid] or 0) > 0,
        smoke = BarrelSmokeShown[uid] or 0,
    }

    ---o[ Cold stage, fire out: the embers' countdown, then "cooling" ]o---
    local graceLeft = ColdGraceLeft(uid, os.time())
    if graceLeft and graceLeft > 0 then
        gauge.fire.coolIn = math.ceil(graceLeft)
    elseif graceLeft == 0 then
        gauge.fire.cooling = true
    end

    local mix = BarrelMix[uid]
    if mix then
        gauge.mix = {
            product = GSC.Mash.ProductLabel(BarrelLoaded[uid], mix.strength),
            batch = mix.batch or 1,
        }
    end

    if BarrelStage[uid] == Shared.BarrelStage.BREWING and Config.Cuts.Enabled then
        gauge.cut = CutReading(uid)
    end

    if BarrelStage[uid] == Shared.BarrelStage.BREWING and Config.Condenser.Enabled and BarrelCondenser[uid] then
        gauge.condenser = {
            level = BarrelCondenser[uid],
            hotBelow = Config.Condenser.HotBelow,
            hot = BarrelCondenserHot[uid] == true,
        }
    end

    if BarrelStage[uid] == Shared.BarrelStage.FERMENTING then
        local state = FermentState(uid, os.time())
        if state then
            gauge.ferment = {
                strength = state.strength,
                minStrength = Config.Fermentation.MinStrength,
                turning = state.turnIn <= 0,
                turnIn = math.max(0, state.turnIn),
                spoilIn = math.max(0, state.spoilIn),
                climate = state.band and state.band.label or nil,
                tended = (BarrelMix[uid] and BarrelMix[uid].tend ~= nil) or nil, -- the [G] prompt hides once done
            }
        end
    end

    for src in pairs(watchers) do
        TriggerClientEvent('gsc_kassippu:client:updateHeat', src, uid, heat, progress, bottles, gauge)
    end
end

---o[ Tell whoever is actually stood at the barrel ]o---
local function NotifyBarrelWatchers(uid, text, ms)
    local watchers = BarrelWatchers[uid]
    if not watchers or not text then return end

    for src in pairs(watchers) do
        GSC.Notify.Send(src, text, ms or 3000)
    end
end

---oo[ Ownership ]oo---
local function OwnerIdOf(Character)
    return Shared.CharId(Character)
end

---o[ The owner's server ID, if he is online ]o---
local function FindOwnerSource(uid)
    local owner = BarrelOwner[uid]
    if not owner then return nil end

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local Character = src and Shared.GetChar(src)
        if Character and (OwnerIdOf(Character) == owner or Character.identifier == owner) then
            return src
        end
    end

    return nil
end

---o[ The people at the still, plus the owner and crew wherever they are ]o---
local function NotifyBarrel(uid, text, ms)
    if not text then return end

    NotifyBarrelWatchers(uid, text, ms)

    local told = {}
    for src in pairs(BarrelWatchers[uid] or {}) do told[src] = true end

    local away = GSC.BarrelCrew.OnlineSources(uid)
    away[#away + 1] = FindOwnerSource(uid)

    for _, src in ipairs(away) do
        if not told[src] then
            told[src] = true
            GSC.Notify.Send(src, text, ms or 3000)
        end
    end
end

---o[ Everything a client needs to draw every barrel ]o---
local function BarrelSyncList()
    local list = {}
    for uid, pos in pairs(BarrelPositions) do
        list[uid] = { x = pos.x, y = pos.y, z = pos.z, h = BarrelHeadings[uid] or 0.0,
            dressing = DressingOf(uid) }
    end
    return list
end

RegisterServerEvent('gsc_kassippu:server:watchBarrel')
AddEventHandler('gsc_kassippu:server:watchBarrel', function(uid)
    if uid ~= nil and type(uid) ~= 'string' then return end
    SetBarrelWatcher(source, uid)

    if uid and BarrelPositions[uid] then GSC.BarrelCrew.SendAccess(source, uid) end
end)

AddEventHandler('playerDropped', function()
    SetBarrelWatcher(source, nil)
end)

---o[ What the sky is doing over a barrel ]o---
RegisterServerEvent('gsc_kassippu:server:barrelWeather')
AddEventHandler('gsc_kassippu:server:barrelWeather', function(uid, raining, covered)
    local _source = source
    if type(uid) ~= 'string' or WatchedBarrel[_source] ~= uid then return end
    BarrelExposure[uid] = { raining = raining == true, covered = covered == true, at = os.time() }
end)

---oo[ Helper Functions ]oo---

---o[ Tables that were renamed: old name -> new name ]o---
local RenamedTables = {
    { from = 'gsc_climb_trees', to = 'gsc_kasippu_trees' },
}

local function AwaitQuery(sql, params)
    local p = promise.new()
    exports.oxmysql:execute(sql, params or {}, function(result, err)
        if err then print("^1[Database]^7 " .. tostring(err)) end
        p:resolve(not err and (result or {}) or nil)
    end, GetCurrentResourceName(), true)
    return Citizen.Await(p)
end

---o[ Move an old table to its new name once, before the CREATEs would make an empty one ]o---
local function RenameOldTables()
    for _, t in ipairs(RenamedTables) do
        local rows = AwaitQuery([[
            SELECT TABLE_NAME AS name FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN (?, ?)
        ]], { t.from, t.to })

        if rows then
            local have = {}
            for _, row in ipairs(rows) do have[row.name] = true end

            if have[t.from] and not have[t.to] then
                if AwaitQuery(string.format("RENAME TABLE `%s` TO `%s`", t.from, t.to)) then
                    print(string.format("^2[Database]^7 Renamed table %s to %s", t.from, t.to))
                end
            elseif have[t.from] and have[t.to] then
                print(string.format("^3[Database]^7 Both %s and %s exist - using %s. Drop %s by hand once checked.",
                    t.from, t.to, t.to, t.from))
            end
        end
    end
end

---o[ Persistence Models Loads & Auto-Seed from SQL File ]o---
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end

    RenameOldTables()

    local sqlFile = LoadResourceFile(GetCurrentResourceName(), "database/cv_kasippu_tables.sql")

    if sqlFile then
        local stripped = sqlFile:gsub("%-%-[^\n]*", "")
        local ok = true

        for raw in stripped:gmatch("[^;]+") do
            local statement = raw:match("^%s*(.-)%s*$")
            if statement ~= "" then
                local p = promise.new()
                exports.oxmysql:execute(statement, {}, function(result, err)
                    if err then print("^1[Database]^7 " .. tostring(err)) end
                    p:resolve(err == nil)
                end, GetCurrentResourceName(), true)
                if not Citizen.Await(p) then ok = false end
            end
        end

        if ok then
            Shared.Debug("^2[Database]^7 Auto-seeded from database/cv_kasippu_tables.sql")
        else
            print("^1[Error]^7 One or more statements in database/cv_kasippu_tables.sql failed, see above")
        end
    else
        print("^1[Error]^7 Could not find database/cv_kasippu_tables.sql in the resource folder!")
    end

    Distillery.TablesReady = true -- tree_store.lua waits on this before touching gsc_kasippu_trees
    Distillery.LoadBarrelsFromDB()
    GSC.Crates.LoadCratesFromDB()
end)

---oo[ Barrel Load Function ]oo---
function Distillery.LoadBarrelsFromDB()
    exports.oxmysql:execute('SELECT * FROM gsc_kassippu_barrels', {}, function(results, err)
        ---o[ Failed ]o---
        if err then
            return print("^1[Error]^7 Could not load stills from gsc_kassippu_barrels - no stills this session: " .. tostring(err))
        end
        BarrelsLoaded = true
        if results then
            local count = 0
            for _, v in ipairs(results) do
                local coordsData = json.decode(v.coords)
                if coordsData then
                    local uid = v.uid
                    BarrelPositions[uid] = vector3(coordsData.x, coordsData.y, coordsData.z)
                    BarrelHeadings[uid] = tonumber(v.heading) or 0.0
                    BarrelOwner[uid] = v.owner
                    BarrelStage[uid] = v.stage or Shared.BarrelStage.IDLE

                    BarrelHeat[uid] = tonumber(v.heat) or 0.0
                    BarrelFuelCount[uid] = 0
                    BarrelFirePower[uid] = 1.0
                    if type(v.fire) == 'string' and v.fire ~= "" then
                        local ok, fire = pcall(json.decode, v.fire)
                        if ok and type(fire) == 'table' then
                            BarrelFuelCount[uid] = tonumber(fire.fuel) or 0
                            BarrelFirePower[uid] = tonumber(fire.power) or 1.0
                            BarrelTarp[uid] = fire.tarp == true or nil
                            BarrelRepairCount[uid] = math.max(0, math.floor(tonumber(fire.repairs) or 0))
                        end
                    end
                    BarrelBrewProgress[uid] = tonumber(v.progress) or 0
                    BarrelRemainingBottles[uid] = tonumber(v.remaining_bottles) or 0
                    BarrelLoaded[uid] = Shared.RecipeKey(v.recipe)

                    BarrelTargetQuality[uid] = v.quality
                    BarrelUsageCount[uid] = tonumber(v.usage_count) or 0
                    BarrelCondition[uid] = tonumber(v.condition_pct) or Config.BarrelCondition.Max
                    BarrelResidue[uid] = tonumber(v.residue) or 0.0
                    GSC.BarrelCrew.Load(uid, v.crew)
                    GSC.Stations.Load(uid, v.stations)
                    if type(v.upgrades) == 'string' and v.upgrades ~= "" then
                        local ok, keys = pcall(json.decode, v.upgrades)
                        if ok then SetUpgrades(uid, keys) end
                    end

                    if type(v.ferment) == 'string' and v.ferment ~= "" then
                        local ok, f = pcall(json.decode, v.ferment)
                        if ok and type(f) == 'table' then BarrelFerment[uid] = f end
                    end
                    if type(v.mix) == 'string' and v.mix ~= "" then
                        local ok, mix = pcall(json.decode, v.mix)
                        if ok and type(mix) == 'table' then BarrelMix[uid] = mix end
                    end

                    if v.stage == Shared.BarrelStage.BREWING and Config.Cuts.Enabled then
                        BarrelBrewProgress[uid] = 0
                    end

                    if v.stage == Shared.BarrelStage.FERMENTING then
                        BarrelFerment[uid] = BarrelFerment[uid] or { spiked = 0 }
                        if (tonumber(BarrelFerment[uid].started) or 0) <= 0 then
                            BarrelFerment[uid].started = os.time()
                        end
                    end

                    ---o[ Batches laid down under the old in-barrel aging ]o---
                    if BarrelStage[uid] == "AGING" then
                        BarrelStage[uid] = Shared.BarrelStage.COMPLETED
                    end

                    ---o[ A timed stage carries on where it left off ]o---
                    local stage = BarrelStage[uid]
                    if stage == Shared.BarrelStage.MIXING or stage == Shared.BarrelStage.HEAT_PAUSE then
                        local deadline = tonumber(v.stage_deadline) or 0
                        if deadline <= 0 then
                            local ms = stage == Shared.BarrelStage.MIXING
                                and Config.Mixing.Time or Config.HeatManagement.HeatInterval
                            deadline = os.time() + math.ceil(ms / 1000)
                        end
                        BarrelStageDeadline[uid] = deadline
                    end

                    count = count + 1
                end
            end

            TriggerClientEvent('gsc_kassippu:client:syncAllBarrels', -1, BarrelSyncList(), BarrelStage)
            print("^2[Kassippu]^7 Loaded " .. count .. " barrels.")
        end
        GSC.Stations.Loaded()
    end, GetCurrentResourceName(), true)
end

---oo[ The Barrel Stash ]oo---
local function RegisterStash(invId)
    exports.vorp_inventory:registerInventory({
        id = invId,
        name = Config.BarrelStash.StashName,
        limit = Config.BarrelStash.StashItemsLimit,
        maxWeight = Config.BarrelStash.StashWeight,
        acceptCustomItems = Config.BarrelStash.StashCustomItemsStatus,
        shared = Config.BarrelStash.StashSharedStatus
    })
end

---o[ Empty it for good ]o---
local function ClearStash(invId, cb)
    CreateThread(function()
        RegisterStash(invId)
        exports.vorp_inventory:deleteCustomInventory(invId)
        exports.vorp_inventory:removeInventory(invId)
        if cb then cb() end
    end)
end

---o[ Stacks + weapons left in it ]o---
local function CountStash(invId, cb)
    CreateThread(function()
        RegisterStash(invId)
        local items = exports.vorp_inventory:getCustomInventoryItems(invId)
        local weapons = exports.vorp_inventory:getCustomInventoryWeapons(invId)
        cb((type(items) == 'table' and #items or 0) + (type(weapons) == 'table' and #weapons or 0))
    end)
end

---o[ Barrel Info Save to Database Function ]o---
local function SaveBarrelToDB(uid)
    local coords = BarrelPositions[uid]
    if not coords or BarrelDoomed[uid] then return end

    local cleanCoords = { x = Shared.Round(coords.x, 2), y = Shared.Round(coords.y, 2), z = Shared.Round(coords.z, 2) }

    local parameters = {
        uid = uid,
        owner = BarrelOwner[uid] or "Unknown",
        coords = json.encode(cleanCoords),
        stage = BarrelStage[uid] or Shared.BarrelStage.IDLE,
        heat = tonumber(BarrelHeat[uid]) or 0.0,
        fuel = math.min(127, math.floor(tonumber(BarrelFuelCount[uid]) or 0)),
        fire = json.encode({ fuel = BarrelFuelCount[uid] or 0, power = BarrelFirePower[uid] or 1.0,
            tarp = BarrelTarp[uid] == true, repairs = BarrelRepairCount[uid] or 0 }),
        progress = tonumber(BarrelBrewProgress[uid]) or 0,
        recipe = BarrelLoaded[uid] or "none",
        bottles = tonumber(BarrelRemainingBottles[uid]) or 0,
        quality = BarrelTargetQuality[uid],
        usage = tonumber(BarrelUsageCount[uid]) or 0,
        condition_pct = tonumber(BarrelCondition[uid]) or Config.BarrelCondition.Max,
        residue = tonumber(BarrelResidue[uid]) or 0.0,
        heading = tonumber(BarrelHeadings[uid]) or 0.0,
        stage_deadline = tonumber(BarrelStageDeadline[uid]) or 0,
        crew = GSC.BarrelCrew.Serialize(uid),
        ferment = BarrelFerment[uid] and json.encode(BarrelFerment[uid]) or nil,
        mix = BarrelMix[uid] and json.encode(BarrelMix[uid]) or nil,
        upgrades = BarrelUpgrades[uid] and json.encode(UpgradeKeys(uid)) or nil,
        stations = GSC.Stations.Serialize(uid),
    }

    exports.oxmysql:execute([[
        INSERT INTO gsc_kassippu_barrels
            (uid, owner, coords, heading, stage, stage_deadline, heat, fuel, progress, recipe, remaining_bottles,
             quality, usage_count, condition_pct, residue, crew, ferment, mix, fire, upgrades, stations, aging_started,
             cask_score, aged_tier)
        VALUES
            (:uid, :owner, :coords, :heading, :stage, :stage_deadline, :heat, :fuel, :progress, :recipe, :bottles,
             :quality, :usage, :condition_pct, :residue, :crew, :ferment, :mix, :fire, :upgrades, :stations, 0, 0, NULL)
        ON DUPLICATE KEY UPDATE
            fire = VALUES(fire),
            upgrades = VALUES(upgrades),
            stations = VALUES(stations),
            crew = VALUES(crew),
            ferment = VALUES(ferment),
            mix = VALUES(mix),
            heading = VALUES(heading),
            stage = VALUES(stage),
            stage_deadline = VALUES(stage_deadline),
            heat = VALUES(heat),
            fuel = VALUES(fuel),
            progress = VALUES(progress),
            recipe = VALUES(recipe),
            remaining_bottles = VALUES(remaining_bottles),
            quality = VALUES(quality),
            usage_count = VALUES(usage_count),
            condition_pct = VALUES(condition_pct),
            residue = VALUES(residue),
            aging_started = VALUES(aging_started),
            cask_score = VALUES(cask_score),
            aged_tier = VALUES(aged_tier)
    ]], parameters)
end

---oo[ What the crew module needs of a barrel ]oo---

function Distillery.Position(uid)
    return BarrelPositions[uid]
end

function Distillery.LoadedRecipe(uid)
    return BarrelLoaded[uid]
end

function Distillery.Watchers(uid)
    return BarrelWatchers[uid] or {}
end

function Distillery.WatchedBy(src)
    return WatchedBarrel[src]
end

function Distillery.OwnerSource(uid)
    return FindOwnerSource(uid)
end

function Distillery.OwnerId(uid)
    return BarrelOwner[uid]
end

function Distillery.IsOwner(Character, uid)
    local owner = BarrelOwner[uid]
    if not owner or owner == "Unknown" then return true end
    return OwnerIdOf(Character) == owner or Character.identifier == owner
end

function Distillery.Save(uid)
    SaveBarrelToDB(uid)
end

---o[ For the recipe book's preview ]o---
function Distillery.RegisterStash(uid)
    RegisterStash(uid)
end

---o[ Tracking Product Qualities ]o---
local function GetCurrentQualityBracket(heat)
    for key, range in pairs(Config.Product.Qualities) do
        if heat >= range.min and heat <= range.max then
            return key
        end
    end
    return nil
end

---oo[ The Graded Final Push - scoring ]oo---

---o[ Where the line sits right now ]o---
local function GetTargetHeat(uid, now)
    local conf = Config.HeatSkill
    local amplitude = conf.DriftAmplitude or 0.0

    if amplitude <= 0.0 then return conf.TargetCentre end

    local period = math.max(1, conf.DriftPeriodSeconds or 24)
    local elapsed = now - (BarrelPushStart[uid] or now)

    return conf.TargetCentre + (math.sin((elapsed / period) * math.pi * 2.0) * amplitude)
end

---o[ Mark this tick, 0.0 to 1.0 ]o---
local function ScoreHeatTick(heat, target, bandScale)
    local conf = Config.HeatSkill
    local offset = math.abs(heat - target)
    local band = (conf.TargetHalfWidth or 5.0) * (bandScale or 1.0)

    if offset <= band then return 1.0 end

    local falloff = conf.ToleranceFalloff or 12.0
    if falloff <= 0.0 then return 0.0 end

    return math.max(0.0, 1.0 - ((offset - band) / falloff))
end

---o[ Turn the run's average into a reward tier ]o---
local function GradeRun(averagePercent)
    local best, bestCut = "NORMAL", -1

    for tier, cutoff in pairs(Config.HeatSkill.Grades or {}) do
        if averagePercent >= cutoff and cutoff > bestCut then
            best, bestCut = tier, cutoff
        end
    end

    return best
end

---oo[ Condition and Fouling ]oo---

local function GetCondition(uid)
    return BarrelCondition[uid] or Config.BarrelCondition.Max
end

local function GetResidue(uid)
    return BarrelResidue[uid] or 0.0
end

---o[ Take condition off a barrel, and tell the still-house when she is going ]o---
local function WearBarrel(uid, amount)
    if not Config.BarrelCondition.Enabled or amount <= 0 then return end
    amount = amount * UpgradeProduct(uid, "wearMultiplier") -- iron hoops

    local conf = Config.BarrelCondition
    local before = GetCondition(uid)
    local after = math.max(0.0, before - amount)

    BarrelCondition[uid] = after

    if after <= conf.WarnConditionAt and not BarrelConditionWarned[uid] then
        BarrelConditionWarned[uid] = true
        NotifyBarrelWatchers(uid, Config.Text.ConditionWarning, 5000)
    elseif after > (conf.WarnConditionAt * 1.35) then
        BarrelConditionWarned[uid] = nil
    end

    return after
end

---o[ The best grade this barrel is still able to make ]o---
local TIER_ORDER = { NORMAL = 1, GOOD = 2, PERFECT = 3 }

local function CapTierByCondition(uid, tier)
    if not Config.BarrelCondition.Enabled then return tier, nil end

    local condition = GetCondition(uid) + UpgradeSum(uid, "capBonus")
    local caps = Config.BarrelCondition.QualityCaps or {}

    local allowed, allowedRank = "NORMAL", TIER_ORDER.NORMAL
    for capTier, needed in pairs(caps) do
        local rank = TIER_ORDER[capTier] or 0
        if condition >= needed and rank > allowedRank then
            allowed, allowedRank = capTier, rank
        end
    end

    if (TIER_ORDER[tier] or 0) <= allowedRank then
        return tier, nil -- she was never the limiting factor
    end

    return allowed, tier
end

---o[ Wipe a barrel's run state ]o---
local function ClearRunState(uid)
    BarrelPushStart[uid] = nil
    BarrelScoreSum[uid] = nil
    BarrelScoreTicks[uid] = nil
    BarrelTargetHeat[uid] = nil
    BarrelNextEvent[uid] = nil
    BarrelPressure[uid] = nil
    BarrelPressureWarned[uid] = nil
    BarrelStageDeadline[uid] = nil
    BarrelFerment[uid] = nil
    BarrelMix[uid] = nil
    BarrelStirPending[uid] = nil
    BarrelStirSentAt[uid] = nil
    BarrelStirTries[uid] = nil
    BarrelTendPending[uid] = nil
    BarrelBottlePending[uid] = nil
    BarrelCut[uid] = nil
    BarrelCondenser[uid] = nil
    BarrelCondenserHot[uid] = nil
    BarrelIncident[uid] = nil
    PushGame[uid] = nil
end

---oo[ The Fire ]oo---

local function FireLit(uid)
    return (BarrelFuelCount[uid] or 0) > 0
end

---o[ How much smoke the fire puts up ]o---
local function SmokeLevelOf(uid)
    local fuel = BarrelFuelCount[uid] or 0
    if fuel <= 0 then return 0 end

    local size = fuel * (BarrelFirePower[uid] or 1.0) / math.max(1, Config.Fuel.MaxBurnSeconds or 150)
    if size < 0.34 then return 1 end
    if size < 0.67 then return 2 end
    return 3
end

---oo[ Still Dressing ]oo---
DressingOf = function(uid)
    local stage = BarrelStage[uid]
    local jar = nil

    if stage == Shared.BarrelStage.BREWING and Config.Cuts.Enabled then
        local cut = BarrelCut[uid]
        jar = (cut and cut.keepFrom and not cut.keepTo) and "full" or "empty"
    end

    return {
        lit = FireLit(uid),
        jar = jar,
        jugs = stage == Shared.BarrelStage.COMPLETED and (BarrelRemainingBottles[uid] or 0) or 0,
        tarp = BarrelTarp[uid] == true,
        steam = BarrelCondenserHot[uid] == true,
        smoke = SmokeLevelOf(uid),
    }
end

---o[ Dressing goes to everyone, so changes are batched ]o---
local DressingDirty = {}
local dressingFlushPending = false

local function FlushDressing()
    dressingFlushPending = false
    local dirty = DressingDirty
    DressingDirty = {}
    for uid in pairs(dirty) do
        if BarrelPositions[uid] then
            TriggerClientEvent('gsc_kassippu:client:barrelDressing', -1, uid, DressingOf(uid))
        end
    end
end

local function SyncDressing(uid)
    if not BarrelPositions[uid] then return end
    DressingDirty[uid] = true
    if not dressingFlushPending then
        dressingFlushPending = true
        SetTimeout(250, FlushDressing)
    end
end

---o[ Tell clients when the fire, or its smoke, changes ]o---
local function RefreshSmoke(uid)
    local level = SmokeLevelOf(uid)
    if BarrelSmokeShown[uid] ~= level then
        BarrelSmokeShown[uid] = level
        SyncDressing(uid)
    end
end

local function SyncFire(uid)
    RefreshSmoke(uid)
end

---o[ A log on the fire ]o---
local function AddLog(uid, log)
    local fuel = BarrelFuelCount[uid] or 0
    local power = BarrelFirePower[uid] or log.power

    BarrelFirePower[uid] = ((fuel * power) + (log.burnSeconds * log.power)) / (fuel + log.burnSeconds)
    BarrelFuelCount[uid] = fuel + log.burnSeconds
    BarrelFireOut[uid] = nil

    SyncFire(uid)
end

local function PutOutFire(uid)
    local wasLit = FireLit(uid)
    BarrelFuelCount[uid] = 0
    BarrelSoak[uid] = nil
    if wasLit then
        BarrelFireOut[uid] = { at = os.time(), warned = false }
        SyncFire(uid)
    end
end

---o[ Cold stage, fire out ]o---
ColdGraceLeft = function(uid, now)
    if BarrelStage[uid] ~= Shared.BarrelStage.IDLE or FireLit(uid) or (BarrelHeat[uid] or 0) <= 0 then
        return nil
    end

    local out = BarrelFireOut[uid]
    if not out then
        out = { at = now, warned = false }
        BarrelFireOut[uid] = out
    end

    return math.max(0, (Config.Fuel.ColdGraceSeconds or 0) - (now - out.at))
end

---o[ The stages where [E] puts a log on ]o---
local function TakesWood(stage)
    local S = Shared.BarrelStage
    return stage == S.IDLE or stage == S.MID_CLIMB or stage == S.HEAT_PAUSE or stage == S.FINAL_PUSH
end

---o[ "Put more on" ]o---
local function NotifyFireOut(uid)
    if not TakesWood(BarrelStage[uid] or Shared.BarrelStage.IDLE) then return end

    for src in pairs(BarrelWatchers[uid] or {}) do
        if GSC.BarrelCrew.Can(src, uid, "fuel") then
            GSC.Notify.Send(src, Config.Text.FireOut, 4000)
        end
    end
end

---o[ One second of fire ]o---
local function BurnFire(uid, now)
    if not FireLit(uid) then return false, 0 end

    local rain = Config.Fuel.Rain or {}
    local seen = BarrelExposure[uid]
    local wet = rain.Enabled and not BarrelTarp[uid] and seen and (now - seen.at) <= (rain.ReportSeconds or 20)
        and seen.raining and not seen.covered

    if wet then
        BarrelSoak[uid] = (BarrelSoak[uid] or 0) + 1
        if BarrelSoak[uid] == 1 then
            NotifyBarrelWatchers(uid, Config.Text.FireRainWarn, 5000)
        end
        if BarrelSoak[uid] >= (rain.OutSeconds or 20) then
            PutOutFire(uid)
            NotifyBarrel(uid, Config.Text.FireRainedOut, 6000)
            return false, 0
        end
    else
        BarrelSoak[uid] = nil
    end

    ---o[ Hold The Heat as a game ]o---
    local frozen = PushGameOn() ~= nil and BarrelStage[uid] == Shared.BarrelStage.FINAL_PUSH
    if not frozen then
        BarrelFuelCount[uid] = math.max(0, BarrelFuelCount[uid] - IncidentFactor(uid, "burnMultiplier"))
    end
    if BarrelFuelCount[uid] <= 0 then
        PutOutFire(uid)
        NotifyFireOut(uid)
        return false, 0
    end

    RefreshSmoke(uid)

    return true, (BarrelFirePower[uid] or 1.0) * IncidentFactor(uid, "powerMultiplier")
end

---oo[ The Batch ]oo---

local function BatchOf(uid)
    return math.max(1, tonumber(BarrelMix[uid] and BarrelMix[uid].batch) or 1)
end

---o[ A bigger batch is harder to hold: pressure builds faster ]o---
local function BatchPressureMultiplier(uid)
    return 1.0 + (BatchOf(uid) - 1) * ((Config.Mash or {}).BatchPressureStep or 0.0)
end

---o[ Fruit and freshness, on the final score ]o---
local function MixScoreMod(uid)
    local mix = BarrelMix[uid]
    if not mix then return 0 end
    return (tonumber(mix.scoreMod) or 0) + (tonumber(mix.stir) or 0) + (tonumber(mix.tend) or 0)
end

---o[ A bottle of this recipe, grade and strength, exactly as a still fills it ]o---
local function MakeBottle(recipeKey, quality, strengthKey, tainted, profile)
    local hide = Config.Tasting and Config.Tasting.Enabled and Config.Tasting.HideUntasted
    local reward = Config.Recipes[recipeKey].rewards[quality]
    local strength = GSC.Mash.Strength(recipeKey, strengthKey)
    local label = GSC.Mash.ProductLabel(recipeKey, strength and strength.key)

    local item = (strength and strength.item) or reward.item
    local metadata = GSC.Crates.FreshBottleMetadata(recipeKey, quality, strength and strength.key) or {}

    if strength then
        metadata.strength = strength.key
        metadata.productLabel = label
        if not strength.item then metadata.label = label end
    end

    metadata.quality = metadata.quality or quality
    metadata.recipe = metadata.recipe or recipeKey
    if strength and strength.proof then
        metadata.proof = strength.proof
        metadata.description = (metadata.description or label) .. string.format(Config.Text.BottleProof, strength.proof)
    end

    if tainted then
        metadata.tainted = true
        if not hide then
            metadata.description = (metadata.description or label) .. Config.Text.Cuts.TaintedDescription
            if Config.Cuts.TaintedLabel then
                metadata.label = string.format(Config.Cuts.TaintedLabel, metadata.label or label)
            end
        end
    end

    ---o[ What a taster will find ]o---
    if profile and GSC.Tasting and GSC.Tasting.Encode then
        metadata.profile = GSC.Tasting.Encode(profile)
    end

    if next(metadata) == nil then metadata = nil end
    return item, metadata, label
end

---o[ The bottle this batch fills, at this grade ]o---
local function BottleFor(uid, recipeKey, quality)
    local mix = BarrelMix[uid]
    return MakeBottle(recipeKey, quality, mix and mix.strength, mix and mix.tainted, mix and mix.profile)
end

---oo[ Admin: Give Any Output, Exactly As The Game Makes It ]oo---
local GIVE_STATES = { FRESH = true, RESTED = true, MELLOW = true, FINE = true, TURNED = true }

local function IsGiveAdmin(src)
    return GSC.Admin.Is(src, Config.GiveCommand)
end

local function GiveReply(src, text)
    if src == 0 then print("[kasippu] " .. Shared.PlainText(text)) else GSC.Notify.Send(src, text, 6000) end
end

local function KeysOf(list, field)
    local keys = {}
    for k, v in pairs(list or {}) do keys[#keys + 1] = field and v[field] or k end
    table.sort(keys)
    return table.concat(keys, ", ")
end

if Config.GiveCommand and Config.GiveCommand.Enabled then
    RegisterCommand(Config.GiveCommand.Name, function(source, args)
        local _source = source
        local T = Config.Text
        if not IsGiveAdmin(_source) then return GiveReply(_source, T.GiveNoAccess) end

        local target = tonumber(args[1])
        local recipeKey = args[2] and args[2]:lower()
        local grade = args[3] and args[3]:upper()
        if not target or not recipeKey or not grade then
            return GiveReply(_source, string.format(T.GiveUsage, Config.GiveCommand.Name))
        end
        if not Shared.GetChar(target) then return GiveReply(_source, string.format(T.GiveBadPlayer, args[1])) end

        local recipe = Config.Recipes[recipeKey]
        if not recipe then return GiveReply(_source, string.format(T.GiveBadRecipe, args[2], KeysOf(Config.Recipes))) end
        if not recipe.rewards[grade] then
            return GiveReply(_source, string.format(T.GiveBadGrade, args[3], KeysOf(recipe.rewards)))
        end

        local strengthKey = args[4] and args[4] ~= "-" and args[4]:upper() or nil
        if strengthKey and not GSC.Mash.Strength(recipeKey, strengthKey) then
            return GiveReply(_source, string.format(T.GiveBadStrength, args[4], KeysOf(recipe.strengths, "key")))
        end
        strengthKey = strengthKey or (recipe.strengths and recipe.strengths[1] and recipe.strengths[1].key)

        local amount = math.floor(tonumber(args[5]) or 1)
        amount = math.max(1, math.min(Config.GiveCommand.MaxAmount or 20, amount))

        local state, tainted = "FRESH", false
        for i = 6, #args do
            local word = args[i]:upper()
            if word == "TAINTED" then tainted = true
            elseif GIVE_STATES[word] then state = word
            else return GiveReply(_source, string.format(T.GiveBadState, args[i])) end
        end

        local item, metadata = MakeBottle(recipeKey, grade, strengthKey, tainted)
        if state ~= "FRESH" then
            item, metadata = GSC.Crates.AgedBottle(item, metadata, recipeKey, grade, state)
            if not item then return GiveReply(_source, T.GiveNoCrate) end
        end

        if not exports.vorp_inventory:canCarryItem(target, item, amount) then
            return GiveReply(_source, T.GiveCantCarry)
        end
        exports.vorp_inventory:addItem(target, item, amount, metadata)

        local shown = (metadata and metadata.label) or item
        GiveReply(_source, string.format(T.GiveDone, amount, shown, item, target))
        Shared.Debug(string.format("^6[Give]^7 %s gave %dx %s (%s %s %s %s%s) to %s", tostring(_source), amount, item,
            recipeKey, grade, tostring(strengthKey), state, tainted and " tainted" or "", target))

        GSC.Logs.Send("admin", (Config.Text.Logs or {}).Give, {
            { name = GSC.Logs.Label("Admin"), value = GSC.Logs.Player(_source), raw = true },
            { name = GSC.Logs.Label("Target"), value = GSC.Logs.Player(target), raw = true },
            { name = GSC.Logs.Label("Item"), value = string.format("%s (%s)", shown, item), inline = true },
            { name = GSC.Logs.Label("Amount"), value = tostring(amount), inline = true },
            { name = GSC.Logs.Label("Details"), value = string.format("%s · %s · %s · %s%s", tostring(recipeKey), tostring(grade),
                tostring(strengthKey), tostring(state), tainted and " · tainted" or "") },
        })
    end, false)
end

---oo[ Fermentation ]oo---

---o[ Where a fermenting wash stands at `now` ]o---
FermentState = function(uid, now)
    local f = BarrelFerment[uid]
    if not f or (tonumber(f.started) or 0) <= 0 then return nil end

    local conf = Config.Fermentation
    local band, ageRate, keepRate = Shared.CrateClimate(f.temp, f.sheltered)

    local elapsed = math.max(0, now - f.started)
    local fermented = (elapsed / 60.0) * ageRate
    local strength = math.min(100.0, (fermented / math.max(0.01, conf.ReadyMinutes)) * 100.0)

    local keepClock = elapsed + (tonumber(f.spiked) or 0)

    return {
        strength = strength,
        turnIn = (conf.TurnMinutes * 60.0 * keepRate) - keepClock,
        spoilIn = (conf.SpoilMinutes * 60.0 * keepRate) - keepClock,
        band = band,
    }
end

---o[ A weak wash makes fewer bottles ]o---
local function ScaleByStrength(uid, bottles)
    local f = BarrelFerment[uid]
    if not (Config.Fermentation.Enabled and f and f.strength) then return bottles end
    return math.max(1, math.floor(bottles * (f.strength / 100.0) + 0.5))
end

---o[ The wash turned: the batch is lost ]o---
local function SpoilWash(uid)
    BarrelStage[uid] = Shared.BarrelStage.IDLE
    BarrelLoaded[uid] = nil
    PutOutFire(uid)
    BarrelTargetQuality[uid] = nil
    ClearRunState(uid)

    if Config.BarrelCondition.Enabled then
        local cconf = Config.BarrelCondition
        BarrelResidue[uid] = math.min(cconf.ResidueMax,
            (BarrelResidue[uid] or 0.0) + (Config.Fermentation.SpoilResidue or 0.0))
    end

    SaveBarrelToDB(uid)
    TriggerClientEvent('gsc_kassippu:client:updateStage', -1, uid, Shared.BarrelStage.IDLE)
    NotifyBarrel(uid, Config.Text.FermentSpoiled, 6000)

    Shared.Debug("^1[Ferment]^7 Barrel " .. uid .. " spoiled.")
end

---o[ Light the fire under the wash: on to the distillation ]o---
local function LightUnderWash(src, uid)
    local state = FermentState(uid, os.time())
    local strength = state and state.strength or 100.0

    if strength < (Config.Fermentation.MinStrength or 0) then
        GSC.Notify.Send(src, string.format(Config.Text.FermentTooYoung, math.floor(strength)), 4000)
        return false
    end

    BarrelFerment[uid] = BarrelFerment[uid] or {}
    BarrelFerment[uid].strength = strength

    BarrelStage[uid] = Shared.BarrelStage.MID_CLIMB
    SaveBarrelToDB(uid)
    TriggerClientEvent('gsc_kassippu:client:updateStage', -1, uid, Shared.BarrelStage.MID_CLIMB)

    NotifyBarrelWatchers(uid, string.format(Config.Text.FermentLit, math.floor(strength)), 4000)
    if strength < 100.0 then
        NotifyBarrelWatchers(uid, Config.Text.FermentWeak, 5000)
    end

    Shared.Debug(string.format("^2[Ferment]^7 Barrel %s distilling at %.0f%% strength", uid, strength))
    return true
end

---o[ A rival's spike ]o---
function Distillery.SpikeWash(uid, seconds, byThief)
    local f = BarrelFerment[uid]
    if not f or BarrelStage[uid] ~= Shared.BarrelStage.FERMENTING then return false end

    f.spiked = (tonumber(f.spiked) or 0) + seconds
    if byThief then f.spikes = Distillery.SpikeCount(uid) + 1 end -- kept in the ferment JSON
    SaveBarrelToDB(uid)
    return true
end

---o[ How many times thieves have spiked this wash ]o---
function Distillery.SpikeCount(uid)
    local f = BarrelFerment[uid]
    return f and tonumber(f.spikes) or 0
end

---o[ The batch's hidden character, for tasting ]o---
local function BuildProfile(uid)
    local conf = Config.Tasting
    if not (conf and conf.Enabled) then return nil end

    local mix = BarrelMix[uid] or {}
    local f = BarrelFerment[uid]
    local strength = f and tonumber(f.strength)
    local score = tonumber(mix.pushScore)
    local stir, tend = tonumber(mix.stir), tonumber(mix.tend)
    local tainted = mix.tainted or mix.inheritedTaint
    local notes, flaws = {}, {}

    if f and (tonumber(f.spiked) or 0) > 0 then flaws[#flaws + 1] = "spiked" end
    if tainted then flaws[#flaws + 1] = "harsh" end
    if (tonumber(mix.vapourLoss) or 0) > 0 or (tonumber(mix.leakLoss) or 0) > 0 then flaws[#flaws + 1] = "scorched" end
    if GetResidue(uid) > (conf.MustyResidue or 25) then flaws[#flaws + 1] = "musty" end
    if strength and strength < 100 then flaws[#flaws + 1] = "thin" end
    if (tonumber(mix.stale) or 0) > (conf.StaleFrom or 0.3) then flaws[#flaws + 1] = "stale" end
    if (stir and stir < 0) or (tend and tend < 0) then flaws[#flaws + 1] = "lumpy" end

    if not tainted and score and score >= (conf.CleanFrom or 80) then notes[#notes + 1] = "clean" end
    if stir and stir > 0 and not (tend and tend < 0) then notes[#notes + 1] = "silky" end
    if (tonumber(mix.fruit) or 0) > 0 then notes[#notes + 1] = "fruity" end
    if strength and strength >= 100 then notes[#notes + 1] = "bold" end

    return { score = score and math.floor(score + 0.5) or nil, notes = notes, flaws = flaws }
end

---oo[ The Batch Is Done ]oo---
local function CompleteBatch(uid)
    local recipeKey = BarrelLoaded[uid]
    local qualityKey = BarrelTargetQuality[uid] or "NORMAL"
    local recipe = Config.Recipes[recipeKey]
    local totalBottles = 1

    if recipe and recipe.rewards[qualityKey] then
        totalBottles = ScaleByStrength(uid, recipe.rewards[qualityKey].count * BatchOf(uid))

        local yield = BarrelMix[uid] and tonumber(BarrelMix[uid].heartsYield)
        if yield then totalBottles = math.max(1, math.floor(totalBottles * yield + 0.5)) end

        local loss = BarrelMix[uid] and tonumber(BarrelMix[uid].vapourLoss)
        if loss and loss > 0 then
            totalBottles = math.max(1, math.floor(totalBottles * (1.0 - loss) + 0.5))
            NotifyBarrelWatchers(uid, string.format(Config.Text.CondenserLost, math.floor(loss * 100 + 0.5)), 5000)
        end

        local leak = BarrelMix[uid] and tonumber(BarrelMix[uid].leakLoss)
        if leak and leak > 0 then
            totalBottles = math.max(1, math.floor(totalBottles * (1.0 - math.min(0.9, leak)) + 0.5))
        end

        Shared.Debug(string.format("^5[Quality Reward]^7 Recipe: %s | Quality: %s | Bottles: %s",
            recipeKey, qualityKey, totalBottles))
    else
        Shared.Debug("^1[Error]^7 Recipe reward data missing for " .. tostring(recipeKey))
    end

    if BarrelMix[uid] and BarrelMix[uid].inheritedTaint then BarrelMix[uid].tainted = true end

    ---o[ What a taster will find in its bottles (saved with the mix) ]o---
    BarrelMix[uid] = BarrelMix[uid] or {}
    BarrelMix[uid].profile = BuildProfile(uid)

    PutOutFire(uid)
    BarrelCondenser[uid] = nil
    BarrelCondenserHot[uid] = nil

    BarrelStage[uid] = Shared.BarrelStage.COMPLETED
    BarrelRemainingBottles[uid] = totalBottles
    SaveBarrelToDB(uid)

    TriggerClientEvent('gsc_kassippu:client:updateStage', -1, uid, Shared.BarrelStage.COMPLETED)
    SyncBarrelHeat(uid, BarrelHeat[uid] or 0.0, 100, totalBottles)
    SyncDressing(uid) -- the jugs come out
end

---oo[ The Cuts ]oo---

local function PhaseAt(cut, progress)
    if progress < cut.headsEnd then return "heads" end
    if progress < cut.tailsStart then return "hearts" end
    return "tails"
end

---o[ What the gauge shows of a run ]o---
CutReading = function(uid)
    local cut = BarrelCut[uid]
    if not cut then return nil end

    local progress = BarrelBrewProgress[uid] or 0
    local phase = PhaseAt(cut, progress)
    local ahead = PhaseAt(cut, math.min(100, progress + (Config.Cuts.WarnAhead or 0)))

    return {
        progress = progress,
        phase = phase,
        soon = ahead ~= phase and ahead or nil,
        started = cut.keepFrom ~= nil,
        keeping = cut.keepFrom ~= nil and cut.keepTo == nil,
    }
end

---o[ A run begins ]o---
local function StartCutRun(uid)
    local conf = Config.Cuts
    local jitter = math.floor(conf.Jitter or 0)
    local headsEnd = conf.HeadsEnd + math.random(-jitter, jitter)
    local tailsStart = conf.TailsStart + math.random(-jitter, jitter)

    BarrelCut[uid] = { headsEnd = headsEnd, tailsStart = math.max(headsEnd + 10, tailsStart) }
    BarrelBrewProgress[uid] = 0
    SyncDressing(uid) -- the catch jar goes under the spout
end

---o[ The run is over: judge the jar ]o---
local function FinishCutRun(uid)
    local cut = BarrelCut[uid]
    if not cut then return CompleteBatch(uid) end

    local conf = Config.Cuts
    local T = Config.Text.Cuts

    local from, to = cut.keepFrom or 0, cut.keepTo or 100
    local function inJar(lo, hi) return math.max(0, math.min(to, hi) - math.max(from, lo)) end

    local heads = inJar(0, cut.headsEnd)
    local hearts = inJar(cut.headsEnd, cut.tailsStart) / math.max(1, cut.tailsStart - cut.headsEnd)
    local tails = inJar(cut.tailsStart, 100) / math.max(1, 100 - cut.tailsStart)

    local tainted = heads > (conf.HeadsTolerance or 0)
    local clean = not tainted and hearts >= (conf.CleanHearts or 1) and tails <= (conf.CleanTails or 0)

    local mix = BarrelMix[uid] or {}
    BarrelMix[uid] = mix
    mix.heartsYield = math.max(conf.MinYield or 0, hearts)
    mix.tainted = (tainted or mix.inheritedTaint) or nil

    ---o[ The final grade ]o---
    local score = tonumber(mix.pushScore)
    if score then
        score = score - tails * (conf.TailsPenalty or 0) + (clean and (conf.CleanBonus or 0) or 0)
        score = math.max(0.0, math.min(100.0, score))

        local tier, wouldHaveBeen = CapTierByCondition(uid, GradeRun(score))
        local label = (Config.Product.Qualities[tier] or {}).label or tier
        if wouldHaveBeen then
            NotifyBarrelWatchers(uid, Config.Text.ConditionCapped .. label, 5000)
        end

        BarrelTargetQuality[uid] = tier
        NotifyBarrelWatchers(uid, string.format(T.Graded, label, math.floor(score)), 6000)
    end

    if tainted then
        NotifyBarrelWatchers(uid, T.Tainted, 7000)
    elseif clean then
        NotifyBarrelWatchers(uid, T.Clean, 5000)
    end
    if tails > 0.25 then NotifyBarrelWatchers(uid, T.Oily, 5000) end
    if hearts < 0.6 then NotifyBarrelWatchers(uid, T.Short, 5000) end

    Shared.Debug(string.format("^2[Cut]^7 Barrel %s kept %.0f-%.0f: heads %.1f, hearts %.0f%%, tails %.0f%%%s",
        uid, from, to, heads, hearts * 100, tails * 100, tainted and " TAINTED" or ""))

    BarrelCut[uid] = nil
    CompleteBatch(uid)
end

---oo[ The Condenser ]oo---

---o[ One second of it, during the run ]o---
local function TickCondenser(uid)
    local conf = Config.Condenser
    if not conf.Enabled then return end

    local mix = BarrelMix[uid] or {}
    BarrelMix[uid] = mix

    local level = BarrelCondenser[uid]
    if level == nil then
        level = conf.StartLevel or 60
        mix.vapourLoss = nil
    end

    level = math.max(0, level - (conf.DrainPerSecond or 2))
    BarrelCondenser[uid] = level

    local hot = level < (conf.HotBelow or 25)
    if hot then
        mix.vapourLoss = math.min(conf.MaxLoss or 1, (tonumber(mix.vapourLoss) or 0) + (conf.LossPerSecond or 0))
    end

    if hot ~= (BarrelCondenserHot[uid] == true) then
        BarrelCondenserHot[uid] = hot or nil
        NotifyBarrelWatchers(uid, hot and Config.Text.CondenserHot or Config.Text.CondenserCool, 5000)
        SyncDressing(uid)
    end
end

---oo[ The Water Bucket ]oo---

local function BucketUses(item)
    local full = Config.WaterBucket.Uses or 1
    local left = tonumber(item.metadata and item.metadata.waterUsesLeft) or full
    return math.max(0, math.min(full, left))
end

local function Buckets(src)
    local name = Config.WaterBucket.Item
    local list = {}
    for _, item in ipairs(exports.vorp_inventory:getUserInventoryItems(src) or {}) do
        if item.name == name and (tonumber(item.count) or 0) > 0 then list[#list + 1] = item end
    end
    table.sort(list, function(a, b) return BucketUses(a) < BucketUses(b) end)
    return list
end

---o[ How many uses of water the player carries, across every bucket ]o---
local function WaterUsesLeft(src)
    local total = 0
    for _, item in ipairs(Buckets(src)) do total = total + BucketUses(item) * item.count end
    return total
end

---o[ Take `uses` of water from the player's buckets ]o---
local function UseWater(src, uses)
    uses = uses or 1
    if WaterUsesLeft(src) < uses then return false end

    local conf = Config.WaterBucket
    local full = conf.Uses or 1

    for _ = 1, 20 do
        if uses <= 0 then break end
        local bucket = Buckets(src)[1]
        if not bucket then return false end

        local left = BucketUses(bucket)
        local take = math.min(left, uses)
        uses = uses - take
        left = left - take

        if left <= 0 then
            if not exports.vorp_inventory:subItemById(src, bucket.id, nil, nil, 1) then return false end -- not taken: no water
            if conf.EmptyItem and exports.vorp_inventory:canCarryItem(src, conf.EmptyItem, 1) then
                exports.vorp_inventory:addItem(src, conf.EmptyItem, 1)
            end
        else
            local meta = {}
            for k, v in pairs(bucket.metadata or {}) do meta[k] = v end
            meta.waterUsesLeft = left
            meta.description = string.format(Config.Text.BucketDescription, left, full)
            exports.vorp_inventory:setItemMetadata(src, bucket.id, meta, 1)
        end
    end
    return true
end

function Distillery.UseWater(src, uses)
    return UseWater(src, uses)
end

---o[ For GSC.Stations ]o---
function Distillery.WaterUsesLeft(src)
    return WaterUsesLeft(src)
end

---oo[ Where the still's logs and water come from ]oo---
local function FromStock()
    local conf = Config.Stations
    return conf ~= nil and conf.Enabled == true and conf.StillUsesStock == true
end

---o[ One log of `kind` for this still ]o---
local function StillLog(src, uid, kind, take)
    local log = Config.Fuel.Logs[kind]
    if not log then return false end

    if FromStock() then
        local words = Config.Text.Stations or {}
        if not GSC.Stations.Has(uid, "rack") then
            GSC.Notify.Send(src, words.NeedRack, 4000)
            return false
        end
        if GSC.Stations.LogCount(uid, kind) < 1 then
            GSC.Notify.Send(src, string.format(words.RackNoKind, log.label), 4000)
            return false
        end
        if take then GSC.Stations.TakeLog(uid, kind) end
        return true
    end

    if exports.vorp_inventory:getItemCount(src, nil, log.item) < 1 then
        GSC.Notify.Send(src, string.format(Config.Text.FuelNone, log.label), 3000)
        return false
    end
    if take and not exports.vorp_inventory:subItem(src, log.item, 1) then
        GSC.Notify.Send(src, string.format(Config.Text.FuelNone, log.label), 3000)
        return false
    end
    return true
end

---o[ `uses` of water for this still ]o---
local function StillWater(src, uid, uses, failText)
    uses = uses or 1

    if FromStock() then
        local words = Config.Text.Stations or {}
        if not GSC.Stations.Has(uid, "water") then
            GSC.Notify.Send(src, words.NeedWater, 4000)
            return false
        end
        local litres = uses * (tonumber(((Config.Stations or {}).WaterBarrel or {}).PerUse) or 10)
        if not GSC.Stations.TakeWaterExact(uid, litres) then
            GSC.Notify.Send(src, string.format(words.WaterLow, math.floor(GSC.Stations.WaterLeft(uid))), 4000)
            return false
        end
        return true
    end

    if not UseWater(src, uses) then
        if failText then GSC.Notify.Send(src, failText, 3000) end
        return false
    end
    return true
end

---o[ Water in the condenser ]o---
local function TopUpCondenser(src, uid)
    local conf = Config.Condenser
    local level = BarrelCondenser[uid] or conf.StartLevel or 60

    if level >= 100 then
        return GSC.Notify.Send(src, Config.Text.CondenserFull, 3000)
    end

    if not StillWater(src, uid, 1, Config.Text.CoolingSysNotEnoughWater) then return end

    BarrelCondenser[uid] = math.min(100, level + (conf.TopUp or 30))

    GSC.Notify.Send(src, string.format(Config.Text.CondenserTopped, math.floor(BarrelCondenser[uid])), 3000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', src, "water")

    if BarrelCondenserHot[uid] and BarrelCondenser[uid] >= (conf.HotBelow or 25) then
        BarrelCondenserHot[uid] = nil
        NotifyBarrelWatchers(uid, Config.Text.CondenserCool, 4000)
        SyncDressing(uid)
    end

    SyncBarrelHeat(uid, BarrelHeat[uid] or 0.0, BarrelBrewProgress[uid] or 0, BarrelRemainingBottles[uid] or 0)
end

---oo[ Trouble At The Still ]oo---

local function StageFits(conf, stage, uid)
    for _, s in ipairs(conf.stages or {}) do
        if s == stage then
            return not conf.needsFire or FireLit(uid)
        end
    end
    return false
end

---o[ Nobody dealt with it in time ]o---
local function MissIncident(uid, conf)
    local mix = BarrelMix[uid] or {}
    BarrelMix[uid] = mix

    if conf.missLoss then
        mix.leakLoss = math.min(0.9, (tonumber(mix.leakLoss) or 0) + conf.missLoss)
    end
    if conf.missPutsOut and FireLit(uid) then PutOutFire(uid) end
    if conf.missWear then WearBarrel(uid, conf.missWear) end
    if conf.missPressure and Config.Pressure.Enabled then
        BarrelPressure[uid] = math.min(Config.Pressure.Max, (BarrelPressure[uid] or 0) + conf.missPressure)
    end
    if conf.missSpikeMinutes and BarrelStage[uid] == Shared.BarrelStage.FERMENTING then
        Distillery.SpikeWash(uid, conf.missSpikeMinutes * 60)
    end

    NotifyBarrel(uid, conf.missed, 6000)
    Shared.Debug(string.format("^1[Incident]^7 %s at %s went unanswered", conf.key, uid))
end

---o[ One second of it ]o---
local function TickIncidents(uid, stage, now)
    local conf = Config.Incidents
    if not conf or not conf.Enabled then return end

    local incident = BarrelIncident[uid]
    local active = ActiveIncident(uid)

    if incident and active then
        if not StageFits(active, stage, uid) then
            BarrelIncident[uid] = nil
            return
        end

        ---o[ While it lasts ]o---
        if active.leakPerSecond then
            local mix = BarrelMix[uid] or {}
            BarrelMix[uid] = mix
            mix.leakLoss = math.min(0.9, (tonumber(mix.leakLoss) or 0) + active.leakPerSecond)
        end
        if active.wearPerSecond then WearBarrel(uid, active.wearPerSecond) end

        if now >= incident.deadline then
            BarrelIncident[uid] = nil
            BarrelIncidentNext[uid] = now + (conf.MinGapSeconds or 60)
            MissIncident(uid, active)
        end
        return
    end

    ---o[ Something new? ]o---
    if not BarrelIncidentNext[uid] then
        BarrelIncidentNext[uid] = now + (conf.FirstAfterSeconds or 30)
        return
    end
    if now < BarrelIncidentNext[uid] then return end

    local fits, total = {}, 0
    for _, entry in ipairs(conf.List or {}) do
        if StageFits(entry, stage, uid) then
            fits[#fits + 1] = entry
            total = total + math.max(0, entry.weight or 1)
        end
    end
    if #fits == 0 or total <= 0 then return end
    if math.random() >= (conf.ChancePerMinute or 0) / 60.0 then return end

    local roll = math.random() * total
    local chosen = fits[#fits]
    for _, entry in ipairs(fits) do
        roll = roll - math.max(0, entry.weight or 1)
        if roll <= 0 then chosen = entry break end
    end

    BarrelIncident[uid] = { key = chosen.key, started = now, deadline = now + (chosen.window or 30) }
    BarrelIncidentNext[uid] = now + (conf.MinGapSeconds or 60)
    NotifyBarrel(uid, chosen.due, 6000)
    Shared.Debug(string.format("^3[Incident]^7 %s at %s", chosen.key, uid))
end

---o[ One second of the drip ]o---
local function TickCutRun(uid)
    if not BarrelCut[uid] then StartCutRun(uid) end
    local cut = BarrelCut[uid]

    local step = 100.0 / math.max(1, Config.Cuts.RunSeconds or 60)
    local progress = math.min(100.0, (BarrelBrewProgress[uid] or 0) + step)
    BarrelBrewProgress[uid] = progress

    local phase = PhaseAt(cut, progress)
    if phase ~= cut.phase then
        cut.phase = phase
        NotifyBarrelWatchers(uid, Config.Text.Cuts.Smell[phase], 4000)
    end

    if progress >= 100.0 then FinishCutRun(uid) end
end

---oo[ A client asks for every barrel itself ]oo---
RegisterServerEvent('gsc_kassippu:server:requestBarrels')
AddEventHandler('gsc_kassippu:server:requestBarrels', function()
    local _source = source
    if not BarrelsLoaded then return end
    local now = os.time()
    if LastBarrelRequest[_source] and now - LastBarrelRequest[_source] < 15 then return end
    LastBarrelRequest[_source] = now
    TriggerClientEvent('gsc_kassippu:client:syncAllBarrels', _source, BarrelSyncList(), BarrelStage)
end)

AddEventHandler('playerDropped', function()
    LastBarrelRequest[source] = nil
end)

---oo[ Brew state survives a restart ]oo---
local function Working(uid)
    local stage = BarrelStage[uid] or Shared.BarrelStage.IDLE
    return FireLit(uid) or (stage ~= Shared.BarrelStage.IDLE and stage ~= Shared.BarrelStage.COMPLETED)
end

CreateThread(function()
    while true do
        Wait(math.max(15, Config.KasiyaBarrelKitConf.SaveEverySeconds or 60) * 1000)
        if BarrelsLoaded then
            for uid in pairs(BarrelPositions) do
                if Working(uid) then SaveBarrelToDB(uid) end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() or not BarrelsLoaded then return end
    for uid in pairs(BarrelPositions) do SaveBarrelToDB(uid) end -- oxmysql is still up during a restart
end)

---oo[ Database To Character Sync On Character Selection ]oo---
AddEventHandler("vorp:SelectedCharacter", function(source, character)
    local _source = source

    SetTimeout(4000, function()
        TriggerClientEvent('gsc_kassippu:client:syncAllBarrels', _source, BarrelSyncList(), BarrelStage)
    end)
end)

---oo[ Rigging A Tarp Over A Still ]oo---
local function TarpOn()
    return Config.Fuel.Rain and Config.Fuel.Rain.TarpEnabled
end

local function RigTarp(_source, uid)
    if BarrelTarp[uid] then
        return GSC.Notify.Send(_source, Config.Text.TarpAlready, 3000)
    end

    if exports.vorp_inventory:getItemCount(_source, nil, Config.Items.StillTarp) < 1
        or not exports.vorp_inventory:subItem(_source, Config.Items.StillTarp, 1) then
        return GSC.Notify.Send(_source, Config.Text.TarpNone, 4000)
    end

    BarrelTarp[uid] = true
    BarrelSoak[uid] = nil
    SaveBarrelToDB(uid)
    SyncDressing(uid)

    GSC.Notify.Send(_source, Config.Text.TarpRigged, 5000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "tarp")
end

---o[ Used from the satchel while standing at a still ]o---
exports.vorp_inventory:registerUsableItem(Config.Items.StillTarp, function(data)
    local _source = data.source
    if not Shared.GetChar(_source) then return end
    if not TarpOn() then return end

    local uid = WatchedBarrel[_source]
    if not uid or not BarrelPositions[uid] then
        return GSC.Notify.Send(_source, Config.Text.TarpNotAtStill, 4000)
    end

    if not GSC.BarrelCrew.Allow(_source, uid, "repair") then return end

    exports.vorp_inventory:closeInventory(_source)
    RigTarp(_source, uid)
end)

---oo[ Fitting An Upgrade ]oo---
local function FitUpgrade(src, uid, key)
    local up = UpgradeList()[key]
    if not up or not up.item or BarrelDoomed[uid] then return end
    local label = up.label or key

    if not Shared.UpgradeUsable(up) then
        return GSC.Notify.Send(src, string.format(Config.Text.UpgradeNotUsed, label), 4000)
    end

    if BarrelUpgrades[uid] and BarrelUpgrades[uid][key] then
        return GSC.Notify.Send(src, string.format(Config.Text.UpgradeAlready, label), 3000)
    end

    if exports.vorp_inventory:getItemCount(src, nil, up.item) < 1
        or not exports.vorp_inventory:subItem(src, up.item, 1) then -- not taken: not fitted
        return GSC.Notify.Send(src, string.format(Config.Text.UpgradeNoItem, label), 4000)
    end

    BarrelUpgrades[uid] = BarrelUpgrades[uid] or {}
    BarrelUpgrades[uid][key] = true
    SaveBarrelToDB(uid)
    SyncBarrelHeat(uid, BarrelHeat[uid] or 0.0, BarrelBrewProgress[uid] or 0, BarrelRemainingBottles[uid] or 0)

    Shared.Debug(string.format("^2[Upgrade]^7 (ID: %s) fitted %s to %s", src, key, uid))
    GSC.Notify.Send(src, string.format(Config.Text.UpgradeFitted, label), 5000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', src, "upgrade")
end

for key, up in pairs(UpgradeList()) do
    if up.item then
        exports.vorp_inventory:registerUsableItem(up.item, function(data)
            local _source = data.source
            if not Shared.GetChar(_source) then return end

            local uid = WatchedBarrel[_source]
            if not uid or not BarrelPositions[uid] then
                return GSC.Notify.Send(_source, Config.Text.UpgradeNotAtStill, 4000)
            end

            if not GSC.BarrelCrew.Allow(_source, uid, "repair") then return end

            exports.vorp_inventory:closeInventory(_source)
            FitUpgrade(_source, uid, key)
        end)
    end
end

---oo[ Spent Mash: horse feed ]oo---
if Config.SpentMash and Config.SpentMash.Enabled and Config.SpentMash.HorseFeed then
    exports.vorp_inventory:registerUsableItem(Config.SpentMash.Item, function(data)
        if not Shared.GetChar(data.source) then return end
        exports.vorp_inventory:closeInventory(data.source)
        TriggerClientEvent('gsc_kassippu:client:feedHorse', data.source)
    end)

    RegisterServerEvent('gsc_kassippu:server:fedHorse')
    AddEventHandler('gsc_kassippu:server:fedHorse', function()
        local _source = source
        if not Shared.GetChar(_source) then return end
        if exports.vorp_inventory:getItemCount(_source, nil, Config.SpentMash.Item) < 1 then return end

        if not exports.vorp_inventory:subItem(_source, Config.SpentMash.Item, 1) then return end
        TriggerClientEvent('gsc_kassippu:client:horseFed', _source)
        GSC.Notify.Send(_source, Config.Text.SpentMashFed, 3000)
    end)
end

---oo[ Setting Down A Kit ]oo---
local PendingKit = {} -- [src] = { id, meta }

---o[ Has this character already set down Config.KasiyaBarrelKitConf.MaxPerPlayer barrels? Tells him if so ]o---
local function AtBarrelLimit(src, Character)
    local limit = tonumber(Config.KasiyaBarrelKitConf.MaxPerPlayer) or 0
    if limit <= 0 then return false end
    if not BarrelsLoaded then return true end

    local ownerId, identifier, owned = OwnerIdOf(Character), Character.identifier, 0
    for _, owner in pairs(BarrelOwner) do
        if owner == ownerId or owner == identifier then owned = owned + 1 end -- old rows hold the identifier
    end
    if owned < limit then return false end

    GSC.Notify.SendObjective(src, string.format(Config.Text.BarrelLimitReached, limit), 4000)
    return true
end

AddEventHandler('playerDropped', function()
    PendingKit[source] = nil
end)

exports.vorp_inventory:registerUsableItem(Config.KasiyaBarrelKitConf.KasiyaBarrelItemName, function(data)
    local _source = data.source
    local Character = Shared.GetChar(_source)
    if not Character then return end
    if AtBarrelLimit(_source, Character) then return end

    local item = data.item
    if type(item) == 'table' and item.id and type(item.metadata) == 'table' and item.metadata.condition then
        PendingKit[_source] = { id = item.id, meta = item.metadata }
    else
        PendingKit[_source] = nil
    end

    Shared.Debug(string.format("^6[UsableItems]^7 (ID: %s) %s used Barrel Kit", _source, Character.firstname))

    exports.vorp_inventory:closeInventory(_source)
    TriggerClientEvent('gsc_kassippu:client:startPlacement', _source)
end)

---oo[ Save Barrel Item On Database After Placed ]oo---
RegisterServerEvent('gsc_kassippu:server:saveBarrel')
AddEventHandler('gsc_kassippu:server:saveBarrel', function(_, coords, heading)
    local _source = source
    local Character = Shared.GetChar(_source)
    if not Character or type(coords) ~= 'table' and type(coords) ~= 'vector3' then return end

    local pos = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)

    if #(GetEntityCoords(GetPlayerPed(_source)) - pos) > 6.0 then
        Shared.Debug("^1[Warning]^7 Player " .. _source .. " tried to place a barrel from too far away.")
        return
    end

    if AtBarrelLimit(_source, Character) then return end

    ---o[ Room for the barrel and its fire ]o---
    for _, other in pairs(BarrelPositions) do
        if #(other - pos) < 2.0 then
            return GSC.Notify.SendObjective(_source, Config.Text.BarrelTooClose, 3000)
        end
    end

    local kit = Config.KasiyaBarrelKitConf.KasiyaBarrelItemName
    if exports.vorp_inventory:getItemCount(_source, nil, kit) < 1 then return end

    local pending = PendingKit[_source]
    PendingKit[_source] = nil
    if pending and exports.vorp_inventory:subItemById(_source, pending.id, nil, nil, 1) == false then
        pending = nil
    end
    if not pending and not exports.vorp_inventory:subItem(_source, kit, 1) then
        return -- no kit taken: no barrel
    end

    local uid = Shared.GenerateBarrelUID(pos)

    BarrelPositions[uid] = pos
    BarrelHeadings[uid] = tonumber(heading) or 0.0
    BarrelOwner[uid] = OwnerIdOf(Character)
    BarrelStage[uid] = Shared.BarrelStage.IDLE
    BarrelFuelCount[uid] = 0
    BarrelHeat[uid] = 0.0

    ---o[ A picked-up barrel comes back as she was ]o---
    local meta = pending and pending.meta
    BarrelUpgrades[uid] = nil
    BarrelTarp[uid] = nil
    if meta then
        local max = Config.BarrelCondition.Max
        BarrelCondition[uid] = math.max(0.0, math.min(max, tonumber(meta.condition) or max))
        BarrelResidue[uid] = math.max(0.0, tonumber(meta.residue) or 0.0)
        BarrelUsageCount[uid] = math.max(0, math.floor(tonumber(meta.usage) or 0))
        BarrelRepairCount[uid] = math.max(0, math.floor(tonumber(meta.repairs) or 0))
        BarrelTarp[uid] = meta.tarp == true or nil
        SetUpgrades(uid, meta.upgrades)
    end

    ---o[ Save Barrel Item On Database Calling SaveBarrelToDB Function ]o---
    SaveBarrelToDB(uid)

    TriggerClientEvent('gsc_kassippu:client:syncNewBarrel', -1, uid,
        { x = pos.x, y = pos.y, z = pos.z }, BarrelHeadings[uid])
    GSC.Notify.SendObjective(_source, Config.Text.KasiyaBarrelPlacementSuccess, 3000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "place_still")
end)

---oo[ Wood Addon To Barrel Event ]oo---
RegisterServerEvent('gsc_kassippu:server:addOneWood')
AddEventHandler('gsc_kassippu:server:addOneWood', function(uid, kind)
    local _source = source
    local Character = Shared.GetChar(_source)
    if not Character or type(uid) ~= 'string' then return end

    ---o[ Check Barrel is Already Exists Using UID ]o---
    if not BarrelPositions[uid] then
        Shared.Debug("^1[Error]^7 UID " .. uid .. " not found in BarrelPositions.")
        return
    end

    local log = Config.Fuel.Logs[kind or "wood"]
    if not log then return end

    if not GSC.BarrelCrew.Allow(_source, uid, "fuel") then return end

    if #(GetEntityCoords(GetPlayerPed(_source)) - BarrelPositions[uid])
        > (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0) then
        Shared.Debug("^1[Warning]^7 Player " .. _source .. " tried to add wood from too far away.")
        return
    end

    if not StillLog(_source, uid, kind or "wood", false) then return end

    if not BarrelHeat[uid] then BarrelHeat[uid] = 0.0 end
    local stage = BarrelStage[uid] or Shared.BarrelStage.IDLE
    if stage == Shared.BarrelStage.FINAL_PUSH and PushGameOn() then return end -- the game stokes instead (pushStoke)

    ---o[ The fire under a fermenting wash ends the ferment ]o---
    if stage == Shared.BarrelStage.FERMENTING then
        if LightUnderWash(_source, uid) then
            if StillLog(_source, uid, kind or "wood", true) then AddLog(uid, log) end
            SaveBarrelToDB(uid)
            TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "wood")
        end
        return
    end

    if not TakesWood(stage) then return end

    if (BarrelFuelCount[uid] or 0) + log.burnSeconds > (Config.Fuel.MaxBurnSeconds or math.huge) then
        return GSC.Notify.Send(_source, Config.Text.FuelBoxFull, 3000)
    end

    if not StillLog(_source, uid, kind or "wood", true) then return end
    AddLog(uid, log)

    Shared.Debug(string.format("^6[WoodAddons]^7 (ID: %s) %s put %s on %s: %.0fs, power %.2f",
        _source, Character.firstname, kind or "wood", uid, BarrelFuelCount[uid], BarrelFirePower[uid]))

    if stage == Shared.BarrelStage.FINAL_PUSH then
        BarrelHeat[uid] = BarrelHeat[uid] + (Config.Fuel.ManualBoost or 0) * log.power
        if BarrelHeat[uid] >= Config.HeatManagement.MaxHeat then
            TriggerEvent('gsc_kassippu:server:explodeBarrel', uid, "overfed")
            return
        end
    end

    GSC.Notify.Send(_source,
        string.format(Config.Text.FuelAdded, log.label, math.floor(BarrelFuelCount[uid])), 3000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "wood")
    SyncBarrelHeat(uid, BarrelHeat[uid], BarrelBrewProgress[uid] or 0, BarrelRemainingBottles[uid] or 0)
    SaveBarrelToDB(uid)
end)

---oo[ Hold The Heat - the game (Config.HeatSkill.Game) ]oo---

local function AtStillToo(src, uid)
    return #(GetEntityCoords(GetPlayerPed(src)) - BarrelPositions[uid])
        <= (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0)
end

---o[ One second of the push ]o---
TickPushGame = function(uid, heat, lit, game)
    local st = PushState(uid)

    if lit then
        heat = heat - (tonumber(game.Sag) or 0.4)
    else
        heat = heat - (Config.Fuel.PushCoolRate or 0.6)
    end

    local keep = {}
    for _, stoke in ipairs(st.stokes) do
        heat = heat + stoke.perSec
        stoke.left = stoke.left - 1
        if stoke.left > 0 then keep[#keep + 1] = stoke end
    end
    st.stokes = keep

    local open = false
    for src in pairs(st.taps) do
        if GetPlayerName(src) and AtStillToo(src, uid) then open = true else st.taps[src] = nil end
    end
    if open then
        local want = tonumber(game.TapWater) or 1.0
        local got = GSC.Stations.TakeWater(uid, want)
        if got > 0 then
            heat = heat - (tonumber(game.TapCool) or 1.5) * (got / want)
        else
            st.taps = {}
            NotifyBarrelWatchers(uid, (Config.Text.PushGame or {}).WaterEmpty, 3000)
        end
    end

    return math.max(0.0, heat)
end

---o[ May this player work the push of this still right now? ]o---
local function PushReady(src, uid, right)
    if type(uid) ~= 'string' or not BarrelPositions[uid] then return false end
    if BarrelStage[uid] ~= Shared.BarrelStage.FINAL_PUSH or not PushGameOn() then return false end
    if not Shared.GetChar(src) or not AtStillToo(src, uid) then return false end
    return GSC.BarrelCrew.Allow(src, uid, right)
end

---o[ No split on the rack ]o---
local function SatchelLog(src)
    if FromStock() then return nil end -- the rack is the only wood
    local order = ((Config.Stations or {}).LogRack or {}).BurnOrder or {}
    local seen = {}
    local function Try(kind)
        local log = Config.Fuel.Logs[kind]
        if not log or seen[kind] then return nil end
        seen[kind] = true
        if (exports.vorp_inventory:getItemCount(src, nil, log.item) or 0) < 1 then return nil end
        if not exports.vorp_inventory:subItem(src, log.item, 1) then return nil end
        return kind
    end
    for _, kind in ipairs(order) do
        local got = Try(kind)
        if got then return got end
    end
    for kind in pairs(Config.Fuel.Logs) do
        local got = Try(kind)
        if got then return got end
    end
    return nil
end

RegisterServerEvent('gsc_kassippu:server:pushStoke')
AddEventHandler('gsc_kassippu:server:pushStoke', function(uid)
    local _source = source
    if not PushReady(_source, uid, "fuel") then return end

    local game = PushGameOn()
    local st = PushState(uid)
    local now = GetGameTimer()
    if st.stokeAt[_source] and now - st.stokeAt[_source] < (tonumber(game.StokeCooldown) or 1.0) * 1000 then return end
    st.stokeAt[_source] = now

    local power, kind = GSC.Stations.TakeSplit(uid)
    if not power then
        kind = SatchelLog(_source)
        if not kind then
            return GSC.Notify.Send(_source, (Config.Text.PushGame or {}).NoWood, 3000)
        end
        power = tonumber(Config.Fuel.Logs[kind].power) or 1.0
        if GSC.Stations.Has(uid, "rack") and not st.rackWarned then
            st.rackWarned = true
            GSC.Notify.Send(_source, (Config.Text.PushGame or {}).RackEmpty, 4000)
        end
    end

    ---o[ The fire went out (rain, ash): the split brings it back ]o---
    if not FireLit(uid) and Config.Fuel.Logs[kind] then
        AddLog(uid, Config.Fuel.Logs[kind])
        SyncDressing(uid)
        GSC.Notify.Send(_source, (Config.Text.PushGame or {}).Rekindled, 3000)
    end

    local seconds = math.max(1, math.floor(tonumber(game.StokeSeconds) or 3))
    local total = (tonumber(game.StokeHeat) or 3.0) * power * IncidentFactor(uid, "powerMultiplier")
    st.stokes[#st.stokes + 1] = { left = seconds, perSec = total / seconds }

    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "wood")
end)

RegisterServerEvent('gsc_kassippu:server:pushTap')
AddEventHandler('gsc_kassippu:server:pushTap', function(uid, open)
    local _source = source
    if open ~= true then
        local st = type(uid) == 'string' and PushGame[uid] or nil
        if st then st.taps[_source] = nil end
        return
    end
    if not PushReady(_source, uid, "cool") then return end

    local st = PushState(uid)
    if GSC.Stations.Has(uid, "water") then
        if GSC.Stations.WaterLeft(uid) <= 0 then
            return GSC.Notify.Send(_source, (Config.Text.PushGame or {}).WaterEmpty, 3000)
        end
        st.taps[_source] = true
        return
    end

    ---o[ No water barrel ]o---
    if FromStock() then
        return GSC.Notify.Send(_source, (Config.Text.Stations or {}).NeedWater, 4000)
    end
    local now = GetGameTimer()
    if st.pourAt and now - st.pourAt < 1000 then return end
    st.pourAt = now
    if not UseWater(_source, 1) then
        return GSC.Notify.Send(_source, (Config.Text.PushGame or {}).NoWater, 3000)
    end
    BarrelHeat[uid] = math.max(0.0, (BarrelHeat[uid] or 0.0) - Config.CoolingSystem.HeatReductionValue)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "water")
    SyncBarrelHeat(uid, BarrelHeat[uid], BarrelBrewProgress[uid] or 0, BarrelRemainingBottles[uid] or 0)
end)

---oo[ Water Addon Event For Barrel ]oo---
RegisterServerEvent('gsc_kassippu:server:addWater')
AddEventHandler('gsc_kassippu:server:addWater', function(uid)
    local _source = source
    local Character = Shared.GetChar(_source)
    if not Character then return end

    ---o[ Check Barrel UID Actually On Databse ]o---
    if not BarrelPositions[uid] then
        Shared.Debug("^1[Error]^7 UID " .. tostring(uid) .. " not found in BarrelPositions for Water event.")
        return
    end

    ---o[ Only where the still offers water ]o---
    local waterStage = BarrelStage[uid]
    if not (waterStage == Shared.BarrelStage.HEAT_PAUSE or waterStage == Shared.BarrelStage.FINAL_PUSH
        or (waterStage == Shared.BarrelStage.BREWING and Config.Condenser.Enabled)) then
        return
    end

    if not GSC.BarrelCrew.Allow(_source, uid, "cool") then return end
    if BarrelStage[uid] == Shared.BarrelStage.FINAL_PUSH and PushGameOn() then return end -- the game's tap instead (pushTap)

    ---o[ During the run the water goes in the condenser, not on the fire ]o---
    if BarrelStage[uid] == Shared.BarrelStage.BREWING and Config.Condenser.Enabled then
        if #(GetEntityCoords(GetPlayerPed(_source)) - BarrelPositions[uid])
            > (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0) then
            return
        end
        return TopUpCondenser(_source, uid)
    end

    Shared.Debug(string.format("^6[WaterAddons]^7 (ID: %s) %s for UID: %s", _source, Character.firstname, uid))

    local playerPed = GetPlayerPed(_source)
    local playerCoords = GetEntityCoords(playerPed)
    local barrelCoords = BarrelPositions[uid]

    if #(playerCoords - barrelCoords) <= (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0) then
        local count = FromStock() and 1 or WaterUsesLeft(_source)

        if count >= 1 then
            if not BarrelHeat[uid] then BarrelHeat[uid] = 0.0 end
            local currentHeat = BarrelHeat[uid]

            if currentHeat > 0 and not StillWater(_source, uid, 1) then
                return
            elseif currentHeat > 0 then
                local reduction = Config.CoolingSystem.HeatReductionValue
                BarrelHeat[uid] = math.max(0.0, currentHeat - reduction)

                GSC.Notify.Send(_source, Config.Text.CoolingSysAddedWater .. math.floor(BarrelHeat[uid]) .. "%",
                    3000)
                TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "water")
                if BarrelHeat[uid] < 36.0 and BarrelStage[uid] ~= Shared.BarrelStage.IDLE then
                    BarrelStage[uid] = Shared.BarrelStage.IDLE
                    ClearRunState(uid)
                    TriggerClientEvent('gsc_kassippu:client:updateStage', -1, uid, Shared.BarrelStage.IDLE)
                end

                SyncBarrelHeat(uid, BarrelHeat[uid])
            else
                GSC.Notify.Send(_source, Config.Text.CoolingSysAlreadyCold, 3000)
            end
        else
            GSC.Notify.Send(_source, Config.Text.CoolingSysNotEnoughWater .. Character.firstname .. "!", 3000)
        end
    else
        Shared.Debug("^1[Warning]^7 Player " .. _source .. " tried to add water from too far away.")
    end
end)

---oo[ Vent Pressure Event ]oo---
RegisterServerEvent('gsc_kassippu:server:ventBarrel')
AddEventHandler('gsc_kassippu:server:ventBarrel', function(uid)
    local _source = source
    local Character = Shared.GetChar(_source)
    if not Character then return end

    if not Config.Pressure.Enabled then return end

    if not BarrelPositions[uid] then
        Shared.Debug("^1[Error]^7 UID " .. tostring(uid) .. " not found in BarrelPositions for Vent event.")
        return
    end

    if not GSC.BarrelCrew.Allow(_source, uid, "vent") then return end

    ---o[ Same range check every other barrel action uses ]o---
    local playerCoords = GetEntityCoords(GetPlayerPed(_source))
    local barrelCoords = BarrelPositions[uid]

    if #(playerCoords - barrelCoords) > (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0) then
        Shared.Debug("^1[Warning]^7 Player " .. _source .. " tried to vent from too far away.")
        return
    end

    local pressure = BarrelPressure[uid] or 0.0
    if pressure <= 0.0 then
        return GSC.Notify.Send(_source, Config.Text.PressureNothingToVent, 3000)
    end

    BarrelPressure[uid] = math.max(0.0, pressure - Config.Pressure.VentAmount)
    BarrelHeat[uid] = math.max(0.0, (BarrelHeat[uid] or 0.0)
        - Config.Pressure.VentHeatCost * UpgradeProduct(uid, "ventHeatMultiplier"))
    BarrelPressureWarned[uid] = nil

    Shared.Debug(string.format("^3[Vent]^7 (ID: %s) %s vented %s: pressure %.0f, heat %.1f",
        _source, Character.firstname, uid, BarrelPressure[uid], BarrelHeat[uid]))

    GSC.Notify.Send(_source,
        Config.Text.PressureVented .. math.floor(BarrelPressure[uid]) .. "%", 3000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "vent")

    SyncBarrelHeat(uid, BarrelHeat[uid], BarrelBrewProgress[uid] or 0, BarrelRemainingBottles[uid] or 0)
end)

---oo[ Maintenance: Scrub and Repair ]oo---

local function ValidateMaintenance(src, uid, action)
    local Character = Shared.GetChar(src)
    if not Character then return nil end

    if not Config.BarrelCondition.Enabled then return nil end

    if not BarrelPositions[uid] then
        Shared.Debug("^1[Error]^7 UID " .. tostring(uid) .. " not found for maintenance.")
        return nil
    end

    if not GSC.BarrelCrew.Allow(src, uid, action) then return nil end

    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    if #(playerCoords - BarrelPositions[uid]) > (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0) then
        Shared.Debug("^1[Warning]^7 Player " .. src .. " tried maintenance from too far away.")
        return nil
    end

    if (BarrelStage[uid] or Shared.BarrelStage.IDLE) ~= Shared.BarrelStage.IDLE then
        GSC.Notify.Send(src, Config.Text.ScrubWrongStage, 4000)
        return nil
    end

    return Character
end

---o[ Scrub the fouling out ]o---
RegisterServerEvent('gsc_kassippu:server:scrubBarrel')
AddEventHandler('gsc_kassippu:server:scrubBarrel', function(uid)
    local _source = source
    local Character = ValidateMaintenance(_source, uid, "scrub")
    if not Character then return end

    local conf = Config.BarrelCondition

    if GetResidue(uid) <= 0.0 then
        return GSC.Notify.Send(_source, Config.Text.ScrubNothingToDo, 3000)
    end

    if not StillWater(_source, uid, conf.ScrubUses or 1, Config.Text.ScrubNoItem) then return end

    BarrelResidue[uid] = math.max(0.0, GetResidue(uid) - conf.ScrubRemoves)

    Shared.Debug(string.format("^2[Scrub]^7 (ID: %s) %s scrubbed %s: residue %.0f",
        _source, Character.firstname, uid, GetResidue(uid)))

    GSC.Notify.Send(_source, Config.Text.ScrubDone .. math.floor(GetResidue(uid)) .. "%", 3000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "scrub")

    SaveBarrelToDB(uid)
    SyncBarrelHeat(uid, BarrelHeat[uid] or 0.0, BarrelBrewProgress[uid] or 0, BarrelRemainingBottles[uid] or 0)
end)

---oo[ The Barrel Repair Kit (several uses, like the water bucket) ]oo---

local function RepairKitFull()
    return math.max(1, math.floor(tonumber(Config.BarrelCondition.RepairKitUses) or 1))
end

---o[ Uses left in one kit: no metadata yet = a new kit ]o---
local function RepairKitUses(item)
    local full = RepairKitFull()
    local left = tonumber(item.metadata and item.metadata.repairUsesLeft) or full
    return math.max(0, math.min(full, math.floor(left)))
end

---o[ The player's kits, the most worn first ]o---
local function RepairKits(src)
    local name = Config.BarrelCondition.RepairItem
    local list = {}
    for _, item in ipairs(exports.vorp_inventory:getUserInventoryItems(src) or {}) do
        if item.name == name and (tonumber(item.count) or 0) > 0 then list[#list + 1] = item end
    end
    table.sort(list, function(a, b) return RepairKitUses(a) < RepairKitUses(b) end)
    return list
end

local function RepairUsesLeft(src)
    local total = 0
    for _, item in ipairs(RepairKits(src)) do total = total + RepairKitUses(item) * item.count end
    return total
end

---o[ Take `uses` from the player's kits ]o---
local function UseRepairKit(src, uses)
    if RepairUsesLeft(src) < uses then return false end

    local full = RepairKitFull()
    for _ = 1, 20 do
        if uses <= 0 then break end
        local kit = RepairKits(src)[1]
        if not kit then return false end

        local left = RepairKitUses(kit)
        local take = math.min(left, uses)
        uses = uses - take
        left = left - take

        if left <= 0 then
            if not exports.vorp_inventory:subItemById(src, kit.id, nil, nil, 1) then return false end
            GSC.Notify.Send(src, Config.Text.RepairKitUsedUp, 3000)
        else
            local meta = {}
            for k, v in pairs(kit.metadata or {}) do meta[k] = v end
            meta.repairUsesLeft = left
            meta.description = string.format(Config.Text.RepairKitDescription, left, full)
            exports.vorp_inventory:setItemMetadata(src, kit.id, meta, 1) -- one kit off the stack
        end
    end
    return true
end

---o[ Mend the staves ]o---
RegisterServerEvent('gsc_kassippu:server:repairBarrel')
AddEventHandler('gsc_kassippu:server:repairBarrel', function(uid)
    local _source = source
    local Character = ValidateMaintenance(_source, uid, "repair")
    if not Character then return end

    local conf = Config.BarrelCondition

    if BarrelDoomed[uid] then return end

    ---o[ Lifetime cap: checked before the kit is taken ]o---
    if RepairsLeft(uid) == 0 then
        return GSC.Notify.Send(_source, Config.Text.RepairLimitReached, 4000)
    end

    if GetCondition(uid) >= conf.Max then
        return GSC.Notify.Send(_source, Config.Text.RepairNotNeeded, 3000)
    end

    if not UseRepairKit(_source, math.max(1, math.floor(tonumber(conf.RepairCost) or 1))) then
        return GSC.Notify.Send(_source, Config.Text.RepairNoItem, 4000)
    end
    BarrelCondition[uid] = math.min(conf.Max, GetCondition(uid) + conf.RepairRestores)
    BarrelConditionWarned[uid] = nil
    BarrelRepairCount[uid] = (BarrelRepairCount[uid] or 0) + 1

    Shared.Debug(string.format("^2[Repair]^7 (ID: %s) %s mended %s: condition %.0f, repair %d",
        _source, Character.firstname, uid, GetCondition(uid), BarrelRepairCount[uid]))

    local msg = Config.Text.RepairDone .. math.floor(GetCondition(uid)) .. "%"
    local repairsLeft, batchesLeft = RepairsLeft(uid), BatchesLeft(uid)
    if repairsLeft then
        msg = msg .. (repairsLeft > 0 and string.format(Config.Text.RepairsLeft, repairsLeft)
            or Config.Text.RepairLastOne)
    end
    if batchesLeft then msg = msg .. string.format(Config.Text.BatchesLeft, batchesLeft) end
    GSC.Notify.Send(_source, msg, 5000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "repair")

    SaveBarrelToDB(uid)
    SyncBarrelHeat(uid, BarrelHeat[uid] or 0.0, BarrelBrewProgress[uid] or 0, BarrelRemainingBottles[uid] or 0)
end)

---o[ One mix at a time per still: claimed before anything waits, so a second request can't use the same stash ]o---
local MixClaim = {}          -- [uid] = os.time() the mix was claimed
local MIX_CLAIM_SECONDS = 15 -- a claim whose stash read never answered lapses after this

local function MixClaimed(uid)
    local at = MixClaim[uid]
    return at ~= nil and (os.time() - at) < MIX_CLAIM_SECONDS
end

---o[ Register And Open Barrel Stash ]o---
RegisterServerEvent('gsc_kassippu:server:openBarrelInv')
AddEventHandler('gsc_kassippu:server:openBarrelInv', function(uid)
    local _source = source
    local Character = Shared.GetChar(_source)
    if not Character then return end

    ---o[ Check UID Exists On Database ]o---
    if not BarrelPositions[uid] then
        Shared.Debug("^1[Error]^7 UID " .. tostring(uid) .. " not found in BarrelPositions for Inventory.")
        return
    end

    if not GSC.BarrelCrew.Allow(_source, uid, "ingredients") then return end

    ---o[ Only standing at it: the stash is not remote storage ]o---
    if #(GetEntityCoords(GetPlayerPed(_source)) - BarrelPositions[uid])
        > (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0) then
        Shared.Debug("^1[Warning]^7 Player " .. _source .. " tried to open stash " .. uid .. " from too far away.")
        return
    end

    ---o[ Not while the wash is being mixed out of it ]o---
    if MixClaimed(uid) then
        return GSC.Notify.Send(_source, Config.Text.StashBusyMixing, 3000)
    end

    local stage = BarrelStage[uid] or Shared.BarrelStage.IDLE
    Shared.Debug(string.format("^6[BarrelStash]^7 (ID: %s) %s for UID: %s", _source, Character.firstname, uid))

    ---o[ Define Inventory ID To Barrel UID ]o---
    local invId = uid

    ---o[ Register Barrel Stash Using VORP Inventory ]o---
    RegisterStash(invId)
    ---o[ Stash Open Event ]o---
    exports.vorp_inventory:openInventory(_source, invId)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "store")

    Shared.Debug("^2[GSC_KASSIPPU]^7 Opened stash: " .. invId .. " | Stage: " .. stage)
end)

---o[ Barrel Items Mixing Event ]o---
RegisterServerEvent('gsc_kassippu:server:startMixing')
AddEventHandler('gsc_kassippu:server:startMixing', function(uid, recipeKey, climate)
    local _source = source
    local Character = Shared.GetChar(_source)
    if not Character then return end

    ---o[ Where the wash will ferment ]o---
    local fermentTemp, fermentSheltered = nil, false
    if type(climate) == 'table' then
        fermentTemp = tonumber(climate.temp)
        if fermentTemp then fermentTemp = math.max(-40.0, math.min(60.0, fermentTemp)) end
        fermentSheltered = climate.sheltered == true
    end

    ---o[ Check Barrel UID Exists On Database ]o---
    if not BarrelPositions[uid] then
        Shared.Debug("^1[Error]^7 UID " .. tostring(uid) .. " not found in BarrelPositions for Mixing.")
        return
    end

    if not GSC.BarrelCrew.Allow(_source, uid, "mix") then return end

    if #(GetEntityCoords(GetPlayerPed(_source)) - BarrelPositions[uid])
        > (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0) then
        Shared.Debug("^1[Warning]^7 Player " .. _source .. " tried to mix " .. uid .. " from too far away.")
        return
    end

    ---o[ Convert Inventory ID to Barrel UID ]o---
    local invId = uid
    local recipe = Config.Recipes[recipeKey]

    Shared.Debug(string.format("^6[Mixing]^7 (ID: %s) %s for UID: %s", _source, Character.firstname, uid))

    ---o[ Stage Check ]o---
    if BarrelStage[uid] ~= Shared.BarrelStage.FREEZE then
        return GSC.Notify.Send(_source, Config.Text.MixingNotReady, 4000)
    end

    if not recipe then return end

    if not GSC.Mash.Knows(_source, recipeKey) then
        return GSC.Notify.Send(_source, Config.Text.RecipeUnknown, 4000)
    end

    ---o[ Claim the still now, before the stash read waits: a second request is turned away ]o---
    if MixClaimed(uid) then return end
    MixClaim[uid] = os.time()

    ---o[ Shut the stash on everyone else at the still, so nothing leaves it between the read and the clear ]o---
    local here = BarrelPositions[uid]
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        local ped = target and target ~= _source and GetPlayerPed(playerId)
        if ped and ped ~= 0 and #(GetEntityCoords(ped) - here) <= 10.0 then
            exports.vorp_inventory:closeInventory(target)
        end
    end

    ---o[ Read the barrel ]o---
    RegisterStash(invId)
    exports.vorp_inventory:getCustomInventoryItems(invId, function(storedItems)
        local function Release() MixClaim[uid] = nil end

        if BarrelStage[uid] ~= Shared.BarrelStage.FREEZE then return Release() end

        local stacks = (tonumber(recipe.coconutMl) or 0) > 0 and GSC.Mash.CoconutStacks(_source) or nil
        local mash = GSC.Mash.Evaluate(recipeKey, storedItems, stacks, os.time())

        if not mash.ok then
            Release()
            Shared.Debug("^1[Mixing]^7 Refused: " .. tostring(mash.problems[1]))
            TriggerClientEvent('gsc_kassippu:client:mixPreview', _source, uid, recipeKey, mash)
            return GSC.Notify.Send(_source, mash.problems[1], 5000)
        end

        ---o[ Room for the containers that come back (empty pots), before anything is used ]o---
        for item, count in pairs(mash.returns or {}) do
            if not exports.vorp_inventory:canCarryItem(_source, item, count) then
                Release()
                return GSC.Notify.Send(_source, string.format(Config.Text.MashNoRoomForReturns, count), 5000)
            end
        end

        if mash.coconutMl > 0 then
            GSC.Mash.UseCoconut(_source, stacks, mash.coconutMl)
        end

        ClearStash(invId, function()
            SaveBarrelToDB(uid)
            Shared.Debug("^2[DATABASE]^7 Cleared items for inventory: " .. invId)
        end)

        for item, count in pairs(mash.returns or {}) do
            exports.vorp_inventory:addItem(_source, item, count)
        end

        ---o[ Update Barrel Data ]o---
        BarrelLoaded[uid] = recipeKey
        BarrelStage[uid] = Shared.BarrelStage.MIXING
        Release() -- the stage guards it from here
        PutOutFire(uid)

        BarrelMix[uid] = {
            batch = mash.batch,
            strength = mash.strength,
            inheritedTaint = mash.tainted or nil,
            scoreMod = mash.scoreMod,
            fruit = mash.fruit,
            stale = mash.stale,
        }

        if mash.clog > 0 and Config.BarrelCondition.Enabled then
            BarrelResidue[uid] = math.min(Config.BarrelCondition.ResidueMax, GetResidue(uid) + mash.clog)
        end

        if Config.Fermentation.Enabled then
            BarrelFerment[uid] = { started = 0, temp = fermentTemp, sheltered = fermentSheltered, spiked = 0 }
        end

        ---o[ Stirring - or, with that switched off, a plain wait ]o---
        local stir = Config.Mixing.Stir
        if stir and stir.Enabled then
            BarrelStirPending[uid] = _source
            BarrelStageDeadline[uid] = os.time() + (stir.WaitSeconds or 30)
        else
            BarrelStageDeadline[uid] = os.time() + math.ceil(Config.Mixing.Time / 1000)
        end

        TriggerClientEvent('gsc_kassippu:client:updateStage', -1, uid, Shared.BarrelStage.MIXING)

        local batchName = (Config.Text.BatchNames or {})[mash.batch] or tostring(mash.batch)
        GSC.Notify.Send(_source, string.format(Config.Text.MixingItemsMatched, batchName, mash.product), 5000)
        for _, warning in ipairs(mash.warnings) do
            GSC.Notify.Send(_source, warning, 5000)
        end

        if BarrelStirPending[uid] == _source then
            BarrelStirSentAt[uid] = GetGameTimer()
            BarrelStirTries[uid] = 1
            TriggerClientEvent('gsc_kassippu:client:stirMash', _source, uid, recipeKey) -- the recipe stocks the spoon's tray
        end

        Shared.Debug(string.format("^2[Mixing]^7 %s: %dx %s, score %+d, clog %.0f",
            uid, mash.batch, tostring(mash.strength), mash.scoreMod, mash.clog))
    end)
end)

---oo[ Stirring The Mash ]oo---
RegisterServerEvent('gsc_kassippu:server:stirResult')
AddEventHandler('gsc_kassippu:server:stirResult', function(uid, passed)
    local _source = source
    if type(uid) ~= 'string' or BarrelStirPending[uid] ~= _source then return end
    BarrelStirPending[uid] = nil

    if BarrelStage[uid] ~= Shared.BarrelStage.MIXING then return end

    local stir = Config.Mixing.Stir
    BarrelMix[uid] = BarrelMix[uid] or {}

    ---o[ Sooner than a real stir can be won: it counts as bad ]o---
    local took = (GetGameTimer() - (BarrelStirSentAt[uid] or 0)) / 1000.0
    BarrelStirSentAt[uid] = nil
    if passed == true and took < (stir.MinSeconds or 0) then
        Shared.Debug(string.format("^1[Stir]^7 (ID: %s) result after %.2fs - too fast, counted as bad", _source, took))
        passed = false
    end

    ---o[ A failed stir gets another go while tries are left ]o---
    local tries = BarrelStirTries[uid] or 1
    if passed ~= true and tries < (tonumber(stir.Tries) or 1) then
        local delay = tonumber(stir.RetryDelay) or 3
        BarrelStirPending[uid] = _source
        BarrelStageDeadline[uid] = os.time() + delay + (stir.WaitSeconds or 30)
        GSC.Notify.Send(_source, string.format(Config.Text.StirRetry, (tonumber(stir.Tries) or 1) - tries), 4000, "warning")

        SetTimeout(math.floor(delay * 1000), function()
            if BarrelStirPending[uid] ~= _source or BarrelStage[uid] ~= Shared.BarrelStage.MIXING then return end
            if not GetPlayerName(_source) or not BarrelPositions[uid] then return end -- gone: the deadline counts it missed
            if #(GetEntityCoords(GetPlayerPed(_source)) - BarrelPositions[uid])
                > (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0) then return end -- walked off: missed too
            BarrelStirTries[uid] = tries + 1
            BarrelStirSentAt[uid] = GetGameTimer()
            TriggerClientEvent('gsc_kassippu:client:stirMash', _source, uid, BarrelLoaded[uid])
        end)
        Shared.Debug(string.format("^6[Stir]^7 (ID: %s) failed try %d on %s - again in %ds", _source, tries, uid, delay))
        return
    end
    BarrelStirTries[uid] = nil

    if passed == true then
        BarrelMix[uid].stir = stir.GoodBonus or 0
        GSC.Notify.Send(_source, Config.Text.StirGood, 4000)
    else
        BarrelMix[uid].stir = -(stir.BadPenalty or 0)
        GSC.Notify.Send(_source, Config.Text.StirBad, 4000)
    end

    BarrelStageDeadline[uid] = os.time()
    SaveBarrelToDB(uid)
end)

---oo[ Tending The Fermenting Wash ]oo---
local function TendConf()
    local f = Config.Fermentation
    return f and f.Enabled and f.Tend and f.Tend.Enabled and f.Tend or nil
end

local function AtStill(src, uid)
    return #(GetEntityCoords(GetPlayerPed(src)) - BarrelPositions[uid])
        <= (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0)
end

local function TendWindow(conf)
    return (tonumber(conf.Minigame and conf.Minigame.time) or 22) + 10 -- the game, plus slack
end

RegisterServerEvent('gsc_kassippu:server:tendWash')
AddEventHandler('gsc_kassippu:server:tendWash', function(uid)
    local _source = source
    if not Shared.GetChar(_source) then return end
    if type(uid) ~= 'string' or not BarrelPositions[uid] then return end

    local conf = TendConf()
    if not conf or BarrelStage[uid] ~= Shared.BarrelStage.FERMENTING then return end

    if not FermentState(uid, os.time()) then
        return GSC.Notify.Send(_source, Config.Text.TendWashNotYet, 3000)
    end
    if BarrelMix[uid] and BarrelMix[uid].tend ~= nil then
        return GSC.Notify.Send(_source, Config.Text.TendWashAlready, 3000)
    end

    if not GSC.BarrelCrew.Allow(_source, uid, "mix") then return end
    if not AtStill(_source, uid) then return end

    local now = os.time()
    local pending = BarrelTendPending[uid]
    if pending and pending.src ~= _source and (now - pending.at) < TendWindow(conf) then
        return GSC.Notify.Send(_source, Config.Text.TendWashBusy, 3000)
    end

    BarrelTendPending[uid] = { src = _source, at = now }
    TriggerClientEvent('gsc_kassippu:client:tendWash', _source, uid, BarrelLoaded[uid]) -- the recipe stocks the tray
    Shared.Debug(string.format("^6[Tend]^7 %s is tending %s", _source, uid))
end)

RegisterServerEvent('gsc_kassippu:server:tendWashResult')
AddEventHandler('gsc_kassippu:server:tendWashResult', function(uid, passed)
    local _source = source
    if type(uid) ~= 'string' or not BarrelPositions[uid] then return end

    local pending = BarrelTendPending[uid]
    if not pending or pending.src ~= _source then return end -- only the game the server opened
    BarrelTendPending[uid] = nil

    local conf = TendConf()
    if not conf or BarrelStage[uid] ~= Shared.BarrelStage.FERMENTING then return end
    if BarrelMix[uid] and BarrelMix[uid].tend ~= nil then return end
    if not AtStill(_source, uid) then return end

    local took = os.time() - pending.at
    if took > TendWindow(conf) then return end -- far too late: that game is over

    ---o[ Sooner than a real game can be won: botched ]o---
    local good = passed == true and took >= (conf.MinSeconds or 4)

    BarrelMix[uid] = BarrelMix[uid] or {}
    if good then
        BarrelMix[uid].tend = conf.GoodBonus or 0
        GSC.Notify.Send(_source, string.format(Config.Text.TendWashGood, conf.GoodBonus or 0), 5000)
    else
        BarrelMix[uid].tend = -(conf.BadPenalty or 0)
        GSC.Notify.Send(_source, string.format(Config.Text.TendWashBad, conf.BadPenalty or 0), 5000, "warning")
    end

    SaveBarrelToDB(uid)
    SyncBarrelHeat(uid, BarrelHeat[uid] or 0.0, BarrelBrewProgress[uid] or 0, BarrelRemainingBottles[uid] or 0)
    Shared.Debug(string.format("^6[Tend]^7 %s tended %s: %s in %ds (score %+d)", _source, uid,
        good and "good" or "botched", took, BarrelMix[uid].tend))
end)

AddEventHandler('playerDropped', function()
    local src = source
    for uid, pending in pairs(BarrelTendPending) do
        if pending.src == src then BarrelTendPending[uid] = nil end
    end
    for uid, pending in pairs(BarrelBottlePending) do
        if pending.src == src then BarrelBottlePending[uid] = nil end
    end
end)

---oo[ Switching Jars While The Spirit Drips ]oo---
RegisterServerEvent('gsc_kassippu:server:switchJar')
AddEventHandler('gsc_kassippu:server:switchJar', function(uid)
    local _source = source
    if not Config.Cuts.Enabled or type(uid) ~= 'string' or not BarrelPositions[uid] then return end
    if not Shared.GetChar(_source) then return end

    if not GSC.BarrelCrew.Allow(_source, uid, "cuts") then return end

    if #(GetEntityCoords(GetPlayerPed(_source)) - BarrelPositions[uid])
        > (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0) then
        return
    end

    local cut = BarrelCut[uid]
    if BarrelStage[uid] ~= Shared.BarrelStage.BREWING or not cut then return end

    local progress = BarrelBrewProgress[uid] or 0

    if not cut.keepFrom then
        cut.keepFrom = progress
        NotifyBarrelWatchers(uid, Config.Text.Cuts.Started, 3000)
        SyncBarrelHeat(uid, BarrelHeat[uid] or 0.0, progress, 0)
        SyncDressing(uid) -- the jar starts to fill
    elseif not cut.keepTo then
        cut.keepTo = progress
        NotifyBarrelWatchers(uid, Config.Text.Cuts.Stopped, 3000)
        FinishCutRun(uid)
    end
end)

---oo[ Dealing With Trouble ]oo---
RegisterServerEvent('gsc_kassippu:server:fixIncident')
AddEventHandler('gsc_kassippu:server:fixIncident', function(uid)
    local _source = source
    if type(uid) ~= 'string' or not BarrelPositions[uid] or not Shared.GetChar(_source) then return end

    local incident = BarrelIncident[uid]
    local conf = ActiveIncident(uid)
    if not incident or not conf then return end

    if not GSC.BarrelCrew.Allow(_source, uid, "fix") then return end
    if #(GetEntityCoords(GetPlayerPed(_source)) - BarrelPositions[uid])
        > (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0) then
        return
    end

    local now = os.time()

    if incident.fixer and incident.fixer ~= _source and now - (incident.fixStarted or 0) < 30 then
        return GSC.Notify.Send(_source, Config.Text.IncidentBusy, 3000)
    end
    if incident.retryAt and now < incident.retryAt then return end

    incident.fixer, incident.fixStarted, incident.fixStartedMs = _source, now, GetGameTimer()
    TriggerClientEvent('gsc_kassippu:client:incidentGame', _source, uid, conf.key, conf.minigame, conf.label)
end)

RegisterServerEvent('gsc_kassippu:server:incidentResult')
AddEventHandler('gsc_kassippu:server:incidentResult', function(uid, key, passed)
    local _source = source
    local incident = BarrelIncident[uid]
    if type(uid) ~= 'string' or not incident or incident.key ~= key or incident.fixer ~= _source then return end

    ---o[ Sooner than a real fix can be won: it counts as botched ]o---
    local took = (GetGameTimer() - (incident.fixStartedMs or 0)) / 1000.0
    if passed == true and took < ((Config.Incidents or {}).MinSeconds or 0) then
        Shared.Debug(string.format("^1[Incident]^7 (ID: %s) fix after %.2fs - too fast, counted as botched", _source, took))
        passed = false
    end

    incident.fixer, incident.fixStarted, incident.fixStartedMs = nil, nil, nil
    local conf = ActiveIncident(uid)

    if passed == true and conf then
        BarrelIncident[uid] = nil
        NotifyBarrel(uid, conf.fixed, 4000)
        Shared.Debug(string.format("^2[Incident]^7 %s at %s fixed by %s", key, uid, _source))
    else
        incident.retryAt = os.time() + ((Config.Incidents or {}).RetrySeconds or 3)
        GSC.Notify.Send(_source, Config.Text.IncidentFailed, 3000)
    end

    SyncBarrelHeat(uid, BarrelHeat[uid] or 0.0, BarrelBrewProgress[uid] or 0, BarrelRemainingBottles[uid] or 0)
end)

---oo[ Barrel Explosion Event ]oo---
AddEventHandler('gsc_kassippu:server:explodeBarrel', function(uid, cause)
    ---o[ Get Barrel Position Using Database ]o---
    local barrelCoords = BarrelPositions[uid]

    if barrelCoords then
        TriggerClientEvent('gsc_kassippu:client:barrelBoom', -1, uid, barrelCoords)

        ---o[ For the staff log, while the owner and crew are still on record ]o---
        local L = Config.Text.Logs or {}
        GSC.Logs.Send("explosion", L.Explosion, {
            { name = GSC.Logs.Label("Still"), value = uid, inline = true },
            { name = GSC.Logs.Label("Cause"), value = (L.Causes or {})[cause or ""] or cause or "?", inline = true },
            { name = GSC.Logs.Label("Owner"), value = GSC.Logs.Owner(BarrelOwner[uid]), raw = true },
            { name = GSC.Logs.Label("Crew"), value = table.concat(GSC.BarrelCrew.Names(uid), ", ") },
            { name = GSC.Logs.Label("Where"), value = GSC.Logs.Where(barrelCoords), inline = true },
        })

        ---o[ Cleanup Data ]o---
        BarrelFuelCount[uid]        = nil
        BarrelFirePower[uid]        = nil
        BarrelSoak[uid]             = nil
        BarrelFireOut[uid]          = nil
        BarrelExposure[uid]         = nil
        BarrelTarp[uid]             = nil
        BarrelSmokeShown[uid]       = nil
        BarrelIncidentNext[uid]     = nil
        BarrelHeat[uid]             = nil
        BarrelStage[uid]            = nil
        BarrelPositions[uid]        = nil
        BarrelTargetQuality[uid]    = nil
        BarrelQualityTrack[uid]     = nil
        BarrelBrewProgress[uid]     = nil
        BarrelRemainingBottles[uid] = nil
        BarrelGracePeriodDone[uid]  = nil
        BarrelCondition[uid]        = nil
        BarrelResidue[uid]          = nil
        BarrelConditionWarned[uid]  = nil
        BarrelUsageCount[uid]       = nil
        BarrelRepairCount[uid]      = nil
        BarrelUpgrades[uid]         = nil
        BarrelDoomed[uid]           = nil
        ClearRunState(uid)
        GSC.Stations.Explode(uid)

        ---o[ And take her off the books ]o---
        exports.oxmysql:execute('DELETE FROM gsc_kassippu_barrels WHERE uid = ?', { uid })
        ClearStash(uid)

        ---o[ Tell the owner, and anyone stood at it ]o---
        NotifyBarrel(uid, Config.Text.BarrelExploideNotify, 5000)
        GSC.BarrelCrew.Forget(uid)
        BarrelOwner[uid] = nil
        BarrelHeadings[uid] = nil

        Shared.Debug("^1[DANGER]^7 Barrel UID " .. uid .. " exploded and all server data was cleared.")
    else
        Shared.Debug("^1[ERROR]^7 Attempted to explode " .. tostring(uid) .. " but it doesn't exist in BarrelPositions.")
    end
end)

---oo[ Heat Management System ( Loop ) ]oo---
CreateThread(function()
    while true do
        if next(BarrelStage) == nil then
            Wait(5000)
            goto continue
        end

        Wait(1000)
        local currentTime = os.time()
        for barrelId, stage in pairs(BarrelStage) do
            ---o[ Stage Completed ]o---
            if stage ~= Shared.BarrelStage.COMPLETED then
                ---o[ Timed stages that have run out ]o---
                local deadline = BarrelStageDeadline[barrelId]
                if deadline and currentTime >= deadline then
                    BarrelStageDeadline[barrelId] = nil

                    ---o[ Nobody stirred it ]o---
                    if stage == Shared.BarrelStage.MIXING and BarrelStirPending[barrelId] then
                        BarrelStirPending[barrelId] = nil
                        BarrelMix[barrelId] = BarrelMix[barrelId] or {}
                        BarrelMix[barrelId].stir = -((Config.Mixing.Stir or {}).BadPenalty or 0)
                        NotifyBarrel(barrelId, Config.Text.StirMissed, 5000)
                    end

                    if stage == Shared.BarrelStage.MIXING and Config.Fermentation.Enabled and not IsSecondRun(barrelId) then
                        ---o[ Mixed: now it ferments ]o---
                        local f = BarrelFerment[barrelId] or { spiked = 0 }
                        f.started = currentTime
                        BarrelFerment[barrelId] = f

                        BarrelStage[barrelId] = Shared.BarrelStage.FERMENTING
                        SaveBarrelToDB(barrelId)
                        TriggerClientEvent('gsc_kassippu:client:updateStage', -1, barrelId, Shared.BarrelStage.FERMENTING)

                        local band = Shared.CrateClimate(f.temp, f.sheltered)
                        NotifyBarrel(barrelId, string.format(Config.Text.FermentStarted,
                            band and band.label or "Mild"), 6000)
                        Shared.Debug("^2[Stage Transition]^7 UID: " .. barrelId .. " is now FERMENTING")
                    elseif stage == Shared.BarrelStage.MIXING then
                        BarrelStage[barrelId] = Shared.BarrelStage.MID_CLIMB
                        SaveBarrelToDB(barrelId)
                        TriggerClientEvent('gsc_kassippu:client:updateStage', -1, barrelId, Shared.BarrelStage.MID_CLIMB)

                        ---o[ Notify Put Woods Again ]o---
                        NotifyBarrel(barrelId, Config.Text.MixingFuelAddAgain, 5000)
                        Shared.Debug("^2[Stage Transition]^7 UID: " .. barrelId .. " is now MID_CLIMB")
                    elseif stage == Shared.BarrelStage.HEAT_PAUSE then
                        Shared.Debug(string.format("^2[SAFETY]^7 Barrel %s Released. Moving to FINAL_PUSH.", barrelId))
                        BarrelGracePeriodDone[barrelId] = true
                        BarrelStage[barrelId] = Shared.BarrelStage.FINAL_PUSH
                        SaveBarrelToDB(barrelId)
                        TriggerClientEvent('gsc_kassippu:client:updateStage', -1, barrelId, Shared.BarrelStage.FINAL_PUSH)
                    end

                    stage = BarrelStage[barrelId]
                end

                local heat = BarrelHeat[barrelId] or 0.0

                local lit, power = BurnFire(barrelId, currentTime)

                ---o[ Stage IDLE: warming her up ]o---
                if stage == Shared.BarrelStage.IDLE and not lit then
                    ---o[ Fire out while she warms ]o---
                    local graceLeft = ColdGraceLeft(barrelId, currentTime)
                    if graceLeft == 0 then
                        local out = BarrelFireOut[barrelId]
                        if out and not out.warned then
                            out.warned = true
                            NotifyBarrel(barrelId, Config.Text.ColdCooling, 6000)
                        end
                        BarrelHeat[barrelId] = math.max(0.0, heat - (Config.Fuel.ColdCoolRate or Config.Fuel.CoolDownRate or 1.0))
                    end
                elseif stage == Shared.BarrelStage.IDLE then
                    BarrelHeat[barrelId] = math.min(Config.HeatManagement.InitialHeat,
                        heat + (Config.Fuel.WarmUpIncrement or Config.Fuel.HeatIncrement) * power) -- the first warm-up has its own pace
                    if BarrelHeat[barrelId] >= Config.HeatManagement.InitialHeat then
                        Shared.Debug(string.format("^3[STAGE]^7 Barrel %s reached 36%%. Ready to Mix.", barrelId))
                        BarrelStage[barrelId] = Shared.BarrelStage.FREEZE
                        SaveBarrelToDB(barrelId)
                        TriggerClientEvent('gsc_kassippu:client:updateStage', -1, barrelId, Shared.BarrelStage.FREEZE)
                    end

                    ---o[ Stage FERMENTING ]o---
                elseif stage == Shared.BarrelStage.FERMENTING then
                    BarrelHeat[barrelId] = math.max(0.0, heat - (Config.Fermentation.CoolRate or 0.5))

                    if not BarrelFerment[barrelId] or (tonumber(BarrelFerment[barrelId].started) or 0) <= 0 then
                        BarrelFerment[barrelId] = BarrelFerment[barrelId] or { spiked = 0 }
                        BarrelFerment[barrelId].started = currentTime
                    end

                    local f = BarrelFerment[barrelId]
                    local state = FermentState(barrelId, currentTime)

                    if not state then
                    elseif state.spoilIn <= 0 then
                        SpoilWash(barrelId)
                    elseif state.turnIn <= 0 and not f.turning then
                        f.turning = true
                        SaveBarrelToDB(barrelId)
                        NotifyBarrel(barrelId, Config.Text.FermentTurning, 6000)
                    elseif state.strength >= 100.0 and not f.ready then
                        f.ready = true
                        SaveBarrelToDB(barrelId)
                        NotifyBarrel(barrelId, Config.Text.FermentReady, 6000)
                    end

                    stage = BarrelStage[barrelId]

                    ---o[ Stage MID_CLIMB: heating up, while the fire is fed ]o---
                elseif stage == Shared.BarrelStage.MID_CLIMB and not lit then
                    BarrelHeat[barrelId] = math.max(0.0, heat - (Config.Fuel.CoolDownRate or 1.0))
                elseif stage == Shared.BarrelStage.MID_CLIMB then
                    if not BarrelGracePeriodDone[barrelId] then
                        BarrelHeat[barrelId] = math.min(Config.HeatManagement.CommonHeat,
                            heat + Config.Fuel.HeatIncrement * power)
                        if BarrelHeat[barrelId] >= Config.HeatManagement.CommonHeat then
                            Shared.Debug(string.format("^3[STAGE]^7 Barrel %s at 100%%. HEAT_PAUSE (60s Safety).", barrelId))
                            BarrelStage[barrelId] = Shared.BarrelStage.HEAT_PAUSE
                            BarrelStageDeadline[barrelId] = currentTime +
                                math.ceil(Config.HeatManagement.HeatInterval / 1000)
                            SaveBarrelToDB(barrelId)
                            TriggerClientEvent('gsc_kassippu:client:updateStage', -1, barrelId, Shared.BarrelStage.HEAT_PAUSE)
                        end
                    end

                    ---o[ Stage FINAL_PUSH ( Tracking Qualities ) ]o---
                elseif stage == Shared.BarrelStage.FINAL_PUSH then
                    local game = PushGameOn()
                    if game then
                        BarrelHeat[barrelId] = TickPushGame(barrelId, heat, lit, game)
                    elseif lit then
                        BarrelHeat[barrelId] = heat +
                            (Config.Fuel.HeatIncrement / Config.HeatManagement.HeatIncrementDivide) * power
                    else
                        BarrelHeat[barrelId] = math.max(0.0, heat - (Config.Fuel.PushCoolRate or 0.6))
                    end

                    local liveHeat = BarrelHeat[barrelId] or 0.0

                    if not Config.HeatSkill.Enabled then
                        ---o[ Old behaviour: hold a bracket for QualityTrackingTime ]o---
                        local currentBracket = GetCurrentQualityBracket(liveHeat)

                        if currentBracket then
                            if BarrelTargetQuality[barrelId] ~= currentBracket then
                                BarrelTargetQuality[barrelId] = currentBracket
                                BarrelQualityTrack[barrelId] = currentTime
                                Shared.Debug(string.format("^2[QUALITY]^7 Barrel %s stabilized: %s", barrelId,
                                    Config.Product.Qualities[currentBracket].label))
                                NotifyBarrel(barrelId,
                                    Config.Text.QualityTracked .. Config.Product.Qualities[currentBracket].label, 3000)
                            else
                                local elapsed = os.difftime(currentTime, BarrelQualityTrack[barrelId])
                                if elapsed >= Config.HeatManagement.QualityTrackingTime then
                                    Shared.Debug(string.format("^2[QUALITY SECURED]^7 Barrel %s: Starting Brewing.", barrelId))
                                    BarrelStage[barrelId] = Shared.BarrelStage.BREWING
                                    BarrelBrewProgress[barrelId] = 0
                                    SaveBarrelToDB(barrelId)
                                    TriggerClientEvent('gsc_kassippu:client:updateStage', -1, barrelId, Shared.BarrelStage.BREWING)
                                end
                            end
                        else
                            if BarrelTargetQuality[barrelId] ~= nil then
                                Shared.Debug(string.format("^1[LOST]^7 Barrel %s heat unstable!", barrelId))
                                BarrelTargetQuality[barrelId] = nil
                                BarrelQualityTrack[barrelId] = nil
                            end
                        end
                    else
                        ---o[ Graded run ]o---
                        local conf = Config.HeatSkill

                        if not BarrelPushStart[barrelId] then
                            BarrelPushStart[barrelId] = currentTime
                            BarrelScoreSum[barrelId] = 0.0
                            BarrelScoreTicks[barrelId] = 0
                            BarrelNextEvent[barrelId] = currentTime +
                                math.random(conf.EventMinSeconds or 8, conf.EventMaxSeconds or 18)

                            Shared.Debug(string.format("^3[PUSH]^7 Barrel %s started a %ds graded run.",
                                barrelId, conf.PushSeconds))
                            NotifyBarrelWatchers(barrelId, Config.Text.PushStarted, 4000)

                            if GetResidue(barrelId) > 0 then
                                NotifyBarrelWatchers(barrelId, Config.Text.ResidueWarning, 5000)
                            end

                            if MixScoreMod(barrelId) ~= 0 then
                                NotifyBarrelWatchers(barrelId,
                                    string.format(Config.Text.MashIngredientBonus, MixScoreMod(barrelId)), 5000)
                            end
                        end

                        ---o[ The game warns WarnSeconds ahead, so a good hand gets ready for it ]o---
                        local pushGame = PushGameOn()
                        local warnAhead = pushGame and (tonumber(pushGame.WarnSeconds) or 0) or 0
                        local pushState = pushGame and PushState(barrelId) or nil
                        if conf.EventsEnabled and BarrelNextEvent[barrelId] and pushState and warnAhead > 0
                            and not pushState.warn and currentTime >= BarrelNextEvent[barrelId] - warnAhead then
                            pushState.warn = math.random(2) == 1 and "flare" or "draught"
                            local words = Config.Text.PushGame or {}
                            NotifyBarrelWatchers(barrelId,
                                pushState.warn == "flare" and words.WarnFlare or words.WarnDraught, 3000)
                        end

                        if conf.EventsEnabled and BarrelNextEvent[barrelId]
                            and currentTime >= BarrelNextEvent[barrelId] then
                            local flare = math.random(2) == 1
                            if pushState and pushState.warn then
                                flare = pushState.warn == "flare" -- what was warned is what comes
                                pushState.warn = nil
                            end
                            local shove = flare and (conf.FlareHeat or 0.0) or (conf.DraughtHeat or 0.0)

                            BarrelHeat[barrelId] = math.max(0.0, (BarrelHeat[barrelId] or 0.0) + shove)
                            liveHeat = BarrelHeat[barrelId]

                            BarrelNextEvent[barrelId] = currentTime +
                                math.random(conf.EventMinSeconds or 8, conf.EventMaxSeconds or 18)

                            Shared.Debug(string.format("^3[PUSH]^7 Barrel %s %s (%+.1f)", barrelId,
                                flare and "flare-up" or "draught", shove))
                            NotifyBarrelWatchers(barrelId,
                                flare and Config.Text.PushFlare or Config.Text.PushDraught, 3000)
                        end

                        ---o[ Mark this tick against the moving line ]o---
                        local target = GetTargetHeat(barrelId, currentTime)
                        BarrelTargetHeat[barrelId] = target

                        BarrelScoreSum[barrelId] = (BarrelScoreSum[barrelId] or 0.0) + ScoreHeatTick(liveHeat, target, PushBand(barrelId))
                        BarrelScoreTicks[barrelId] = (BarrelScoreTicks[barrelId] or 0) + 1

                        ---o[ Run over: grade it ]o---
                        if (currentTime - BarrelPushStart[barrelId]) >= (conf.PushSeconds or 60) then
                            local ticks = math.max(1, BarrelScoreTicks[barrelId])
                            local average = (BarrelScoreSum[barrelId] / ticks) * 100.0

                            local fouling = Config.BarrelCondition.Enabled
                                and (GetResidue(barrelId) * Config.BarrelCondition.ScorePenaltyPerResidue)
                                or 0.0
                            average = math.max(0.0, math.min(100.0, average - fouling + MixScoreMod(barrelId)
                                + UpgradeSum(barrelId, "scoreBonus")))

                            local tier = GradeRun(average)

                            local capped, wouldHaveBeen = CapTierByCondition(barrelId, tier)
                            if wouldHaveBeen and not Config.Cuts.Enabled then
                                local cappedLabel = (Config.Product.Qualities[capped] or {}).label or capped
                                NotifyBarrelWatchers(barrelId,
                                    Config.Text.ConditionCapped .. cappedLabel, 5000)
                                Shared.Debug(string.format("^3[WEAR]^7 Barrel %s scored %s but condition %.0f caps it at %s",
                                    barrelId, wouldHaveBeen, GetCondition(barrelId), capped))
                            end
                            tier = capped

                            BarrelTargetQuality[barrelId] = tier
                            BarrelStage[barrelId] = Shared.BarrelStage.BREWING
                            BarrelBrewProgress[barrelId] = 0

                            if Config.Cuts.Enabled then
                                BarrelMix[barrelId] = BarrelMix[barrelId] or {}
                                BarrelMix[barrelId].pushScore = average
                                BarrelCut[barrelId] = nil
                            end

                            BarrelPushStart[barrelId] = nil
                            BarrelScoreSum[barrelId] = nil
                            BarrelScoreTicks[barrelId] = nil
                            BarrelNextEvent[barrelId] = nil
                            BarrelTargetHeat[barrelId] = nil
                            PushGame[barrelId] = nil

                            Shared.Debug(string.format("^2[PUSH GRADED]^7 Barrel %s scored %.1f -> %s",
                                barrelId, average, tier))

                            local label = (Config.Product.Qualities[tier] or {}).label or tier
                            if Config.Cuts.Enabled then
                                NotifyBarrelWatchers(barrelId,
                                    string.format(Config.Text.PushGradedCuts, math.floor(average), label), 6000)
                            else
                                NotifyBarrelWatchers(barrelId,
                                    string.format("%s%s (%d%%)", Config.Text.PushGraded, label, math.floor(average)), 5000)
                            end

                            SaveBarrelToDB(barrelId)
                            TriggerClientEvent('gsc_kassippu:client:updateStage', -1, barrelId, Shared.BarrelStage.BREWING)
                            SyncDressing(barrelId)
                        end
                    end
                    ---o[ Stage BREWING: the cuts ]o---
                elseif stage == Shared.BarrelStage.BREWING and Config.Cuts.Enabled then
                    TickCondenser(barrelId)
                    TickCutRun(barrelId)
                    stage = BarrelStage[barrelId]

                    ---o[ Stage BREWING: the plain progress bar (cuts off) ]o---
                elseif stage == Shared.BarrelStage.BREWING then
                    TickCondenser(barrelId)
                    local currentProgress = BarrelBrewProgress[barrelId] or 0

                    if currentProgress < Config.HeatManagement.BrewgProgress then
                        BarrelBrewProgress[barrelId] = currentProgress + Config.HeatManagement.BrewProgressIncreValue

                        if BarrelBrewProgress[barrelId] >= Config.HeatManagement.BrewgProgress then
                            Shared.Debug(string.format("^2[COMPLETED]^7 Barrel %s finished brewing.", barrelId))
                            CompleteBatch(barrelId)
                            stage = BarrelStage[barrelId]
                        end
                    end
                end
                ---o[ Trouble at the still ]o---
                TickIncidents(barrelId, stage, currentTime)

                ---o[ Pressure ]o---
                local nowHeat = BarrelHeat[barrelId] or 0.0

                if Config.Pressure.Enabled then
                    local pconf = Config.Pressure
                    local pressure = BarrelPressure[barrelId] or 0.0

                    local canBuild = stage == Shared.BarrelStage.HEAT_PAUSE
                        or stage == Shared.BarrelStage.FINAL_PUSH

                    if canBuild and nowHeat > pconf.BuildAboveHeat then
                        local span = math.max(1.0, Config.HeatManagement.MaxHeat - pconf.BuildAboveHeat)
                        local intensity = math.min(1.0, (nowHeat - pconf.BuildAboveHeat) / span)

                        local wornMult = 1.0
                        if Config.BarrelCondition.Enabled then
                            local cconf = Config.BarrelCondition
                            local wear = 1.0 - (GetCondition(barrelId) / cconf.Max)
                            wornMult = 1.0 + (wear * ((cconf.WornPressureMultiplier or 1.0) - 1.0))
                        end

                        pressure = pressure + (pconf.BuildRate * intensity * wornMult * BatchPressureMultiplier(barrelId)
                            * IncidentFactor(barrelId, "pressureMultiplier"))
                    else
                        pressure = pressure - pconf.BleedRate
                    end

                    BarrelPressure[barrelId] = math.max(0.0, math.min(pconf.Max, pressure))

                    ---o[ Tell the owner once per climb past the warning line ]o---
                    local warnAt = UpgradeMin(barrelId, "warnAt", pconf.WarnAt) -- a gauge warns sooner
                    if BarrelPressure[barrelId] >= warnAt then
                        if not BarrelPressureWarned[barrelId] then
                            BarrelPressureWarned[barrelId] = true
                            NotifyBarrelWatchers(barrelId, Config.Text.PressureWarning, 4000)
                        end
                    elseif BarrelPressure[barrelId] < (warnAt * 0.75) then
                        BarrelPressureWarned[barrelId] = nil
                    end
                end

                ---o[ Abuse wear ]o---
                if Config.BarrelCondition.Enabled
                    and (stage == Shared.BarrelStage.HEAT_PAUSE or stage == Shared.BarrelStage.FINAL_PUSH) then
                    local cconf = Config.BarrelCondition
                    local abuse = 0.0

                    if nowHeat > cconf.HotWearAbove then
                        local span = math.max(1.0, Config.HeatManagement.MaxHeat - cconf.HotWearAbove)
                        abuse = abuse + (cconf.HotWearRate * math.min(1.0, (nowHeat - cconf.HotWearAbove) / span))
                    end

                    local pnow = BarrelPressure[barrelId] or 0.0
                    if Config.Pressure.Enabled and pnow > cconf.PressureWearAbove then
                        local span = math.max(1.0, Config.Pressure.Max - cconf.PressureWearAbove)
                        abuse = abuse + (cconf.PressureWearRate * math.min(1.0, (pnow - cconf.PressureWearAbove) / span))
                    end

                    if abuse > 0.0 then WearBarrel(barrelId, abuse) end
                end

                ---o[ Sync Barrel Heat And Explosion ]o---
                local burstPressure = Config.Pressure.Enabled
                    and (BarrelPressure[barrelId] or 0.0) >= Config.Pressure.Max

                if nowHeat >= Config.HeatManagement.MaxHeat or burstPressure then
                    if burstPressure then
                        NotifyBarrelWatchers(barrelId, Config.Text.PressureBurst, 5000)
                    end
                    TriggerEvent('gsc_kassippu:server:explodeBarrel', barrelId, burstPressure and "pressure" or "heat")
                else
                    local progress = BarrelBrewProgress[barrelId] or 0
                    local bottles = BarrelRemainingBottles[barrelId] or 0
                    SyncBarrelHeat(barrelId, nowHeat, progress, bottles)
                end
            end
        end

        ::continue::
    end
end)

---oo[ Removing A Barrel For Good ]oo---
local function RemoveBarrel(uid)
    local coords = BarrelPositions[uid]
    TriggerClientEvent('gsc_kassippu:client:BarrelCleanup', -1, uid, coords)

    BarrelUsageCount[uid] = nil
    BarrelRepairCount[uid] = nil
    BarrelStage[uid] = nil
    BarrelHeat[uid] = nil
    BarrelFuelCount[uid] = nil
    BarrelFirePower[uid] = nil
    BarrelSoak[uid] = nil
    BarrelFireOut[uid] = nil
    BarrelExposure[uid] = nil
    BarrelTarp[uid] = nil
    BarrelSmokeShown[uid] = nil
    BarrelIncidentNext[uid] = nil
    BarrelBrewProgress[uid] = nil
    BarrelRemainingBottles[uid] = nil
    BarrelPositions[uid] = nil
    BarrelHeadings[uid] = nil
    BarrelOwner[uid] = nil
    BarrelLoaded[uid] = nil
    BarrelCondition[uid] = nil
    BarrelResidue[uid] = nil
    BarrelConditionWarned[uid] = nil
    BarrelUpgrades[uid] = nil
    BarrelDoomed[uid] = nil
    BarrelTargetQuality[uid] = nil
    BarrelQualityTrack[uid] = nil
    BarrelGracePeriodDone[uid] = nil
    ClearRunState(uid)
    GSC.BarrelCrew.Forget(uid)
    GSC.Stations.Forget(uid)

    exports.oxmysql:execute('DELETE FROM gsc_kassippu_barrels WHERE uid = ?', { uid })
    ClearStash(uid)
end

---oo[ Spent Mash ]oo---
local function GiveSpentMash(_source, uid, recipeKey)
    local conf = Config.SpentMash
    if not (conf and conf.Enabled and conf.Item) then return end
    if Config.Recipes[recipeKey] and Config.Recipes[recipeKey].secondRun then return end

    local amount = math.floor((conf.PerBatch or 1) * BatchOf(uid))
    if amount <= 0 then return end
    if not exports.vorp_inventory:canCarryItem(_source, conf.Item, amount) then return end

    exports.vorp_inventory:addItem(_source, conf.Item, amount)
    GSC.Notify.Send(_source, string.format(Config.Text.SpentMashGot, amount), 4000)
end

---o[ How many bottles a finished batch holds ]o---
local function EnsureRemaining(uid, recipeKey)
    if BarrelRemainingBottles[uid] == nil or BarrelRemainingBottles[uid] <= 0 then
        local quality = BarrelTargetQuality[uid] or Config.Recipes[recipeKey].rewards.NORMAL.quality
        if quality == Config.Recipes[recipeKey].rewards.PERFECT.quality then
            BarrelRemainingBottles[uid] = Config.Recipes[recipeKey].rewards.PERFECT.count
        elseif quality == Config.Recipes[recipeKey].rewards.GOOD.quality then
            BarrelRemainingBottles[uid] = Config.Recipes[recipeKey].rewards.GOOD.count
        else
            BarrelRemainingBottles[uid] = Config.Recipes[recipeKey].rewards.NORMAL.count
        end
        BarrelRemainingBottles[uid] = ScaleByStrength(uid, BarrelRemainingBottles[uid] * BatchOf(uid))
    end
    return BarrelRemainingBottles[uid]
end

---oo[ Draw One Bottle Off A Finished Batch ]oo---
local function DrawBottle(_source, uid, quiet, spill)
    local Character = Shared.GetChar(_source)

    ---o[ Character And Barrel UID Validation ]o---
    if not Character or not BarrelPositions[uid] then return false end

    if BarrelDoomed[uid] then
        GSC.Notify.Send(_source, Config.Text.BarrelEmpty, 4000)
        return false
    end

    if BarrelStage[uid] ~= Shared.BarrelStage.COMPLETED then
        return GSC.Notify.Send(_source, Config.Text.CollectProdNotReady, 4000)
    end

    local recipeKey = BarrelLoaded[uid]
    local recipeData = Config.Recipes[recipeKey]
    if not recipeData then
        return GSC.Notify.Send(_source, Config.Text.RecipeDataLost, 4000)
    end

    local remaining = EnsureRemaining(uid, recipeKey)
    if remaining <= 0 then
        GSC.Notify.Send(_source, Config.Text.BarrelEmpty, 4000)
        return
    end
    local savedQualityTier = BarrelTargetQuality[uid] or "NORMAL"
    ---o[ Product Required Items Check ]o---
    local emptyItem = Config.Product.FillingItem
    local productItem, productMeta, productLabel = BottleFor(uid, recipeKey, savedQualityTier)

    local hasBottle = exports.vorp_inventory:getItemCount(_source, nil, emptyItem)

    if spill or hasBottle >= 1 then
        if not spill then
            if not exports.vorp_inventory:subItem(_source, emptyItem, 1) then
                GSC.Notify.Send(_source, Config.Text.RequiredFillingItem .. Character.firstname, 4000)
                return false
            end
            exports.vorp_inventory:addItem(_source, productItem, 1, productMeta)
        end

        BarrelRemainingBottles[uid] = remaining - 1
        local newRemaining = BarrelRemainingBottles[uid]

        ---o[ UPDATE UI DURING COLLECTION ]o---
        TriggerClientEvent('gsc_kassippu:client:updateBrewUI', _source, uid, 100, newRemaining)

        ---o[ Process Data Reset Logic ]o---
        if newRemaining <= 0 then
            GiveSpentMash(_source, uid, recipeKey)

            ---o[ Increment usage ]o---
            BarrelUsageCount[uid] = (BarrelUsageCount[uid] or 0) + 1
            Shared.Debug("^3[Usage] ^7Barrel " .. uid .. " used " .. BarrelUsageCount[uid] .. " times.")

            ---o[ The batch takes its bite out of the barrel ]o---
            local worn = false
            if Config.BarrelCondition.Enabled then
                local cconf = Config.BarrelCondition
                local recipeWear = Config.Recipes[recipeKey] and Config.Recipes[recipeKey].wearMultiplier or 1.0
                WearBarrel(uid, cconf.WearPerBatch * recipeWear)
                BarrelResidue[uid] = math.min(cconf.ResidueMax,
                    GetResidue(uid) + cconf.ResiduePerBatch)
                worn = GetCondition(uid) <= 0.0

                Shared.Debug(string.format("^3[Wear]^7 Barrel %s: condition %.0f, residue %.0f",
                    uid, GetCondition(uid), GetResidue(uid)))
            end

            ---o[ Lifetime cap ]o---
            local outOfBatches = Config.BarrelCondition.Enabled and BatchesLeft(uid) == 0

            local spent
            if Config.BarrelCondition.Enabled then
                spent = worn or outOfBatches
            else
                spent = BarrelUsageCount[uid] >= Config.KasiyaBarrelKitConf.BarrelUsageTime
            end

            if spent then
                BarrelDoomed[uid] = true
                exports.oxmysql:execute('DELETE FROM gsc_kassippu_barrels WHERE uid = ?', { uid })
                if worn then
                    GSC.Notify.Send(_source, Config.Text.ConditionCollapsed, 8000)
                elseif outOfBatches then
                    GSC.Notify.Send(_source, Config.Text.BatchLimitReached, 8000)
                end
                GSC.Notify.Send(_source, Config.Text.BarrelDetroyWarning, 10000)

                SetTimeout(Config.KasiyaBarrelKitConf.BarrelDestroyingTime, function()
                    if not BarrelPositions[uid] then return end -- seized in the meantime
                    RemoveBarrel(uid)
                    GSC.Notify.Send(_source, Config.Text.BarrelDestroyedNotify, 5000)
                end)
            else
                ---o[ RESET FOR NEXT USE (Only after last bottle) ]o---
                BarrelStage[uid] = Shared.BarrelStage.IDLE
                BarrelLoaded[uid] = nil
                BarrelHeat[uid] = 0.0
                PutOutFire(uid)
                BarrelBrewProgress[uid] = 0
                BarrelGracePeriodDone[uid] = nil
                BarrelQualityTrack[uid] = nil
                BarrelTargetQuality[uid] = nil
                BarrelRemainingBottles[uid] = 0
                ClearRunState(uid)

                TriggerClientEvent('gsc_kassippu:client:updateStage', -1, uid, Shared.BarrelStage.IDLE)
                SyncBarrelHeat(uid, 0.0, 0, 0)
                TriggerClientEvent('gsc_kassippu:client:updateBrewUI', _source, uid, 0, 0)

                SaveBarrelToDB(uid)

                GSC.Notify.Send(_source, Config.Text.BarrelCleanNotify, 5000)
            end
        else
            ---o[ STILL BOTTLES LEFT ]o---
            exports.oxmysql:execute(
                'UPDATE gsc_kassippu_barrels SET remaining_bottles = ? WHERE uid = ?',
                { newRemaining, uid })

            if not quiet then
                GSC.Notify.Send(_source, string.format(Config.Text.RemainingBottles, productLabel, newRemaining), 3000)
            end
        end

        SyncDressing(uid) -- one jug fewer beside her
        return true, productLabel
    else
        GSC.Notify.Send(_source, Config.Text.RequiredFillingItem .. Character.firstname, 4000)
    end

    return false
end

---o[ Bottle all ]o---
local function BottleAll(_source, uid)
    local drawn, label = 0, nil
    local emptyItem = Config.Product.FillingItem

    for _ = 1, 500 do
        if BarrelStage[uid] ~= Shared.BarrelStage.COMPLETED or BarrelDoomed[uid] then break end
        if drawn > 0 and (BarrelRemainingBottles[uid] or 0) <= 0 then break end
        if exports.vorp_inventory:getItemCount(_source, nil, emptyItem) < 1 then break end

        local ok, productLabel = DrawBottle(_source, uid, true)
        if not ok then break end
        drawn, label = drawn + 1, productLabel
    end

    if drawn == 0 then return DrawBottle(_source, uid) end

    GSC.Notify.Send(_source, string.format(Config.Text.BottledAll, drawn, label,
        math.max(0, BarrelRemainingBottles[uid] or 0)), 4000)
    return true
end

---oo[ Bottling: the pour-and-cork minigame (Config.Bottling) ]oo---

local function BottlingConf()
    local b = Config.Bottling
    return b and b.Enabled and b or nil
end

---o[ How long a pour of this many bottles may take, plus slack ]o---
local function BottleWindow(conf, rounds)
    local m = conf.Minigame or {}
    return (rounds or 1) * ((m.bottleTime or 7) + (m.corkTime or 3) + 2) + 10
end

---o[ Bottles lost ]o---
function Distillery.BottlingSpills(drawable, rounds, handSpills, conf)
    conf = conf or Config.Bottling or {}
    rounds = math.min(rounds, drawable)
    handSpills = math.max(0, math.min(handSpills, rounds))
    if handSpills == 0 or rounds <= 0 then return 0 end

    local rest = drawable - rounds
    local restSpills = math.floor(rest * (handSpills / rounds) * (conf.RestFactor or 0.5))
    local cap = math.floor(drawable * (conf.MaxSpillShare or 0.25))
    return math.max(handSpills, math.min(handSpills + restSpills, cap))
end

---o[ The outcomes the game reports ]o---
local function CountSpills(outcomes, rounds)
    if type(outcomes) ~= 'table' or #outcomes ~= rounds then return nil end
    local spills = 0
    for i = 1, rounds do
        local o = outcomes[i]
        if o == "spill" then
            spills = spills + 1
        elseif o ~= "clean" then
            return nil
        end
    end
    return spills
end

---o[ Draw `count` bottles; the last `spilled` of them are spills ]o---
local function DrawBatch(_source, uid, count, spilled)
    local emptyItem = Config.Product.FillingItem
    local drawn, lost, label = 0, 0, nil

    for i = 1, count do
        if BarrelStage[uid] ~= Shared.BarrelStage.COMPLETED or BarrelDoomed[uid] then break end
        if (BarrelRemainingBottles[uid] or 0) <= 0 then break end

        local spill = i > count - spilled
        if not spill and exports.vorp_inventory:getItemCount(_source, nil, emptyItem) < 1 then break end

        local ok, productLabel = DrawBottle(_source, uid, true, spill)
        if not ok then break end
        label = productLabel
        if spill then lost = lost + 1 else drawn = drawn + 1 end
    end
    return drawn, lost, label
end

---o[ The hold at a finished still: open the pour ]o---
local function OpenBottling(_source, uid, conf)
    local Character = Shared.GetChar(_source)
    if not Character or type(uid) ~= 'string' then return end

    if BarrelDoomed[uid] then return GSC.Notify.Send(_source, Config.Text.BarrelEmpty, 4000) end
    if BarrelStage[uid] ~= Shared.BarrelStage.COMPLETED then
        return GSC.Notify.Send(_source, Config.Text.CollectProdNotReady, 4000)
    end
    local recipeKey = BarrelLoaded[uid]
    if not Config.Recipes[recipeKey or ""] then return GSC.Notify.Send(_source, Config.Text.RecipeDataLost, 4000) end
    if not AtStill(_source, uid) then return end

    local remaining = EnsureRemaining(uid, recipeKey)
    if remaining <= 0 then return GSC.Notify.Send(_source, Config.Text.BarrelEmpty, 4000) end

    local empties = tonumber(exports.vorp_inventory:getItemCount(_source, nil, Config.Product.FillingItem)) or 0
    if empties < 1 then
        return GSC.Notify.Send(_source, Config.Text.RequiredFillingItem .. Character.firstname, 4000)
    end

    local now = os.time()
    local pending = BarrelBottlePending[uid]
    if pending and pending.src ~= _source and (now - pending.at) < BottleWindow(conf, pending.rounds) then
        return GSC.Notify.Send(_source, Config.Text.BottlingBusy, 3000)
    end

    local drawable = Config.Product.BottleAll and math.min(remaining, empties) or 1
    local rounds = math.max(1, math.min(drawable, math.floor(conf.HandPour or 4)))

    BarrelBottlePending[uid] = { src = _source, at = now, rounds = rounds }
    TriggerClientEvent('gsc_kassippu:client:bottleGame', _source, uid, rounds, recipeKey)
    Shared.Debug(string.format("^6[Bottling]^7 %s pours %s: %d by hand of %d", _source, uid, rounds, drawable))
end

---o[ How the pour went: the server works out what that costs ]o---
RegisterServerEvent('gsc_kassippu:server:bottleResult')
AddEventHandler('gsc_kassippu:server:bottleResult', function(uid, outcomes)
    local _source = source
    if type(uid) ~= 'string' or not BarrelPositions[uid] then return end

    local pending = BarrelBottlePending[uid]
    if not pending or pending.src ~= _source then return end -- only the pour the server opened
    BarrelBottlePending[uid] = nil

    local conf = BottlingConf()
    if not conf or not Shared.GetChar(_source) then return end
    if BarrelStage[uid] ~= Shared.BarrelStage.COMPLETED or BarrelDoomed[uid] then return end
    if not GSC.BarrelCrew.Allow(_source, uid, "bottle") then return end
    if not AtStill(_source, uid) then return end

    local took = os.time() - pending.at
    if took > BottleWindow(conf, pending.rounds) then return end -- far too late: that pour is over

    local handSpills = CountSpills(outcomes, pending.rounds)
    if not handSpills then return end
    ---o[ Sooner than bottles can be poured: every one went over ]o---
    if took < pending.rounds * (conf.MinPerBottle or 1.5) then handSpills = pending.rounds end

    ---o[ What is left to draw now ]o---
    local remaining = BarrelRemainingBottles[uid] or 0
    local empties = tonumber(exports.vorp_inventory:getItemCount(_source, nil, Config.Product.FillingItem)) or 0
    local drawable = math.min(remaining, Config.Product.BottleAll and empties or math.min(empties, 1))
    if drawable <= 0 then
        return GSC.Notify.Send(_source, remaining <= 0 and Config.Text.BarrelEmpty
            or (Config.Text.RequiredFillingItem .. (Shared.GetChar(_source).firstname or "")), 4000)
    end

    local spilled = Distillery.BottlingSpills(drawable, pending.rounds, handSpills, conf)
    local drawn, lost, label = DrawBatch(_source, uid, drawable, spilled)
    local left = math.max(0, BarrelRemainingBottles[uid] or 0)

    if drawn > 0 and lost > 0 then
        GSC.Notify.Send(_source, string.format(Config.Text.BottledSpilled, drawn, label, lost, left), 5000, "warning")
    elseif drawn > 0 then
        GSC.Notify.Send(_source, string.format(Config.Text.BottledAll, drawn, label, left), 4000)
    elseif lost > 0 then
        GSC.Notify.Send(_source, string.format(Config.Text.BottlingAllSpilled, lost, left), 5000, "warning")
    end
    if drawn > 0 then TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "bottle") end

    Shared.Debug(string.format("^6[Bottling]^7 %s poured %s in %ds: %d by hand, %d spilled by hand -> %d bottled, %d lost",
        _source, uid, took, pending.rounds, handSpills, drawn, lost))
end)

---oo[ Collect Final Product Event ]oo---
RegisterServerEvent('gsc_kassippu:server:collectProduct')
AddEventHandler('gsc_kassippu:server:collectProduct', function(uid)
    local _source = source
    if not Shared.GetChar(_source) or not BarrelPositions[uid] then return end

    if not GSC.BarrelCrew.Allow(_source, uid, "bottle") then return end

    ---o[ The pour minigame decides it ]o---
    local bottling = BottlingConf()
    if bottling then return OpenBottling(_source, uid, bottling) end

    if not AtStill(_source, uid) then return end

    local bottled
    if Config.Product.BottleAll then
        bottled = BottleAll(_source, uid)
    else
        bottled = DrawBottle(_source, uid)
    end

    if bottled == true then TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "bottle") end
end)

---oo[ The Law At The Still ]oo---

---o[ Is there anything here to seize it for? ]o---
local function HasEvidence(uid)
    local stage = BarrelStage[uid] or Shared.BarrelStage.IDLE
    return stage ~= Shared.BarrelStage.IDLE or FireLit(uid)
end

---o[ The owner and online crew, wherever they are ]o---
local function Keepers(uid)
    local list, seen = {}, {}
    local owner = FindOwnerSource(uid)
    if owner then list[1], seen[owner] = owner, true end
    for _, src in ipairs(GSC.BarrelCrew.OnlineSources(uid)) do
        if not seen[src] then list[#list + 1], seen[src] = src, true end
    end
    return list
end

local function AtBarrel(src, uid)
    return #(GetEntityCoords(GetPlayerPed(src)) - BarrelPositions[uid])
        <= (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0)
end

---oo[ Picking Up A Barrel ]oo---
local function PickupReady(uid)
    return BarrelPositions[uid] ~= nil and not BarrelDoomed[uid]
        and (BarrelStage[uid] or Shared.BarrelStage.IDLE) == Shared.BarrelStage.IDLE
        and not FireLit(uid) and not ActiveIncident(uid)
        and (BarrelRemainingBottles[uid] or 0) <= 0
end

local function KitMetadata(uid)
    local condition = GetCondition(uid)
    local shown = math.floor(condition + 0.5)
    local keys = UpgradeKeys(uid)

    local names = {}
    for i, key in ipairs(keys) do names[i] = UpgradeList()[key].label or key end
    local fittings = #names > 0 and string.format(Config.Text.KitFittings, table.concat(names, ", ")) or ""

    return {
        label = string.format(Config.Text.KitLabel, shown),
        description = string.format(Config.Text.KitDescription, shown, fittings),
        condition = condition,
        residue = GetResidue(uid),
        usage = BarrelUsageCount[uid] or 0,
        repairs = BarrelRepairCount[uid] or 0,
        upgrades = keys,
        tarp = BarrelTarp[uid] == true or nil,
    }
end

RegisterServerEvent('gsc_kassippu:server:pickupBarrel')
AddEventHandler('gsc_kassippu:server:pickupBarrel', function(uid)
    local _source = source
    local Character = Shared.GetChar(_source)
    if not Character or not BarrelPositions[uid] then return end
    if not (Config.BarrelPickup and Config.BarrelPickup.Enabled) then return end
    if not Distillery.IsOwner(Character, uid) or not AtBarrel(_source, uid) then return end

    if not PickupReady(uid) then
        return GSC.Notify.Send(_source, Config.Text.PickupNotEmpty, 4000)
    end

    local kit = Config.KasiyaBarrelKitConf.KasiyaBarrelItemName
    if not exports.vorp_inventory:canCarryItem(_source, kit, 1) then
        return GSC.Notify.Send(_source, Config.Text.PickupNoRoom, 4000)
    end

    CountStash(uid,
        function(stashed)
            if stashed > 0 then
                return GSC.Notify.Send(_source, Config.Text.PickupStash, 4000)
            end

            if not PickupReady(uid) then return end

            local meta = KitMetadata(uid)
            GSC.Stations.ReturnAll(_source, uid)
            RemoveBarrel(uid)
            exports.vorp_inventory:addItem(_source, kit, 1, meta)
            GSC.Notify.Send(_source, Config.Text.PickupDone, 4000)
            TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "pickup")
            Shared.Debug(string.format("^3[Pickup]^7 (ID: %s) %s packed up %s at %.0f%%",
                _source, Character.firstname, uid, meta.condition))
        end)
end)

---oo[ The Fittings Slip: fit an upgrade from the book ]oo---
RegisterServerEvent('gsc_kassippu:server:fitUpgrade')
AddEventHandler('gsc_kassippu:server:fitUpgrade', function(uid, key)
    local _source = source
    if type(uid) ~= 'string' or type(key) ~= 'string' then return end
    if not Shared.GetChar(_source) or not BarrelPositions[uid] then return end
    if not AtBarrel(_source, uid) then
        return GSC.Notify.Send(_source, Config.Text.UpgradeNotAtStill, 4000)
    end
    if not GSC.BarrelCrew.Allow(_source, uid, "repair") then return end

    FitUpgrade(_source, uid, key)
end)

---oo[ The Tarp Prompt ]oo---
RegisterServerEvent('gsc_kassippu:server:toggleTarp')
AddEventHandler('gsc_kassippu:server:toggleTarp', function(uid)
    local _source = source
    if not Shared.GetChar(_source) or not BarrelPositions[uid] then return end
    if not TarpOn() or BarrelDoomed[uid] or not AtBarrel(_source, uid) then return end
    if not GSC.BarrelCrew.Allow(_source, uid, "repair") then return end

    if not BarrelTarp[uid] then return RigTarp(_source, uid) end

    if not exports.vorp_inventory:canCarryItem(_source, Config.Items.StillTarp, 1) then
        return GSC.Notify.Send(_source, Config.Text.TarpNoRoom, 4000)
    end

    BarrelTarp[uid] = nil
    SaveBarrelToDB(uid)
    SyncDressing(uid)
    exports.vorp_inventory:addItem(_source, Config.Items.StillTarp, 1)

    GSC.Notify.Send(_source, Config.Text.TarpTakenDown, 4000)
    TriggerClientEvent('gsc_kassippu:client:barrelAnim', _source, "pickup")
end)

---o[ Pour it all out ]o---
local function PourOut(uid)
    ClearStash(uid)

    ClearRunState(uid)
    BarrelLoaded[uid] = nil
    BarrelTargetQuality[uid] = nil
    BarrelQualityTrack[uid] = nil
    BarrelGracePeriodDone[uid] = nil
    BarrelRemainingBottles[uid] = 0
    BarrelBrewProgress[uid] = 0
    BarrelHeat[uid] = 0.0
    PutOutFire(uid)
    BarrelStage[uid] = Shared.BarrelStage.IDLE

    SaveBarrelToDB(uid)
    TriggerClientEvent('gsc_kassippu:client:updateStage', -1, uid, Shared.BarrelStage.IDLE)
    SyncBarrelHeat(uid, 0.0, 0, 0)
    SyncDressing(uid)
end

RegisterServerEvent('gsc_kassippu:server:pourOut')
AddEventHandler('gsc_kassippu:server:pourOut', function(uid)
    local _source = source
    local conf = Config.Law or {}
    if not (conf.Enabled and conf.Pour and conf.Pour.Enabled) then return end
    if type(uid) ~= 'string' or not BarrelPositions[uid] or not Shared.GetChar(_source) then return end

    if not GSC.BarrelCrew.Allow(_source, uid, "pour") then return end
    if not AtBarrel(_source, uid) then return end

    if not HasEvidence(uid) then
        return GSC.Notify.Send(_source, Config.Text.PourNothing, 3000)
    end

    PourOut(uid)
    NotifyBarrel(uid, Config.Text.PourDone, 5000)
    Shared.Debug(string.format("^3[Law]^7 (ID: %s) poured out %s", _source, uid))

    GSC.Logs.Send("law", (Config.Text.Logs or {}).PouredOut, {
        { name = GSC.Logs.Label("Who"), value = GSC.Logs.Player(_source), raw = true },
        { name = GSC.Logs.Label("Still"), value = uid, inline = true },
        { name = GSC.Logs.Label("Owner"), value = GSC.Logs.Owner(BarrelOwner[uid]), raw = true },
        { name = GSC.Logs.Label("Where"), value = GSC.Logs.Where(BarrelPositions[uid]), inline = true },
    })
end)

---o[ A lawman seizes the still ]o---
RegisterServerEvent('gsc_kassippu:server:seizeBarrel')
AddEventHandler('gsc_kassippu:server:seizeBarrel', function(uid)
    local _source = source
    local conf = Config.Law or {}
    if not (conf.Enabled and conf.Seize and conf.Seize.Enabled) then return end
    if type(uid) ~= 'string' or not BarrelPositions[uid] then return end

    local Character = Shared.GetChar(_source)
    if not Shared.IsLawman(Character) then return end

    if GSC.BarrelCrew.Role(_source, uid) ~= "none" then return end
    if not AtBarrel(_source, uid) then return end

    if not HasEvidence(uid) then
        return GSC.Notify.Send(_source, Config.Text.SeizeNothing, 4000)
    end

    local keepers = Keepers(uid)

    ---o[ For the staff log, before the still and its owner are taken off the books ]o---
    GSC.Logs.Send("law", (Config.Text.Logs or {}).Seized, {
        { name = GSC.Logs.Label("Lawman"), value = GSC.Logs.Player(_source), raw = true },
        { name = GSC.Logs.Label("Still"), value = uid, inline = true },
        { name = GSC.Logs.Label("Owner"), value = GSC.Logs.Owner(BarrelOwner[uid]), raw = true },
        { name = GSC.Logs.Label("Told"), value = tostring(#keepers), inline = true },
        { name = GSC.Logs.Label("Where"), value = GSC.Logs.Where(BarrelPositions[uid]), inline = true },
    })

    RemoveBarrel(uid)

    GSC.Notify.Send(_source, Config.Text.SeizeDone, 5000)
    for _, src in ipairs(keepers) do
        if src ~= _source then GSC.Notify.Send(src, Config.Text.SeizeOwner, 8000) end
    end

    Shared.Debug(string.format("^1[Law]^7 (ID: %s) seized %s", _source, uid))
end)

---oo[ What the law module needs of a barrel ]oo---

---o[ For GSC.Upkeep ]o---
function Distillery.Owners()
    local owners = {}
    for uid in pairs(BarrelPositions) do
        local owner = BarrelOwner[uid]
        if owner then owners[owner] = (owners[owner] or 0) + 1 end
    end
    return owners
end

function Distillery.ExpireOwner(owner)
    local removed = 0
    for uid in pairs(BarrelPositions) do
        if BarrelOwner[uid] == owner then
            RemoveBarrel(uid)
            removed = removed + 1
        end
    end
    return removed
end

function Distillery.List()
    return BarrelPositions
end

function Distillery.SmokeLevel(uid)
    return SmokeLevelOf(uid)
end

function Distillery.Covered(uid)
    local seen = BarrelExposure[uid]
    return seen ~= nil and seen.covered == true
end

function Distillery.Keepers(uid)
    return Keepers(uid)
end

---oo[ What the theft module needs of a barrel ]oo---
function Distillery.DrawBottle(src, uid)
    return DrawBottle(src, uid)
end

function Distillery.Stage(uid)
    return BarrelStage[uid]
end

function Distillery.RemainingBottles(uid)
    return BarrelRemainingBottles[uid] or 0
end

---oo[ All Barrels Request Sync Event ]oo---
local LastSyncAsk = {}

AddEventHandler('playerDropped', function()
    LastSyncAsk[source] = nil
end)

RegisterServerEvent('gsc_kassippu:server:requestSync')
AddEventHandler('gsc_kassippu:server:requestSync', function(barrelId)
    local _source = source
    if type(barrelId) ~= 'string' or not BarrelPositions[barrelId] then return end

    local nowMs = GetGameTimer()
    if LastSyncAsk[_source] and nowMs - LastSyncAsk[_source] < 500 then return end -- spam guard
    LastSyncAsk[_source] = nowMs

    local Character = Shared.GetChar(_source)
    if not Character then return end

    Shared.Debug(string.format("^6[RequestSync]^7 (ID: %s) %s", _source, Character.firstname))

    local heat = BarrelHeat[barrelId] or 0.0
    local progress = BarrelBrewProgress[barrelId] or 0
    local stage = BarrelStage[barrelId] or Shared.BarrelStage.IDLE

    TriggerClientEvent('gsc_kassippu:client:updateHeat', _source, barrelId, heat, progress)
    TriggerClientEvent('gsc_kassippu:client:updateBrewUI', _source, barrelId, progress)
    TriggerClientEvent('gsc_kassippu:client:updateStage', _source, barrelId, stage)
end)
