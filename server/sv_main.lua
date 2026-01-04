-- Global variables (přístupné ve všech souborech)
VORP_INV = exports.vorp_inventory
VorpCore = {}
Apiaries = {}

-- Načtení VORP Core
TriggerEvent("getCore", function(core)
    VorpCore = core
end)

-----------------------------------------------------------------------
-- SQL FUNCTIONS (Globální, aby je mohly volat eventy)
-----------------------------------------------------------------------

function SaveApiaryToDB(apiaryId, unload)
    local apiary = Apiaries[apiaryId]
    if not apiary then return end

    local hivesData = json.encode(apiary.hives)

    MySQL.update('UPDATE aprts_apiaries SET hives_data = ? WHERE id = ?', {hivesData, apiaryId}, function(affectedRows)
        if unload then
            Apiaries[apiaryId] = nil
        end
    end)
end

function LoadApiariesFromDB()
    MySQL.query('SELECT * FROM aprts_apiaries', {}, function(result)
        if result then
            local count = 0
            for _, row in ipairs(result) do
                local hives = json.decode(row.hives_data) or {}

                for hiveId, hive in pairs(hives) do
                    if not hive.inventoryId then
                        hive.inventoryId = Config.InventoryPrefix .. "GEN_" .. row.id .. "_" .. hiveId
                    end
                    -- Validace logů při načtení
                    if not hive.logs then hive.logs = {} end
                    
                    local invName = "Úl " .. row.id .. " - #" .. hiveId
                    -- Voláme funkci z sv_functions.lua (musí být načtena)
                    if RegisterHiveInventory then 
                        RegisterHiveInventory(hive.inventoryId, invName)
                    end
                end

                Apiaries[row.id] = {
                    id = row.id,
                    ownerIdentifier = row.owner_identifier,
                    charIdentifier = row.char_identifier,
                    coords = DeserializeCoords(row.coords),
                    hives = hives
                }
                count = count + 1
            end
            print("[Aprts Apiary] Načteno " .. count .. " včelínů.")
        end
    end)
end

-----------------------------------------------------------------------
-- MAIN LOOP & INIT
-----------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(Config.UpdateInterval)
        for apiaryId, apiary in pairs(Apiaries) do
            local env = CalculateEnvironment(apiary.coords)
            for _, hive in pairs(apiary.hives) do
                ProcessHiveLogic(hive, env, apiaryId)
            end
        end
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    -- Malé zpoždění, aby se stihly načíst funkce z sv_functions
    Wait(500) 
    LoadApiariesFromDB()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    for id, _ in pairs(Apiaries) do
        SaveApiaryToDB(id, true)
    end
end)