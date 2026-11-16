---o[ Discord webhooks - SERVER ONLY ]o---
-- Paste your Discord webhook URLs here. This file is loaded as a server script only
-- (fxmanifest.lua -> server_scripts), so it is never sent to players, unlike the other
-- config files. Do NOT move it into shared_scripts.
--
-- Main    = every log group goes here unless the group has its own URL below.
-- <group> = optional: send that group to its own channel ("" = use Main).
-- A server.cfg convar (set gsc_kasippu_webhook "..." / gsc_kasippu_webhook_<group> "...")
-- still works and wins over this file, if you prefer to keep URLs there.
-- Turn groups on or off in config/main.lua -> Config.Logs.Events.
--
-- Keep this file out of public git repos: anyone with a webhook URL can post to your channel.
Config.Webhooks = {
    Main      = "", -- e.g. "https://discord.com/api/webhooks/123/abc"

    explosion = "", -- a still blew up
    theft     = "", -- bottles stolen, washes spiked, crate bottles taken
    law       = "", -- stills seized, batches poured out
    lockpick  = "", -- crate locks picked
    admin     = "", -- admin commands, tree changes
    market    = "", -- bottles sold to buyers
}
