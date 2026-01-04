local ApiariesClient = {} -- Lokální kopie pro clienta (syncovaná serverem)
local Prompts = {}
local PromptGroup = GetRandomIntInRange(0, 0xffffff)
-- Inicializace promptů
CreateThread(function()
    local str = "Otevřít úl"
    local insertStr = "Vložit Královnu"
    local harvestStr = "Sklidit Med"

    Prompts.Open = PromptRegisterBegin()
    PromptSetControlAction(Prompts.Open, 0x760A9C6F) -- G
    PromptSetText(Prompts.Open, CreateVarString(10, "LITERAL_STRING", str))
    PromptSetHoldMode(Prompts.Open, true)
    PromptSetEnabled(Prompts.Open, true)
    PromptSetVisible(Prompts.Open, true)
    PromptSetGroup(Prompts.Open, PromptGroup)
    PromptRegisterEnd(Prompts.Open)

    Prompts.Insert = PromptRegisterBegin()
    PromptSetControlAction(Prompts.Insert, 0xC7B5340A) -- ENTER (nebo jiná klávesa)
    PromptSetText(Prompts.Insert, CreateVarString(10, "LITERAL_STRING", insertStr))
    PromptSetHoldMode(Prompts.Insert, true)
    PromptSetEnabled(Prompts.Insert, true)
    PromptSetVisible(Prompts.Insert, true)
    PromptSetGroup(Prompts.Insert, PromptGroup)
    PromptRegisterEnd(Prompts.Insert)

    Prompts.Harvest = PromptRegisterBegin()
    PromptSetControlAction(Prompts.Harvest, 0xE8342FF2) -- ALT (příklad)
    PromptSetText(Prompts.Harvest, CreateVarString(10, "LITERAL_STRING", harvestStr))
    PromptSetHoldMode(Prompts.Harvest, true)
    PromptSetEnabled(Prompts.Harvest, true)
    PromptSetVisible(Prompts.Harvest, true)
    PromptSetGroup(Prompts.Harvest, PromptGroup)
    PromptRegisterEnd(Prompts.Harvest)
end)

-- Event pro přijetí dat o včelínech (při připojení nebo vytvoření)
RegisterNetEvent("bees:apiaryCreated", function(id, coords, type)
    ApiariesClient[id] = {
        coords = coords,
        type = type
    }
    -- Zde by se spawnul prop (objekt úlu) pomocí CreateObject...
end)

-- Příklad vykreslení objektu v Client/Main.lua uvnitř eventu
RegisterNetEvent("bees:apiaryCreated", function(id, coords, type)
    if ApiariesClient[id] then
        return
    end -- Už o něm víme

    ApiariesClient[id] = {
        coords = coords,
        type = type
    }

    -- Model podle typu
    local modelHash = GetHashKey("p_beehive01x") -- Příklad modelu
    if type == "medium" then
        modelHash = GetHashKey("p_beehive02x")
    end

    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(10)
    end

    -- Korekce Z souřadnice, aby úl nelevitoval (nebo použij PlaceObjectOnGroundProperly)
    local obj = CreateObject(modelHash, coords.x, coords.y, coords.z, false, true, false)
    SetEntityAsMissionEntity(obj, true, true)
    FreezeEntityPosition(obj, true)
    PlaceObjectOnGroundProperly(obj)

    ApiariesClient[id].entity = obj
end)

AddEventHandler("onClientResourceStart", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    TriggerServerEvent("bees:getData")
end)

-- Cleanup při vypnutí resourcu (aby nezůstaly propy ve světě)
AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end
    for id, data in pairs(ApiariesClient) do
        if DoesEntityExist(data.entity) then
            DeleteObject(data.entity)
        end
    end
end)

-- Hlavní smyčka pro interakci
CreateThread(function()
    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)

        for id, data in pairs(ApiariesClient) do
            local dist = #(playerCoords - data.coords)

            if dist < 2.0 then
                sleep = 5

                -- Zobrazení 3D textu nad úlem (stav)
                -- DrawText3D(data.coords.x, data.coords.y, data.coords.z + 1.0, "Včelín #"..id)

                local label = CreateVarString(10, "LITERAL_STRING", "Úl")
                PromptSetActiveGroupThisFrame(PromptGroup, label)

                -- Logika stisku kláves
                if PromptHasHoldModeCompleted(Prompts.Open) then
                    -- Předpokládáme 1 úl na včelín pro jednoduchost v tomto client loopu, 
                    -- jinak by se muselo raycastovat na konkrétní entitu.
                    print(json.encode(data, {
                        indent = true
                    })) -- Debug výpis
                    TriggerServerEvent("bees:openHive", id, 1)
                    Wait(500) -- Debounce
                end

                if PromptHasHoldModeCompleted(Prompts.Insert) then -- Vložit královnu
                    local inventory = exports.vorp_inventory:getInventoryItems()
                    local QueenItem = false
                    for _, item in pairs(inventory) do
                        if item.name == Config.Items.Queen and item.count > 0 then
                            print(json.encode(item, {
                                indent = true
                            })) -- Debug výpis
                            QueenItem = item
                            break
                        end
                    end
                    -- print("Hráč se pokouší vložit královnu do úlu. Má královnu: " .. tostring(hasQueen))
                    TriggerServerEvent("bees:insertQueen", id, 1, QueenItem)
                    Wait(500) -- Debounce
                end

                if PromptHasHoldModeCompleted(Prompts.Harvest) then -- Sklidit
                    TriggerServerEvent("bees:harvestFrame", id, 1)
                    Wait(500) -- Debounce
                end
            end
        end
        Wait(sleep)
    end
end)

-- Debug funkce pro NUI (zjednodušená notifikace statistik)
RegisterNetEvent("bees:showHiveStats", function(data)
    local msg =
        string.format("Populace: %d | Zdraví: %d%% | Med: %d", data.population, data.health, data.honey or 0)
    TriggerEvent("vorp:NotifyLeft", "Statistiky Úlu", msg, "generic_textures", "tick", 5000)
end)
