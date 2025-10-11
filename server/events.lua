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
            print(('[aprts_bee] Uvolněn zámek na úl %d kvůli odpojení hráče.'):format(hiveId))
        end
    end
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
