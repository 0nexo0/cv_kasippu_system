local AdminPanel = GSC.module('AdminPanel')

---oo[ Settings panel (the server decides who may open it, and checks every save) ]oo---

local open = false

function AdminPanel.IsOpen()
    return open
end

function AdminPanel.Close()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "cfgClose" })
end

RegisterNetEvent('gsc_kassippu:client:cfgPanelOpen')
AddEventHandler('gsc_kassippu:client:cfgPanelOpen', function(data)
    if type(data) ~= 'table' or type(data.files) ~= 'table' then return end
    if GSC.UiGuard ~= nil and GSC.UiGuard.ResetAll and IsNuiFocused() then GSC.UiGuard.ResetAll() end -- one screen at a time
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "cfgOpen", files = data.files, file = data.file, text = (Config.Text or {}).AdminPanel or {} })
end)

RegisterNetEvent('gsc_kassippu:client:cfgPanelFile')
AddEventHandler('gsc_kassippu:client:cfgPanelFile', function(data)
    if not open or type(data) ~= 'table' then return end
    SendNUIMessage({ action = "cfgFile", data = data })
end)

RegisterNetEvent('gsc_kassippu:client:cfgPanelResult')
AddEventHandler('gsc_kassippu:client:cfgPanelResult', function(result)
    if not open or type(result) ~= 'table' then return end
    SendNUIMessage({ action = "cfgResult", result = result })
end)

RegisterNUICallback('cfgLoadFile', function(data, cb)
    if open and type(data) == 'table' and type(data.file) == 'string' then
        TriggerServerEvent('gsc_kassippu:server:cfgPanelFile', data.file)
    end
    cb('ok')
end)

RegisterNUICallback('cfgSave', function(data, cb)
    if open and type(data) == 'table' and type(data.changes) == 'table' then
        TriggerServerEvent('gsc_kassippu:server:cfgPanelSave', data.file, data.changes)
    end
    cb('ok')
end)

RegisterNUICallback('cfgClose', function(_, cb)
    AdminPanel.Close()
    cb('ok')
end)

---oo[ Saved values reach this game (GlobalState already gave them at start) ]oo---
RegisterNetEvent('gsc_kassippu:client:cfgSync')
AddEventHandler('gsc_kassippu:client:cfgSync', function(map)
    if type(map) ~= 'table' then return end
    GSC.ConfigLive.ApplyAll(map)
end)

CreateThread(function()
    Wait(3000)
    TriggerServerEvent('gsc_kassippu:server:cfgSyncRequest')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if open then SetNuiFocus(false, false) end
end)
