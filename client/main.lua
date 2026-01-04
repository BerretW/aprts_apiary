ApiariesClient = {}
local Prompts = {}
local PromptGroup = GetRandomIntInRange(0, 0xffffff)
-- Oddělená grupa pro Medomet, aby se nemíchaly texty, pokud by byly blízko sebe
local ExtractorPromptGroup = GetRandomIntInRange(0, 0xffffff) 

CreateThread(function()
    -- 1. Prompty pro ÚL
    local strOpen = "Otevřít úl"
    local strInsert = "Vložit Královnu"
    local strHarvest = "Vyměnit rámek" -- Přejmenováno pro jasnost
    local strCure = "Podat lék"

    Prompts.Open = PromptRegisterBegin()
    PromptSetControlAction(Prompts.Open, 0x760A9C6F) -- G
    PromptSetText(Prompts.Open, CreateVarString(10, "LITERAL_STRING", strOpen))
    PromptSetHoldMode(Prompts.Open, true)
    PromptSetEnabled(Prompts.Open, true)
    PromptSetVisible(Prompts.Open, true)
    PromptSetGroup(Prompts.Open, PromptGroup)
    PromptRegisterEnd(Prompts.Open)

    Prompts.Insert = PromptRegisterBegin()
    PromptSetControlAction(Prompts.Insert, 0xC7B5340A) -- ENTER
    PromptSetText(Prompts.Insert, CreateVarString(10, "LITERAL_STRING", strInsert))
    PromptSetHoldMode(Prompts.Insert, true)
    PromptSetEnabled(Prompts.Insert, true)
    PromptSetVisible(Prompts.Insert, true)
    PromptSetGroup(Prompts.Insert, PromptGroup)
    PromptRegisterEnd(Prompts.Insert)

    Prompts.Harvest = PromptRegisterBegin()
    PromptSetControlAction(Prompts.Harvest, 0xE8342FF2) -- ALT
    PromptSetText(Prompts.Harvest, CreateVarString(10, "LITERAL_STRING", strHarvest))
    PromptSetHoldMode(Prompts.Harvest, true)
    PromptSetEnabled(Prompts.Harvest, true)
    PromptSetVisible(Prompts.Harvest, true)
    PromptSetGroup(Prompts.Harvest, PromptGroup)
    PromptRegisterEnd(Prompts.Harvest)

    Prompts.Cure = PromptRegisterBegin()
    PromptSetControlAction(Prompts.Cure, 0xE30CD707) -- R
    PromptSetText(Prompts.Cure, CreateVarString(10, "LITERAL_STRING", strCure))
    PromptSetHoldMode(Prompts.Cure, true)
    PromptSetEnabled(Prompts.Cure, true)
    PromptSetVisible(Prompts.Cure, true)
    PromptSetGroup(Prompts.Cure, PromptGroup)
    PromptRegisterEnd(Prompts.Cure)

    -- 2. Prompt pro MEDOMET
    local strProcess = "Stáčet Med"
    Prompts.Process = PromptRegisterBegin()
    PromptSetControlAction(Prompts.Process, 0x760A9C6F) -- G
    PromptSetText(Prompts.Process, CreateVarString(10, "LITERAL_STRING", strProcess))
    PromptSetHoldMode(Prompts.Process, true)
    PromptSetEnabled(Prompts.Process, true)
    PromptSetVisible(Prompts.Process, true)
    PromptSetGroup(Prompts.Process, ExtractorPromptGroup)
    PromptRegisterEnd(Prompts.Process)
end)

-- Event: Založení propu úlu
RegisterNetEvent("bees:apiaryCreated", function(id, coords, type)
    if ApiariesClient[id] then return end

    ApiariesClient[id] = { coords = coords, type = type }

    local modelHash = GetHashKey("aprts_prop_014")
    if type == "medium" then modelHash = GetHashKey("aprts_prop_014") end

    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do Wait(10) end

    local obj = CreateObject(modelHash, coords.x, coords.y, coords.z, false, true, false)
    SetEntityAsMissionEntity(obj, true, true)
    FreezeEntityPosition(obj, true)
    PlaceObjectOnGroundProperly(obj)

    ApiariesClient[id].entity = obj
end)

