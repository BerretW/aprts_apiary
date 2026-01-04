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

local function ValidateHiveData(hive)
    if not hive.production.emptyFrames then
        hive.production.emptyFrames = 0
    end
    -- Fallback pokud by neseděly počty (prevence chyb)
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
        
        -- Získání životnosti (podpora pro staré i nové struktury)
        local lifespan = 0
        if v.queenGenetics and v.queenGenetics.lifespan then
            lifespan = v.queenGenetics.lifespan
        end

        nuiData[tostring(k)] = {
            id = v.id,
            hasQueen = v.hasQueen,
            health = v.stats.health,
            population = v.stats.population,
            disease = v.stats.disease,
            filledFrames = v.production.filledFrames,
            emptyFrames = v.production.emptyFrames,
            progress = math.floor(v.production.currentProgress),
            maxSlots = Config.HiveStats[v.type].slots,
            queenLifespan = lifespan
        }
    end
    return nuiData
end

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
        debugPrint("Registrován inventář: " .. fullInventoryId)
    end
    return fullInventoryId
end

local function CalculateEnvironment(coords)
    local season = "SUMMER" -- Zde by se dalo napojit na weather script
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
            production = { filledFrames = 0, emptyFrames = 0, currentProgress = 0 },
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

                TriggerClientEvent("bees:apiaryCreated", -1, insertId, coords, hiveType, 1)
                TriggerClientEvent("vorp:NotifyLeft", source, "Včelařství", "Včelín založen!", "generic_textures", "tick", 4000)
            end
        end)
end

-- Použití itemu pro založení (Bee Box)
exports.vorp_inventory:registerUsableItem(Config.Items.HiveSmall, function(data)
    local _source = data.source
    if VORP_INV:subItem(_source, Config.Items.HiveSmall, 1) then
        CreateNewApiary(_source, "small")
    end
end)

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

    if VORP_INV:getItemCount(_source, nil, Config.Items.HiveSmall) > 0 then
        if VORP_INV:subItem(_source, Config.Items.HiveSmall, 1) then

            local newId = currentCount + 1
            local randomInvId = Config.InventoryPrefix .. tostring(math.random(100000, 999999))

            apiary.hives[newId] = {
                id = newId,
                type = "small",
                hasQueen = false,
                queenGenetics = {},
                stats = { health = 100, population = 0, disease = nil },
                production = { filledFrames = 0, emptyFrames = 0, currentProgress = 0 },
                inventoryId = randomInvId,
                calmedUntil = 0
            }

            RegisterHiveInventory(randomInvId, "Úl " .. apiaryId .. " - #" .. newId)
            SaveApiaryToDB(apiaryId, false)

            TriggerClientEvent("bees:updateHiveCount", -1, apiaryId, newId)
            TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Přidán úl #" .. newId, "generic_textures", "tick", 4000)
            
            -- Refresh menu pro hráče, který staví
            RefreshClientMenu(_source, apiaryId)
        end
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Chyba", "Nemáš položku úlu!", "menu_textures", "cross", 4000)
    end
end)

-----------------------------------------------------------------------
-- SIMULACE & LOGIKA (CORE GENETICS)
-----------------------------------------------------------------------

