AddEventHandler("onClientResourceStart", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    TriggerServerEvent('aprts_apiary:Server:LoadData')
end)

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    debugPrint("Resource stopping, deleting hives...")
    FreezeEntityPosition(PlayerPedId(), false)
    for _, apiary in pairs(Apiaries) do
        for v, hive in pairs(apiary.hives) do
            if DoesEntityExist(hive.obj) then
                DeleteEntity(hive.obj)
            end
            if Config.UseBeeFX and hive.swarm and hive.swarm ~= 0 then
                debugPrint("Deleting bee fx for hive: "..v)
                StopParticleFxLooped(hive.swarm, 0)
                hive.swarm = nil
            end
        end
    end

end)

RegisterNetEvent('aprts_apiary:Client:SyncApiaries')
AddEventHandler('aprts_apiary:Client:SyncApiaries', function(apiaries)
    Apiaries = apiaries
    debugPrint("Sync apiaries: DONE")
end)
