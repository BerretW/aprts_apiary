local VORP_INV = exports.vorp_inventory
local VorpCore = {}

-- Načtení VORP Core
TriggerEvent("getCore", function(core)
    VorpCore = core
end)

-- Datová struktura
local Apiaries = {}

function debugPrint(msg)
    if Config.Debug then
        print("[Aprts Apiary DEBUG] " .. msg)
    end
end

-----------------------------------------------------------------------
-- HELPER FUNCTIONS (Prostředí & Inventáře)
-----------------------------------------------------------------------

-- OPRAVA: Funkce nyní přijímá kompletní ID inventáře (string), nevytváří ho znovu.
local function RegisterHiveInventory(fullInventoryId, inventoryName)
    if not fullInventoryId then
        return nil
    end

    local isRegistered = exports.vorp_inventory:isCustomInventoryRegistered(fullInventoryId)

    if not isRegistered then
        local data = {
            id = fullInventoryId,
            name = inventoryName,
            limit = 100, -- Limit váhy/slotů
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
    else
        -- debugPrint("Inventář již existuje: " .. fullInventoryId)
    end
    return fullInventoryId
end

-- Simulace prostředí
local function CalculateEnvironment(coords)
    local season = "SUMMER" -- Ideálně napojit na weather script
    local baseData = Config.Seasons[season] or Config.Seasons["SUMMER"]
    return {
        temp = baseData.temp,
        flora = baseData.floraBonus,
        season = season
    }
end

local function SerializeCoords(coords)
    return json.encode({
        x = coords.x,
        y = coords.y,
        z = coords.z
    })
end

local function DeserializeCoords(coordsJson)
    local c = json.decode(coordsJson)
    return vector3(c.x, c.y, c.z)
end

-----------------------------------------------------------------------
-- SQL FUNCTIONS (PERSISTENCE)
-----------------------------------------------------------------------

local function SaveApiaryToDB(apiaryId, unload)
    local apiary = Apiaries[apiaryId]
    if not apiary then
        return
    end

    local hivesData = json.encode(apiary.hives)

    MySQL.update('UPDATE aprts_apiaries SET hives_data = ? WHERE id = ?', {hivesData, apiaryId}, function(affectedRows)
        if Config.Debug and affectedRows > 0 then
            -- debugPrint("Uloženo ID: " .. apiaryId)
        end
        if unload then
            Apiaries[apiaryId] = nil
        end
    end)
end

-- OPRAVA: Při načítání bereme ID inventáře z uložených dat, negenerujeme nové podle ID úlu.
local function LoadApiariesFromDB()
    MySQL.query('SELECT * FROM aprts_apiaries', {}, function(result)
        if result then
            local count = 0
            for _, row in ipairs(result) do
                local hives = json.decode(row.hives_data) or {}

                -- Oprava struktury a registrace inventářů
                for hiveId, hive in pairs(hives) do
                    -- Fallback: Kdyby náhodou stará data neměla inventoryId, vygenerujeme ho (pro kompatibilitu)
                    if not hive.inventoryId then
                        hive.inventoryId = Config.InventoryPrefix .. "GEN_" .. row.id .. "_" .. hiveId
                    end

                    local invName = "Úl " .. row.id .. " - #" .. hiveId

                    -- Zde voláme registraci s ULOŽENÝM ID
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
            print("[Aprts Apiary] Načteno " .. count .. " včelínů z databáze.")
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

    -- Generování unikátního ID inventáře
    -- Používáme náhodné číslo, ale bezpečnější by bylo použít UUID nebo kombinaci SteamID+Time
    local randomInvId = Config.InventoryPrefix .. tostring(math.random(100000, 999999))

    local newHiveData = {
        [1] = {
            id = 1,
            type = hiveType,
            hasQueen = false,
            queenGenetics = {},
            stats = {
                health = 100,
                population = 0
            },
            production = {
                filledFrames = 0,
                currentProgress = 0
            },
            inventoryId = randomInvId -- Ukládáme toto ID
        }
    }

    MySQL.insert(
        'INSERT INTO aprts_apiaries (owner_identifier, char_identifier, coords, hives_data) VALUES (?, ?, ?, ?)',
        {u_identifier, u_charid, SerializeCoords(coords), json.encode(newHiveData)}, function(insertId)
            if insertId then
                -- Registrace inventáře OKAMŽITĚ po vytvoření
                RegisterHiveInventory(randomInvId, "Úl " .. insertId .. " - #1")

                Apiaries[insertId] = {
                    id = insertId,
                    ownerIdentifier = u_identifier,
                    charIdentifier = u_charid,
                    coords = coords,
                    hives = newHiveData
                }

                TriggerClientEvent("bees:apiaryCreated", -1, insertId, coords, hiveType)
                TriggerClientEvent("vorp:NotifyLeft", source, "Včelařství", "Včelín založen!", "generic_textures",
                    "tick", 4000)
                debugPrint("Nový včelín ID: " .. insertId .. " s inventářem: " .. randomInvId)
            end
        end)
end

-----------------------------------------------------------------------
-- COMMANDS
-----------------------------------------------------------------------

RegisterCommand(Config.Commands.TestApiary, function(source, args)
    if source == 0 then
        return
    end
    CreateNewApiary(source, "small")
end)

RegisterCommand(Config.Commands.TestQueen, function(source, args)
    if source == 0 then
        return
    end
    local genes = Genetics.GenerateRandomGenetics()
    local metadata = {
        label = "Včelí Královna",
        description = string.format("Prod: %d%% | Odol: %d%%", math.floor(genes.productivity * 100),
            math.floor(genes.hardiness * 100)),
        genetics = genes
    }
    VORP_INV:addItem(source, Config.Items.Queen, 1, metadata)
    TriggerClientEvent("vorp:NotifyLeft", source, "Včelařství", "Získal jsi testovací královnu",
        "generic_textures", "tick", 3000)
end)

-----------------------------------------------------------------------
-- UPDATE LOOPS & EVENTS
-----------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(Config.SaveInterval)
        for id, _ in pairs(Apiaries) do
            SaveApiaryToDB(id, false)
        end
        -- debugPrint("Automatické uložení dat.")
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end
    LoadApiariesFromDB()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end
    for id, _ in pairs(Apiaries) do
        SaveApiaryToDB(id, true)
    end
    print("[Aprts Apiary] Data uložena.")
end)

RegisterServerEvent("bees:getData")
AddEventHandler("bees:getData", function()
    local _source = source
    Wait(2000) -- Krátká prodleva pro načtení klienta
    for id, apiary in pairs(Apiaries) do
        local hiveType = "small"
        if apiary.hives[1] then
            hiveType = apiary.hives[1].type
        end
        TriggerClientEvent("bees:apiaryCreated", _source, id, apiary.coords, hiveType)
    end
end)

-----------------------------------------------------------------------
-- CORE LOGIC (Simulace)
-----------------------------------------------------------------------

local function ProcessHiveLogic(hive, envData)
    if not hive.hasQueen then
        return
    end

    local healthChange = 0
    if envData.temp < 0 and hive.stats.population < 500 then
        healthChange = -5
    end

    if hive.stats.disease then
        local dInfo = Config.Diseases[hive.stats.disease]
        if dInfo then
            local res = hive.queenGenetics.hardiness or 0.5
            healthChange = healthChange - (dInfo.damage * (1.0 - res))
        end
    end

    hive.stats.health = hive.stats.health + healthChange
    if hive.stats.health > 100 then
        hive.stats.health = 100
    end

    if hive.stats.health <= 0 then
        hive.hasQueen = false
        hive.stats.population = 0
        hive.queenGenetics = {}
        debugPrint("Úl vymřel.")
        return
    end

    if envData.temp > 10 then
        local prod = hive.queenGenetics.productivity or 0.5
        local factor = (hive.stats.population / 1000) * envData.flora * prod
        local maxFrames = Config.HiveStats[hive.type].slots

        if hive.production.filledFrames < maxFrames then
            hive.production.currentProgress = hive.production.currentProgress + factor
            if hive.production.currentProgress >= 100 then
                hive.production.filledFrames = hive.production.filledFrames + 1
                hive.production.currentProgress = 0
                debugPrint("Vyprodukován rámek v úlu " .. hive.inventoryId)
            end
        end
    end

    local growth = 20 * (hive.queenGenetics.productivity or 0.5)
    if envData.season == "WINTER" then
        growth = -10
    end
    hive.stats.population = hive.stats.population + growth
    if hive.stats.population < 0 then
        hive.stats.population = 0
    end
    if hive.stats.population > 10000 then
        hive.stats.population = 10000
    end
end

CreateThread(function()
    while true do
        Wait(Config.UpdateInterval)
        for _, apiary in pairs(Apiaries) do
            local env = CalculateEnvironment(apiary.coords)
            for _, hive in pairs(apiary.hives) do
                ProcessHiveLogic(hive, env)
            end
        end
    end
end)

-----------------------------------------------------------------------
-- INTERACTION EVENTS
-----------------------------------------------------------------------

RegisterServerEvent("bees:insertQueen")
AddEventHandler("bees:insertQueen", function(apiaryId, hiveId, item)
    local _source = source
    local apiary = Apiaries[apiaryId]
    if not apiary then
        return
    end

    local hive = apiary.hives[tonumber(hiveId)]
    if not hive then
        return
    end

    if hive.hasQueen then
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Úl už má královnu!", "menu_textures",
            "cross", 4000)
        return
    end

    local metadata = item.metadata or {}
    if not metadata.genetics then
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Toto není platná královna!",
            "menu_textures", "cross", 4000)
        return
    end

    if exports.vorp_inventory:subItem(_source, Config.Items.Queen, 1, item.metadata) then
        hive.hasQueen = true
        hive.queenGenetics = metadata.genetics or Genetics.GenerateRandomGenetics()
        hive.stats.population = 200
        hive.stats.health = 100
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Královna vložena.",
                    "generic_textures", "tick", 4000)
                SaveApiaryToDB(apiaryId, false)
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Nepodařilo se odebrat královnu z inventáře!",
            "menu_textures", "cross", 4000)
        return
    end

