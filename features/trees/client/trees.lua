local Trees = GSC.module('Trees')

local spawnedTrees = {}
local spawnedByUid = {}
local treeDataCache = {}
local treeBuckets = {}

local streamDistance = Config.TreeClimbConf.StreamDistance or 100.0
local despawnDistance = Config.TreeClimbConf.DespawnDistance or 120.0

if despawnDistance < (streamDistance + 20.0) then
    local corrected = streamDistance + 40.0
    print(("^3[GSC.Trees]^7 DespawnDistance (%.1f) must exceed StreamDistance (%.1f) - using %.1f instead")
        :format(despawnDistance, streamDistance, corrected))
    despawnDistance = corrected
end

---oo[ Non-Blocking Model Load ]oo---
local function EnsureModel(hash)
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    return false
end

---oo[ Helper: Delete One Locally-Owned Object ]oo---
local function DeleteLocalObject(entity)
    if not entity or not DoesEntityExist(entity) then return end
    SetEntityAsMissionEntity(entity, true, true)
    DeleteObject(entity)
    if DoesEntityExist(entity) then DeleteEntity(entity) end
end

---oo[ Helper: Clear All Trees (Client + Server) ]oo---
function Trees.ClearAll()
    for entity, _ in pairs(spawnedTrees) do
        DeleteLocalObject(entity)
    end
    for uid, bucket in pairs(treeBuckets) do
        DeleteLocalObject(bucket)
        treeBuckets[uid] = nil
    end
    spawnedTrees = {}
    spawnedByUid = {}
    Shared.Debug("^1[Cleanup]^7 All trees cleared from client")
end

---oo[ Helper: Clear All Trees from Database ]oo---
local function SpawnTreeBucket(uid, treeEntity)
    if treeBuckets[uid] and DoesEntityExist(treeBuckets[uid]) then return end

    local conf = Config.CoconutBucketConf
    local bucketModel = GetHashKey(conf.BucketModel)

    if not EnsureModel(bucketModel) then return end

    local coords = GetEntityCoords(treeEntity)
    local bucket = CreateObject(bucketModel, coords.x, coords.y, coords.z, false, false, false)

    AttachEntityToEntity(bucket, treeEntity, conf.AttachBone,
        conf.AttachOffset.x, conf.AttachOffset.y, conf.AttachOffset.z,
        conf.AttachRotation.x, conf.AttachRotation.y, conf.AttachRotation.z,
        true, false, false, false, 2, true)

    SetModelAsNoLongerNeeded(bucketModel)
    treeBuckets[uid] = bucket
end

local function DespawnTreeBucket(uid)
    DeleteLocalObject(treeBuckets[uid])
    treeBuckets[uid] = nil
end

---oo[ Check if tree exists at coordinates ]oo---
local function DoesTreeExist(uid)
    local entity = spawnedByUid[uid]
    return entity ~= nil and DoesEntityExist(entity)
end

