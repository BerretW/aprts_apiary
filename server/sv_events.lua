-----------------------------------------------------------------------
-- ITEMS USABLE
-----------------------------------------------------------------------

exports.vorp_inventory:registerUsableItem(Config.Items.HiveSmall, function(data)
    local _source = data.source
    if VORP_INV:subItem(_source, Config.Items.HiveSmall, 1) then
        CreateNewApiary(_source, "small")
    end
end)

exports.vorp_inventory:registerUsableItem("bee_microscope", function(data)
    local _source = data.source
    local queenItem = exports.vorp_inventory:getItem(_source, Config.Items.Queen)
    local targetQueen = nil
    
    if queenItem and type(queenItem) == "table" and #queenItem > 0 then
        targetQueen = queenItem[1]
    elseif queenItem and queenItem.count > 0 then
        targetQueen = queenItem
    end
    
    if targetQueen then
        local genes = targetQueen.metadata.genetics
        if not genes then
            -- Pozor: Genetics musí být dostupné
            genes = Genetics.GenerateRandomGenetics()
        end
        TriggerClientEvent("bees:openMicroscopeClient", _source, genes)
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Mikroskop", "Nemáš žádnou královnu k analýze!", "menu_textures", "cross", 4000)
    end
end)

exports.vorp_inventory:registerUsableItem(Config.Items.Smoker, function(data)
    TriggerClientEvent("bees:useSmokerClient", data.source)
end)

-----------------------------------------------------------------------
-- NETWORK EVENTS
-----------------------------------------------------------------------

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

            apiary.hives[newId] = CreateHiveTable(newId, "small", randomInvId)

            RegisterHiveInventory(randomInvId, "Úl " .. apiaryId .. " - #" .. newId)
            SaveApiaryToDB(apiaryId, false)

            TriggerClientEvent("bees:updateHiveCount", -1, apiaryId, newId)
            TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Přidán úl #" .. newId, "generic_textures", "tick", 4000)
            
            RefreshClientMenu(_source, apiaryId)
        end
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Chyba", "Nemáš položku úlu!", "menu_textures", "cross", 4000)
    end
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
    local apiary = Apiaries[apiaryId]
    local targetHiveId = tonumber(hiveId)
    local hive = apiary and apiary.hives[targetHiveId]

    if not hive then return end

    if exports.vorp_inventory:subItem(_source, Config.Items.Medicine, 1) then
        hive.stats.disease = nil
        hive.stats.health = hive.stats.health + 20
        if hive.stats.health > 100 then hive.stats.health = 100 end
        
        AddHiveLog(apiaryId, targetHiveId, "Podán lék proti roztočům.")
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Vyléčeno.", "generic_textures", "tick", 4000)
        SaveApiaryToDB(apiaryId, false)
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
        if hive.stats.population < 50 then
            hive.stats.population = 200
        end
        AddHiveLog(apiaryId, hiveId, "Vložena nová královna.")
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
    
    local aggression = 50 
    if hive.queenGenetics and hive.queenGenetics.aggression then
        aggression = hive.queenGenetics.aggression
    end

    local stingChance = aggression 
    if isCalmed then stingChance = stingChance / 5 end
    if hive.stats.population < 100 or not hive.hasQueen then stingChance = 0 end

    if math.random(0, 100) < stingChance then
        TriggerClientEvent("bees:clientStung", _source)
        TriggerClientEvent("vorp:NotifyLeft", _source, "Au!", "Dostal jsi žihadlo!", "menu_textures", "cross", 4000)
    end

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
        AddHiveLog(apiaryId, hiveId, "Vložen nový rámek.")
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

        local quality = 50
        if hive.queenGenetics and hive.queenGenetics.productivity then
            quality = hive.queenGenetics.productivity
        end
        
        local metadata = {
            description = "Kvalita včelstva: " .. quality .. "%",
            quality = quality
        }

        VORP_INV:addItem(_source, Config.Items.FrameFull, 1, metadata)
        AddHiveLog(apiaryId, hiveId, "Sklizen plný medový rámek.")
        
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

RegisterServerEvent("bees:removeQueen")
AddEventHandler("bees:removeQueen", function(apiaryId, hiveId)
    local _source = source
    local apiary = Apiaries[apiaryId]
    if not apiary then return end
    
    local targetHiveId = tonumber(hiveId)
    local hive = apiary.hives[targetHiveId]

    if not hive.hasQueen then
        TriggerClientEvent("vorp:NotifyLeft", _source, "Chyba", "V úlu není královna.", "menu_textures", "cross", 4000)
        return
    end

    local currentGenes = hive.queenGenetics
    local metadata = {
        label = "Včelí Královna",
        genetics = currentGenes,
        description = string.format("Gen: %d | Kvalita: %d", currentGenes.generation or 1, currentGenes.productivity or 50)
    }

   if exports.vorp_inventory:canCarryItem(_source, Config.Items.Queen, 1) then
        exports.vorp_inventory:addItem(_source, Config.Items.Queen, 1, metadata)
        hive.hasQueen = false
        hive.queenGenetics = {} 
        
        AddHiveLog(apiaryId, targetHiveId, "Královna byla vyjmuta včelařem.")
        TriggerClientEvent("vorp:NotifyLeft", _source, "Včelařství", "Královna vyjmuta.", "generic_textures", "tick", 4000)
        
        SaveApiaryToDB(apiaryId, false)
        RefreshClientMenu(_source, apiaryId)
    else
        TriggerClientEvent("vorp:NotifyLeft", _source, "Inventář", "Máš plný inventář!", "menu_textures", "cross", 4000)
    end
end)