local ActiveParticles = {}

-- Funkce pro spuštění efektu
local function StartBeeParticle(entity)
    if not DoesEntityExist(entity) then return nil end
    
    -- Načtení assetu
    local particleDict = "scr_amb_insects"
    local particleName = "scr_amb_insects_flies" -- Nebo jiný vhodný efekt včel/much
    
    RequestNamedPtfxAsset(particleDict)
    while not HasNamedPtfxAssetLoaded(particleDict) do
        Wait(10)
    end

    UseParticleFxAsset(particleDict)
    -- Spustíme efekt na entitě úlu
    local handle = StartParticleFxLoopedOnEntity(particleName, entity, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 1.0, false, false, false)
    return handle
end

-- Smyčka pro správu efektů (běží na klientovi)
CreateThread(function()
    while true do
        local sleep = 1000
        local playerCoords = GetEntityCoords(PlayerPedId())

        for id, data in pairs(ApiariesClient) do
            if DoesEntityExist(data.entity) then
                local dist = #(playerCoords - data.coords)
                
                -- Efekt zapneme jen pokud je hráč blízko (optimalizace)
                if dist < 15.0 then
                    if not ActiveParticles[id] then
                        ActiveParticles[id] = StartBeeParticle(data.entity)
                    end
                else
                    -- Pokud je daleko, efekt vypneme
                    if ActiveParticles[id] then
                        StopParticleFxLooped(ActiveParticles[id], false)
                        ActiveParticles[id] = nil
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- Cleanup při vypnutí
AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    for id, handle in pairs(ActiveParticles) do
        StopParticleFxLooped(handle, false)
    end
end)