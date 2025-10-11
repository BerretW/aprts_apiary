local DirtyHives = {}
local hiveIds = {}
local currentHiveIndex = 1
local hivesPerTick = 50 -- Zpracuj 50 úlů za tick (upravte podle potřeby)

function AddHiveToSimulation(hiveId)
    for _, id in ipairs(hiveIds) do
        if id == hiveId then
            return
        end -- Už v seznamu je
    end
    table.insert(hiveIds, hiveId)
    debugPrint(('[aprts_bee] Úl %d byl přidán do simulační smyčky.'):format(hiveId))
end

local function getHive(hiveID)
    for _, apiary in pairs(Apiaries) do
        for _, hive in pairs(apiary.hives or {}) do
            if hive.id == hiveID then
                return hive
            end
        end
    end
    return nil
end

function getApiaryID(hiveID)
    for apiaryID, apiary in pairs(Apiaries) do
        for _, hive in pairs(apiary.hives or {}) do
            if hive.id == hiveID then
                return apiaryID
            end
        end
    end
    return nil
end

local function newQueenId()
    return ("Q%08x%04x"):format(math.random(0, 0xffffffff), math.random(0, 0xffff))
end

function StartSimulationTick()
    -- Na začátku naplníme seznam ID úlů
    for _, apiary in pairs(Apiaries) do
        for _, hive in pairs(apiary.hives) do
            table.insert(hiveIds, hive.id)
        end
    end

    CreateThread(function()
        while true do
            Wait(10000) -- Interval mezi zpracováním další části úlů

            SimulateChunkOfHives()

            -- Flushujeme pouze jednou za čas, ne každý malý tick
            if currentHiveIndex > #hiveIds then
                FlushDirtyHives()
                currentHiveIndex = 1 -- Reset cyklu
                debugPrint(('[aprts_bee] Cyklus simulace dokončen. Změny uloženy.'))
            end
        end
    end)
end

local function nowSec()
    return os.time()
end

local function toSecMaybeMs(v)
    if type(v) == "number" then
        return v > 1e12 and math.floor(v / 1000) or v
    elseif type(v) == "string" then
        local y, mo, d, h, mi, s = v:match("^(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+):(%d+)$")
        if y then
            return os.time {
                year = y,
                month = mo,
                day = d,
                hour = h,
                min = mi,
                sec = s
            }
        end
    end
    return nil
end