local function ProcessHiveLogic(hive, envData, apiaryId)
    if not hive.hasQueen then return end

    local genes = hive.queenGenetics
    -- Fallback pro staré královny (migrace)
    if not genes.productivity then genes.productivity = 50 end
    if not genes.aggression then genes.aggression = 50 end
    if not genes.fertility then genes.fertility = 50 end
    if not genes.resilience then genes.resilience = 50 end
    if not genes.adaptability then genes.adaptability = 50 end
    if not genes.lifespan then genes.lifespan = Config.QueenLifespan or 100 end

    -- 1. STÁRNUTÍ (LIFESPAN)
    genes.lifespan = genes.lifespan - 1
    if genes.lifespan <= 0 then
        hive.hasQueen = false
        hive.stats.population = 0
        hive.stats.health = 0
        debugPrint("Královna v úlu " .. hive.inventoryId .. " zemřela stářím.")
        return
    end

    -- 2. ZIMNÍ KRMENÍ A ADAPTABILITA
    -- Adaptabilita snižuje poškození zimou (100% adaptability = 0 dmg)
    local weatherDamage = 0
    if envData.season == "WINTER" then
        local hasFood = exports.vorp_inventory:getItemCount(nil, nil, Config.Items.SugarWater, hive.inventoryId)
        if hasFood > 0 then
            exports.vorp_inventory:subItem(nil, Config.Items.SugarWater, 1, {}, hive.inventoryId)
        else
            local resistance = genes.adaptability / 100
            weatherDamage = -15 * (1.0 - resistance)
            hive.stats.population = hive.stats.population - (50 * (1.0 - resistance))
        end
    else
        weatherDamage = 2 -- Regenerace v létě
    end

    -- 3. NEMOCI A ODOLNOST (RESILIENCE)
    if hive.stats.disease then
        local dInfo = Config.Diseases[hive.stats.disease]
        if dInfo then
            -- Vyšší resilience = menší damage od nemoci
            local dmgMitigation = genes.resilience / 100 -- 0.0 až 1.0
            weatherDamage = weatherDamage - (dInfo.damage * (1.0 - dmgMitigation))
        end
    else
        -- Šance chytit nemoc (vyšší resilience = menší šance)
        -- Base šance cca 2%
        local diseaseChance = 2.0 - (1.8 * (genes.resilience / 100))
        if math.random() * 100 < diseaseChance then
            hive.stats.disease = "mites"
        end
    end

    -- Aplikace zdraví
    hive.stats.health = hive.stats.health + weatherDamage
    if hive.stats.health > 100 then hive.stats.health = 100 end
    if hive.stats.health <= 0 then
        hive.hasQueen = false
        hive.stats.population = 0
        hive.queenGenetics = {}
        return
    end

    -- 4. ROJENÍ (SWARMING)
    if hive.stats.population > Config.SwarmPopulation and hive.stats.health > 90 then
        if math.random(1, 100) <= 5 then
            local newGenes = Genetics.Mutate(hive.queenGenetics)
            local metadata = {
                description = string.format("Gen: %d", newGenes.generation),
                genetics = newGenes,
                label = "Mladá Královna"
            }
            if exports.vorp_inventory:canCarryItem(nil, Config.Items.Queen, 1, hive.inventoryId) then
                exports.vorp_inventory:addItem(nil, Config.Items.Queen, 1, metadata, hive.inventoryId)
                hive.stats.population = math.floor(hive.stats.population / 2)
                debugPrint("Rojení v úlu " .. hive.inventoryId)
            end
        end
    end

    -- 5. PRODUKCE MEDU (PRODUCTIVITY)
    if envData.temp > 10 and envData.season ~= "WINTER" then
        if hive.production.emptyFrames > 0 then
            -- Produktivita ovlivňuje rychlost progresu
            local prodFactor = (genes.productivity / 50) -- 0.2 až 2.0x
            local popFactor = (hive.stats.population / 1000)
            
            local progressAdd = popFactor * envData.flora * prodFactor
            hive.production.currentProgress = hive.production.currentProgress + progressAdd

            if hive.production.currentProgress >= 100 then
                hive.production.emptyFrames = hive.production.emptyFrames - 1
                hive.production.filledFrames = hive.production.filledFrames + 1
                hive.production.currentProgress = 0
                debugPrint("Úl vyprodukoval med.")
            end
        end
    end

    -- 6. RŮST POPULACE (FERTILITY)
    local baseGrowth = 20
    if envData.season == "WINTER" then baseGrowth = -10 end
    
    -- Fertility bonus: 0% = 0.5x, 100% = 1.5x speed
    local fertilityMult = 0.5 + (genes.fertility / 100)
    local growth = baseGrowth * fertilityMult
    
    hive.stats.population = hive.stats.population + growth
    
    if hive.stats.population < 0 then hive.stats.population = 0 end
    
    -- Použití Configu pro max populaci (fallback 10000)
    local maxPop = Config.MaxPopulation or 10000
    if hive.stats.population > maxPop then hive.stats.population = maxPop end

    -- Reset uklidnění
    if hive.calmedUntil and hive.calmedUntil < GetGameTimer() then
        hive.calmedUntil = nil
    end
end

