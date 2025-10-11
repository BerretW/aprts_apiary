-- CREATE TABLE `aprts_bee_apiaries` (
--   `id` int(11) NOT NULL AUTO_INCREMENT,
--   `owner_identifier` varchar(64) NOT NULL,
--   `name` varchar(64) DEFAULT NULL,
--   `pos_x` float DEFAULT NULL,
--   `pos_y` float DEFAULT NULL,
--   `pos_z` float DEFAULT NULL,
--   `heading` float DEFAULT NULL,
--   `radius` float NOT NULL DEFAULT 20,
--   `flora_profile` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
--   `nectar_baseline` float NOT NULL,
--   `pollination_radius` float NOT NULL DEFAULT 20,
--   `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
--   PRIMARY KEY (`id`)
-- ) ENGINE=InnoDB;
-- CREATE TABLE IF NOT EXISTS `aprts_bee_hives` (
--   `id` int(11) NOT NULL AUTO_INCREMENT,
--   `apiary_id` int(11) NOT NULL,
--   `hive_label` varchar(32) DEFAULT NULL,
--   `coords` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '{"x":0.0,"y":0.0,"z":0.0,"h":0.0}' CHECK (json_valid(`coords`)),
--   `state` enum('DORMANT','GROWTH','PEAK','DECLINE') NOT NULL DEFAULT 'GROWTH',
--   `substate` enum('HEALTHY','DISEASED','STARVING','SWARMING','QUEENLESS','LOOTED') NOT NULL DEFAULT 'HEALTHY',
--   `queen_uid` varchar(32) DEFAULT NULL,
--   `bee_genetics` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
--   `population` int(11) DEFAULT 10000,
--   `stores_honey` float DEFAULT 0,
--   `stores_wax` float DEFAULT 0,
--   `frames_total` int(11) DEFAULT 10,
--   `frames_capped` int(11) DEFAULT 0,
--   `super_count` int(11) DEFAULT 0,
--   `disease_progress` float DEFAULT 0,
--   `mite_level` float DEFAULT 0,
--   `rain_state` float DEFAULT 0,
--   `rain_updated_at` timestamp NULL DEFAULT NULL,
--   `last_bear_attack` timestamp NULL DEFAULT NULL,
--   `last_tick` timestamp NULL DEFAULT current_timestamp(),
--   PRIMARY KEY (`id`),
--   KEY `apiary_id` (`apiary_id`),
--   CONSTRAINT `aprts_bee_hives_ibfk_1` FOREIGN KEY (`apiary_id`) REFERENCES `aprts_bee_apiaries` (`id`) ON DELETE CASCADE
-- ) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
-- CREATE TABLE `aprts_bee_queens` (
--   `id` int(11) NOT NULL AUTO_INCREMENT,
--   `hive_id` int(11) DEFAULT NULL,
--   `queen_uid` varchar(36) DEFAULT NULL,
--   `age_days` int(11) DEFAULT 0,
--   `genetics` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
--   `fertility` float DEFAULT 1,
--   `alive` tinyint(1) DEFAULT 1,
--   `origin` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
--   `pedigree` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
--   `quality_score` float DEFAULT 0,
--   PRIMARY KEY (`id`),
--   UNIQUE KEY `queen_uid` (`queen_uid`),
--   KEY `hive_id` (`hive_id`),
--   CONSTRAINT `aprts_bee_queens_ibfk_1` FOREIGN KEY (`hive_id`) REFERENCES `aprts_bee_hives` (`id`) ON DELETE SET NULL
-- ) ENGINE=InnoDB;
local loaded = false
AddEventHandler("onResourceStart", function(resource)
    if resource == GetCurrentResourceName() then
        local dataReady = false
        MySQL:execute("SELECT * FROM aprts_bee_apiaries", {}, function(result)
            debugPrint("Loading apiaries...")
            for k, v in pairs(result) do
                v.coords = vector3(v.pos_x, v.pos_y, v.pos_z)
                v.flora_profile = json.decode(v.flora_profile)
                v.hives = {}
                Apiaries[v.id] = v
            end
            dataReady = true
        end)
        while not dataReady do
            Wait(100)
        end
        dataReady = false
        MySQL:execute("SELECT * FROM aprts_bee_hives", {}, function(result)
            debugPrint("Loading hives...")
            for k, v in pairs(result) do
                v.bee_genetics = json.decode(v.bee_genetics)
                v.coords = json.decode(v.coords)
                v.heading = v.coords.h
                if Apiaries[v.apiary_id] then
                    debugPrint(" - Hive " .. v.id .. " loaded into apiary " .. v.apiary_id)
                    Apiaries[v.apiary_id].hives[v.id] = v
                end
            end
            dataReady = true
        end)
        while not dataReady do
            Wait(100)
        end
        dataReady = false

        -- ... ve třetím SELECTu (queens):
        MySQL:execute("SELECT * FROM aprts_bee_queens", {}, function(result)
            debugPrint("Loading queens...")
            QueensByUID = {}
            QueensByHive = {}
            for _, q in pairs(result) do
                q.genetics = json.decode(q.genetics)
                q.origin = json.decode(q.origin)
                q.pedigree = json.decode(q.pedigree)
                q.alive = (q.alive == 1 or q.alive == true)

                QueensByUID[q.queen_uid] = q
                if q.hive_id then
                    QueensByHive[q.hive_id] = q
                    for apiaryId, apiary in pairs(Apiaries) do
                        local hive = apiary.hives[q.hive_id]
                        if hive then
                            debugPrint(" - Queen " .. q.queen_uid .. " loaded into hive " .. q.hive_id)
                            hive.queen = q
                            hive.queen_uid = q.queen_uid -- sync
                        end
                    end
                end
            end
            dataReady = true
        end)
        while not dataReady do
            Wait(100)
        end
        LOG("0", "APIARIES_LOADED", "All apiaries and hives loaded")
        loaded = true
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        print('[aprts_apiary] Resource is stopping, forcing a flush of dirty hives...')
        FlushDirtyHives()
        print('[aprts_apiary] Flush complete.')
    end
end)

RegisterServerEvent("aprts_apiary:Server:LoadData")
AddEventHandler("aprts_apiary:Server:LoadData", function()
    local _source = source
    while not loaded do
        Wait(100)
    end
    TriggerClientEvent("aprts_apiary:Client:SyncApiaries", _source, Apiaries)
    LOG(_source, "APIARIES_SYNCED", "All apiaries synced to " .. _source)
end)

-- Přidejte event handler pro odpojení hráče
AddEventHandler('playerDropped', function(reason)
    local src = source
    local identifier = GetIdentifier(src)
    for hiveId, lock in pairs(HiveLocks) do
        if lock.identifier == identifier then
            UnlockHive(hiveId)
            print(('[aprts_apiary] Uvolněn zámek na úl %d kvůli odpojení hráče.'):format(hiveId))
        end
    end
end)

RegisterServerEvent('aprts_apiary:Server:TreatHive')
AddEventHandler('aprts_apiary:Server:TreatHive', function(hiveId, treatmentItemName)
    local src = source
    local player = Player(src)
    local apiary = getApiaryID(hiveId)
    local hive = Apiaries[apiary] and Apiaries[apiary].hives[hiveId]

    if not hive or IsHiveLocked(hiveId, src) then
        return
    end

    local treatment = Config.Treatments[treatmentItemName]
    if not treatment then
        return
    end

    -- Zkontroluj cooldown
    if hive.last_treatment_at then
        local cooldownEnd = toSecMaybeMs(hive.last_treatment_at) + (treatment.cooldownHours * 3600)
        if os.time() < cooldownEnd then
            Notify(src, 'Tento úl byl nedávno ošetřen. Počkej.', 'error')
            return
        end
    end

    -- Zkontroluj a odeber item
    -- Tady přijde logika pro tvůj inventář (např. exports.vorp_inventory:removeItem)
    -- Příklad: if exports.vorp_inventory:hasItem(src, treatmentItemName, 1) then ...

    -- Aplikuj efekt
    hive.mite_level = math.max(0, hive.mite_level - treatment.effectiveness)
    hive.last_treatment_at = os.date('%Y-%m-%d %H:%M:%S', os.time())
    MarkHiveAsDirty(hiveId) -- Označ pro uložení

    Notify(src, ('Úspěšně jsi aplikoval "%s". Hladina kleštíka klesla.'):format(treatment.name), 'success')
end)

RegisterServerEvent('aprts_apiary:Server:GraftQueenCell')
AddEventHandler('aprts_apiary:Server:GraftQueenCell', function(hiveId)
    local src = source
    local apiary = getApiaryID(hiveId)
    local hive = Apiaries[apiary] and Apiaries[apiary].hives[hiveId]

    if not hive or not hive.queen or not hive.queen.alive then
        Notify(src, 'Tento úl nemá plodící královnu.', 'error')
        return
    end

    if math.random() <= Config.Breeding.graftingSuccessChance then
        local motherGenetics = hive.queen.genetics
        -- Vytvoř item 'queen_cell_grafted' s metadaty
        -- Příklad: exports.vorp_inventory:addItem(src, 'queen_cell_grafted', 1, { genetics = motherGenetics })
        Notify(src, 'Podařilo se ti odebrat matečník s larvou!', 'success')
    else
        Notify(src, 'Přelarvení se nepovedlo, larva byla poškozena.', 'error')
    end
end)

-- Tento event se zavolá, když hráč do oplodňáčku vloží 'queen_virgin' a 'bee_drone'
RegisterServerEvent('aprts_apiary:Server:StartMatingFlight')
AddEventHandler('aprts_apiary:Server:StartMatingFlight', function(matingBoxData)
    -- matingBoxData by obsahovalo: { virginQueenMetadata, droneMetadata }
    local src = source

    -- Zkontroluj počasí, denní dobu atd.
    -- ...

    if math.random() <= Config.Breeding.matingFlightSuccessChance then
        local motherGenetics = matingBoxData.virginQueenMetadata.genetics
        -- Zjednodušení: předpokládáme, že trubci mají stejnou genetiku jako úl, ze kterého pochází
        local droneGenetics = matingBoxData.droneMetadata.genetics

        local newGenetics = {}
        -- Smíchej genetiku
        for gene, motherValue in pairs(motherGenetics) do
            local droneValue = droneGenetics[gene] or Config.DefaultGenetics[gene]
            local inheritedValue = (motherValue * Config.Breeding.inheritanceFactor) +
                                       (droneValue * (1 - Config.Breeding.inheritanceFactor))
            -- Přidej mutaci
            local mutation = (math.random() * 2 - 1) * Config.Breeding.mutationFactor
            newGenetics[gene] = math.max(0, math.min(1, inheritedValue + mutation))
        end

        -- Odeber 'queen_virgin' a 'bee_drone'
        -- Přidej novou královnu 'bee_queen' s vypočítanou genetikou v metadatech
        -- Příklad: exports.vorp_inventory:addItem(src, Config.queen_item, 1, { genetics = newGenetics })

        Notify(src, 'Snubní let byl úspěšný! Máš novou, oplozenou královnu.', 'success')
    else
        -- Odeber 'queen_virgin', protože se nevrátila
        Notify(src, 'Královna se ze snubního letu nevrátila.', 'error')
    end
end)

-- Registruj event, který se zavolá, když hráč použije item na úl
RegisterServerEvent('aprts_apiary:Server:AddPopulation')
AddEventHandler('aprts_apiary:Server:AddPopulation', function(hiveId)
    local src = source
    local identifier = GetIdentifier(src)
    local apiary = getApiaryID(hiveId)
    local hive = Apiaries[apiary] and Apiaries[apiary].hives[hiveId]

    if not hive or IsHiveLocked(hiveId, src) then
        Notify(src, 'Nelze interagovat s tímto úlem.', 'error')
        return
    end

    local beeItemName = Config.bee_item or "bee_drone"
    local amountNeeded = 1 -- Kolik itemů odebereme

    -- 1. Ověření itemu a odebrání (Zde použij API tvého inventáře)
    -- PŘÍKLAD:
    local hasItem = exports.vorp_inventory:hasItem(src, beeItemName, amountNeeded)
    if not hasItem then
        Notify(src, 'Nemáš dostatek včel dělnic k vložení do úlu.', 'error')
        return
    end
    -- exports.vorp_inventory:removeItem(src, beeItemName, amountNeeded) -- Odebrat item

    -- 2. Získání startovací populace
    local startPop = Config.starter_population or 5000

    -- 3. Aplikace populace
    hive.population = (hive.population or 0) + startPop

    -- 4. Změna stavu úlu, pokud byl beznadějný (např. populace 0)
    if hive.substate == 'STARVING' or hive.substate == 'QUEENLESS' or hive.population > 0 then
        -- Pokud má královnu, resetujeme queenless stav, i když je slabá
        if hive.queen and hive.queen.alive then
            hive.substate = 'HEALTHY'
            hive._queenlessAccum = 0
        end
    end

    MarkHiveAsDirty(hiveId)

    Notify(src, ('Do úlu byla vložena populace %d včel. Kolonie se začíná rozvíjet.'):format(startPop), 'success')
end)

-- AddEventHandler("vorp_inventory:useItem")
-- RegisterServerEvent("vorp_inventory:useItem", function(data)
--     local _source = source
--     local itemName = data.item
--     exports.vorp_inventory:getItemByMainId(_source, data.id, function(data)
--         if data == nil then
--             return
--         end
--         local metadata = data.metadata
--         if metadata then

--         end
--     end)
-- end)

-- RegisterServerEvent("aprts_vzor:Server:log", function(eventName, playerMessage)
--     local _source = source
--     if _source then
--         local coords = GetEntityCoords(GetPlayerPed(_source))
--         local charID = Player(_source).state.Character.CharId

--         local playerName = Player(_source).state.Character.FirstName .. " " .. Player(_source).state.Character.LastName
--         local text = Player(_source).state.Character.CharId .. "/" .. playerName .. ": "
--         lib.logger(_source, 'eventName', text, "charId:" .. charID,
--             "coords: " .. coords.x .. " " .. coords.y .. " " .. coords.z)
--     end
-- end)
