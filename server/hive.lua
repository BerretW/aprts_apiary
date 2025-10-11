-- Globální tabulky pro držený stav
HiveLocks = {}
PlayerWildQueenCooldowns = {}

-- [[ INICIALIZACE ]]
CreateThread(function()
    Wait(1000) -- Počkáme, až se vše načte
    StartSimulationTick()
end)


function LockHive(hiveId, source)
    local identifier = GetIdentifier(source)
    if HiveLocks[hiveId] then
        return false
    end
    HiveLocks[hiveId] = {
        identifier = identifier,
        expires = GetGameTimer() + 120000
    }
    return true
end

function IsHiveLocked(hiveId, source)
    local lock = HiveLocks[hiveId]
    if not lock then
        return false
    end
    if GetGameTimer() > lock.expires then
        UnlockHive(hiveId)
        return false
    end
    return lock.identifier ~= GetIdentifier(source)
end

function UnlockHive(hiveId)
    HiveLocks[hiveId] = nil
end



function LogEvent(hiveId, eventType, payload)
    MySQL.insert('INSERT INTO aprts_bee_events (hive_id, type, payload) VALUES (?, ?, ?)',
        {hiveId, eventType, json.encode(payload)})
end

-- [[ EXPORTY ]]
exports('getApiaryBuffAt', function(coords)
    -- Projdi všechny včelnice a najdi tu, která pokrývá dané souřadnice
    for _, apiary in pairs(Apiaries) do
        local dist = #(vector3(apiary.pos_x, apiary.pos_y, apiary.pos_z) - coords)
        if dist <= apiary.pollination_radius then
            -- Vrať multiplikátor založený např. na počtu úlů nebo zdraví kolonií
            local hiveCount = 0
            for _, hive in pairs(apiary.hives) do
                if hive.substate == 'HEALTHY' then
                    hiveCount = hiveCount + 1
                end
            end
            return 1.0 + (hiveCount * 0.05) -- Příklad: +5% za každý úl
        end
    end
    return 1.0 -- Bez buffu
end)

exports('getHiveInfo', function(hiveId)
    for k, v in pairs(Apiaries) do
        for _, hive in pairs(v.hives) do
            if hive.id == hiveId then
                return hive
            end
        end
    end
    return nil
end)

exports('awardWildQueen', function(playerId, biome)
    -- Tato funkce se volá z externího skriptu
    -- Zjednodušená verze volání interní logiky
    HandleAwardWildQueen(playerId, biome or 'default', nil)
end)
