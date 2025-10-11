local bees_cloud_group = "core"
local bees_cloud_name = "ent_amb_insect_bee_swarm"

local function LoadModel(model)
    local model = GetHashKey(model)
    RequestModel(model)
    while not HasModelLoaded(model) do
        RequestModel(model)
        Citizen.Wait(10)
    end
end

local function spawnProp(prop, coords, h)
    local hash = GetHashKey(prop)
    LoadModel(prop)
    debugPrint('Spawning prop: ' .. prop, ' at coords: ' .. json.encode(coords) .. ' with heading: ' .. h)
    local object = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(object, h)
    SetModelAsNoLongerNeeded(hash)
    PlaceObjectOnGroundProperly(object)
    FreezeEntityPosition(object, true)
    return object
end

local function spawnPed(model, coords)
    debugPrint('Spawning ped: ' .. model)
    model = LoadModel(model)
    local ped = CreatePed(model, coords.x, coords.y, coords.z, 0.0, true, false)
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true)

    PlaceEntityOnGroundProperly(ped)
    SetModelAsNoLongerNeeded(model)
    return ped
end

local function spawnNPC(model, x, y, z)
    local modelHash = LoadModel(model)
    local npc_ped = CreatePed(model, x, y, z, false, false, false, false)
    PlaceEntityOnGroundProperly(npc_ped)
    Citizen.InvokeNative(0x283978A15512B2FE, npc_ped, true)
    print('npc_ped: ' .. npc_ped)
    SetEntityHeading(npc_ped, 0.0)
    SetEntityCanBeDamaged(npc_ped, false)
    SetEntityInvincible(npc_ped, true)
    FreezeEntityPosition(npc_ped, true)
    SetBlockingOfNonTemporaryEvents(npc_ped, true)
    SetEntityCompletelyDisableCollision(npc_ped, false, false)

    Citizen.InvokeNative(0xC163DAC52AC975D3, npc_ped, 6)
    Citizen.InvokeNative(0xC163DAC52AC975D3, npc_ped, 0)
    Citizen.InvokeNative(0xC163DAC52AC975D3, npc_ped, 1)
    Citizen.InvokeNative(0xC163DAC52AC975D3, npc_ped, 2)

    SetModelAsNoLongerNeeded(modelHash)
    return npc_ped
end

Citizen.CreateThread(function()
    while true do
        local pause = 1000
        nearestApiary = nil
        local nearestDist = 1000.0

        local playerPed = PlayerPedId()
        local playerPos = GetEntityCoords(playerPed)
        for _, apiary in pairs(Apiaries) do
            local dist = #(playerPos - apiary.coords)
            if dist < nearestDist then
                nearestDist = dist
                nearestApiary = apiary.id
            end
            if dist < 50.0 then
                debugPrint('Player is near apiary: ' .. apiary.id)
                for v, hive in pairs(apiary.hives) do
                    if not DoesEntityExist(hive.obj) then
                        hive.obj = spawnProp("aprts_prop_014", hive.coords, hive.coords.h)
                    end
                    if Config.UseBeeFX and not hive.swarm and hive.population > 0 then
                        debugPrint('Spawning bee swarm FX for hive: ' .. v)
                        UseParticleFxAsset(bees_cloud_group)
                        hive.swarm = StartParticleFxLoopedAtCoord(bees_cloud_name, hive.coords.x, hive.coords.y,
                            hive.coords.z, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
                    else
                        if hive.swarm and hive.population == 0 then
                            debugPrint('Stopping bee swarm FX for hive: ' .. v)
                            StopParticleFxLooped(hive.swarm, 0)
                            hive.swarm = nil
                        end
                    end
                end
            else
                for v, hive in pairs(apiary.hives) do
                    if DoesEntityExist(hive.obj) then
                        DeleteObject(hive.obj)
                        hive.obj = nil
                    end
                    if Config.UseBeeFX and hive.swarm and hive.swarm ~= 0 then
                        StopParticleFxLooped(hive.swarm, 0)
                        hive.swarm = nil
                    end
                end
            end
        end
        Citizen.Wait(pause)
    end
end)

