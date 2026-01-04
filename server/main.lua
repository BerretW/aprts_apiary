local VORP_INV = exports.vorp_inventory
local VorpCore = {}

-- Načtení VORP Core
TriggerEvent("getCore", function(core)
    VorpCore = core
end)

-- Datová struktura
Apiaries = {} 

function debugPrint(msg)
    if Config.Debug then
        print("[Aprts Apiary DEBUG] " .. msg)
    end
end

-----------------------------------------------------------------------
-- HELPER FUNCTIONS
-----------------------------------------------------------------------
-- Přidej někam nahoru k helper funkcím
local function ValidateHiveData(hive)
    if not hive.production.emptyFrames then hive.production.emptyFrames = 0 end
    -- Fallback pokud by neseděly počty
    local total = hive.production.filledFrames + hive.production.emptyFrames
    if total > Config.HiveStats[hive.type].slots then
        hive.production.emptyFrames = Config.HiveStats[hive.type].slots - hive.production.filledFrames
    end
end

local function GetApiaryNuiData(apiaryId)
    local apiary = Apiaries[apiaryId]
    if not apiary then return {} end
    
    local nuiData = {}
    for k, v in pairs(apiary.hives) do
        ValidateHiveData(v)
        nuiData[k] = {
            id = v.id,
            hasQueen = v.hasQueen,
            health = v.stats.health,
            population = v.stats.population,
            disease = v.stats.disease,
            filledFrames = v.production.filledFrames,
            emptyFrames = v.production.emptyFrames,
            progress = math.floor(v.production.currentProgress),
            maxSlots = Config.HiveStats[v.type].slots,
            queenLifespan = v.queenGenetics.lifespan or 0
        }
    end
    return nuiData
end

RegisterServerEvent("bees:requestMenuData")
AddEventHandler("bees:requestMenuData", function(apiaryId)
    local _source = source
    local data = GetApiaryNuiData(apiaryId)
    TriggerClientEvent("bees:openApiaryMenu", _source, apiaryId, data, Config.MaxHivesPerApiary)
end)

-- Upravená funkce RefreshClientMenu
local function RefreshClientMenu(source, apiaryId)
    local data = GetApiaryNuiData(apiaryId)
    TriggerClientEvent("bees:updateMenuData", source, data)
end

local function RegisterHiveInventory(fullInventoryId, inventoryName)
    if not fullInventoryId then return nil end

    local isRegistered = exports.vorp_inventory:isCustomInventoryRegistered(fullInventoryId)

    if not isRegistered then
        local data = {
            id = fullInventoryId,
            name = inventoryName,
            limit = 100,
            acceptWeapons = false,
            shared = true,
            ignoreItemStackLimit = true,
            whitelistItems = false,
            UsePermissions = false,
            UseBlackList = false,
            whitelistWeapons = false,
            useWeight = true,
            weight = 200
        }
        exports.vorp_inventory:registerInventory(data)
        debugPrint("Registrován inventář: " .. fullInventoryId .. " (" .. inventoryName .. ")")
    end
    return fullInventoryId
end

local function CalculateEnvironment(coords)
    local season = "SUMMER" 
    local baseData = Config.Seasons[season] or Config.Seasons["SUMMER"]
    return {
        temp = baseData.temp,
        flora = baseData.floraBonus,
        season = season
    }
end

local function SerializeCoords(coords)
    return json.encode({ x = coords.x, y = coords.y, z = coords.z })
end

local function DeserializeCoords(coordsJson)
    local c = json.decode(coordsJson)
    return vector3(c.x, c.y, c.z)
end

-- Pomocná funkce pro zjištění počtu úlů v tabulce (protože to může mít díry v indexech, i když zde jedeme sekvenčně)
local function GetHiveCount(hivesTable)
    local count = 0
    for _ in pairs(hivesTable) do count = count + 1 end
    return count
end

-----------------------------------------------------------------------
-- SQL FUNCTIONS
-----------------------------------------------------------------------

