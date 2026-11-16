local Notify = GSC.module('Notify')

---oo[ The Script's Own Notifications ]oo---
-- Send one note to one player; their GSC.Notify.Show draws it.
-- Same cost as VORP's own NotifyRightTip: one client event per note.
-- kind: "info" (default) | "warning" | "alert" (alert may carry a title)
--
-- Every style (the script's notes, VORP advanced, VORP tip) is drawn by the client, so its
-- notify manager can join notes that land together and replace the one still on screen:
-- a note never waits behind an older one (see features/common/client/notify.lua).

function Notify.Send(src, text, ms, kind, title)
    src = tonumber(src)
    if not src or src <= 0 or text == nil then return end

    TriggerClientEvent('gsc_kassippu:client:notify', src, text, ms, kind, title)
end

---o[ A placement note (setting down a still, crate or station): VORP NotifyObjective on their screen ]o---
function Notify.SendObjective(src, text, ms)
    src = tonumber(src)
    if not src or src <= 0 or text == nil then return end

    TriggerClientEvent('gsc_kassippu:client:notifyObjective', src, text, ms)
end