---oo[ Spawn Tree at Specific Coordinates ]oo---
---o[ uid: the server's id for this tree. Only built from coords when none is given ]o---
function Trees.Spawn(coords, heading, persist, uid)
    heading = heading or 0.0
    persist = persist or false
    uid = uid or Shared.GenerateTreeUID(coords)

    if DoesTreeExist(uid) then
        return nil
    end

    local modelHash = GetHashKey(Config.Models.PlamTreeModel)
    if not EnsureModel(modelHash) then
        return nil
    end

    local cached = treeDataCache[uid]

    local spawnZ = (cached and cached.groundZ) or coords.z
    local treeEntity = CreateObject(modelHash, coords.x, coords.y, spawnZ, false, false, false)

    if not DoesEntityExist(treeEntity) then
        Shared.Debug("^1[Tree Spawn]^7 Failed to create tree entity")
        SetModelAsNoLongerNeeded(modelHash)
        return nil
    end

    SetEntityHeading(treeEntity, heading)
    local groundZ = cached and cached.groundZ
    if not groundZ then
        PlaceObjectOnGroundProperly(treeEntity) -- for the ground height only...
        groundZ = GetEntityCoords(treeEntity).z
        if cached then cached.groundZ = groundZ end
    end
    -- push the model down so its roots are under the ground (the prompt still uses the DB coords)
    local sink = Config.TreeClimbConf.SinkDepth or 0.0
    SetEntityCoordsNoOffset(treeEntity, coords.x, coords.y, groundZ - sink, false, false, false)
    SetEntityRotation(treeEntity, 0.0, 0.0, heading, 2, true) -- ...it also tilts to the slope: stand it straight
    FreezeEntityPosition(treeEntity, true)
    SetModelAsNoLongerNeeded(modelHash)

    spawnedByUid[uid] = treeEntity
    spawnedTrees[treeEntity] = {
        entity = treeEntity,
        coords = coords,
        uid = uid,
        heading = heading,
        persist = persist,
    }

    SpawnTreeBucket(uid, treeEntity)

    Shared.Debug("^2[Tree Spawn]^7 Spawned tree at: " .. tostring(coords) .. " | UID: " .. uid)

    return treeEntity
end

---oo[ Despawn Tree ]oo---
local function DespawnTree(entity)
    local treeData = entity and spawnedTrees[entity]
    if not treeData then
        if entity then spawnedTrees[entity] = nil end
        return
    end

    GSC.Climb.Abort()

    DeleteLocalObject(entity)

    treeData.entity = nil
    spawnedByUid[treeData.uid] = nil
    spawnedTrees[entity] = nil

    DespawnTreeBucket(treeData.uid)

    Shared.Debug("^3[Despawn]^7 Despawned tree: " .. treeData.uid)
end

---oo[ Remove a Climb Tree (Permanent) ]oo---
function Trees.Remove(entity)
    if not entity or not DoesEntityExist(entity) then return end

    local treeData = spawnedTrees[entity]
    if treeData then
        Shared.Debug("^1[Tree Remove]^7 Removing tree: " .. treeData.uid)

        GSC.Climb.Abort()

        DeleteLocalObject(entity)

        for uid, data in pairs(treeDataCache) do
            if data.uid == treeData.uid then
                treeDataCache[uid] = nil
                break
            end
        end

        spawnedByUid[treeData.uid] = nil
        spawnedTrees[entity] = nil

        DespawnTreeBucket(treeData.uid)

        if treeData.persist then
            TriggerServerEvent('nx_trees:server:deleteTree', treeData.uid)
        end
    end
end

---oo[ Get Nearest Climbable Tree ]oo---
function Trees.GetNearest(maxDistance)
    maxDistance = maxDistance or 5.0
    local playerCoords = GetEntityCoords(PlayerPedId())
    local nearestEntity = nil
    local nearestDist = maxDistance + 1
    local nearestData = nil

    -- flat distance to the trunk, plus a height allowance: the tree is sunk SinkDepth into
    -- the ground, and its stored z may sit anywhere between the ground and the sunk base
    local maxRise = (Config.TreeClimbConf.SinkDepth or 0.0) + 3.0

    for entity, data in pairs(spawnedTrees) do
        if DoesEntityExist(entity) then
            local dx, dy = playerCoords.x - data.coords.x, playerCoords.y - data.coords.y
            local dist = math.sqrt((dx * dx) + (dy * dy))
            if dist < nearestDist and math.abs(playerCoords.z - data.coords.z) <= maxRise then
                nearestDist = dist
                nearestEntity = entity
                nearestData = data
            end
        end
    end

    if nearestDist <= maxDistance then
        return nearestEntity, nearestData
    end
    return nil, nil
end

---oo[ Streaming Thread - Spawn/Despawn by Distance ]oo---
CreateThread(function()
    local streamSq = streamDistance * streamDistance
    local despawnSq = despawnDistance * despawnDistance
    local maxSpawns = Config.TreeClimbConf.MaxSpawnsPerPass or 2

    while true do
        local sleep = 1000

        if next(treeDataCache) ~= nil then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local nearestSq = math.huge
            local spawnedThisPass = 0
            local pendingSpawn = false

            for uid, treeInfo in pairs(treeDataCache) do
                local offset = playerCoords - treeInfo.coords
                local distSq = (offset.x * offset.x) + (offset.y * offset.y) + (offset.z * offset.z)

                if distSq < nearestSq then nearestSq = distSq end

                local entity = spawnedByUid[uid]

                if entity and not DoesEntityExist(entity) then
                    spawnedTrees[entity] = nil
                    spawnedByUid[uid] = nil
                    entity = nil
                end

                if not entity then
                    if distSq <= streamSq then
                        if spawnedThisPass < maxSpawns then
                            if Trees.Spawn(treeInfo.coords, treeInfo.heading, treeInfo.persist, uid) then
                                spawnedThisPass = spawnedThisPass + 1
                            else
                                pendingSpawn = true -- model still loading, retry shortly
                            end
                        else
                            pendingSpawn = true -- over budget for this pass
                        end
                    end
                elseif distSq >= despawnSq then
                    DespawnTree(entity)
                end
            end

            if pendingSpawn then
                sleep = 250
            elseif nearestSq <= streamSq then
                sleep = 1000
            elseif nearestSq <= (streamSq * 4) then
                sleep = 2000
            else
                sleep = 5000
            end
        else
            sleep = 3000
        end

        Wait(sleep)
    end
end)
---oo[ Load Trees from Database ONLY ]oo---
function Trees.LoadFromDatabase()
    TriggerServerEvent('nx_trees:server:requestTrees')
end

---oo[ Auto-start ]oo---
CreateThread(function()
    Wait(3000)
    Trees.LoadFromDatabase()
end)
---oo[ EVENT HANDLERS ]oo---
RegisterNetEvent('nx_trees:client:spawnTree')
AddEventHandler('nx_trees:client:spawnTree', function(uid, coords, heading)
    local treeCoords = vector3(coords.x, coords.y, coords.z)
    local uid_key = uid or Shared.GenerateTreeUID(treeCoords) -- the server's uid: the bucket is keyed on it

    if not treeDataCache[uid_key] then
        treeDataCache[uid_key] = {
            uid = uid_key,
            coords = treeCoords,
            heading = heading or 0.0,
            persist = true
        }
    end
end)

RegisterNetEvent('nx_trees:client:loadTrees')
AddEventHandler('nx_trees:client:loadTrees', function(trees)
    Trees.ClearAll()
    treeDataCache = {}

    if trees and #trees > 0 then
        for _, tree in ipairs(trees) do
            local coords = vector3(tree.x, tree.y, tree.z)
            -- the DB uid, not one rebuilt from x/y/z: FLOAT coords can round to a different
            -- uid, and then the server never answers this tree's bucket sync or collect
            local uid = tree.uid or Shared.GenerateTreeUID(coords)

            treeDataCache[uid] = {
                uid = uid,
                coords = coords,
                heading = tree.heading or 0.0,
                persist = true
            }
        end
        Shared.Debug("^2[Load]^7 Loaded " .. #trees .. " trees into cache (will spawn when nearby)")
    else
        Shared.Debug("^3[Load]^7 No trees found in database")
    end
end)

RegisterNetEvent('nx_trees:client:removeNearestTree')
AddEventHandler('nx_trees:client:removeNearestTree', function()
    local nearestTree, treeData = Trees.GetNearest(5.0)
    if nearestTree then
        Trees.Remove(nearestTree)
        GSC.Notify.Show("Tree removed!", 3000)
    else
        GSC.Notify.Show("No tree nearby!", 3000)
    end
end)

RegisterCommand('listtrees', function()
    local count = Shared.TableCount(spawnedTrees)
    local cacheCount = Shared.TableCount(treeDataCache)
    Shared.Debug("^2=== Current Trees (" .. count .. " spawned, " .. cacheCount .. " in cache) ===")
    for entity, data in pairs(spawnedTrees) do
        Shared.Debug(string.format("  - %s at %.2f, %.2f, %.2f", data.uid, data.coords.x, data.coords.y, data.coords.z))
    end
    GSC.Notify.Show("Found " .. count .. " trees spawned, " .. cacheCount .. " in cache", 3000)
end, false)

---o[ /cleartrees and /reloadtrees: admins, checked by the server ]o---
RegisterNetEvent('gsc_kassippu:client:adminCommand')
AddEventHandler('gsc_kassippu:client:adminCommand', function(name)
    if name == 'cleartrees' then
        Trees.ClearAll()
        GSC.Notify.Show("All trees cleared from client! Use /cleartreesdb to clear database too.", 3000)
    elseif name == 'reloadtrees' then
        Trees.LoadFromDatabase()
        GSC.Notify.Show("Reloading trees from database...", 3000)
    end
end)

---oo[ Accessors For Other Modules ]oo---
function Trees.AnySpawned()
    return next(spawnedByUid) ~= nil
end

---oo[ EXPORTS ]oo---
exports('SpawnClimbTree', Trees.Spawn)
exports('RemoveClimbTree', Trees.Remove)
exports('GetNearestClimbTree', Trees.GetNearest)
exports('ClearAllTrees', Trees.ClearAll)

---oo[ Cleanup On Resource Stop ]oo---
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Trees.ClearAll()
end)
