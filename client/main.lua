ApiariesClient = {}
local Prompts = {}
local PromptGroup = GetRandomIntInRange(0, 0xffffff)
local ExtractorPromptGroup = GetRandomIntInRange(0, 0xffffff) 

-----------------------------------------------------------------------
-- INICIALIZACE PROMPTŮ
-----------------------------------------------------------------------
CreateThread(function()
    -- 1. Hlavní prompt pro interakci s úlem (otevře NUI)
    local strManage = "Spravovat Včelín"
    Prompts.Manage = PromptRegisterBegin()
    PromptSetControlAction(Prompts.Manage, 0x760A9C6F) -- Klávesa G
    PromptSetText(Prompts.Manage, CreateVarString(10, "LITERAL_STRING", strManage))
    PromptSetHoldMode(Prompts.Manage, true)
    PromptSetEnabled(Prompts.Manage, true)
    PromptSetVisible(Prompts.Manage, true)
    PromptSetGroup(Prompts.Manage, PromptGroup)
    PromptRegisterEnd(Prompts.Manage)

    -- 2. Prompt pro Medomet (fyzická lokace)
    local strProcess = "Stáčet Med"
    Prompts.Process = PromptRegisterBegin()
    PromptSetControlAction(Prompts.Process, 0x760A9C6F) -- Klávesa G
    PromptSetText(Prompts.Process, CreateVarString(10, "LITERAL_STRING", strProcess))
    PromptSetHoldMode(Prompts.Process, true)
    PromptSetEnabled(Prompts.Process, true)
    PromptSetVisible(Prompts.Process, true)
    PromptSetGroup(Prompts.Process, ExtractorPromptGroup)
    PromptRegisterEnd(Prompts.Process)
end)

-----------------------------------------------------------------------
-- MANAGEMENT OBJEKTŮ (PROPS)
-----------------------------------------------------------------------

-- Event: Založení/Načtení propu úlu
RegisterNetEvent("bees:apiaryCreated", function(id, coords, type, hiveCount)
    -- Pokud už o včelínu víme, jen aktualizujeme data (např. počet úlů, i když vizuálně je to 1 model)
    if ApiariesClient[id] then
        ApiariesClient[id].hiveCount = hiveCount or 1
        return 
    end

    ApiariesClient[id] = { 
        coords = coords, 
        type = type, 
        hiveCount = hiveCount or 1 
    }

    -- Načtení modelu (zde používáme ten, který jsi zmiňoval)
    local modelHash = GetHashKey("aprts_prop_014") 
    -- Případně switch pro medium typ:
    if type == "medium" then 
        modelHash = GetHashKey("aprts_prop_014") 
    end

    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do Wait(10) end

    -- Vytvoření objektu
    local obj = CreateObject(modelHash, coords.x, coords.y, coords.z, false, true, false)
    SetEntityAsMissionEntity(obj, true, true)
    FreezeEntityPosition(obj, true)
    PlaceObjectOnGroundProperly(obj)

    ApiariesClient[id].entity = obj
end)

-- Cleanup při vypnutí resourcu
AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    for id, data in pairs(ApiariesClient) do
        if DoesEntityExist(data.entity) then DeleteObject(data.entity) end
    end
end)

-- Vyžádání dat při startu (pokud se resourcu restartuje za běhu)
AddEventHandler("onClientResourceStart", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    TriggerServerEvent("bees:getData")
end)

-----------------------------------------------------------------------
-- EFEKTY A ANIMACE
-----------------------------------------------------------------------

-- Hráč dostal žihadlo
RegisterNetEvent("bees:clientStung", function()
    local ped = PlayerPedId()
    
    -- Zvukový efekt
    PlaySoundFrontend("Core_Fill_Up", "Consumption_Sounds", true, 0)
    
    -- Vizuální efekt (krátké rozmazání/flash)
    AnimpostfxPlay("CamPusher01", 800, false)
    
    -- Animace vrávorání
    local animDict = "mech_loco_m@generic@reaction@stumble@unarmed@dwd"
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(10) end
    TaskPlayAnim(ped, animDict, "stumble_backward_s_v1", 8.0, -8.0, 1000, 31, 0, true, 0, false, 0, false)
    
    -- Udělení poškození
    ApplyDamageToPed(ped, 10, false)
end)

-- Animace použití kouřáku
RegisterNetEvent("bees:useSmokerClient", function()
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    
    -- Najdeme nejbližší úl
    local closestId = nil
    local minDist = 3.0
    for id, data in pairs(ApiariesClient) do
        local dist = #(pCoords - data.coords)
        if dist < minDist then
            minDist = dist
            closestId = id
        end
    end

    if closestId then
        -- Animace foukání kouře
        TaskStartScenarioInPlace(ped, "WORLD_HUMAN_SMOKE_INTERACTION", 6000, true, false, false, false)
        Wait(6000)
        ClearPedTasks(ped)
        
        -- Odeslání na server (aplikuje se na celý včelín)
        TriggerServerEvent("bees:applySmoker", closestId, 1)
    else
        TriggerEvent("vorp:NotifyLeft", "Kouřák", "Nejsi u úlu.", "generic_textures", "cross", 3000)
    end
end)

-----------------------------------------------------------------------
-- HLAVNÍ SMYČKA (INTERAKCE)
-----------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)

        -- 1. INTERAKCE S ÚLY (Otevření NUI)
        for id, data in pairs(ApiariesClient) do
            local dist = #(playerCoords - data.coords)

            if dist < 2.0 then
                sleep = 5
                
                -- Nastavení skupiny promptů
                local label = CreateVarString(10, "LITERAL_STRING", "Včelín")
                PromptSetActiveGroupThisFrame(PromptGroup, label)

                -- Pokud hráč podrží G
                if PromptHasHoldModeCompleted(Prompts.Manage) then
                    -- Pošleme žádost serveru o data pro NUI menu.
                    -- Server odpoví eventem 'bees:openApiaryMenu' (viz client/nui.lua)
                    TriggerServerEvent("bees:requestMenuData", id)
                    Wait(500) -- Debounce
                end
            end
        end

        -- 2. INTERAKCE S MEDOMETEM (Fyzická lokace)
        if Config.ExtractorLocations then
            for _, exCoords in ipairs(Config.ExtractorLocations) do
                local dist = #(playerCoords - exCoords)
                if dist < 2.0 then
                    sleep = 5
                    
                    local label = CreateVarString(10, "LITERAL_STRING", "Zpracování")
                    PromptSetActiveGroupThisFrame(ExtractorPromptGroup, label)

                    if PromptHasHoldModeCompleted(Prompts.Process) then
                        -- Animace práce (zalévání/točení klikou)
                        TaskStartScenarioInPlace(playerPed, "WORLD_HUMAN_GARDENER_WATER_PLANT_CAN", 5000, true, false, false, false)
                        Wait(5000)
                        ClearPedTasks(playerPed)
                        
                        -- Server zpracuje itemy
                        TriggerServerEvent("bees:processFrames")
                        Wait(500)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

RegisterNetEvent("bees:openMicroscopeClient", function(genes)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openMicroscope",
        genetics = genes
    })
end)

RegisterNUICallback("closeMicroscope", function(data, cb)
    SetNuiFocus(false, false)
    cb("ok")
end)