-----------------------------------------------------------------------
-- HELPER FUNCTIONS (Globální)
-----------------------------------------------------------------------

function debugPrint(msg)
    if Config.Debug then
        print("[Aprts Apiary DEBUG] " .. msg)
    end
end

function CreateHiveTable(id, type, inventoryId)
    return {
        id = id,
        type = type or "small",
        hasQueen = false,
        queenGenetics = {},
        stats = { health = 100, population = 0, disease = nil },
        production = { filledFrames = 0, emptyFrames = 0, currentProgress = 0 },
        inventoryId = inventoryId,
        calmedUntil = 0,
        logs = {} 
    }
end

function AddHiveLog(apiaryId, hiveId, message)
    local apiary = Apiaries[apiaryId]
    if not apiary then return end
    local hive = apiary.hives[tonumber(hiveId)]
    if not hive then return end

    if not hive.logs then hive.logs = {} end
    local time = os.date("%H:%M") 
    table.insert(hive.logs, 1, { time = time, msg = message })
    if #hive.logs > 10 then
        table.remove(hive.logs)
    end
end

function ValidateHiveData(hive)
    if not hive.production.emptyFrames then hive.production.emptyFrames = 0 end
    if not hive.logs then hive.logs = {} end
    
    local total = hive.production.filledFrames + hive.production.emptyFrames
    if total > Config.HiveStats[hive.type].slots then
        hive.production.emptyFrames = Config.HiveStats[hive.type].slots - hive.production.filledFrames
    end
end

function GetApiaryNuiData(apiaryId)
    local apiary = Apiaries[apiaryId]
    if not apiary then return {} end

    local nuiData = {}
    for k, v in pairs(apiary.hives) do
        ValidateHiveData(v)
        
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
            queenLifespan = lifespan,
            logs = v.logs or {}
        }
    end
    return nuiData
end

function RefreshClientMenu(source, apiaryId)
    local data = GetApiaryNuiData(apiaryId)
    TriggerClientEvent("bees:updateMenuData", source, data)
end

function RegisterHiveInventory(fullInventoryId, inventoryName)
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
    end
    return fullInventoryId
end

function CalculateEnvironment(coords)
    local season = "SUMMER"
    local baseData = Config.Seasons[season] or Config.Seasons["SUMMER"]
    return {
        temp = baseData.temp,
        flora = baseData.floraBonus,
        season = season
    }
end

function SerializeCoords(coords)
    return json.encode({ x = coords.x, y = coords.y, z = coords.z })
end

function DeserializeCoords(coordsJson)
    local c = json.decode(coordsJson)
    return vector3(c.x, c.y, c.z)
end

function GetHiveCount(hivesTable)
    local count = 0
    for _ in pairs(hivesTable) do count = count + 1 end
    return count
end

function CreateNewApiary(source, hiveType)
    local User = VorpCore.getUser(source)
    local Character = User.getUsedCharacter
    local u_charid = Character.charIdentifier
    local u_identifier = Character.identifier
    local coords = GetEntityCoords(GetPlayerPed(source))

    local randomInvId = Config.InventoryPrefix .. tostring(math.random(100000, 999999))

    local newHiveData = {
        [1] = CreateHiveTable(1, hiveType, randomInvId)
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

function ProcessHiveLogic(hive, envData, apiaryId)
    if not hive.hasQueen then 
        if hive.stats.population > 0 then
            local decay = math.floor(hive.stats.population * 0.02) + 10
            hive.stats.population = hive.stats.population - decay
            if hive.stats.population < 0 then hive.stats.population = 0 end
        end
        return 
    end

    local genes = hive.queenGenetics
    if not genes.productivity then genes.productivity = 50 end
    if not genes.aggression then genes.aggression = 50 end
    if not genes.fertility then genes.fertility = 50 end
    if not genes.resilience then genes.resilience = 50 end
    if not genes.adaptability then genes.adaptability = 50 end
    if not genes.lifespan then genes.lifespan = Config.QueenLifespan or 100 end

    -- 1. STÁRNUTÍ
    genes.lifespan = genes.lifespan - 1
    if genes.lifespan <= 0 then
        hive.hasQueen = false
        hive.stats.population = 0
        hive.stats.health = 0
        hive.queenGenetics = {}
        AddHiveLog(apiaryId, hive.id, "Královna zemřela přirozenou smrtí.")
        return
    end

    -- 2. KRMENÍ
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
        weatherDamage = 2 
    end

    -- 3. NEMOCI
    if hive.stats.disease then
        local dInfo = Config.Diseases[hive.stats.disease]
        if dInfo then
            local dmgMitigation = genes.resilience / 100 
            weatherDamage = weatherDamage - (dInfo.damage * (1.0 - dmgMitigation))
        end
    else
        local diseaseChance = 2.0 - (1.8 * (genes.resilience / 100))
        if math.random() * 100 < diseaseChance then
            hive.stats.disease = "mites"
            AddHiveLog(apiaryId, hive.id, "Úl byl napaden roztoči!")
        end
    end

    -- Aplikace zdraví
    hive.stats.health = hive.stats.health + weatherDamage
    if hive.stats.health > 100 then hive.stats.health = 100 end
    if hive.stats.health <= 0 then
        hive.hasQueen = false
        hive.stats.population = 0
        hive.queenGenetics = {}
        AddHiveLog(apiaryId, hive.id, "Úl uhynul (zdravotní stav).")
        return
    end

    -- 4. ROJENÍ
    if hive.stats.population > Config.SwarmPopulation and hive.stats.health > 90 then
        if math.random(1, 100) <= 5 then
            -- Pozor: Předpokládám, že Genetics je globální tabulka z jiného souboru nebo Configu
            local newGenes = Genetics.Mutate(hive.queenGenetics)
            local metadata = {
                description = string.format("Gen: %d", newGenes.generation),
                genetics = newGenes,
                label = "Mladá Královna"
            }
            if exports.vorp_inventory:canCarryItem(nil, Config.Items.Queen, 1, hive.inventoryId) then
                exports.vorp_inventory:addItem(nil, Config.Items.Queen, 1, metadata, hive.inventoryId)
                hive.stats.population = math.floor(hive.stats.population / 2)
                AddHiveLog(apiaryId, hive.id, "Úl se vyrojil (nová královna).")
            end
        end
    end

    -- 5. PRODUKCE MEDU
    if envData.temp > 10 and envData.season ~= "WINTER" then
        if hive.production.emptyFrames > 0 then
            local prodFactor = (genes.productivity / 50) 
            local popFactor = (hive.stats.population / 1000)
            
            local progressAdd = popFactor * envData.flora * prodFactor
            hive.production.currentProgress = hive.production.currentProgress + progressAdd

            if hive.production.currentProgress >= 100 then
                hive.production.emptyFrames = hive.production.emptyFrames - 1
                hive.production.filledFrames = hive.production.filledFrames + 1
                hive.production.currentProgress = 0
            end
        end
    end

    -- 6. POPULACE
    local baseGrowth = 20
    if envData.season == "WINTER" then baseGrowth = -10 end
    local fertilityMult = 0.5 + (genes.fertility / 100)
    local growth = baseGrowth * fertilityMult
    
    hive.stats.population = hive.stats.population + growth
    if hive.stats.population < 0 then hive.stats.population = 0 end
    local maxPop = Config.MaxPopulation or 10000
    if hive.stats.population > maxPop then hive.stats.population = maxPop end

    if hive.calmedUntil and hive.calmedUntil < GetGameTimer() then
        hive.calmedUntil = nil
    end
end