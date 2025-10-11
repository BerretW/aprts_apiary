Apiaries = {}
Hives = {}
Queens = {}
Bees = {}
nearestApiary = nil
local Prompt = nil
local promptGroup = GetRandomIntInRange(0, 0xffffff)
Progressbar = exports["feather-progressbar"]:initiate()
playingAnimation = false
function debugPrint(msg)
    if Config.Debug == true then
        print("^1[VČELÍN]^0 " .. msg)
    end
end

function notify(text)
    TriggerEvent('notifications:notify', "VČELÍN", text, 3000)
end

function table.count(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function round(num)
    return math.floor(num * 100 + 0.5) / 100
end

-- Config.Jobs = {
--     {job = 'police', grade = 1},
--     {job = 'doctor', grade = 3}
-- }
function hasJob(jobtable)
    local pjob = LocalPlayer.state.Character.Job
    local pGrade = LocalPlayer.state.Character.Grade
    local pLabel = LocalPlayer.state.Character.Label
    for _, v in pairs(jobtable) do
        if v.job == pjob and v.grade <= pGrade and (v.label == "" or v.label == nil or v.label == pLabel) then
            return true
        end
    end
    return false
end
-- SetResourceKvp("aprts_vzor:deht", 0)
-- local deht = GetResourceKvpString("aprts_vzor:deht")

local function prompt()
    Citizen.CreateThread(function()
        local str = "Správa úlu"
        local wait = 0
        Prompt = Citizen.InvokeNative(0x04F97DE45A519419)
        PromptSetControlAction(Prompt, 0x760A9C6F)
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(Prompt, str)
        PromptSetEnabled(Prompt, true)
        PromptSetVisible(Prompt, true)
        PromptSetHoldMode(Prompt, true)
        PromptSetGroup(Prompt, promptGroup)
        PromptRegisterEnd(Prompt)
    end)
end
function playAnim(entity, dict, name, flag, time)
    playingAnimation = true
    RequestAnimDict(dict)
    local waitSkip = 0
    while not HasAnimDictLoaded(dict) do
        waitSkip = waitSkip + 1
        if waitSkip > 100 then
            break
        end
        Citizen.Wait(0)
    end
    
    Progressbar.start("Něco dělám", time, function()
    end, 'linear', 'rgba(255, 255, 255, 0.8)', '20vw', 'rgba(255, 255, 255, 0.1)', 'rgba(211, 11, 21, 0.5)')


    TaskPlayAnim(entity, dict, name, 1.0, 1.0, time, flag, 0, true, 0, false, 0, false)
    Wait(time)
    playingAnimation = false
end

function equipProp(model, bone, coords)
    local ped = PlayerPedId()
    local playerPos = GetEntityCoords(ped)
    local mainProp = CreateObject(model, playerPos.x, playerPos.y, playerPos.z + 0.2, true, true, true)
    local boneIndex = GetEntityBoneIndexByName(ped, bone)
    AttachEntityToEntity(mainProp, ped, boneIndex, coords.x, coords.y, coords.z, coords.xr, coords.yr, coords.zr, true,
        true, false, true, 1, true)
    return mainProp
end


function CreateBlip(coords, sprite, name)
    -- print("Creating Blip: ")
    -- hash sprite if is string
    if type(sprite) == "string" then
        sprite = GetHashKey(sprite)
    end
    local blip = BlipAddForCoords(1664425300, coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite, 1)
    SetBlipScale(blip, 0.2)
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, name)
    return blip
end

function SetBlipStyle(blip, styleHash)
    -- hash if stylehash is string
    if type(styleHash) == "string" then
        styleHash = GetHashKey(styleHash)
    end
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, styleHash)
end

function isActive()
    local currentHour = GetClockHours()
    if currentHour >= Config.ActiveTimeStart or currentHour < Config.ActiveTimeEnd then
        return true
    end
    return false
end

function isGreenTime()
    local year, month, day, hour, minute, second = GetPosixTime()
    hour = tonumber(hour) + tonumber(Config.DST) -- Přidáme DST, pokud je potřeba
    if hour > 23 then
        hour = hour - 24 -- Oprava, pokud hodina přesáhne 23
    end
    if hour >= Config.GreenTimeStart and hour < Config.GreenTimeEnd then
        return true
    end
    return false
end

CreateThread(function()
    while true do
        local pause = 1000
        if menuOpen == true or PlayingAnimation == true then
            DisableActions(PlayerPedId())
            DisableBodyActions(PlayerPedId())
            pause = 0
        end
        Citizen.Wait(pause)
    end
end)

function DisableBodyActions(ped)
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0x27D1C284, true) -- loot
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0x399C6619, true) -- loot
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0x41AC83D1, true) -- loot
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0xBE8593AF, true) -- INPUT_PICKUP_CARRIABLE2
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0xEB2AC491, true) -- INPUT_PICKUP_CARRIABLE
end
function DisableActions(ped)
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0xA987235F, true) -- LookLeftRight
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0xD2047988, true) -- LookUpDown
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0x39CCABD5, true) -- VehicleMouseControlOverride

    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0x4D8FB4C1, true) -- disable left/right
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0xFDA83190, true) -- disable forward/back
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0xDB096B85, true) -- INPUT_DUCK
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0x8FFC75D6, true) -- disable sprint

    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0x9DF54706, true) -- veh turn left
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0x97A8FD98, true) -- veh turn right
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0x5B9FD4E2, true) -- veh forward
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0x6E1F639B, true) -- veh backwards
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0xFEFAB9B4, true) -- disable exit vehicle

    Citizen.InvokeNative(0x2970929FD5F9FC89, ped, true) -- Disable weapon firing
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0x07CE1E61, true) -- disable attack
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0xF84FA74F, true) -- disable aim
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0xAC4BD4F1, true) -- disable weapon select
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0x73846677, true) -- disable weapon
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0x0AF99998, true) -- disable weapon
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0xB2F377E8, true) -- disable melee
    Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, 0xADEAF48C, true) -- disable melee
end

Citizen.CreateThread(function()
    prompt()
    while true do
        local pause = 1000
        local playerPed = PlayerPedId()
        -- local name = CreateVarString(10, 'LITERAL_STRING', "Prompt")
        -- PromptSetActiveGroupThisFrame(promptGroup, name)
        -- if PromptHasHoldModeCompleted(Prompt) then

        -- end

        for _, apiary in pairs(Apiaries) do
            local dist = #(GetEntityCoords(playerPed) - apiary.coords)
            if dist < 50.0 then
                pause = 0
                DrawMarker(2, apiary.coords.x, apiary.coords.y, apiary.coords.z + 1)
            end
        end
        Citizen.Wait(pause)
    end
end)
-- 