local function SaveApiaryToDB(apiaryId, unload)
    local apiary = Apiaries[apiaryId]
    if not apiary then return end

    local hivesData = json.encode(apiary.hives)

    MySQL.update('UPDATE aprts_apiaries SET hives_data = ? WHERE id = ?', {hivesData, apiaryId}, function(affectedRows)
        if unload then
            Apiaries[apiaryId] = nil
        end
    end)
end

local function LoadApiariesFromDB()
    MySQL.query('SELECT * FROM aprts_apiaries', {}, function(result)
        if result then
            local count = 0
            for _, row in ipairs(result) do
                local hives = json.decode(row.hives_data) or {}

                for hiveId, hive in pairs(hives) do
                    if not hive.inventoryId then
                        hive.inventoryId = Config.InventoryPrefix .. "GEN_" .. row.id .. "_" .. hiveId
                    end
                    local invName = "Úl " .. row.id .. " - #" .. hiveId
                    RegisterHiveInventory(hive.inventoryId, invName)
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
-- LOGIKA ZAKLÁDÁNÍ A PŘIDÁVÁNÍ
-----------------------------------------------------------------------

local function CreateNewApiary(source, hiveType)
    local User = VorpCore.getUser(source)
    local Character = User.getUsedCharacter
    local u_charid = Character.charIdentifier
    local u_identifier = Character.identifier
    local coords = GetEntityCoords(GetPlayerPed(source))

    local randomInvId = Config.InventoryPrefix .. tostring(math.random(100000, 999999))

    local newHiveData = {
        [1] = {
            id = 1,
            type = hiveType,
            hasQueen = false,
            queenGenetics = {},
            stats = { health = 100, population = 0, disease = nil },
            production = { filledFrames = 0, currentProgress = 0 },
            inventoryId = randomInvId,
            calmedUntil = 0
        }
    }

    MySQL.insert(
        'INSERT INTO aprts_apiaries (owner_identifier, char_identifier, coords, hives_data) VALUES (?, ?, ?, ?)',
        {u_identifier, u_charid, SerializeCoords(coords), json.encode(newHiveData)}, function(insertId)
            if insertId then
                RegisterHiveInventory(randomInvId, "Úl " .. insertId .. " - #1")

                Apiaries[insertId] = {
                    id = insertId,
                    ownerIdentifier = u_identifier,
                    charIdentifier = u_charid,
                    coords = coords,
                    hives = newHiveData
                }

                -- Posíláme info clientovi (včetně počtu úlů = 1)
                TriggerClientEvent("bees:apiaryCreated", -1, insertId, coords, hiveType, 1)
                TriggerClientEvent("vorp:NotifyLeft", source, "Včelařství", "Včelín založen!", "generic_textures", "tick", 4000)
            end
        end)
end

-- NOVÝ EVENT: Přidání úlu
RegisterServerEvent("bees:addHive")
AddEventHandler("bees:addHive", function(apiaryId)
    local _source = source
    local apiary = Apiaries[apiaryId]
    if not apiary then return end

    local currentCount = GetHiveCount(apiary.hives)
    if currentCount >= Config.MaxHivesPerApiary then
        TriggerClientEvent("vorp:NotifyLeft", _source, "Chyba", "Včelín je plný!", "menu_textures", "cross", 4000)
        return
    end

    -- Kontrola itemu (Úl)
    if VORP_INV:getItemCount(_source, nil, Config.Items.HiveSmall) > 0 then
        if VORP_INV:subItem(_source, Config.Items.HiveSmall, 1) then
            
            local newId = currentCount + 1
            local randomInvId = Config.InventoryPrefix .. tostring(math.random(100000, 999999))
            
            apiary.hives[newId] = {
                id = newId,
                type = "small", -- Defaultně small
                hasQueen = false,
                queenGenetics = {},
                stats = { health = 100, population = 0, disease = nil },
                production = { filledFrames = 0, currentProgress = 0 },
                inventoryId = randomInvId,
                calmedUntil = 0
            }

            RegisterHiveInventory(randomInvId, "Úl " .. apiaryId .. " - #" .. newId)
            SaveApiaryToDB(apiaryId, false)
            
            -- Aktualizovat clienta
            TriggerClientEvent("bees:updateHiveCount", -1, apiaryId, newId)
            TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Přidán úl #"..newId, "generic_textures", "tick", 4000)
        end
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Chyba", "Nemáš položku úlu!", "menu_textures", "cross", 4000)
    end
end)

-----------------------------------------------------------------------
-- SIMULACE & LOGIKA (CORE)
-----------------------------------------------------------------------

local function ProcessHiveLogic(hive, envData, apiaryId)
    if not hive.hasQueen then return end

    -- 1. STÁRNUTÍ
    if not hive.queenGenetics.lifespan then hive.queenGenetics.lifespan = Config.QueenLifespan end
    hive.queenGenetics.lifespan = hive.queenGenetics.lifespan - 1
    
    if hive.queenGenetics.lifespan <= 0 then
        hive.hasQueen = false
        hive.stats.population = 0
        hive.stats.health = 0
        debugPrint("Královna v úlu " .. hive.inventoryId .. " zemřela stářím.")
        return
    end

    -- 2. ZIMNÍ KRMENÍ
    local healthChange = 0
    if envData.season == "WINTER" then
        local hasFood = exports.vorp_inventory:getItemCount(nil, nil, Config.Items.SugarWater, hive.inventoryId)
        if hasFood > 0 then
            exports.vorp_inventory:subItem(nil, Config.Items.SugarWater, 1, {}, hive.inventoryId)
        else
            healthChange = -15
            hive.stats.population = hive.stats.population - 50
        end
    else
        healthChange = 2
    end

    -- 3. NEMOCI
    if hive.stats.disease then
        local dInfo = Config.Diseases[hive.stats.disease]
        if dInfo then
            local res = hive.queenGenetics.hardiness or 0.5
            healthChange = healthChange - (dInfo.damage * (1.0 - res))
        end
    else
        if math.random() > (hive.queenGenetics.hardiness + 0.3) and math.random(1, 100) == 1 then
            hive.stats.disease = "mites"
        end
    end

    hive.stats.health = hive.stats.health + healthChange
    if hive.stats.health > 100 then hive.stats.health = 100 end
    if hive.stats.health <= 0 then
        hive.hasQueen = false; hive.stats.population = 0; hive.queenGenetics = {}
        return
    end

    -- 4. ROJENÍ
    if hive.stats.population > Config.SwarmPopulation and hive.stats.health > 90 then
        if math.random(1, 100) <= 5 then
            local newGenes = require('server/Genetics').Mutate(hive.queenGenetics)
            local metadata = { description = string.format("Gen: %d", newGenes.generation), genetics = newGenes }
            if exports.vorp_inventory:canCarryItem(nil, Config.Items.Queen, 1, hive.inventoryId) then
                exports.vorp_inventory:addItem(nil, Config.Items.Queen, 1, metadata, hive.inventoryId)
                hive.stats.population = math.floor(hive.stats.population / 2)
                debugPrint("Rojení v úlu " .. hive.inventoryId)
            end
        end
    end


    -- 5. PRODUKCE MEDU
    -- Včely pracují pouze, pokud mají PRÁZDNÝ RÁMEK (emptyFrames > 0)
    if envData.temp > 10 and envData.season ~= "WINTER" then
        if hive.production.emptyFrames > 0 then
            
            local prod = hive.queenGenetics.productivity or 0.5
            local factor = (hive.stats.population / 1000) * envData.flora * prod
            
            hive.production.currentProgress = hive.production.currentProgress + factor
            
            if hive.production.currentProgress >= 100 then
                -- HOTOVO: Přeměníme 1 prázdný rámek na 1 plný
                hive.production.emptyFrames = hive.production.emptyFrames - 1
                hive.production.filledFrames = hive.production.filledFrames + 1
                hive.production.currentProgress = 0
                debugPrint("Úl vyprodukoval med. (Plné: "..hive.production.filledFrames..")")
            end
        end
    end

    local growth = 20 * (hive.queenGenetics.productivity or 0.5)
    if envData.season == "WINTER" then growth = -10 end
    hive.stats.population = hive.stats.population + growth
    if hive.stats.population < 0 then hive.stats.population = 0 end
    if hive.stats.population > 10000 then hive.stats.population = 10000 end
    
    if hive.calmedUntil and hive.calmedUntil < GetGameTimer() then hive.calmedUntil = nil end
end

CreateThread(function()
    while true do
        Wait(Config.UpdateInterval)
        for apiaryId, apiary in pairs(Apiaries) do
            local env = CalculateEnvironment(apiary.coords)
            for _, hive in pairs(apiary.hives) do ProcessHiveLogic(hive, env, apiaryId) end
        end
    end
end)

-----------------------------------------------------------------------
-- EVENTY & INTERAKCE
-----------------------------------------------------------------------

RegisterCommand(Config.Commands.TestApiary, function(source, args)
    if source == 0 then return end
    CreateNewApiary(source, "small")
end)

RegisterCommand(Config.Commands.TestQueen, function(source, args)
    if source == 0 then return end
    local genes = require('server/Genetics').GenerateRandomGenetics()
    local metadata = { label = "Včelí Královna", genetics = genes }
    VORP_INV:addItem(source, Config.Items.Queen, 1, metadata)
end)

exports.vorp_inventory:registerUsableItem(Config.Items.Smoker, function(data)
    TriggerClientEvent("bees:useSmokerClient", data.source)
end)

RegisterServerEvent("bees:applySmoker")
AddEventHandler("bees:applySmoker", function(apiaryId, hiveId)
    local apiary = Apiaries[apiaryId]
    if apiary and apiary.hives[hiveId] then
        apiary.hives[hiveId].calmedUntil = GetGameTimer() + Config.SmokerDuration
        TriggerClientEvent("vorp:NotifyLeft", source, "Včelařství", "Včely uklidněny.", "generic_textures", "tick", 4000)
    end
    
end)

RegisterServerEvent("bees:applyMedicine")
AddEventHandler("bees:applyMedicine", function(apiaryId, hiveId)
    local _source = source
    if exports.vorp_inventory:subItem(_source, Config.Items.Medicine, 1) then
        local apiary = Apiaries[apiaryId]
        if apiary and apiary.hives[hiveId] then
            apiary.hives[hiveId].stats.disease = nil
            apiary.hives[hiveId].stats.health = apiary.hives[hiveId].stats.health + 20
            TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Vyléčeno.", "generic_textures", "tick", 4000)
            SaveApiaryToDB(apiaryId, false)
        end
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Chyba", "Nemáš lék.", "menu_textures", "cross", 4000)
    end
    RefreshClientMenu(_source, apiaryId)
end)

RegisterServerEvent("bees:insertQueen")
AddEventHandler("bees:insertQueen", function(apiaryId, hiveId, item)
    local _source = source
    local apiary = Apiaries[apiaryId]
    local hive = apiary.hives[tonumber(hiveId)]

    if hive.hasQueen then
        TriggerClientEvent("vorp:NotifyLeft", _source, "Chyba", "Úl už má královnu.", "menu_textures", "cross", 4000)
        return
    end

    if exports.vorp_inventory:subItem(_source, Config.Items.Queen, 1, item.metadata) then
        hive.hasQueen = true
        hive.queenGenetics = item.metadata.genetics or require('server/Genetics').GenerateRandomGenetics()
        hive.stats.population = 200; hive.stats.health = 100
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Královna vložena.", "generic_textures", "tick", 4000)
        SaveApiaryToDB(apiaryId, false)
    end
    RefreshClientMenu(_source, apiaryId)
end)

RegisterServerEvent("bees:openHive")
AddEventHandler("bees:openHive", function(apiaryId, hiveId)
    local _source = source
    local apiary = Apiaries[apiaryId]
    if not apiary then return end
    local hive = apiary.hives[tonumber(hiveId)]
    if not hive then return end

    local isCalmed = hive.calmedUntil and hive.calmedUntil > GetGameTimer()
    local aggression = hive.queenGenetics.aggression or 0.1
    local stingChance = (aggression * 100)
    if isCalmed then stingChance = stingChance / 5 end
    if hive.stats.population < 100 or not hive.hasQueen then stingChance = 0 end

    if math.random(0, 100) < stingChance then
        TriggerClientEvent("bees:clientStung", _source)
        TriggerClientEvent("vorp:NotifyLeft", _source, "Au!", "Dostal jsi žihadlo!", "menu_textures", "cross", 4000)
    end

    TriggerClientEvent("bees:showHiveStats", _source, hive.stats)
    
    if not exports.vorp_inventory:isCustomInventoryRegistered(hive.inventoryId) then
        RegisterHiveInventory(hive.inventoryId, "Úl " .. apiaryId .. " - #" .. hiveId)
    end
    VORP_INV:openInventory(_source, hive.inventoryId)
end)


RegisterServerEvent("bees:processFrames")
AddEventHandler("bees:processFrames", function()
    local _source = source
    if VORP_INV:subItem(_source, Config.Items.FrameFull, 1) then
        Wait(2000)
        VORP_INV:addItem(_source, Config.Items.HoneyJar, math.random(1, 2))
        VORP_INV:addItem(_source, Config.Items.Wax, math.random(1, 2))
        VORP_INV:addItem(_source, Config.Items.FrameEmpty, 1)
        TriggerClientEvent("vorp:NotifyLeft", _source, "Medomet", "Zpracováno.", "generic_textures", "tick", 3000)
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Medomet", "Nemáš plné rámky.", "menu_textures", "cross", 4000)
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    LoadApiariesFromDB()
end)
AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    for id, _ in pairs(Apiaries) do SaveApiaryToDB(id, true) end
end)

