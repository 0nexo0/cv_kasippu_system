local TreeStore = GSC.module('TreeStore')

local treeStates = {}
local REGROW_TIME = Config.TreeClimbConf.TreeGrowingTime
local Rewards = Config.TreeItemsSearchRewards
local configTreesMigrated = false
local TreeBucketFill = {}       -- [uid] = cached current percent
local TreeBucketLastUpdate = {}
local TreeCoords = {}

---o[ One query, waited for ]o---
local function Exec(sql, params)
    local p = promise.new()
    exports.oxmysql:execute(sql, params or {}, function(result, err)
        if err then print("^1[Database]^7 " .. tostring(err)) end
        p:resolve(not err and (result or {}) or nil)
    end, GetCurrentResourceName(), true)
    return Citizen.Await(p)
end

---oo[ Ensure fill_percent / last_update Columns Exist On gsc_climb_trees ]oo---
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end

    local columns = Exec([[
        SELECT COLUMN_NAME AS name FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gsc_climb_trees'
    ]])
    if not columns then return end
    if #columns == 0 then
        return print("^1[Error]^7 Table gsc_climb_trees not found - run database/schema.sql. No climbable trees loaded.")
    end

    local have = {}
    for _, col in ipairs(columns) do have[tostring(col.name):lower()] = true end

    if not have.fill_percent then
        Exec("ALTER TABLE `gsc_climb_trees` ADD COLUMN `fill_percent` DECIMAL(5,2) NOT NULL DEFAULT 0.00")
    end
    if not have.last_update then
        Exec("ALTER TABLE `gsc_climb_trees` ADD COLUMN `last_update` INT(11) NOT NULL DEFAULT 0")
    end
    Shared.Debug("^2[Bucket]^7 gsc_climb_trees fill_percent/last_update columns ready.")

    ---oo[ Load Every Defined Tree + Start Filling On Boot ]oo---
    local results = Exec('SELECT uid, x, y, z, fill_percent, last_update FROM gsc_climb_trees')
    if not results then return end

    local now = os.time()
    for _, row in ipairs(results) do
        TreeCoords[row.uid] = vector3(row.x + 0.0, row.y + 0.0, row.z + 0.0)
        TreeBucketFill[row.uid] = tonumber(row.fill_percent) or 0.0

        if not row.last_update or tonumber(row.last_update) == 0 then
            TreeBucketLastUpdate[row.uid] = now
            TreeStore.SaveBucketToDB(row.uid)
        else
            TreeBucketLastUpdate[row.uid] = tonumber(row.last_update)
        end
    end

    Shared.Debug("^2[Bucket]^7 Loaded & started filling " .. #results .. " tree(s) from gsc_climb_trees.")
end)

---oo[ Lazily Calculate Current Fill % For a Tree ]oo---
function TreeStore.GetBucketFillPercent(uid)
    local conf = Config.CoconutBucketConf
    local current = TreeBucketFill[uid]

    if current and current >= conf.MaxFillPercent then
        return current
    end

    local now = os.time()

    if current == nil then
        TreeBucketFill[uid] = 0.0
        TreeBucketLastUpdate[uid] = now
        return 0.0
    end

    local elapsedMinutes = (now - (TreeBucketLastUpdate[uid] or now)) / 60
    local intervalMinutes = conf.FillIntervalMinutes

    if elapsedMinutes >= intervalMinutes then
        local intervalsPassed = math.floor(elapsedMinutes / intervalMinutes)
        local gained = intervalsPassed * conf.FillPercentPerInterval

        TreeBucketFill[uid] = math.min(conf.MaxFillPercent, current + gained)
        TreeBucketLastUpdate[uid] = TreeBucketLastUpdate[uid] + (intervalsPassed * intervalMinutes * 60)
    end

    return TreeBucketFill[uid]
end

---oo[ Save Bucket State to DB ]oo---
function TreeStore.SaveBucketToDB(uid)
    exports.oxmysql:execute([[
        UPDATE gsc_climb_trees
        SET fill_percent = :fill, last_update = :updated
        WHERE uid = :uid
    ]], { uid = uid, fill = TreeBucketFill[uid] or 0.0, updated = TreeBucketLastUpdate[uid] or os.time() })
end

