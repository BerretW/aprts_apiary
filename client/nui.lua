local isMenuOpen = false

-- Funkce pro otevření menu
RegisterNetEvent("bees:openApiaryMenu", function(apiaryId, hivesData, maxHives)
    if isMenuOpen then return end
    isMenuOpen = true
    SetNuiFocus(true, true)
    
    SendNUIMessage({
        action = "open",
        apiaryId = apiaryId,
        hives = hivesData,
        maxHives = maxHives,
        items = Config.Items -- Posíláme názvy itemů pro kontrolu v JS (volitelné)
    })
end)

-- Funkce pro zavření menu (volaná z JS nebo ESC)
RegisterNUICallback("close", function(data, cb)
    isMenuOpen = false
    SetNuiFocus(false, false)
    cb("ok")
end)

-- Callbacky pro akce tlačítek v menu

RegisterNUICallback("openInventory", function(data, cb)
    -- Zavřeme NUI, aby se mohl otevřít inventář
    isMenuOpen = false
    SetNuiFocus(false, false)
    TriggerServerEvent("bees:openHive", data.apiaryId, data.hiveId)
    cb("ok")
end)

RegisterNUICallback("insertQueen", function(data, cb)
    -- Kontrola itemu na straně klienta pro rychlou odezvu, ale validace je na serveru
    local inventory = exports.vorp_inventory:getInventoryItems()
    local QueenItem = false
    for _, item in pairs(inventory) do
        if item.name == Config.Items.Queen and item.count > 0 then
            QueenItem = item
            break
        end
    end

    if QueenItem then
        TriggerServerEvent("bees:insertQueen", data.apiaryId, data.hiveId, QueenItem)
        -- Pošleme zprávu zpět do NUI pro refresh dat (server pošle update)
    else
        TriggerEvent("vorp:NotifyLeft", "Včelařství", "Nemáš královnu!", "generic_textures", "cross", 3000)
    end
    cb("ok")
end)

RegisterNUICallback("harvest", function(data, cb)
    TriggerServerEvent("bees:harvestFrame", data.apiaryId, data.hiveId)
    cb("ok")
end)

RegisterNUICallback("cure", function(data, cb)
    TriggerServerEvent("bees:applyMedicine", data.apiaryId, data.hiveId)
    cb("ok")
end)

RegisterNUICallback("build", function(data, cb)
    TriggerServerEvent("bees:addHive", data.apiaryId)
    cb("ok")
end)

-- Aktualizace dat v otevřeném menu (pokud hráč něco udělá)
RegisterNetEvent("bees:updateMenuData", function(hivesData)
    if isMenuOpen then
        SendNUIMessage({
            action = "update",
            hives = hivesData
        })
    end
end)