RegisterServerEvent("bees:getData")
AddEventHandler("bees:getData", function()
    local _source = source
    Wait(2000)
    for id, apiary in pairs(Apiaries) do
        local hiveType = apiary.hives[1] and apiary.hives[1].type or "small"
        local count = GetHiveCount(apiary.hives)
        TriggerClientEvent("bees:apiaryCreated", _source, id, apiary.coords, hiveType, count)
    end
end)



-- NOVÝ EVENT: VLOŽIT RÁMEK (Insert Frame)
RegisterServerEvent("bees:insertFrame")
AddEventHandler("bees:insertFrame", function(apiaryId, hiveId)
    local _source = source
    local apiary = Apiaries[apiaryId]
    if not apiary then return end
    local hive = apiary.hives[tonumber(hiveId)]
    ValidateHiveData(hive)

    local totalFrames = hive.production.filledFrames + hive.production.emptyFrames
    if totalFrames >= Config.HiveStats[hive.type].slots then
        TriggerClientEvent("vorp:NotifyLeft", _source, "Chyba", "Úl je plný!", "menu_textures", "cross", 4000)
        return
    end

    if VORP_INV:subItem(_source, Config.Items.FrameEmpty, 1) then
        hive.production.emptyFrames = hive.production.emptyFrames + 1
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Vložen rámek.", "generic_textures", "tick", 3000)
        SaveApiaryToDB(apiaryId, false)
        RefreshClientMenu(_source, apiaryId)
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Chyba", "Nemáš prázdný rámek.", "menu_textures", "cross", 4000)
    end
end)


-- UPRAVENÝ EVENT: SKLIZEŇ (Harvest Frame)
-- Nyní pouze vyjme plný rámek (slot zůstane prázdný)
RegisterServerEvent("bees:harvestFrame")
AddEventHandler("bees:harvestFrame", function(apiaryId, hiveId)
    local _source = source
    local apiary = Apiaries[apiaryId]
    local hive = apiary.hives[tonumber(hiveId)]
    
    if hive.production.filledFrames > 0 then
        -- Nemusíme odebírat FrameEmpty od hráče, protože rámek už v úlu byl
        hive.production.filledFrames = hive.production.filledFrames - 1
        
        -- Kalkulace kvality
        local quality = math.floor((hive.queenGenetics.productivity or 0.5) * 100)
        local metadata = { description = "Kvalita: " .. quality .. "%", quality = quality }
        
        -- Dáme hráči plný rámek
        VORP_INV:addItem(_source, Config.Items.FrameFull, 1, metadata)
        
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Rámek vyjmut.", "generic_textures", "tick", 4000)
        SaveApiaryToDB(apiaryId, false)
        RefreshClientMenu(_source, apiaryId)
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Info", "Žádný med k odběru.", "menu_textures", "cross", 4000)
    end
end)

