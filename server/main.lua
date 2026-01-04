local VORP_INV = exports.vorp_inventory
local VorpCore = {}

-- Načtení VORP Core
TriggerEvent("getCore", function(core)
    VorpCore = core
end)

-- Datová struktura
Apiaries = {} -- Global kvůli přístupu z jiných threadů

function debugPrint(msg)
    if Config.Debug then
        print("[Aprts Apiary DEBUG] " .. msg)
    end
end

-----------------------------------------------------------------------
-- HELPER FUNCTIONS
-----------------------------------------------------------------------

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
    local season = "SUMMER" -- Zde by mělo být napojení na script počasí/sync
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
-- LOGIKA ZAKLÁDÁNÍ
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
            stats = {
                health = 100,
                population = 0,
                disease = nil
            },
            production = {
                filledFrames = 0,
                currentProgress = 0
            },
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

                TriggerClientEvent("bees:apiaryCreated", -1, insertId, coords, hiveType)
                TriggerClientEvent("vorp:NotifyLeft", source, "Včelařství", "Včelín založen!", "generic_textures", "tick", 4000)
            end
        end)
end

-----------------------------------------------------------------------
-- SIMULACE & LOGIKA (CORE)
-----------------------------------------------------------------------

local function ProcessHiveLogic(hive, envData, apiaryId)
    if not hive.hasQueen then
        return
    end

    -- 1. STÁRNUTÍ KRÁLOVNY
    if not hive.queenGenetics.lifespan then hive.queenGenetics.lifespan = Config.QueenLifespan end
    hive.queenGenetics.lifespan = hive.queenGenetics.lifespan - 1
    
    if hive.queenGenetics.lifespan <= 0 then
        hive.hasQueen = false
        hive.stats.population = 0
        hive.stats.health = 0
        debugPrint("Královna v úlu " .. hive.inventoryId .. " zemřela stářím.")
        return
    end

    -- 2. ZIMNÍ KRMENÍ A ZDRAVÍ
    local healthChange = 0
    
    if envData.season == "WINTER" then
        -- Kontrola krmení
        local hasFood = exports.vorp_inventory:getItemCount(nil, nil, Config.Items.SugarWater, hive.inventoryId)
        if hasFood > 0 then
            exports.vorp_inventory:subItem(nil, Config.Items.SugarWater, 1, {}, hive.inventoryId)
            debugPrint("Úl " .. hive.inventoryId .. " zkonzumoval cukernou vodu.")
        else
            healthChange = -15 -- Hladovění
            hive.stats.population = hive.stats.population - 50
        end
    else
        healthChange = 2 -- Regenerace v létě
    end

    -- 3. NEMOCI
    if hive.stats.disease then
        local dInfo = Config.Diseases[hive.stats.disease]
        if dInfo then
            local res = hive.queenGenetics.hardiness or 0.5
            healthChange = healthChange - (dInfo.damage * (1.0 - res))
        end
    else
        -- Šance na nemoc (roztoči)
        if math.random() > (hive.queenGenetics.hardiness + 0.3) and math.random(1, 100) == 1 then
            hive.stats.disease = "mites"
            debugPrint("Úl " .. hive.inventoryId .. " chytil roztoče!")
        end
    end

    hive.stats.health = hive.stats.health + healthChange
    if hive.stats.health > 100 then hive.stats.health = 100 end

    if hive.stats.health <= 0 then
        hive.hasQueen = false
        hive.stats.population = 0
        hive.queenGenetics = {}
        debugPrint("Úl vymřel.")
        return
    end

    -- 4. ROJENÍ (SWARMING)
    if hive.stats.population > Config.SwarmPopulation and hive.stats.health > 90 then
        if math.random(1, 100) <= 5 then -- 5% šance na vyrojení
            local newGenes = Genetics.Mutate(hive.queenGenetics)
            local metadata = {
                description = string.format("Gen: %d | Prod: %d%%", newGenes.generation, math.floor(newGenes.productivity*100)),
                genetics = newGenes
            }
            
            local canAdd = exports.vorp_inventory:canCarryItem(nil, Config.Items.Queen, 1, hive.inventoryId)
            if canAdd then
                exports.vorp_inventory:addItem(nil, Config.Items.Queen, 1, metadata, hive.inventoryId)
                hive.stats.population = math.floor(hive.stats.population / 2) -- Polovina populace odletí
                debugPrint("Úl " .. hive.inventoryId .. " se vyrojil!")
            end
        end
    end

    -- 5. PRODUKCE MEDU
    if envData.temp > 10 and envData.season ~= "WINTER" then
        local prod = hive.queenGenetics.productivity or 0.5
        local factor = (hive.stats.population / 1000) * envData.flora * prod
        local maxFrames = Config.HiveStats[hive.type].slots

        if hive.production.filledFrames < maxFrames then
            hive.production.currentProgress = hive.production.currentProgress + factor
            if hive.production.currentProgress >= 100 then
                hive.production.filledFrames = hive.production.filledFrames + 1
                hive.production.currentProgress = 0
                -- Zde bychom mohli měnit frame_empty na frame_full přímo v inventáři, 
                -- ale pro zjednodušení hráč "Sklidí" pomocí tlačítka nebo vezme item.
                -- V této verzi předpokládáme, že hráč musí mít rámky, takže jen zvyšujeme čítač,
                -- který se "vybere" přes Harvest.
            end
        end
    end

    -- Růst populace
    local growth = 20 * (hive.queenGenetics.productivity or 0.5)
    if envData.season == "WINTER" then growth = -10 end
    
    hive.stats.population = hive.stats.population + growth
    if hive.stats.population < 0 then hive.stats.population = 0 end
    if hive.stats.population > 10000 then hive.stats.population = 10000 end
    
    -- Timer kouřáku
    if hive.calmedUntil and hive.calmedUntil < GetGameTimer() then
        hive.calmedUntil = nil
    end