end)

RegisterServerEvent("bees:harvestFrame")
AddEventHandler("bees:harvestFrame", function(apiaryId, hiveId)
    local _source = source
    local apiary = Apiaries[apiaryId]
    if not apiary then
        return
    end

    local hive = apiary.hives[tonumber(hiveId)]
    if not hive then
        return
    end

    if hive.production.filledFrames > 0 then
        local count = VORP_INV:getItemCount(_source, nil, Config.Items.FrameEmpty)
        if count > 0 then
            VORP_INV:subItem(_source, Config.Items.FrameEmpty, 1)
            hive.production.filledFrames = hive.production.filledFrames - 1

            local quality = math.floor((hive.queenGenetics.productivity or 0.5) * 100)
            local metadata = {
                description = "Kvalita medu: " .. quality .. "%",
                quality = quality
            }

            VORP_INV:addItem(_source, Config.Items.FrameFull, 1, metadata)
            TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Sklizeno!", "generic_textures", "tick",
                4000)
            SaveApiaryToDB(apiaryId, false)
        else
            TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Chybí prázdný rámek!", "menu_textures",
                "cross", 4000)
        end
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Žádný med.", "menu_textures", "cross", 4000)
    end
end)

RegisterServerEvent("bees:openHive")
AddEventHandler("bees:openHive", function(apiaryId, hiveId)
    local _source = source
    local apiary = Apiaries[apiaryId]

    if not apiary then
        return
    end
    local hive = apiary.hives[tonumber(hiveId)]
    if not hive then
        return
    end

    -- Zaslání statistik (volitelně)
    TriggerClientEvent("bees:showHiveStats", _source, hive.stats)

    -- OPRAVA: Otevíráme striktně podle uloženého inventoryId
    if hive.inventoryId then
        debugPrint("Otevírám inventář: " .. hive.inventoryId)

        -- Pojistka: Pokud by inventář nebyl zaregistrován (např. chyba při startu), zkusíme to teď
        if not exports.vorp_inventory:isCustomInventoryRegistered(hive.inventoryId) then
            RegisterHiveInventory(hive.inventoryId, "Úl " .. apiaryId .. " - #" .. hiveId)
        end

        VORP_INV:openInventory(_source, hive.inventoryId)
    else
        debugPrint("CHYBA: Úl nemá přiřazené ID inventáře!")
    end
end)