---oo[ Optional DB Snapshot - OFF by default ]oo---
CreateThread(function()
    local conf = Config.CoconutBucketConf
    local snapshotMinutes = tonumber(conf.DbSnapshotMinutes) or 0

    if snapshotMinutes <= 0 then
        Shared.Debug("^2[Bucket]^7 DB snapshots off - fill state is derived from (fill_percent, last_update)")
        return -- thread exits, nothing left ticking
    end

    local tickMs = snapshotMinutes * 60 * 1000
    local written = {}

    while true do
        Wait(tickMs)

        local queries = nil

        for uid in pairs(TreeBucketFill) do
            local percent = TreeStore.GetBucketFillPercent(uid)
            local updated = TreeBucketLastUpdate[uid] or os.time()
            local stamp = percent .. ":" .. updated

            if written[uid] ~= stamp then
                written[uid] = stamp
                queries = queries or {}
                queries[#queries + 1] = {
                    query = 'UPDATE gsc_climb_trees SET fill_percent = ?, last_update = ? WHERE uid = ?',
                    values = { percent, updated, uid },
                }
            end
        end

        if queries then
            exports.oxmysql:transaction(queries)
            Shared.Debug(string.format("^2[Bucket]^7 Snapshot persisted %d tree(s) in one transaction", #queries))
        end
    end
end)

---oo[ Climb Rope Requirement Check ]oo---
local Climbs = {}

---o[ Up THIS tree ]o---
local function ClimbedUp(src, uid)
    local climb = Climbs[src]
    if not climb or climb.uid ~= uid then return false end

    local conf = Config.TreeClimbConf
    local took = (GetGameTimer() - climb.at) / 1000.0
    return took >= (conf.MinClimbSeconds or 0) and took <= (conf.MaxTopMinutes or 30) * 60
end

RegisterServerEvent('gsc_kassippu:server:requestClimb')
AddEventHandler('gsc_kassippu:server:requestClimb', function(uid)
    local _source = source
    local Character = Shared.GetChar(_source)
    if not Character then return end

    local requiredItem = Config.TreeClimbConf.ClimbRequiredItem
    local hasRope = exports.vorp_inventory:getItemCount(_source, nil, requiredItem) >= 1

    ---o[ Remember the climb ]o---
    local treePos = type(uid) == 'string' and TreeCoords[uid]
    if hasRope and treePos then
        local p = GetEntityCoords(GetPlayerPed(_source))
        local reach = Config.TreeClimbConf.SearchMaxDistance or 6.0
        if ((p.x - treePos.x) ^ 2 + (p.y - treePos.y) ^ 2) <= reach * reach then
            Climbs[_source] = { uid = uid, at = GetGameTimer() }
        end
    end

    TriggerClientEvent('gsc_kassippu:client:climbResponse', _source, uid, hasRope)

    if not hasRope then
        Shared.Debug(string.format("^1[Climb Denied]^7 %s tried to climb without %s", Character.firstname, requiredItem))
    end
end)

---oo[ Regrow Cooldown ]oo---
local function GetBucketCooldownRemaining(uid)
    local waitUntil = TreeBucketLastUpdate[uid]
    if not waitUntil then return 0 end
    return math.max(0, waitUntil - os.time())
end

---oo[ Send Current Bucket Fill % When Player Reaches Top ]oo---
local lastSyncRequest = {}
local lastTreeRequest = {}

RegisterServerEvent('gsc_kassippu:server:requestBucketSync')
AddEventHandler('gsc_kassippu:server:requestBucketSync', function(uid)
    local _source = source
    if type(uid) ~= 'string' or not TreeCoords[uid] then return end

    local now = GetGameTimer()
    local last = lastSyncRequest[_source]
    if last and (now - last) < 1000 then return end
    lastSyncRequest[_source] = now

    local before = TreeBucketFill[uid]
    local percent = TreeStore.GetBucketFillPercent(uid)

    if percent ~= before then
        TreeStore.SaveBucketToDB(uid)
    end

    TriggerClientEvent('gsc_kassippu:client:bucketSync', _source, uid, percent, GetBucketCooldownRemaining(uid))
end)

AddEventHandler('playerDropped', function()
    lastSyncRequest[source] = nil
    lastTreeRequest[source] = nil
    Climbs[source] = nil
end)

---oo[ Collect Coconut Water Into The Player's Pots ]oo---
local Collecting = {}     -- [src] = true while their collect runs
local CollectingTree = {} -- [uid] = true while somebody is collecting from it

---o[ The older of two picked stamps: topped-up water is as old as its oldest part ]o---
local function OlderStamp(a, b)
    a, b = tonumber(a), tonumber(b)
    if a and b then return math.min(a, b) end
    return a or b
end

---o[ Pour up to `available` ml into the player's pots: part-filled pots first, then empty ones ]o---
local function FillPots(src, available, picked)
    local conf = Config.CoconutBucketConf
    local capacity = conf.PotCapacityMl or (conf.MaxFillPercent * conf.MlPerPercent)
    local taken, topped, filled, heavy = 0, 0, 0, false

    ---o[ 1. Top up part-filled pots, fullest first ]o---
    local partial = {}
    for _, item in ipairs(exports.vorp_inventory:getUserInventoryItems(src) or {}) do
        local ml = item.name == conf.FilledPotItem and item.metadata and tonumber(item.metadata.ml) or nil
        if ml and ml < capacity then
            partial[#partial + 1] = { id = item.id, count = item.count or 1, ml = math.max(0, ml), metadata = item.metadata }
        end
    end
    table.sort(partial, function(a, b) return a.ml > b.ml end)

    for _, pot in ipairs(partial) do
        for _ = 1, pot.count do
            if available - taken <= 0 then break end

            local add = math.min(capacity - pot.ml, available - taken)
            local metadata = GSC.Mash.PotMetadata(pot.ml + add, OlderStamp(pot.metadata.picked, picked), pot.metadata)
            if exports.vorp_inventory:setItemMetadata(src, pot.id, metadata, 1) == false then break end

            taken = taken + add
            topped = topped + 1
        end
    end

    ---o[ 2. Fill empty pots with what is left ]o---
    local empties = exports.vorp_inventory:getItemCount(src, nil, conf.RequiredPotItem) or 0
    for _ = 1, empties do
        if available - taken <= 0 then break end

        if not exports.vorp_inventory:canCarryItem(src, conf.FilledPotItem, 1) then
            heavy = true
            break
        end
        if not exports.vorp_inventory:subItem(src, conf.RequiredPotItem, 1) then break end -- no empty pot taken: no filled one

        local ml = math.min(capacity, available - taken)
        exports.vorp_inventory:addItem(src, conf.FilledPotItem, 1, GSC.Mash.PotMetadata(ml, picked))

        taken = taken + ml
        filled = filled + 1
    end

    return taken, topped, filled, heavy
end

RegisterServerEvent('gsc_kassippu:server:collectCoconutWater')
AddEventHandler('gsc_kassippu:server:collectCoconutWater', function(uid)
    local _source = source
    local Character = Shared.GetChar(_source)
    if not Character then return end

    ---o[ Only a real tree, and only standing at it ]o---
    local treePos = type(uid) == 'string' and TreeCoords[uid]
    if not treePos then return end
    local p = GetEntityCoords(GetPlayerPed(_source))
    local reach = Config.TreeClimbConf.SearchMaxDistance or 6.0
    if ((p.x - treePos.x) ^ 2 + (p.y - treePos.y) ^ 2) > reach * reach then
        Shared.Debug("^1[Warning]^7 Player " .. _source .. " tried to collect from tree " .. uid .. " from too far away.")
        return
    end

    ---o[ Only after climbing it ]o---
    if not ClimbedUp(_source, uid) then
        Shared.Debug("^1[Warning]^7 Player " .. _source .. " tried to collect from tree " .. uid .. " without climbing it.")
        return
    end

    ---o[ One collect at a time, per player and per tree ]o---
    if Collecting[_source] or CollectingTree[uid] then return end
    Collecting[_source], CollectingTree[uid] = true, true

    local ok, err = pcall(function()
        local conf = Config.CoconutBucketConf
        local percent = TreeStore.GetBucketFillPercent(uid)
        local totalMl = math.floor(percent * conf.MlPerPercent) -- 1% = 10ml

        ---o[ Still On Its Regrow Cooldown From The Last Collect ]o---
        local cooldownLeft = GetBucketCooldownRemaining(uid)
        if cooldownLeft > 0 then
            TriggerClientEvent('gsc_kassippu:client:bucketSync', _source, uid, percent, cooldownLeft)
            GSC.Notify.Send(_source, Config.Text.TreeReGrowingNotify, 3000)
            return
        end

        if totalMl <= 0 then
            GSC.Notify.Send(_source, Config.Text.CoconutBucketEmptyNotify, 3000)
            return
        end

        local picked = Config.Freshness.Enabled and GSC.Mash.Stamp() or nil
        local taken, topped, filled, heavy = FillPots(_source, totalMl, picked)

        if taken <= 0 then
            if heavy then
                GSC.Notify.Send(_source, Config.Text.TreeItemsSearchPocketHeavyNotify, 3000)
            else
                GSC.Notify.Send(_source, Config.Text.CoconutPotRequiredNotify, 3000)
            end
            return
        end

        ---o[ Take it out of the tree's pot ]o---
        local leftMl = totalMl - taken
        local cooldown = 0

        if leftMl <= 0 then
            ---o[ Drained: reset it and start its regrow cooldown ]o---
            cooldown = math.max(0, conf.RegrowCooldownSeconds or 0)
            TreeBucketFill[uid] = 0.0
            TreeBucketLastUpdate[uid] = os.time() + cooldown
        else
            ---o[ Some left: it stays in the tree and keeps filling from now ]o---
            if percent >= conf.MaxFillPercent then TreeBucketLastUpdate[uid] = os.time() end
            TreeBucketFill[uid] = math.max(0.0, percent - taken / conf.MlPerPercent)
        end
        TreeStore.SaveBucketToDB(uid)

        TriggerClientEvent('gsc_kassippu:client:bucketSync', _source, uid, TreeBucketFill[uid], cooldown)
        GSC.Notify.Send(_source, string.format(Config.Text.CoconutCollectedNotify, taken), 3000)
        if leftMl > 0 then
            GSC.Notify.Send(_source, string.format(Config.Text.CoconutLeftInTreeNotify, leftMl), 4000)
        end

        Shared.Debug(string.format(
            "^2[Coconut]^7 %s collected %dml from %s (%d pot(s) topped up, %d filled, %dml left in the tree, regrowing for %ds)",
            Character.firstname, taken, uid, topped, filled, math.max(0, leftMl), cooldown))
    end)

    Collecting[_source], CollectingTree[uid] = nil, nil
    if not ok then print("^1[Coconut]^7 collect failed: " .. tostring(err)) end
end)

---oo[ Tree Items Search Rewards Function ]oo---
RegisterServerEvent("nx_trees:giveTreeReward")
AddEventHandler("nx_trees:giveTreeReward", function(treeKey)
    local _source = source
    local Character = Shared.GetChar(_source)
    if not Character or not treeKey then return end

    ---o[ Only a real tree, and only standing at it ]o---
    local treePos = type(treeKey) == 'string' and TreeCoords[treeKey]
    if not treePos then
        Shared.Debug("^1[Warning]^7 Player " .. _source .. " searched an unknown tree: " .. tostring(treeKey))
        return
    end
    local p = GetEntityCoords(GetPlayerPed(_source))
    local reach = Config.TreeClimbConf.SearchMaxDistance or 6.0
    if ((p.x - treePos.x) ^ 2 + (p.y - treePos.y) ^ 2) > reach * reach then
        Shared.Debug("^1[Warning]^7 Player " .. _source .. " searched tree " .. treeKey .. " from too far away.")
        return
    end

    ---o[ Only after climbing it ]o---
    if not ClimbedUp(_source, treeKey) then
        Shared.Debug("^1[Warning]^7 Player " .. _source .. " searched tree " .. treeKey .. " without climbing it.")
        return
    end

    local currentTime = os.time()

    if treeStates[treeKey] and (currentTime - treeStates[treeKey]) < REGROW_TIME then
        GSC.Notify.Send(_source, Config.Text.TreeReGrowingNotify, 3000)
        return
    end

    local roll = math.random(1, 100)
    local selectedItem = nil
    local selectedAmount = 0
    local selectedLabel = nil
    local cumulativeChance = 0

    for _, reward in ipairs(Rewards) do
        cumulativeChance = cumulativeChance + reward.chance
        if roll <= cumulativeChance then
            selectedItem = reward.item
            selectedAmount = math.random(reward.amount.min, reward.amount.max)
            selectedLabel = reward.label or reward.item
            break
        end
    end

    if selectedItem then
        local canCarry = exports.vorp_inventory:canCarryItem(_source, selectedItem, selectedAmount)
        if canCarry then
            treeStates[treeKey] = currentTime
            exports.vorp_inventory:addItem(_source, selectedItem, selectedAmount,
                GSC.Mash.PickedMetadata(selectedItem))
            TriggerClientEvent('gsc_kassippu:client:treeReward', _source, selectedItem, selectedAmount, selectedLabel, treeKey)
        else
            GSC.Notify.Send(_source, Config.Text.TreeItemsSearchPocketHeavyNotify, 3000)
        end
    else
        TriggerClientEvent('gsc_kassippu:client:treeReward', _source, nil, nil, nil, treeKey)
    end
end)

---oo[ Tree Admin Check ]oo---
local function IsTreeAdmin(src)
    return GSC.Admin.Is(src, Config.TreeAdmin)
end

---oo[ Save Tree to Database ]oo---
local function SaveTree(coords, heading, onSaved)
    local correctUid = Shared.GenerateTreeUID(coords)

    exports.oxmysql:execute([[
        INSERT INTO gsc_climb_trees (uid, x, y, z, heading)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            x = VALUES(x),
            y = VALUES(y),
            z = VALUES(z),
            heading = VALUES(heading)
    ]], { correctUid, coords.x, coords.y, coords.z, heading }, function(rowsChanged)
        if rowsChanged then
            Shared.Debug("^2[DB]^7 Saved tree: " .. correctUid)
            TreeCoords[correctUid] = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)

            if TreeBucketLastUpdate[correctUid] == nil then
                TreeBucketFill[correctUid] = 0.0
                TreeBucketLastUpdate[correctUid] = os.time()
                TreeStore.SaveBucketToDB(correctUid)
            end
            if onSaved then onSaved(correctUid) end
        end
    end)
end

---oo[ Admin ]oo---
local function Round2(n) return math.floor(n * 100 + 0.5) / 100 end -- the tree uid uses 2 decimals

RegisterCommand(Config.TreeAdmin.AddCommand or 'addtree', function(source, args)
    local _source = source
    if _source == 0 then return print("[kasippu] " .. Config.Text.TreeAddInGame) end

    local Character = Shared.GetChar(_source)
    if not Character then return end
    if not IsTreeAdmin(_source, Character) then
        return GSC.Notify.Send(_source, Config.Text.TreeAdminNoAccess, 3000)
    end

    local pos = GetEntityCoords(GetPlayerPed(_source))
    local coords = vector3(Round2(pos.x), Round2(pos.y), Round2(pos.z))
    local heading = Round2((tonumber(args[1]) or 0.0) % 360)

    exports.oxmysql:execute('SELECT uid, x, y, z FROM gsc_climb_trees', {}, function(rows)
        local spacing = Config.TreeAdmin.MinTreeSpacing or 0
        for _, row in ipairs(rows or {}) do
            local dist = #(coords - vector3(row.x + 0.0, row.y + 0.0, row.z + 0.0))
            if dist < spacing then
                return GSC.Notify.Send(_source, string.format(Config.Text.TreeAddTooClose, dist), 4000)
            end
        end

        SaveTree(coords, heading, function(uid)
            TriggerClientEvent('nx_trees:client:spawnTree', -1, uid, { x = coords.x, y = coords.y, z = coords.z }, heading)
            GSC.Notify.Send(_source, string.format(Config.Text.TreeAddDone, uid), 5000)
            Shared.Debug(string.format("^2[DB]^7 %s added tree %s (heading %.0f)", Character.firstname, uid, heading))
            GSC.Logs.Send("admin", (Config.Text.Logs or {}).TreeAdded, {
                { name = GSC.Logs.Label("Admin"), value = GSC.Logs.Player(_source), raw = true },
                { name = GSC.Logs.Label("Tree"), value = uid, inline = true },
                { name = GSC.Logs.Label("Where"), value = GSC.Logs.Where(coords), inline = true },
            })
        end)
    end)
end, false)

---oo[ Delete Tree from Database ]oo---
RegisterServerEvent('nx_trees:server:deleteTree')
AddEventHandler('nx_trees:server:deleteTree', function(uid)
    local _source = source
    if type(uid) ~= 'string' then return end

    local Character = Shared.GetChar(_source)
    if not Character then return end

    if not IsTreeAdmin(_source, Character) then
        Shared.Debug("^1[Warning]^7 Player " .. _source .. " tried to delete tree " .. uid .. " without tree admin rights.")
        return
    end

    exports.oxmysql:execute('SELECT x, y, z FROM gsc_climb_trees WHERE uid = ?', { uid }, function(results)
        local tree = results and results[1]
        if not tree then return end

        local treePos = vector3(tree.x + 0.0, tree.y + 0.0, tree.z + 0.0)
        if #(GetEntityCoords(GetPlayerPed(_source)) - treePos) > Config.TreeAdmin.MaxDeleteDistance then
            Shared.Debug("^1[Warning]^7 Player " .. _source .. " tried to delete tree " .. uid .. " from too far away.")
            return
        end

        exports.oxmysql:execute('DELETE FROM gsc_climb_trees WHERE uid = ?', { uid }, function(rowsChanged)
            if rowsChanged and rowsChanged > 0 then
                TreeBucketFill[uid] = nil
                TreeBucketLastUpdate[uid] = nil
                TreeCoords[uid] = nil
                Shared.Debug("^1[DB]^7 Deleted tree: " .. uid .. " (by player " .. _source .. ")")
                GSC.Logs.Send("admin", (Config.Text.Logs or {}).TreeDeleted, {
                    { name = GSC.Logs.Label("Admin"), value = GSC.Logs.Player(_source), raw = true },
                    { name = GSC.Logs.Label("Tree"), value = uid, inline = true },
                    { name = GSC.Logs.Label("Where"), value = GSC.Logs.Where(treePos), inline = true },
                })
            end
        end)
    end)
end)

---oo[ Send Every Tree To A Player ]oo---
local function SendTrees(src)
    local nowMs = GetGameTimer()
    if lastTreeRequest[src] and (nowMs - lastTreeRequest[src]) < 5000 then return end
    lastTreeRequest[src] = nowMs

    exports.oxmysql:execute('SELECT * FROM gsc_climb_trees', {}, function(results)
        TriggerClientEvent('nx_trees:client:loadTrees', src, results or {})
        Shared.Debug(string.format("^2[DB]^7 Sent %d trees to player %s", results and #results or 0, src))
    end)
end

RegisterServerEvent('nx_trees:server:requestTrees')
AddEventHandler('nx_trees:server:requestTrees', function()
    SendTrees(source)
end)

---oo[ Auto-load trees when player joins ]oo---
AddEventHandler("vorp:SelectedCharacter", function(source, character)
    local src = source
    SetTimeout(2000, function() SendTrees(src) end)
end)

---oo[ ONE-TIME Config to Database Migration ]oo---
CreateThread(function()
    Wait(3000)

    if not Config.AutoSaveConfigTrees then
        Shared.Debug("^3[DB Init]^7 Config.AutoSaveConfigTrees is disabled, skipping migration")
        return
    end

    if configTreesMigrated then
        Shared.Debug("^3[DB Init]^7 Config trees already migrated, skipping")
        return
    end

    exports.oxmysql:execute('SELECT COUNT(*) as count FROM gsc_climb_trees', {}, function(result)
        local dbCount = 0
        if result and #result > 0 then
            dbCount = result[1].count or 0
        end

        if dbCount == 0 then
            if Config.ClimbTrees and #Config.ClimbTrees > 0 then
                Shared.Debug("^3[DB Init]^7 Database empty. Migrating " .. #Config.ClimbTrees .. " trees from config...")

                for _, treeData in ipairs(Config.ClimbTrees) do
                    if treeData.coords then
                        local uid = Shared.GenerateTreeUID(treeData.coords)
                        local startNow = os.time()
                        exports.oxmysql:execute([[
                            INSERT INTO gsc_climb_trees (uid, x, y, z, heading, fill_percent, last_update)
                            VALUES (?, ?, ?, ?, ?, 0.00, ?)
                        ]], { uid, treeData.coords.x, treeData.coords.y, treeData.coords.z, treeData.heading or 0.0, startNow })

                        TreeBucketFill[uid] = 0.0
                        TreeBucketLastUpdate[uid] = startNow
                        TreeCoords[uid] = vector3(treeData.coords.x + 0.0, treeData.coords.y + 0.0, treeData.coords.z + 0.0)

                        Shared.Debug(string.format("^2[DB Init]^7 Migrated config tree: %s", uid))
                    end
                end

                configTreesMigrated = true
                Shared.Debug("^2[DB Init]^7 Config trees migrated to database successfully!")
            else
                Shared.Debug("^3[DB Init]^7 No trees in config to migrate")
                configTreesMigrated = true
            end
        else
            Shared.Debug("^3[DB Init]^7 Database already has " .. dbCount .. " trees. Config will be IGNORED.")
            configTreesMigrated = true
        end
    end)
end)

---oo[ Admin Commands ]oo---
local function DeniedTreeCommand(src)
    if IsTreeAdmin(src) then return false end
    GSC.Notify.Send(src, Config.Text.AdminNoAccess, 3000)
    return true
end

RegisterCommand('removetree', function(source, args, raw)
    if source == 0 or DeniedTreeCommand(source) then return end
    TriggerClientEvent('nx_trees:client:removeNearestTree', source)
end, false)

---oo[ Dev Tree Commands ]oo---
if Config.DebugTreeCommands then
RegisterCommand('spawntree', function(source, args, raw)
    if source == 0 or DeniedTreeCommand(source) then return end
    local coords = GetEntityCoords(GetPlayerPed(source))
    TriggerClientEvent('nx_trees:client:spawnTree', source, nil, {x = coords.x, y = coords.y, z = coords.z}, 0.0)
    GSC.Notify.Send(source, "Tree spawned at your location.", 3000)
end, false)

RegisterCommand('listtreesdb', function(source, args, raw)
    if source == 0 then
        exports.oxmysql:execute('SELECT * FROM gsc_climb_trees', {}, function(results)
            if results and #results > 0 then
                print("^2=== Trees in Database (" .. #results .. ") ===")
                for _, tree in ipairs(results) do
                    print(string.format("  - %s at %.2f, %.2f, %.2f", tree.uid, tree.x, tree.y, tree.z))
                end
            else
                print("^3No trees found in database")
            end
        end)
        return
    end
    if DeniedTreeCommand(source) then return end

    exports.oxmysql:execute('SELECT COUNT(*) as count FROM gsc_climb_trees', {}, function(result)
        local count = 0
        if result and #result > 0 then
            count = result[1].count or 0
        end
        GSC.Notify.Send(source, "Database contains " .. count .. " trees.", 5000)
    end)
end, false)

local function LogTreesCleared(src, count)
    GSC.Logs.Send("admin", (Config.Text.Logs or {}).TreesCleared, {
        { name = GSC.Logs.Label("Admin"), value = GSC.Logs.Player(src), raw = true },
        { name = GSC.Logs.Label("Count"), value = tostring(count or 0), inline = true },
    })
end

RegisterCommand('cleartreesdb', function(source, args, raw)
    if source == 0 then
        exports.oxmysql:execute('DELETE FROM gsc_climb_trees', {}, function(rowsChanged)
            TreeBucketFill, TreeBucketLastUpdate, TreeCoords = {}, {}, {}
            print("^1[DB]^7 Deleted " .. (rowsChanged or 0) .. " trees from database")
            LogTreesCleared(0, rowsChanged)
        end)
        return
    end

    if DeniedTreeCommand(source) then return end

    exports.oxmysql:execute('DELETE FROM gsc_climb_trees', {}, function(rowsChanged)
        TreeBucketFill, TreeBucketLastUpdate, TreeCoords = {}, {}, {}
        GSC.Notify.Send(source, "Cleared " .. (rowsChanged or 0) .. " trees from the database.", 5000)
        LogTreesCleared(source, rowsChanged)
    end)
end, false)

RegisterCommand('fixduplicates', function(source, args, raw)
    if source == 0 then
        print("^1[FIX]^7 Removing duplicate trees from database...")
        exports.oxmysql:execute("DELETE FROM gsc_climb_trees WHERE uid NOT LIKE 'climb_tree_%'", {}, function(rowsChanged)
            print("^2[FIX]^7 Removed " .. (rowsChanged or 0) .. " duplicate trees with wrong UID format")
        end)
        return
    end
    GSC.Notify.Send(source, "Use /fixduplicates from the server console only.", 3000)
end, false)
end -- Config.DebugTreeCommands
