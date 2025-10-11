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
    debugPrint(('[aprts_apiary] Úl %d byl přidán do simulační smyčky.'):format(hiveId))
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

local function getApiaryID(hiveID)
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
            Wait(10000)
            local startTime = GetGameTimer()

            SimulateChunkOfHives() -- Nová funkce

            -- Flushujeme pouze jednou za čas, ne každý malý tick
            if currentHiveIndex > #hiveIds then
                FlushDirtyHives()
                currentHiveIndex = 1 -- Reset
                debugPrint(('[aprts_apiary] Cyklus simulace dokončen. Změny uloženy.'))
            end

            local endTime = GetGameTimer()
            -- debugPrint(('[aprts_apiary] Tick části úlů dokončen za %d ms.'):format(endTime - startTime))
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
    local function newQueenId()
        return ("Q%08x%04x"):format(math.random(0, 0xffffffff), math.random(0, 0xffff))
    end
    -- označit královnu jako mrtvou a odpojit od úlu (ne mažeme řádek)
    local function KillQueen(queen, now)
        if not queen then
            return
        end
        queen.alive = false
        queen.hive_id = nil
        queen._dirty = true
    end

    -- připojit královnu k úlu
    local function AttachQueenToHive(queen, hive)
        queen.hive_id = hive.id
        queen.alive = true
        hive.queen = queen
        hive.queen_uid = queen.queen_uid
        queen._dirty = true
    end

    -- vytvořit novou královnu (nouzové přelarvení)
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
        q._insert = true -- nutné pro INSERT
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
            debugPrint(('[aprts_apiary] Varování: Úl s ID %d nebyl nalezen v paměti. Přeskakuji.'):format(hiveId))
            goto continue
        end

        local apiary = Apiaries[apiaryID]
        if not apiary then
            debugPrint(('[aprts_apiary] Varování: Úl %d nemá platný včelín (ID: %s). Přeskakuji.'):format(hiveId,
                tostring(hive.apiary_id)))
            goto continue
        end

        -- Časové škálování (tick-agnostic)
        local lastTickSec = toSecMaybeMs(hive.last_tick) or now
        local timeDeltaDays = (now - lastTickSec) / 86400
        local days = math.max(timeDeltaDays, Config.Sim.MinDeltaDays or 1 / 24) -- min. 1h

        -- Počasí (EWMA vyprchávání deště)
        local rainAtSec = toSecMaybeMs(hive.rain_updated_at)
        if rainAtSec and hive.rain_state then
            local hoursSinceRain = (now - rainAtSec) / 3600
            local alpha = Config.RainEWMAAlpha or 0.15
            hive.rain_state = clamp01(hive.rain_state * ((1 - alpha) ^ hoursSinceRain))
        end
        local weatherFactor = 1.0 - clamp01(hive.rain_state)

        -- Genetika: preferuj královnu, fallback hive.genetics -> Config.DefaultGenetics
        local defG = Config.DefaultGenetics or {}
        local baseG = (hive.queen and hive.queen.alive and hive.queen.genetics) or hive.bee_genetics or {}
        setmetatable(baseG, {
            __index = defG
        })

        local fert = baseG.fertility
        local honeyYield = baseG.honeyYield
        local coldResist = baseG.coldResist
        local heatResist = baseG.heatResist
        local diseaseRes = baseG.diseaseResist
        local swarmTend = baseG.swarmTendency or 0.5
        local waxYield = baseG.waxYield or 0.5
        local queenLifeG = baseG.queenLifespan or 0.5

        -- Stav úlu + defaulty
        hive.population = hive.population or 0
        hive.stores_honey = hive.stores_honey or 0
        hive.stores_wax = hive.stores_wax or 0
        hive.frames_total = hive.frames_total or 10
        hive.frames_capped = hive.frames_capped or 0
        hive.super_count = hive.super_count or 0
        hive.state = hive.state or 'GROWTH'
        hive.substate = hive.substate or 'HEALTHY'

        -- Kapacity a vstupy
        local nectarFlowPerDay = (apiary.nectar_baseline or 0) * (monthConfig.nectarFactor or 1) * weatherFactor
        local beesPerFrame = Config.Population.beesPerFrame or 2000
        local superFrames = Config.Supers.framesPerSuper or 9
        local honeyPerCapFrame = Config.Honey.honeyPerCappedFrame or 2.5
        local capacityFrames = hive.frames_total + hive.super_count * superFrames
        local popCapacity = capacityFrames * beesPerFrame

        -- Sezónní bias spotřeby
        local consumptionPerBee = Config.Population.consumptionPerBee or 0
        if monthConfig.cold and (heatResist > coldResist) then
            consumptionPerBee = consumptionPerBee * (1 + (heatResist - coldResist))
        elseif monthConfig.hot and (coldResist > heatResist) then
            consumptionPerBee = consumptionPerBee * (1 + (coldResist - heatResist))
        end

        -- === Stárnutí královny (aging) a potenciální smrt ===
        if hive.queen and hive.queen.alive then
            hive.queen.age_days = (hive.queen.age_days or 0) + days
            hive.queen._dirty = true

            local baseLife = (Config.Queen and Config.Queen.baseLifespanDays) or 60
            local lifeTarget = baseLife * queenLifeG
            local senStartFrac = (Config.Queen and Config.Queen.senescenceStartFrac) or 0.8
            local deathAtEnd = (Config.Queen and Config.Queen.deathChanceAtEnd) or 0.05

            local ageFrac = lifeTarget > 0 and math.min(1, (hive.queen.age_days or 0) / lifeTarget) or 1
            if ageFrac >= senStartFrac then
                local t = (ageFrac - senStartFrac) / math.max(1e-6, (1 - senStartFrac))
                fert = fert * (1 - 0.5 * t) -- plodnost padá až o 50 %
            end

            local deathChancePerDay
            if ageFrac < senStartFrac then
                deathChancePerDay = 0.001
            else
                local t = (ageFrac - senStartFrac) / math.max(1e-6, (1 - senStartFrac))
                deathChancePerDay = 0.001 + t * (deathAtEnd - 0.001)
            end

            if math.random() < (deathChancePerDay * days) then
                -- královna zemřela → odpoj a označ
                KillQueen(hive.queen)
                QueensByHive[hive.id] = nil
                hive.queen = nil
                hive.queen_uid = nil
                hive.substate = 'QUEENLESS'
                -- akumuluj queenless dobu
                hive._queenlessAccum = (hive._queenlessAccum or 0) + days
            else
                -- reset queenless akumulátoru, pokud žije
                hive._queenlessAccum = 0
            end
        else
            -- bez královny akumulujeme queenlessDays
            hive._queenlessAccum = (hive._queenlessAccum or 0) + days
        end

        -- === Bez královny: pokles populace (žádný růst) ===
        local baseGrowthFactor = Config.Population.growthFactor or 0
        local queenlessDecayPerDay = Config.Population.queenlessDecayPerDay or 0.03
        local effectiveFert = fert
        if not hive.queen or not hive.queen.alive then
            effectiveFert = 0.0
            hive.substate = 'QUEENLESS'
            hive.population = hive.population * ((1 - queenlessDecayPerDay) ^ days)
        end

        -- === Nemoci: riziko roste se sezónou, dopad na populaci ===
        local baseRiskPerDay = 0.01 + ((monthConfig.seasonalDiseaseBoost or 0) * 0.2)
        local triggerRisk = baseRiskPerDay * days
        if math.random() < triggerRisk * (1 - diseaseRes) then
            hive.mite_level = math.min(1.0, (hive.mite_level or 0) + 0.05)
        end
        if (hive.mite_level or 0) > 0.5 then
            local diseaseDecayPerDay = Config.Population.diseaseDecayPerDay or 0.02
            hive.population = hive.population * ((1 - diseaseDecayPerDay) ^ days)
            hive.substate = 'DISEASED'
        end

        -- === Růst populace (jen s královnou) ===
        local growthPerDay = (hive.population * baseGrowthFactor * nectarFlowPerDay) * effectiveFert
        local growth = growthPerDay * days

        -- === Spotřeba a produkce ===
        local consumption = (hive.population * consumptionPerBee) * days
        local honeyGain = (nectarFlowPerDay * honeyYield) * days
        local waxGain = honeyGain * (0.02 * (waxYield / 0.5)) -- cca 2 % při waxYield=0.5

        hive.stores_honey = math.max(0, hive.stores_honey + honeyGain - consumption)
        hive.stores_wax = math.max(0, hive.stores_wax + waxGain)

        -- Hladovění → pokles populace
        if hive.stores_honey <= 0 and (honeyGain - consumption) < 0 then
            local starvationDecayPerDay = Config.Population.starvationDecayPerDay or 0.05
            hive.population = hive.population * ((1 - starvationDecayPerDay) ^ days)
            hive.substate = 'STARVING'
        end

        -- Aktualizace populace (po poklesech + růstu)
        hive.population = math.max(0, hive.population + growth)

        -- Kapacita + rojení (jen s královnou, v růstových stavech)
        if hive.queen and hive.queen.alive and (hive.state == 'GROWTH' or hive.state == 'PEAK') then
            if hive.population > popCapacity then
                local over = hive.population / math.max(1, popCapacity)
                local swarmChance = math.min(0.5, (over - 1.0) * (Config.Swarm.baseChanceScale or 0.3)) * days
                swarmChance = swarmChance * (0.75 + 0.5 * swarmTend) -- zohledni genetiku
                if math.random() < swarmChance then
                    local swarmFrac = Config.Swarm.populationFraction or 0.25
                    hive.population = hive.population * (1 - swarmFrac)
                    hive.substate = 'SWARMING'
                end
            end
        end

        -- Capping rámků podle zásob
        local framesCapPossible = math.floor(hive.stores_honey / math.max(0.001, honeyPerCapFrame))
        hive.frames_capped = math.max(0, math.min(capacityFrames, framesCapPossible))

        -- Nouzové přelarvení (pokud je úl bez královny dost dlouho a má zdroje)
        if not hive.queen or not hive.queen.alive then
            local minDaysQueenless = (Config.Queen and Config.Queen.requeenMinDays) or 3
            local requeenBaseChance = (Config.Queen and Config.Queen.emergencyRequeenChancePerDay) or 0.15
            local minPopForRequeen = (Config.Queen and Config.Queen.minPopForRequeen) or 5000
            local nectarNeedFactor = (Config.Queen and Config.Queen.nectarNeedFactor) or 0.5

            local queenlessDays = hive._queenlessAccum or 0
            local resourceFactor = 1.0
            if nectarFlowPerDay < nectarNeedFactor then
                resourceFactor = math.max(0.25, nectarFlowPerDay / math.max(1e-6, nectarNeedFactor))
            end

            if queenlessDays >= minDaysQueenless and hive.population >= minPopForRequeen then
                local chance = requeenBaseChance * resourceFactor * days
                if math.random() < chance then
                    local q = SpawnNewQueenForHive(hive) -- INSERT provede flush
                    hive.substate = 'HEALTHY'
                    hive._queenlessAccum = 0
                    -- refresh genetických defaultů do growthu příště (teď už má queen)
                end
            end
        end

        -- Pokud není jiný problém, nastav HEALTHY
        if hive.substate ~= 'QUEENLESS' and hive.substate ~= 'STARVING' and hive.substate ~= 'DISEASED' and
            hive.substate ~= 'SWARMING' then
            hive.substate = 'HEALTHY'
        end

        -- Ulož aktuální timestamp (sekundy)
        hive.last_tick = now
        MarkHiveAsDirty(hiveId)

        ::continue::
    end