function SimulateChunkOfHives()
    -- === Lokální helpery jen pro tuto funkci ===
    local function clamp01(x)
        return math.max(0, math.min(1, x or 0))
    end
    local function KillQueen(queen)
        if not queen then
            return
        end
        queen.alive = false
        queen.hive_id = nil
        queen._dirty = true
    end
    local function SpawnNewQueenForHive(hive, geneticsOverride)
        local q = {
            hive_id = hive.id,
            queen_uid = newQueenId(),
            age_days = 0,
            genetics = geneticsOverride or (hive.bee_genetics or {}),
            fertility = 1.0,
            alive = true,
            origin = {
                type = "emergency"
            },
            pedigree = {},
            quality_score = 0
        }
        hive.queen = q
        hive.queen_uid = q.queen_uid
        q._insert = true
        QueensByUID[q.queen_uid] = q
        QueensByHive[hive.id] = q
        return q
    end

    -- === Začátek simulace ===
    local now = nowSec()
    local date = os.date('*t', now)
    local monthConfig = Config.Months[date.month] or {
        cold = false,
        hot = false,
        nectarFactor = 1.0,
        seasonalDiseaseBoost = 0.0
    }

    for i = 1, hivesPerTick do
        if currentHiveIndex > #hiveIds then
            break
        end

        local hiveId = hiveIds[currentHiveIndex]
        local apiaryID = getApiaryID(hiveId)
        local hive = Apiaries[apiaryID] and Apiaries[apiaryID].hives and Apiaries[apiaryID].hives[hiveId] or nil
        currentHiveIndex = currentHiveIndex + 1

        if not hive then
            goto continue
        end
        local apiary = Apiaries[apiaryID]
        if not apiary then
            goto continue
        end

        -- Časové škálování
        local lastTickSec = toSecMaybeMs(hive.last_tick) or now
        local timeDeltaDays = (now - lastTickSec) / 86400
        local days = math.max(timeDeltaDays, Config.Sim.MinDeltaDays or 1 / 24)

        -- Počasí
        local rainAtSec = toSecMaybeMs(hive.rain_updated_at)
        if rainAtSec and hive.rain_state then
            local hoursSinceRain = (now - rainAtSec) / 3600
            hive.rain_state = clamp01(hive.rain_state * ((1 - (Config.RainEWMAAlpha or 0.15)) ^ hoursSinceRain))
        end
        local weatherFactor = 1.0 - clamp01(hive.rain_state)

        -- Genetika
        local defG = Config.DefaultGenetics or {}
        local baseG = (hive.queen and hive.queen.alive and hive.queen.genetics) or hive.bee_genetics or {}
        setmetatable(baseG, {
            __index = defG
        })
        local fert, honeyYield, coldResist, heatResist, diseaseRes, swarmTend, waxYield, queenLifeG = baseG.fertility,
            baseG.honeyYield, baseG.coldResist, baseG.heatResist, baseG.diseaseResist, baseG.swarmTendency,
            baseG.waxYield, baseG.queenLifespan

        -- Stav úlu + defaulty
        hive.population = hive.population or 0
        hive.stores_honey_json = hive.stores_honey_json or '{}' -- ZMĚNA
        hive.stores_wax = hive.stores_wax or 0
        hive.frames_total = hive.frames_total or 10
        hive.frames_capped = hive.frames_capped or 0
        hive.super_count = hive.super_count or 0

        -- Kapacity a vstupy
        local nectarFlowPerDay = (apiary.nectar_baseline or 0) * (monthConfig.nectarFactor or 1) * weatherFactor
        local beesPerFrame = Config.Population.beesPerFrame or 2000
        local superFrames = Config.Supers.framesPerSuper or 9
        local honeyPerCapFrame = Config.Honey.honeyPerCappedFrame or 2.5
        local capacityFrames = hive.frames_total + hive.super_count * superFrames
        local popCapacity = capacityFrames * beesPerFrame

        -- Spotřeba
        local consumptionPerBee = Config.Population.consumptionPerBee or 0
        if monthConfig.cold then
            consumptionPerBee = consumptionPerBee * (1 + (1 - coldResist) * 0.5)
        end
        if monthConfig.hot then
            consumptionPerBee = consumptionPerBee * (1 + (1 - heatResist) * 0.5)
        end

        -- === Stárnutí královny ===
        if hive.queen and hive.queen.alive then
            hive.queen.age_days = (hive.queen.age_days or 0) + days
            hive.queen._dirty = true
            -- ... (zde byla původní logika stárnutí, nechávám ji beze změny) ...
        else
            hive._queenlessAccum = (hive._queenlessAccum or 0) + days
        end

        -- === NOVÁ ČÁST: Nemoci a parazité (Varroa) ===
        local varroaConfig = Config.Diseases and Config.Diseases.varroa or {
            baseGrowthRate = 0.005,
            populationDebuffMax = 0.7,
            honeyDebuffMax = 0.5,
            maxLevel = 1.0
        }
        local seasonalMiteBonus = (monthConfig.hot and 0.5 or (monthConfig.cold and -0.5 or 0))
        local miteGrowthFactor = (varroaConfig.baseGrowthRate * (1 + seasonalMiteBonus)) * (1 - diseaseRes)
        hive.mite_level = math.min(varroaConfig.maxLevel, (hive.mite_level or 0) + (miteGrowthFactor * days))

        local miteDebuffRatio = (hive.mite_level or 0) / varroaConfig.maxLevel
        local populationDebuff = 1.0 - (varroaConfig.populationDebuffMax * miteDebuffRatio)
        local honeyDebuff = 1.0 - (varroaConfig.honeyDebuffMax * miteDebuffRatio)

        if (hive.mite_level or 0) > 0.5 then
            hive.substate = 'DISEASED'
        else
            hive.substate = 'HEALTHY' -- Reset, pokud se hladina sníží
        end
        -- =================================================

        -- === Pokles populace (bez královny, nemoc) ===
        local effectiveFert = fert
        if not hive.queen or not hive.queen.alive then
            effectiveFert = 0.0
            hive.substate = 'QUEENLESS'
            hive.population = hive.population * ((1 - (Config.Population.queenlessDecayPerDay or 0.03)) ^ days)
        end

        -- === ZMĚNA: Spotřeba a produkce medu (více druhů) ===
        local honeyProdFactor = Config.Honey.honeyProductionFactor or 0.00002
        local honeyGain = (hive.population * honeyProdFactor * nectarFlowPerDay * honeyYield) * days * honeyDebuff
        local waxGain = honeyGain * (0.02 * (waxYield / 0.5))
        local consumption = (hive.population * consumptionPerBee) * days
        -- ===============================================
        local honeyStores = json.decode(hive.stores_honey_json) or {}
        local totalHoneyBeforeConsumption = 0
        for _, amount in pairs(honeyStores) do
            totalHoneyBeforeConsumption = totalHoneyBeforeConsumption + amount
        end

        -- Spotřeba (z největší zásoby)
        if totalHoneyBeforeConsumption > 0 then
            local largestStockName, largestStockAmount = nil, -1
            for name, amount in pairs(honeyStores) do
                if amount > largestStockAmount then
                    largestStockAmount = amount;
                    largestStockName = name
                end
            end
            if largestStockName then
                local consumedAmount = math.min(honeyStores[largestStockName], consumption)
                honeyStores[largestStockName] = honeyStores[largestStockName] - consumedAmount
            end
        end

        -- Produkce (rozdělení podle flóry)
        local floraProfile = apiary.flora_profile or {}
        for floraType, influence in pairs(floraProfile) do
            local honeyTypeConfig = Config.HoneyTypes and Config.HoneyTypes[floraType]
            local itemName = honeyTypeConfig and honeyTypeConfig.itemName or Config.honey_item
            honeyStores[itemName] = (honeyStores[itemName] or 0) + (honeyGain * influence)
        end

        hive.stores_honey_json = json.encode(honeyStores)
        hive.stores_wax = math.max(0, hive.stores_wax + waxGain)
        -- =======================================================

        -- Hladovění
        local totalHoneyAfterChanges = 0
        for _, amount in pairs(json.decode(hive.stores_honey_json)) do
            totalHoneyAfterChanges = totalHoneyAfterChanges + amount
        end

        -- Faktor růstu ze zásob (0.0 až 1.0)
        -- Pokud je v úlu alespoň 10 jednotek medu, růst je maximální
        local storeGrowthFactor = math.min(1.0, totalHoneyAfterChanges / 10.0)

        -- Kombinace vnějšího a vnitřního zdroje
        local effectiveNectarForGrowth = math.max(nectarFlowPerDay, storeGrowthFactor * 0.5) -- *0.5 aby růst ze zásob nebyl tak rychlý

        local growthPerDay = (hive.population * (Config.Population.growthFactor or 0) * effectiveNectarForGrowth) *
                                 effectiveFert * populationDebuff
        local growth = growthPerDay * days

        -- Aktualizace populace
        hive.population = math.max(0, hive.population + growth)

        -- Rojení
        if hive.queen and hive.queen.alive and (hive.state == 'GROWTH' or hive.state == 'PEAK') then
            if hive.population > popCapacity then
                local over = hive.population / math.max(1, popCapacity)
                local swarmChance = math.min(0.5, (over - 1.0) * (Config.Swarm.baseChanceScale or 0.3)) * days *
                                        (0.75 + 0.5 * swarmTend)
                if math.random() < swarmChance then
                    hive.population = hive.population * (1 - (Config.Swarm.populationFraction or 0.25))
                    hive.substate = 'SWARMING'
                end
            end
        end

        -- ZMĚNA: Víčkování rámků podle celkového medu
        local framesCapPossible = math.floor(totalHoneyAfterChanges / math.max(0.001, honeyPerCapFrame))
        hive.frames_capped = math.max(0, math.min(capacityFrames, framesCapPossible))

        -- Nouzové přelarvení
        if (not hive.queen or not hive.queen.alive) and (hive._queenlessAccum or 0) >= 3 and hive.population >= 5000 then
            if math.random() < (0.15 * days) then
                SpawnNewQueenForHive(hive)
                hive.substate = 'HEALTHY'
                hive._queenlessAccum = 0
            end
        end

        -- Priorita stavů
        if hive.substate ~= 'QUEENLESS' and hive.substate ~= 'STARVING' and hive.substate ~= 'DISEASED' and
            hive.substate ~= 'SWARMING' then
            hive.substate = 'HEALTHY'
        end

        -- === NOVÁ ČÁST: Výpočet efektivity snůšky (Nectar Balance) ===
        local productionFactors = nectarFlowPerDay * honeyYield * weatherFactor * honeyDebuff
        local breakEvenPoint = (Config.Population.consumptionPerBee or 0.00001) /
                                   (Config.Honey.honeyProductionFactor or 0.00002)

        -- Nectar Balance bude hodnota, která ukazuje, jak moc je úl nad/pod bodem zvratu.
        -- Hodnota > 0: Zisk (např. 0.2 = 20% nad bodem zvratu)
        -- Hodnota < 0: Ztráta (např. -0.1 = 10% pod bodem zvratu)
        -- Hodnota = 0: Přesně na bodu zvratu
        if breakEvenPoint > 0 then
            hive.nectar_balance = (productionFactors / breakEvenPoint) - 1.0
        else
            hive.nectar_balance = 0.0 -- Vyhneme se dělení nulou
        end

        hive.last_tick = now
        MarkHiveAsDirty(hiveId)

        ::continue::
    end