end

-- Update Loop
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

-----------------------------------------------------------------------
-- EVENTY & INTERAKCE
-----------------------------------------------------------------------

RegisterCommand(Config.Commands.TestApiary, function(source, args)
    if source == 0 then return end
    CreateNewApiary(source, "small")
end)

RegisterCommand(Config.Commands.TestQueen, function(source, args)
    if source == 0 then return end
    local genes = Genetics.GenerateRandomGenetics()
    local metadata = {
        label = "Včelí Královna",
        description = string.format("Prod: %d%% | Odol: %d%%", math.floor(genes.productivity * 100), math.floor(genes.hardiness * 100)),
        genetics = genes
    }
    VORP_INV:addItem(source, Config.Items.Queen, 1, metadata)
end)

-- POUŽITÍ KOUŘÁKU (Item Usable)
exports.vorp_inventory:registerUsableItem(Config.Items.Smoker, function(data)
    local _source = data.source
    TriggerClientEvent("bees:useSmokerClient", _source)
end)

RegisterServerEvent("bees:applySmoker")
AddEventHandler("bees:applySmoker", function(apiaryId, hiveId)
    local _source = source
    local apiary = Apiaries[apiaryId]
    if apiary and apiary.hives[hiveId] then
        apiary.hives[hiveId].calmedUntil = GetGameTimer() + Config.SmokerDuration
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Včely jsou uklidněné.", "generic_textures", "tick", 4000)
    end
end)

-- APLIKACE LÉKU
RegisterServerEvent("bees:applyMedicine")
AddEventHandler("bees:applyMedicine", function(apiaryId, hiveId)
    local _source = source
    local apiary = Apiaries[apiaryId]
    
    if not apiary or not apiary.hives[hiveId] then return end
    
    if exports.vorp_inventory:subItem(_source, Config.Items.Medicine, 1) then
        local hive = apiary.hives[hiveId]
        if hive.stats.disease then
            hive.stats.disease = nil
            hive.stats.health = hive.stats.health + 20
            TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Úl vyléčen.", "generic_textures", "tick", 4000)
            SaveApiaryToDB(apiaryId, false)
        else
            TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Úl není nemocný (lék spotřebován).", "menu_textures", "cross", 4000)
        end
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Nemáš lék!", "menu_textures", "cross", 4000)
    end
end)

-- VLOŽENÍ KRÁLOVNY
RegisterServerEvent("bees:insertQueen")
AddEventHandler("bees:insertQueen", function(apiaryId, hiveId, item)
    local _source = source
    local apiary = Apiaries[apiaryId]
    if not apiary then return end
    local hive = apiary.hives[tonumber(hiveId)]

    if hive.hasQueen then
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Úl už má královnu!", "menu_textures", "cross", 4000)
        return
    end

    if exports.vorp_inventory:subItem(_source, Config.Items.Queen, 1, item.metadata) then
        hive.hasQueen = true
        hive.queenGenetics = item.metadata.genetics or Genetics.GenerateRandomGenetics()
        hive.stats.population = 200
        hive.stats.health = 100
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Královna vložena.", "generic_textures", "tick", 4000)
        SaveApiaryToDB(apiaryId, false)
    end
end)

