local Notify = GSC.module('Notify')

---oo[ The Script's Own Notifications ]oo---

function Notify.Send(src, text, ms, kind, title)
    src = tonumber(src)
    if not src or src <= 0 or text == nil then return end

    TriggerClientEvent('gsc_kassippu:client:notify', src, text, ms, kind, title)
end

---o[ A placement note ]o---
function Notify.SendObjective(src, text, ms)
    src = tonumber(src)
    if not src or src <= 0 or text == nil then return end

    TriggerClientEvent('gsc_kassippu:client:notifyObjective', src, text, ms)
end