CreateThread(function()
    while true do
        Wait(Config.UpdateInterval)
        for apiaryId, apiary in pairs(Apiaries) do
            if Config.Debug then
                print("Processing apiary ID: " .. tostring(apiaryId))
            end
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

-- Použití Mikroskopu pro analýzu
exports.vorp_inventory:registerUsableItem("bee_microscope", function(data)
    local _source = data.source
    -- Hledání královny v inventáři
    local queenItem = exports.vorp_inventory:getItem(_source, Config.Items.Queen)
    
    local targetQueen = nil
    -- VORP může vrátit tabulku (když je víc slotů) nebo objekt
    if queenItem and type(queenItem) == "table" and #queenItem > 0 then
        targetQueen = queenItem[1]
    elseif queenItem and queenItem.count > 0 then
        targetQueen = queenItem
    end
    
    if targetQueen then
        local genes = targetQueen.metadata.genetics
        -- Pokud item nemá geny (starý item nebo spawnutý přes admin menu), vygenerujeme
        if not genes then
            genes = Genetics.GenerateRandomGenetics()
        end
        TriggerClientEvent("bees:openMicroscopeClient", _source, genes)
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Mikroskop", "Nemáš žádnou královnu k analýze!", "menu_textures", "cross", 4000)
    end
end)

-- Admin příkazy
RegisterCommand(Config.Commands.TestApiary, function(source, args)
    if source == 0 then return end
    CreateNewApiary(source, "small")
end)

RegisterCommand(Config.Commands.TestQueen, function(source, args)
    if source == 0 then return end
    local genes = Genetics.GenerateRandomGenetics()
    local metadata = {
        label = "Včelí Královna",
        genetics = genes,
        description = "Divoká královna"
    }
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
        hive.queenGenetics = item.metadata.genetics or Genetics.GenerateRandomGenetics()
        hive.stats.population = 200;
        hive.stats.health = 100
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
    
    -- Výpočet šance na bodnutí podle Agresivity (0-100)
    -- Agresivita 100 = vysoká šance
    local aggression = 50 
    if hive.queenGenetics and hive.queenGenetics.aggression then
        aggression = hive.queenGenetics.aggression
    end

    local stingChance = aggression -- Základní šance v procentech (např 80%)
    
    if isCalmed then
        stingChance = stingChance / 5 -- Kouřák výrazně snižuje
    end
    
    if hive.stats.population < 100 or not hive.hasQueen then
        stingChance = 0
    end

    if math.random(0, 100) < stingChance then
        TriggerClientEvent("bees:clientStung", _source)
        TriggerClientEvent("vorp:NotifyLeft", _source, "Au!", "Dostal jsi žihadlo!", "menu_textures", "cross", 4000)
    end

    -- Otevření inventáře
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

RegisterServerEvent("bees:insertFrame")
AddEventHandler("bees:insertFrame", function(apiaryId, hiveId)
    local _source = source
    local apiary = Apiaries[apiaryId]
    if not apiary then return end
    
    local hive = apiary.hives[tonumber(hiveId)]
    if not hive then return end

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

RegisterServerEvent("bees:harvestFrame")
AddEventHandler("bees:harvestFrame", function(apiaryId, hiveId)
    local _source = source
    local apiary = Apiaries[apiaryId]
    local hive = apiary.hives[tonumber(hiveId)]

    if hive.production.filledFrames > 0 then
        hive.production.filledFrames = hive.production.filledFrames - 1

        -- Kvalita medu podle genetiky
        local quality = 50
        if hive.queenGenetics and hive.queenGenetics.productivity then
            quality = hive.queenGenetics.productivity
        end
        
        local metadata = {
            description = "Kvalita včelstva: " .. quality .. "%",
            quality = quality
        }

        VORP_INV:addItem(_source, Config.Items.FrameFull, 1, metadata)

        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Rámek vyjmut.", "generic_textures", "tick", 4000)
        SaveApiaryToDB(apiaryId, false)
        RefreshClientMenu(_source, apiaryId)
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Info", "Žádný med k odběru.", "menu_textures", "cross", 4000)
    end
end)

RegisterServerEvent("bees:requestMenuData")
AddEventHandler("bees:requestMenuData", function(apiaryId)
    local _source = source
    local data = GetApiaryNuiData(apiaryId)
    TriggerClientEvent("bees:openApiaryMenu", _source, apiaryId, data, Config.MaxHivesPerApiary)
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

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    LoadApiariesFromDB()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    for id, _ in pairs(Apiaries) do
        SaveApiaryToDB(id, true)
    end
end)