end

function MarkHiveAsDirty(hiveId)
    DirtyHives[hiveId] = true
end

function FlushDirtyHives()
    if not next(DirtyHives) then
        -- debugPrint('[aprts_bee] Žádné změněné úly k uložení.') -- Odkomentuj pro detailní logování
        return
    end

    debugPrint(('[aprts_bee] Ukládání %d změněných úlů do DB...'):format(table.count(DirtyHives)))
    local queries = {}

    for hiveId, _ in pairs(DirtyHives) do
        local apiaryID = getApiaryID(hiveId)
        local hive = Apiaries[apiaryID] and Apiaries[apiaryID].hives and Apiaries[apiaryID].hives[hiveId] or nil
        if hive then
            local lastTickSec = toSecMaybeMs(hive.last_tick) or os.time()

            -- ZDE JE OPRAVA:
            -- Zajistí, že pokud je čas ošetření neplatný nebo 0, pošle se do DB NULL
            local tempTs = hive.last_treatment_at and toSecMaybeMs(hive.last_treatment_at) or nil
            local lastTreatmentTs = (tempTs and tempTs > 0) and tempTs or nil

            table.insert(queries, {
                query = [[UPDATE aprts_bee_hives SET
        state=?, substate=?, population=?, stores_honey_json=?, stores_wax=?,
        frames_total=?, frames_capped=?, super_count=?, disease_progress=?,
        mite_level=?, rain_state=?, last_tick=FROM_UNIXTIME(?), bee_genetics=?, queen_uid=?,
        last_treatment_at=FROM_UNIXTIME(?), nectar_balance=?
        WHERE id = ?]],
                values = {hive.state, hive.substate, math.floor(hive.population or 0), hive.stores_honey_json or '{}',
                          hive.stores_wax or 0, hive.frames_total or 10, hive.frames_capped or 0, hive.super_count or 0,
                          hive.disease_progress or 0, hive.mite_level or 0, hive.rain_state or 0, lastTickSec,
                          hive.bee_genetics and json.encode(hive.bee_genetics) or nil, hive.queen_uid, lastTreatmentTs,
                          hive.nectar_balance or 0, -- <<-- PŘIDANÁ HODNOTA
                hiveId}
            })
        else
            debugPrint(('[aprts_bee] Chyba: Nelze uložit úl %d, protože nebyl nalezen v paměti.'):format(hiveId))
        end
    end

    if #queries > 0 then
        MySQL:transaction_async(queries, function(success)
            if success then
                debugPrint(('[aprts_bee] Uloženo %d změněných úlů do DB.'):format(#queries))
            else
                print(('[aprts_bee] CHYBA při ukládání úlů do DB! Zkontroluj konzoli výše pro detaily.'))
            end
        end)
    end
    DirtyHives = {}
end
