local Harvest = GSC.module('Harvest')

local bucketState = {}      -- [uid] = { percent, cooldown, at } as of the last server answer
local hudTreeUid = nil      -- uid of the tree the player is currently sitting on top of
local hudShownPercent = nil -- eased value the bar actually draws (chases the real one)
local lastSearchAt = {}     -- [treeKey] = when this client last got loot from that tree

---oo[ 2D Text Helper (RedM) ]oo---
local function DrawTxt(text, x, y, scale, r, g, b, a, centre)
    local str = CreateVarString(10, "LITERAL_STRING", text)
    SetTextScale(scale, scale)
    SetTextColor(math.floor(r), math.floor(g), math.floor(b), math.floor(a))
    SetTextDropshadow(1, 0, 0, 0, 220)
    SetTextFontForCurrentCommand(Config.CoconutBucketConf.HudFont or 1)
    SetTextCentre(centre and true or false)
    DisplayText(str, x, y)
end

RegisterNetEvent('gsc_kassippu:client:bucketSync')
AddEventHandler('gsc_kassippu:client:bucketSync', function(uid, percent, cooldown)
    bucketState[uid] = { percent = percent, cooldown = cooldown or 0, at = GetGameTimer() }
end)

---oo[ Work Out A Bucket's Current Reading Without Asking The Server ]oo---
local function GetBucketReading(uid)
    local state = bucketState[uid]
    if not state or state.percent == nil then return nil, nil end

    local conf = Config.CoconutBucketConf
    local elapsed = (GetGameTimer() - state.at) / 1000 -- seconds since that answer
    local cooldown = state.cooldown - elapsed

    if cooldown > 0 then
        return state.percent, cooldown -- still regrowing: nothing accrues yet
    end

    local fillingFor = elapsed - state.cooldown
    local intervalSeconds = math.max(1, conf.FillIntervalMinutes) * 60
    local intervals = math.floor(fillingFor / intervalSeconds)

    if intervals <= 0 then return state.percent, 0 end

    return math.min(conf.MaxFillPercent, state.percent + (intervals * conf.FillPercentPerInterval)), 0
end

---oo[ Bucket Fill HUD ]oo---
local function DrawBar(x, y, w, h, r, g, b, a)
    DrawRect(x, y, w, h, math.floor(r), math.floor(g), math.floor(b), math.floor(a))
end

local function DrawBucketFillHud(percent, cooldown)
    local conf = Config.CoconutBucketConf
    local x = conf.HudPosX or 0.5
    local y = conf.HudPosY or 0.88
    local w = conf.HudBarWidth or 0.14
    local h = conf.HudBarHeight or 0.013
    local maxPct = conf.MaxFillPercent or 100

    DrawBar(x, y, w + 0.011, h + 0.016, 18, 13, 9, 235)
    DrawBar(x, y, w + 0.006, h + 0.010, 116, 88, 54, 220)
    DrawBar(x, y, w, h, 46, 36, 26, 245)

    DrawTxt(Config.Text.CoconutFillHudLabel, x, y - 0.036, 0.42, 226, 209, 176, 235, true)

    if percent == nil then
        DrawTxt(Config.Text.CoconutFillHudWaiting, x, y + 0.014, 0.30, 168, 152, 128, 200, true)
        return
    end

    local pct = math.max(0.0, math.min(percent, maxPct))
    local ratio = (maxPct > 0) and (pct / maxPct) or 0.0
    local ml = math.floor(pct * (conf.MlPerPercent or 10))
    local full = pct >= maxPct

    local r, g, b = 176, 118, 38
    local hr, hg, hb = 214, 162, 74
    if full then
        r, g, b = 205, 154, 52
        hr, hg, hb = 238, 199, 108
    end

    if ratio > 0.0 then
        local fw = w * ratio
        local fx = x - (w / 2) + (fw / 2)
        DrawBar(fx, y, fw, h - 0.002, r, g, b, 245)
        DrawBar(fx, y - (h / 4), fw, h / 3, hr, hg, hb, 200)
    end

    for i = 1, 3 do
        DrawBar(x - (w / 2) + (w * (i / 4)), y, 0.0011, h - 0.002, 24, 18, 12, 190)
    end

    if cooldown and cooldown > 0 then
        local mins = math.floor(cooldown / 60)
        local secs = math.floor(cooldown % 60)
        DrawTxt(string.format("%s  %02d:%02d", Config.Text.CoconutFillHudRegrowing, mins, secs),
            x, y + 0.014, 0.30, 186, 116, 80, 225, true)
    elseif full then
        DrawTxt(string.format("%s  -  %dml", Config.Text.CoconutFillHudReady, ml),
            x, y + 0.014, 0.30, 238, 199, 108, 235, true)
    else
        DrawTxt(string.format("%d%%  -  %dml", math.floor(pct + 0.5), ml),
            x, y + 0.014, 0.30, 214, 199, 172, 220, true)
    end
end

---oo[ Bucket HUD Thread ]oo---
CreateThread(function()
    local lastSync = 0
    local lastFrame = GetGameTimer()
    local lastRead = 0
    local readPercent, readCooldown = nil, nil

    while true do
        local conf = Config.CoconutBucketConf

        if hudTreeUid and conf.ShowFillHud then
            local now = GetGameTimer()
            local dt = math.min((now - lastFrame) / 1000, 0.25) -- clamp so a stutter cannot jump the bar
            lastFrame = now

            if (now - lastRead) > 250 then
                lastRead = now
                readPercent, readCooldown = GetBucketReading(hudTreeUid)
            end

            local target, cooldown = readPercent, readCooldown

            if target == nil then
                hudShownPercent = nil
            elseif hudShownPercent == nil then
                hudShownPercent = target -- first reading, no drain animation
            elseif hudShownPercent ~= target then
                local maxPct = conf.MaxFillPercent or 100
                local step = (maxPct / math.max(0.2, conf.HudEaseSeconds or 2.5)) * dt

                if hudShownPercent < target then
                    hudShownPercent = math.min(target, hudShownPercent + step)
                else
                    hudShownPercent = math.max(target, hudShownPercent - step)
                end
            end

            if cooldown and cooldown > 0 and (hudShownPercent or 0) >= 1.0 then
                cooldown = nil
            end

            DrawBucketFillHud(hudShownPercent, cooldown)

            local syncMs = math.max(1, conf.HudRefreshSeconds or 15) * 1000
            if (now - lastSync) > syncMs then
                lastSync = now
                TriggerServerEvent('gsc_kassippu:server:requestBucketSync', hudTreeUid)
            end

            Wait(0)
        else
            lastSync = 0
            lastRead = 0
            readPercent, readCooldown = nil, nil -- never show the last tree's reading on the next one
            lastFrame = GetGameTimer()
            hudShownPercent = nil
            Wait(1000) -- no tree being watched
        end
    end
end)
---oo[ One Skill Check ]oo---
local function SkillCheck(conf, title, legacyStartText)
    if Config.TreeMinigameProvider == "legacy" then
        if legacyStartText then GSC.Notify.Show(legacyStartText, 3000) end

        local ok, result = pcall(function()
            return exports['syn_minigame']:taskBar(conf.Duration or 4500, conf.Size or 7)
        end)
        if not ok then Shared.Debug("^1[Harvest]^7 syn_minigame errored: " .. tostring(result)) end
        return ok and result == 100
    end

    return GSC.Minigame.Play(conf.Game, title) == true
end

---oo[ Search Tree Items Function ]oo---
function Harvest.SearchTree(ped, treeEntity, treeData)
    local coords = GetEntityCoords(treeEntity)
    local treeKey = treeData.uid or string.format("%.2f%.2f%.2f", coords.x, coords.y, coords.z)
    local conf = Config.TreeItemsSearchMinigameConf

    ---o[ Still bare from the last search? ]o---
    local searchedAt = lastSearchAt[treeKey]
    if searchedAt and (GetGameTimer() - searchedAt) < ((Config.TreeClimbConf.TreeGrowingTime or 60) * 1000) then
        GSC.Notify.Show(Config.Text.TreeReGrowingNotify, 3000)
        return
    end

    local searchDict = Config.AnimConf.TreeItemSearchAnimDict
    local searchAnim = Config.AnimConf.TreeItemSearchAnimName
    local searchAnimFlag = Config.AnimConf.TreeItemsSearchAnimFlag
    local crouchAnimDict = Config.AnimConf.TreeCrouchAnimDict
    local crouchAnim = Config.AnimConf.TreeCrouchAnimName
    local crouchAnimFlag = Config.AnimConf.TreeCrouchAnimFlag

    ---o[ The skill check: part the fronds ]o---
    if not SkillCheck(conf, Config.Text.TreeSearchGameTitle, Config.Text.TreeItemsSearchStartNotify) then
        GSC.Notify.Show(Config.Text.TreeItemsSearchFailNotify, 3000)
        return
    end

    ---o[ Settle back into the crouch, then rummage ]o---
    GSC.Notify.Show(Config.Text.TreeItemsSearchSuccessNotify, 2000)

    RequestAnimDict(crouchAnimDict)
    local timeout = 0
    while not HasAnimDictLoaded(crouchAnimDict) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if HasAnimDictLoaded(crouchAnimDict) then
        TaskPlayAnim(ped, crouchAnimDict, crouchAnim, 8.0, -8.0, -1, crouchAnimFlag, 0, false, false, false)
    end
    Wait(600)

    local searchMs = math.floor(math.max(0, conf.SearchAnimSeconds or 4) * 1000)

    RequestAnimDict(searchDict)
    timeout = 0
    while not HasAnimDictLoaded(searchDict) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if HasAnimDictLoaded(searchDict) then
        TaskPlayAnim(ped, searchDict, searchAnim, 8.0, -8.0, searchMs, searchAnimFlag, 0, false, false, false)
    else
        Shared.Debug("^1[Search]^7 Search anim dict failed to load: " .. tostring(searchDict))
    end

    Wait(searchMs)

    TriggerServerEvent("nx_trees:giveTreeReward", treeKey)

    if HasAnimDictLoaded(crouchAnimDict) then
        TaskPlayAnim(ped, crouchAnimDict, crouchAnim, 8.0, -8.0, -1, crouchAnimFlag, 0, false, false, false)
    end
end

---oo[ Loot Card ]oo---
RegisterNetEvent('gsc_kassippu:client:treeReward')
AddEventHandler('gsc_kassippu:client:treeReward', function(item, amount, label, treeKey)
    local conf = Config.TreeItemsSearchMinigameConf
    local items = {}

    if treeKey and item then lastSearchAt[treeKey] = GetGameTimer() end

    if item then
        items[1] = { item = item, label = label or item, amount = amount or 1 }
        PlaySoundFrontend("Core_Fill_Up", "Consumption_Sounds", true, 0)
    else
        items[1] = { label = Config.Text.TreeLootCardEmpty }
    end

    SendNUIMessage({
        action = "treeLoot",
        title = Config.Text.TreeLootCardTitle,
        items = items,
        empty = item == nil,
        duration = math.floor(math.max(1, conf.LootCardSeconds or 4) * 1000),
    })
end)

---oo[ Collect Coconut Water Minigame ]oo---
function Harvest.CollectCoconutWater(ped, treeEntity, treeData)
    local _, cooldown = GetBucketReading(treeData.uid)
    if cooldown and cooldown > 0 then
        GSC.Notify.Show(Config.Text.TreeReGrowingNotify, 3000)
        return
    end

    ---o[ The skill check: tip the bucket without spilling it ]o---
    if not SkillCheck(Config.CoconutCollectMinigameConf, Config.Text.CoconutGameTitle,
            Config.Text.CoconutCollectMinigameStartNotify) then
        GSC.Notify.Show(Config.Text.CoconutCollectFailNotify, 3000)
        return
    end

    TriggerServerEvent('gsc_kassippu:server:collectCoconutWater', treeData.uid)

    local anim = Config.AnimConf
    local durationMs = math.floor(math.max(0, Config.CoconutBucketConf.CollectAnimSeconds or 3) * 1000)
    if durationMs <= 0 then return end

    local dict = anim.CoconutCollectAnimDict
    RequestAnimDict(dict)

    local timeout = 0
    while not HasAnimDictLoaded(dict) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, anim.CoconutCollectAnimName, 8.0, -8.0, durationMs,
            anim.CoconutCollectAnimFlag or 31, 0, false, false, false)
    else
        Shared.Debug("^1[Coconut]^7 Collect anim dict failed to load: " .. tostring(dict))
    end

    Wait(durationMs) -- hold here so the bar is seen emptying before control returns
end

---oo[ Which Tree Is The Player Sitting On? ]oo---
function Harvest.WatchTree(uid)
    hudTreeUid = uid

    if uid then
        bucketState[uid] = nil -- show "checking..." until the first answer
    else
        hudShownPercent = nil
    end
end