end

function MarkHiveAsDirty(hiveId)
    debugPrint(json.encode(getHive(hiveId), {
        indent = true
    }))
    DirtyHives[hiveId] = true
end

function FlushDirtyHives()
    debugPrint(('[aprts_apiary] Ukládání %d změněných úlů do DB...'):format(#DirtyHives))
    local queries = {}

    for hiveId, _ in pairs(DirtyHives) do
        local apiaryID = getApiaryID(hiveId)
        local hive = Apiaries[apiaryID] and Apiaries[apiaryID].hives and Apiaries[apiaryID].hives[hiveId] or nil
        if hive then
            -- jistota: převod na sekundy (kdyby se tam dostaly ms)
            local lastTickSec
            if type(hive.last_tick) == "number" then
                lastTickSec = (hive.last_tick > 1e12) and math.floor(hive.last_tick / 1000) or hive.last_tick
            end

            local beeGeneticsJson = hive.bee_genetics and json.encode(hive.bee_genetics) or nil

            table.insert(queries, {
                query = [[UPDATE aprts_bee_hives SET
                    state=?, substate=?, population=?, stores_honey=?, stores_wax=?,
                    frames_total=?, frames_capped=?, super_count=?, disease_progress=?,
                    mite_level=?, rain_state=?, last_tick=FROM_UNIXTIME(?), bee_genetics=?, queen_uid=?
                    WHERE id = ?]],
                values = {hive.state, hive.substate, math.floor(hive.population or 0), hive.stores_honey or 0,
                          hive.stores_wax or 0, hive.frames_total or 10, hive.frames_capped or 0, hive.super_count or 0,
                          hive.disease_progress or 0, hive.mite_level or 0, hive.rain_state or 0,
                          lastTickSec or math.floor(getTimeStamp() / 1000), beeGeneticsJson, hive.queen_uid, hiveId}
            })
        else
            debugPrint(('[aprts_apiary] Chyba: Nelze uložit úl %d, protože nebyl nalezen v paměti.'):format(hiveId))
        end
    end

    if #queries > 0 then
        MySQL:transaction_async(queries)
        debugPrint(('[aprts_apiary] Uloženo %d změněných úlů do DB.'):format(#queries))
    else
        debugPrint('[aprts_apiary] Žádné změněné úly k uložení.')
    end
    DirtyHives = {}
end