-- OTEVŘENÍ ÚLU (S RIZIKEM BODNUTÍ)
RegisterServerEvent("bees:openHive")
AddEventHandler("bees:openHive", function(apiaryId, hiveId)
    local _source = source
    local apiary = Apiaries[apiaryId]
    if not apiary then return end
    local hive = apiary.hives[tonumber(hiveId)]
    if not hive then return end

    -- Kalkulace rizika
    local isCalmed = hive.calmedUntil and hive.calmedUntil > GetGameTimer()
    local aggression = hive.queenGenetics.aggression or 0.1
    local stingChance = (aggression * 100) -- v procentech
    
    if isCalmed then stingChance = stingChance / 5 end -- Kouřák snižuje riziko 5x
    if hive.stats.population < 100 then stingChance = 0 end 
    if not hive.hasQueen then stingChance = 0 end

    if math.random(0, 100) < stingChance then
        TriggerClientEvent("bees:clientStung", _source)
        TriggerClientEvent("vorp:NotifyLeft", _source, "Au!", "Úl je agresivní! Použij kouřák.", "menu_textures", "cross", 4000)
    end

    TriggerClientEvent("bees:showHiveStats", _source, hive.stats)

    if hive.inventoryId then
        if not exports.vorp_inventory:isCustomInventoryRegistered(hive.inventoryId) then
            RegisterHiveInventory(hive.inventoryId, "Úl " .. apiaryId .. " - #" .. hiveId)
        end
        VORP_INV:openInventory(_source, hive.inventoryId)
    end
end)

-- SKLIZEŇ (Přeměna rámků v úlu)
-- Pozn: Tento event byl v původním, ale nyní pro "realismus" doporučuji, aby hráč
-- musel fyzicky vyndat item "frame_full" z inventáře úlu a jít k medometu.
-- Ponechávám zde jen pro zpětnou kompatibilitu nebo debug.
RegisterServerEvent("bees:harvestFrame")
AddEventHandler("bees:harvestFrame", function(apiaryId, hiveId)
    local _source = source
    local apiary = Apiaries[apiaryId]
    local hive = apiary.hives[tonumber(hiveId)]
    
    if hive.production.filledFrames > 0 then
        -- Hráč musí mít prázdný rámek u sebe, vymění ho za plný do inventáře
        if VORP_INV:subItem(_source, Config.Items.FrameEmpty, 1) then
            hive.production.filledFrames = hive.production.filledFrames - 1
            local quality = math.floor((hive.queenGenetics.productivity or 0.5) * 100)
            local metadata = { description = "Kvalita: " .. quality .. "%", quality = quality }
            VORP_INV:addItem(_source, Config.Items.FrameFull, 1, metadata)
            TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Sklizeno!", "generic_textures", "tick", 4000)
            SaveApiaryToDB(apiaryId, false)
        else
            TriggerClientEvent("vorp:NotifyLeft", _source, "Chyba", "Nemáš prázdný rámek.", "menu_textures", "cross", 4000)
        end
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Info", "Žádné plné rámky k výměně.", "menu_textures", "cross", 4000)
    end
end)

-- MEDOMET (Zpracování plných rámků)
RegisterServerEvent("bees:processFrames")
AddEventHandler("bees:processFrames", function()
    local _source = source
    local count = VORP_INV:getItemCount(_source, nil, Config.Items.FrameFull)

    if count > 0 then
        -- Zpracuje 1 rámek
        if VORP_INV:subItem(_source, Config.Items.FrameFull, 1) then
            Wait(2000) -- Simulace
            VORP_INV:addItem(_source, Config.Items.HoneyJar, math.random(1, 2))
            VORP_INV:addItem(_source, Config.Items.Wax, math.random(1, 2))
            VORP_INV:addItem(_source, Config.Items.FrameEmpty, 1) -- Vrátí prázdný
            
            TriggerClientEvent("vorp:NotifyLeft", _source, "Medomet", "Med stočen!", "generic_textures", "tick", 3000)
        end
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Medomet", "Nemáš plné rámky.", "menu_textures", "cross", 4000)
    end
end)

-- Sync/Load
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
        TriggerClientEvent("bees:apiaryCreated", _source, id, apiary.coords, hiveType)
    end
end)