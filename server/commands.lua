function IsPlayerAdmin(source)
    return Player(source).state.Character.Group == 'admin'
end

RegisterCommand('bee_createapiary', function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        print('[aprts_apiary] Neoprávněný přístup k příkazu /bee_createapiary od hráče ID: ' .. source)
        return
    end
    local name = args[1] or "Moje včelnice"
    local playerPed = GetPlayerPed(source)
    local coords = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)

    -- Výchozí profil flóry (můžete upravit)
    local floraProfile = {
        clover = 0.8,
        wildflower = 0.6,
        tree_sap = 0.2,
        orange = 0.4,
        lavender = 0.5,
        cactus = 0.1

    }

    local result = MySQL:insert_async([[
        INSERT INTO aprts_bee_apiaries (owner_identifier, name, pos_x, pos_y, pos_z, heading, flora_profile, nectar_baseline, pollination_radius)
        VALUES (?, ?, ?, ?, ?, ?, ?, 1.0, 20.0)
    ]], {GetIdentifier(source), name, coords.x, coords.y, coords.z, heading, json.encode(floraProfile)})
    print(json.encode(result, {
        indent = true
    }))
    if result then
        local apiaryId = result
        Apiaries[apiaryId] = {
            id = apiaryId,
            owner_identifier = GetIdentifier(source),
            name = name,
            pos_x = coords.x,
            pos_y = coords.y,
            pos_z = coords.z,
            heading = heading,
            flora_profile = floraProfile,
            nectar_baseline = 1.0,
            pollination_radius = 20.0
        }
        Notify(source, ('Vytvořena včelnice "%s" s ID: %d'):format(name, apiaryId), 'success')
    else
        Notify(source, 'Nepodařilo se vytvořit včelnici v DB.', 'error')
    end
end, false)

RegisterCommand('bee_createhive', function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        return
    end
    local apiaryId = tonumber(args[1])
    local playerPed = GetPlayerPed(source)
    local coords = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)
    if not apiaryId or not Apiaries[apiaryId] then
        return Notify(source, 'Neplatné ID včelnice. Použití: /bee_createhive [id_včelnice]', 'error')
    end

    local result = MySQL:insert_async([[
        INSERT INTO aprts_bee_hives (apiary_id, hive_label,coords) VALUES (?, ?, ?)
    ]], {apiaryId, 'Nový úl', json.encode({
        x = coords.x,
        y = coords.y,
        z = coords.z,
        h = heading
    })})

    if result then
        local hiveId = result
        -- Načteme nově vytvořený úl z DB, abychom měli všechna výchozí data
        local hiveData = MySQL:query_async('SELECT * FROM aprts_bee_hives WHERE id = ?', {hiveId})
        if hiveData and hiveData[1] then
            Apiaries[apiaryId].hives[hiveId] = hiveData[1]
            Apiaries[apiaryId].hives[hiveId].bee_genetics = nil
            AddHiveToSimulation(hiveId) -- <-- PŘIDAT TENTO ŘÁDEK
            Notify(source, ('Vytvořen nový úl s ID: %d ve včelnici %d'):format(hiveId, apiaryId), 'success')
        end
    else
        Notify(source, 'Nepodařilo se vytvořit úl v DB.', 'error')
    end
end, false)
