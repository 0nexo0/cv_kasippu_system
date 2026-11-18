local Camera = GSC.module('TreeCamera')

local treeCam = nil
local climbCamTree = nil                          -- the tree the climb camera is framing
local HasPointCamAtCoord = PointCamAtCoord ~= nil -- looked up once, not per frame

local fpCam = nil
local fpYaw, fpPitch = 0.0, 0.0
local fpActive = false

---oo[ First Person At The Top ]oo---

local function StopFirstPersonView(blendOut)
    fpActive = false

    local cam = fpCam
    fpCam = nil

    if not cam or not DoesCamExist(cam) then return end

    local blend = Config.StartClimbTreeCamConf.BlendMs or 800

    if blendOut ~= false then
        RenderScriptCams(false, true, blend, true, true)
    end

    SetTimeout(blend + 100, function()
        if DoesCamExist(cam) then DestroyCam(cam, false) end
    end)
end

local function StartFirstPersonView(ped)
    if fpCam and DoesCamExist(fpCam) then return true end

    local conf = Config.TreeClimbConf
    local eye = conf.FirstPersonEyeOffset or vector3(0.0, 0.22, 0.60)

    fpYaw = GetEntityHeading(ped)
    fpPitch = 0.0

    local pos = GetOffsetFromEntityInWorldCoords(ped, eye.x, eye.y, eye.z)

    fpCam = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA",
        pos.x, pos.y, pos.z,
        0.0, 0.0, fpYaw,
        conf.FirstPersonFov or 55.0, false, 0)

    if not fpCam or not DoesCamExist(fpCam) then
        fpCam = nil
        return false
    end

    SetCamActive(fpCam, true)
    RenderScriptCams(true, true, Config.StartClimbTreeCamConf.BlendMs or 800, true, true)
    fpActive = true

    ---o[ Free look ]o---
    CreateThread(function()
        local sensitivity = conf.FirstPersonSensitivity or 8.0
        local pitchLimit = conf.FirstPersonPitchLimit or 80.0

        while fpActive and fpCam and DoesCamExist(fpCam) do
            Wait(0)

            local pedNow = PlayerPedId()
            if not DoesEntityExist(pedNow) then break end

            local lookLR = GetControlNormal(0, 0xA987235F) -- INPUT_LOOK_LR
            local lookUD = GetControlNormal(0, 0xD2047988) -- INPUT_LOOK_UD

            if lookLR == 0.0 then lookLR = GetDisabledControlNormal(0, 0xA987235F) end
            if lookUD == 0.0 then lookUD = GetDisabledControlNormal(0, 0xD2047988) end

            fpYaw = (fpYaw - (lookLR * sensitivity)) % 360.0
            fpPitch = math.max(-pitchLimit, math.min(pitchLimit, fpPitch - (lookUD * sensitivity)))

            local eyePos = GetOffsetFromEntityInWorldCoords(pedNow, eye.x, eye.y, eye.z)

            SetCamCoord(fpCam, eyePos.x, eyePos.y, eyePos.z)
            SetCamRot(fpCam, fpPitch, 0.0, fpYaw, 2)
        end
    end)

    return true
end

function Camera.SetTopView(firstPerson, ped, blendOut)
    if not Config.TreeClimbConf.FirstPersonAtTop then
        if not firstPerson then StopFirstPersonView(blendOut) end
        return false
    end

    if firstPerson then
        return StartFirstPersonView(ped or PlayerPedId())
    end

    StopFirstPersonView(blendOut)

    return false
end
---oo[ Update The Climb Camera ]oo---
function Camera.UpdateHeight(attachZ)
    if not treeCam or not DoesCamExist(treeCam) then return end

    local tree = climbCamTree
    if not tree or not DoesEntityExist(tree) then return end

    local camConf = Config.UpdateCamHeightConf
    local side, forward = GSC.Climb.TrunkOffset()

    local target = GetOffsetFromEntityInWorldCoords(tree, side, forward, attachZ or 0.0)

    local camPos = GetOffsetFromEntityInWorldCoords(tree,
        side + (camConf.SideOffset or 1.1),
        forward + (camConf.Distance or 3.2),
        (attachZ or 0.0) + (camConf.HieghtOffSet or 0.7))

    SetCamCoord(treeCam, camPos.x, camPos.y, camPos.z)

    if HasPointCamAtCoord then
        PointCamAtCoord(treeCam, target.x, target.y, target.z + (camConf.LookAtRaise or 0.45))
    else
        PointCamAtEntity(treeCam, PlayerPedId(), 0.0, 0.0, 0.5, true)
    end
end

---oo[ Climb Start Camera Position ]oo---
function Camera.StartClimb(treeEntity, heightSteps)
    local conf = Config.StartClimbTreeCamConf
    climbCamTree = treeEntity

    if not treeCam or not DoesCamExist(treeCam) then
        treeCam = CreateCamWithParams(conf.CameraType, 0.0, 0.0, 0.0,
            conf.RotX or 0.0, conf.RotY or 0.0, 0.0,
            conf.FOV or 60.0, false, 0)
    end

    Camera.UpdateHeight(GSC.Climb.AttachZForHeight(heightSteps or 0))

    SetCamActive(treeCam, true)
    RenderScriptCams(true, true, conf.BlendMs or 800, true, true)
end
---oo[ Destroy Camera After ClimbUp ]oo---
function Camera.StopClimb(blendOut)
    local cam = treeCam
    climbCamTree = nil
    treeCam = nil

    if not cam or not DoesCamExist(cam) then return end

    local blend = Config.StartClimbTreeCamConf.BlendMs or 800

    if blendOut ~= false then
        RenderScriptCams(false, true, blend, true, true)
    end

    SetTimeout(blend + 100, function()
        if DoesCamExist(cam) then DestroyCam(cam, false) end
    end)
end

---oo[ Is the first person camera up? ]oo---
function Camera.IsFirstPerson()
    return fpActive
end

---oo[ Cleanup On Resource Stop ]oo---
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    Camera.SetTopView(false)
    Camera.StopClimb()
    RenderScriptCams(false, false, 0, true, true)
end)