-- Event: Hráč dostal žihadlo
RegisterNetEvent("bees:clientStung", function()
    local ped = PlayerPedId()
    
    -- Zvuk
    PlaySoundFrontend("Core_Fill_Up", "Consumption_Sounds", true, 0)
    
    -- Efekt obrazovky (Flash)
    AnimpostfxPlay("CamPusher01", 800, false)
    
    -- Animace
    local animDict = "mech_loco_m@generic@reaction@stumble@unarmed@dwd"
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(10) end
    TaskPlayAnim(ped, animDict, "stumble_backward_s_v1", 8.0, -8.0, 1000, 31, 0, true, 0, false, 0, false)
    
    -- Damage
    ApplyDamageToPed(ped, 10, false)
end)

-- Event: Použití kouřáku (animace)
RegisterNetEvent("bees:useSmokerClient", function()
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    
    -- Najít nejbližší úl
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
        TaskStartScenarioInPlace(ped, "WORLD_HUMAN_SMOKE_INTERACTION", 6000, true, false, false, false)
        Wait(6000)
        ClearPedTasks(ped)
        TriggerServerEvent("bees:applySmoker", closestId, 1)
    else
        TriggerEvent("vorp:NotifyLeft", "Kouřák", "Nejsi u úlu.", "generic_textures", "cross", 3000)
    end
end)

AddEventHandler("onClientResourceStart", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    TriggerServerEvent("bees:getData")
end)

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    for id, data in pairs(ApiariesClient) do
        if DoesEntityExist(data.entity) then DeleteObject(data.entity) end
    end
end)

-- Hlavní smyčka
CreateThread(function()
    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)

        -- 1. INTERAKCE S ÚLY
        for id, data in pairs(ApiariesClient) do
            local dist = #(playerCoords - data.coords)

            if dist < 2.0 then
                sleep = 5
                local label = CreateVarString(10, "LITERAL_STRING", "Včelín")
                PromptSetActiveGroupThisFrame(PromptGroup, label)

                if PromptHasHoldModeCompleted(Prompts.Open) then
                    TriggerServerEvent("bees:openHive", id, 1)
                    Wait(500)
                end

                if PromptHasHoldModeCompleted(Prompts.Insert) then
                    local inventory = exports.vorp_inventory:getInventoryItems()
                    local QueenItem = false
                    for _, item in pairs(inventory) do
                        if item.name == Config.Items.Queen and item.count > 0 then
                            QueenItem = item
                            break
                        end
                    end
                    if QueenItem then
                        TriggerServerEvent("bees:insertQueen", id, 1, QueenItem)
                    else
                        TriggerEvent("vorp:NotifyLeft", "Včelařství", "Nemáš královnu.", "generic_textures", "cross", 3000)
                    end
                    Wait(500)
                end

                if PromptHasHoldModeCompleted(Prompts.Harvest) then
                    TriggerServerEvent("bees:harvestFrame", id, 1)
                    Wait(500)
                end

                if PromptHasHoldModeCompleted(Prompts.Cure) then
                    TriggerServerEvent("bees:applyMedicine", id, 1)
                    Wait(500)
                end
            end
        end

        -- 2. INTERAKCE S MEDOMETEM
        if Config.ExtractorLocations then
            for _, exCoords in ipairs(Config.ExtractorLocations) do
                local dist = #(playerCoords - exCoords)
                if dist < 2.0 then
                    sleep = 5
                    local label = CreateVarString(10, "LITERAL_STRING", "Zpracování")
                    PromptSetActiveGroupThisFrame(ExtractorPromptGroup, label)

                    if PromptHasHoldModeCompleted(Prompts.Process) then
                        -- Animace zpracování
                        TaskStartScenarioInPlace(playerPed, "WORLD_HUMAN_GARDENER_WATER_PLANT_CAN", 5000, true, false, false, false)
                        Wait(5000)
                        ClearPedTasks(playerPed)
                        TriggerServerEvent("bees:processFrames")
                        Wait(500)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- NOTIFIKACE STATISTIK
RegisterNetEvent("bees:showHiveStats", function(data)
    local dLabel = "Ne"
    if data.disease then dLabel = Config.Diseases[data.disease].label end
    
    local msg = string.format("Pop: %d | HP: %d%% | Nemoc: %s", data.population, data.health, dLabel)
    TriggerEvent("vorp:NotifyLeft", "Stav Úlu", msg, "generic_textures", "tick", 5000)
end)