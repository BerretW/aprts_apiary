-- aprts_bee/refactor_fixed.lua
-- Refaktor + opravy logiky (catch-up cap, fallback flóry, iterativní spotřeba + hlad,
-- sjednocený nectar_balance, spodní práh počasí). Veřejné API beze změny.

local DirtyHives   = {}
local hiveIds      = {}
local currentHiveIndex = 1
local hivesPerTick = 50 -- kolik úlů zpracovat za jeden tick

---------------------------------------------------------------------
-- Pomocné funkce a utilitky
---------------------------------------------------------------------
local function debugf(fmt, ...) if debugPrint then debugPrint(fmt:format(...)) end end
local function nowSec() return os.time() end

local function clamp01(x)
  return math.max(0, math.min(1, x or 0))
end

local function toSecMaybeMs(v)
  if type(v) == "number" then
    return v > 1e12 and math.floor(v / 1000) or v
  elseif type(v) == "string" then
    local y, mo, d, h, mi, s = v:match("^(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+):(%d+)$")
    if y then
      return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
    end
  end
  return nil
end

local function tableCount(t)
  local c=0; for _ in pairs(t) do c=c+1 end; return c
end

local function newQueenId()
  return ("Q%08x%04x"):format(math.random(0, 0xffffffff), math.random(0, 0xffff))
end

local function getApiaryID(hiveID)
  for apiaryID, apiary in pairs(Apiaries) do
    for _, hive in pairs(apiary.hives or {}) do
      if hive.id == hiveID then return apiaryID end
    end
  end
  return nil
end

local function getHive(hiveID)
  local apiaryID = getApiaryID(hiveID)
  local apiary   = apiaryID and Apiaries[apiaryID]
  return apiary and apiary.hives and apiary.hives[hiveID] or nil, apiaryID, apiary
end

local function markDirty(hiveId) DirtyHives[hiveId] = true end

---------------------------------------------------------------------
-- Správa královen
---------------------------------------------------------------------
local function killQueen(queen)
  if not queen then return end
  queen.alive = false
  queen.hive_id = nil
  queen._dirty = true
end

local function spawnNewQueenForHive(hive, geneticsOverride)
  local q = {
    hive_id  = hive.id,
    queen_uid = newQueenId(),
    age_days  = 0,
    genetics  = geneticsOverride or (hive.bee_genetics or {}),
    fertility = 1.0,
    alive     = true,
    origin    = { type = "emergency" },
    pedigree  = {},
    quality_score = 0,
    _insert   = true,
  }
  hive.queen     = q
  hive.queen_uid = q.queen_uid
  QueensByUID[q.queen_uid] = q
  QueensByHive[hive.id]    = q
  return q
end

---------------------------------------------------------------------
-- Počasí a měsíční parametry
---------------------------------------------------------------------
local function getMonthConfig(now)
  local date = os.date('*t', now)
  return Config.Months[date.month] or { cold=false, hot=false, nectarFactor=1.0, seasonalDiseaseBoost=0.0 }
end

local function applyRainEwma(hive, now)
  local rainAtSec = toSecMaybeMs(hive.rain_updated_at)
  if rainAtSec and hive.rain_state then
    local hoursSinceRain = (now - rainAtSec) / 3600
    hive.rain_state = clamp01(hive.rain_state * ((1 - (Config.RainEWMAAlpha or 0.15)) ^ hoursSinceRain))
  end
  -- Spodní práh počasí, ať nikdy není absolutní nula
  local weatherFactor = math.max(0.2, 1.0 - clamp01(hive.rain_state or 0))
  return weatherFactor
end

---------------------------------------------------------------------
-- Genetika a defaulty
---------------------------------------------------------------------
local function getGenetics(hive)
  local defG = Config.DefaultGenetics or {}
  local baseG = (hive.queen and hive.queen.alive and hive.queen.genetics) or hive.bee_genetics or {}
  return setmetatable(baseG, { __index = defG })
end

local function ensureHiveDefaults(hive)
  hive.population         = hive.population or 0
  hive.stores_honey_json  = hive.stores_honey_json or '{}'
  hive.stores_wax         = hive.stores_wax or 0
  hive.frames_total       = hive.frames_total or 10
  hive.frames_capped      = hive.frames_capped or 0
  hive.super_count        = hive.super_count or 0
end

---------------------------------------------------------------------
-- Výpočty kapacit, přírůstků a spotřeby
---------------------------------------------------------------------
local function computeCapacities(apiary, hive, monthCfg, weatherFactor, genetics)
  local nectarFlowPerDay = (apiary.nectar_baseline or 0) * (monthCfg.nectarFactor or 1) * weatherFactor
  local beesPerFrame     = Config.Population.beesPerFrame or 2000
  local superFrames      = Config.Supers.framesPerSuper or 9
  local honeyPerCapFrame = Config.Honey.honeyPerCappedFrame or 2.5
  local capacityFrames   = hive.frames_total + hive.super_count * superFrames
  local popCapacity      = capacityFrames * beesPerFrame

  local consumptionPerBee = Config.Population.consumptionPerBee or 0
  if monthCfg.cold then consumptionPerBee = consumptionPerBee * (1 + (1 - (genetics.coldResist or 0)) * 0.5) end
  if monthCfg.hot  then consumptionPerBee = consumptionPerBee * (1 + (1 - (genetics.heatResist or 0)) * 0.5) end

  return nectarFlowPerDay, honeyPerCapFrame, capacityFrames, popCapacity, consumptionPerBee
end

---------------------------------------------------------------------
-- Nemoci / Varroa
---------------------------------------------------------------------
local function diseaseTick(hive, monthCfg, genetics, days)
  local varroaConfig = (Config.Diseases and Config.Diseases.varroa) or {
    baseGrowthRate = 0.005,
    populationDebuffMax = 0.7,
    honeyDebuffMax = 0.5,
    maxLevel = 1.0,
  }
  local seasonalMiteBonus = (monthCfg.hot and 0.5 or (monthCfg.cold and -0.5 or 0))
  local diseaseRes = genetics.diseaseResist or 0
  local miteGrowthFactor  = (varroaConfig.baseGrowthRate * (1 + seasonalMiteBonus)) * (1 - diseaseRes)
  hive.mite_level         = math.min(varroaConfig.maxLevel, (hive.mite_level or 0) + (miteGrowthFactor * days))

  local miteDebuffRatio   = (hive.mite_level or 0) / varroaConfig.maxLevel
  local populationDebuff  = 1.0 - (varroaConfig.populationDebuffMax * miteDebuffRatio)
  local honeyDebuff       = 1.0 - (varroaConfig.honeyDebuffMax * miteDebuffRatio)

  if (hive.mite_level or 0) > 0.5 then hive.substate = 'DISEASED' end

  return populationDebuff, honeyDebuff
end

---------------------------------------------------------------------
-- Med a vosk – spotřeba/produkce dle flóry
---------------------------------------------------------------------
local function decodeHoneyStores(hive)
  local ok, t = pcall(json.decode, hive.stores_honey_json or '{}')
  return (ok and t) or {}
end

local function encodeHoneyStores(t)
  return json.encode(t or {})
end

-- iterativní spotřeba přes více bucketů, vrací unmet (nepokrytou spotřebu)
local function consumeHoney(honeyStores, consumption)
  local need = consumption or 0
  if need <= 0 then
    local total = 0; for _, a in pairs(honeyStores) do total = total + a end
    return honeyStores, total, 0
  end

  while need > 0 do
    local k, maxv = nil, 0
    for name, v in pairs(honeyStores) do if v > maxv then maxv, k = v, name end end
    if not k or maxv <= 0 then break end
    local take = math.min(maxv, need)
    honeyStores[k] = maxv - take
    need = need - take
  end

  local totalAfter = 0; for _, a in pairs(honeyStores) do totalAfter = totalAfter + a end
  return honeyStores, totalAfter, need -- need > 0 => hlad
end

local function produceHoneyAndWax(apiary, genetics, nectarFlowPerDay, weatherFactor, honeyDebuff, days)
  local honeyProdFactor = Config.Honey.honeyProductionFactor or 0.00002
  local honeyYield      = genetics.honeyYield or 1
  local honeyGain = (honeyProdFactor * nectarFlowPerDay * honeyYield) * days * honeyDebuff
  local waxYield        = genetics.waxYield or 0.5
  local waxGain   = honeyGain * (0.02 * (waxYield / 0.5))
  return honeyGain, waxGain
end

local function splitHoneyByFlora(apiary, honeyStores, honeyGain)
  local floraProfile = apiary.flora_profile
  if not floraProfile or next(floraProfile) == nil then
    local itemName = (Config.HoneyTypes and Config.HoneyTypes.default and Config.HoneyTypes.default.itemName)
                    or Config.honey_item
    honeyStores[itemName] = (honeyStores[itemName] or 0) + honeyGain
    return honeyStores
  end
  for floraType, influence in pairs(floraProfile) do
    local honeyTypeConfig = Config.HoneyTypes and Config.HoneyTypes[floraType]
    local itemName = (honeyTypeConfig and honeyTypeConfig.itemName) or Config.honey_item
    honeyStores[itemName] = (honeyStores[itemName] or 0) + (honeyGain * influence)
  end
  return honeyStores
end

---------------------------------------------------------------------
-- Růst populace, rojení, víčkování, nouzové přelarvení
---------------------------------------------------------------------
local function growthTick(hive, genetics, nectarFlowPerDay, consumptionPerBee, populationDebuff, days)
  local fert = genetics.fertility or 1

  -- bez královny: úbytek
  if not (hive.queen and hive.queen.alive) then
    hive.substate = 'QUEENLESS'
    hive.population = hive.population * ((1 - (Config.Population.queenlessDecayPerDay or 0.03)) ^ days)
    fert = 0
  end

  -- faktor zásob (využito už v computeNectarBalance implicitně přes nectarFlowPerDay)
  local honeyStores = decodeHoneyStores(hive)
  local totalHoney  = 0
  for _, a in pairs(honeyStores) do totalHoney = totalHoney + a end
  local storeGrowthFactor = math.min(1.0, totalHoney / 10.0)
  local effectiveNectarForGrowth = math.max(nectarFlowPerDay, storeGrowthFactor * 0.5)

  local growthPerDay = (hive.population * (Config.Population.growthFactor or 0) * effectiveNectarForGrowth) * fert * populationDebuff
  hive.population = math.max(0, hive.population + (growthPerDay * days))
end

local function swarmingTick(hive, genetics, popCapacity, days)
  if hive.queen and hive.queen.alive and (hive.state == 'GROWTH' or hive.state == 'PEAK') then
    if hive.population > popCapacity then
      local over = hive.population / math.max(1, popCapacity)
      local swarmChance = math.min(0.5, (over - 1.0) * (Config.Swarm.baseChanceScale or 0.3)) * days * (0.75 + 0.5 * (genetics.swarmTendency or 0))
      if math.random() < swarmChance then
        hive.population = hive.population * (1 - (Config.Swarm.populationFraction or 0.25))
        hive.substate = 'SWARMING'
      end
    end
  end
end

local function capFrames(hive, totalHoney, capacityFrames, honeyPerCapFrame)
  local framesCapPossible = math.floor(totalHoney / math.max(0.001, honeyPerCapFrame))
  hive.frames_capped = math.max(0, math.min(capacityFrames, framesCapPossible))
end

local function emergencyQueen(hive, days)
  if (not hive.queen or not hive.queen.alive) then
    hive._queenlessAccum = (hive._queenlessAccum or 0) + days
    if (hive._queenlessAccum or 0) >= (Config.Queen.requeenMinDays or 3) and hive.population >= (Config.Queen.minPopForRequeen or 5000) then
      if math.random() < ((Config.Queen.emergencyRequeenChancePerDay or 0.15) * days) then
        spawnNewQueenForHive(hive)
        hive.substate = 'HEALTHY'
        hive._queenlessAccum = 0
      end
    end
  end
end

local function settleSubstate(hive)
  if hive.substate ~= 'QUEENLESS' and hive.substate ~= 'STARVING' and hive.substate ~= 'DISEASED' and hive.substate ~= 'SWARMING' then
    hive.substate = 'HEALTHY'
  end
end

local function computeNectarBalance(hive, genetics, nectarFlowPerDay, weatherFactor, honeyDebuff, consumptionPerBee)
  local HPF = (Config.Honey and Config.Honey.honeyProductionFactor) or 0.00002
  local honeyYield = genetics.honeyYield or 1.0
  -- produkce/spotřeba na včelu a den
  local productionPerBeePerDay  = HPF * nectarFlowPerDay * honeyYield * weatherFactor * honeyDebuff
  local consumptionPerBeePerDay = math.max(1e-9, consumptionPerBee or 0)
  hive.nectar_balance = (productionPerBeePerDay / consumptionPerBeePerDay) - 1.0
end

---------------------------------------------------------------------
-- Zpracování jednoho úlu
---------------------------------------------------------------------
local function processHive(hive, apiary, now, days)
  ensureHiveDefaults(hive)

  -- počasí + genetika + měsíční cfg
  local weatherFactor = applyRainEwma(hive, now)
  local genetics      = getGenetics(hive)
  local monthCfg      = getMonthConfig(now)

  -- kapacity + spotřeba
  local nectarFlowPerDay, honeyPerCapFrame, capacityFrames, popCapacity, consumptionPerBee =
    computeCapacities(apiary, hive, monthCfg, weatherFactor, genetics)

  -- stárnutí královny (placeholder – původní logiku můžeš rozšířit sem)
  if hive.queen and hive.queen.alive then
    hive.queen.age_days = (hive.queen.age_days or 0) + days
    hive.queen._dirty = true
  end

  -- nemoci
  local populationDebuff, honeyDebuff = diseaseTick(hive, monthCfg, genetics, days)

  -- med a vosk
  local honeyStores = decodeHoneyStores(hive)
  local consumption = (hive.population * consumptionPerBee) * days
  honeyStores, _, localUnmet = consumeHoney(honeyStores, consumption)

  local honeyGain, waxGain = produceHoneyAndWax(apiary, genetics, nectarFlowPerDay, weatherFactor, honeyDebuff, days)
  honeyStores = splitHoneyByFlora(apiary, honeyStores, honeyGain)
  hive.stores_honey_json = encodeHoneyStores(honeyStores)
  hive.stores_wax = math.max(0, (hive.stores_wax or 0) + waxGain)

  -- součet zásob po změnách
  local totalHoneyAfter = 0
  for _, amt in pairs(honeyStores) do totalHoneyAfter = totalHoneyAfter + amt end

  -- hlad → penalizace populace
  if localUnmet and localUnmet > 0 then
    hive.substate = 'STARVING'
    local rate = Config.Population.starvationDecayPerDay or 0.05
    hive.population = hive.population * ((1 - rate) ^ days)
  end

  -- růst populace + rojení + víčkování + nouzové přelarvení
  growthTick(hive, genetics, nectarFlowPerDay, consumptionPerBee, populationDebuff, days)
  swarmingTick(hive, genetics, popCapacity, days)
  capFrames(hive, totalHoneyAfter, capacityFrames, honeyPerCapFrame)
  emergencyQueen(hive, days)
  settleSubstate(hive)

  -- metriky – sjednocený výpočet
  computeNectarBalance(hive, genetics, nectarFlowPerDay, weatherFactor, honeyDebuff, consumptionPerBee)

  hive.last_tick = now
end

---------------------------------------------------------------------
-- Veřejné funkce
---------------------------------------------------------------------
function AddHiveToSimulation(hiveId)
  for _, id in ipairs(hiveIds) do if id == hiveId then return end end
  table.insert(hiveIds, hiveId)
  debugf('[aprts_bee] Úl %d byl přidán do simulační smyčky.', hiveId)
end

function StartSimulationTick()
  -- naplnění seznamu ID úlů (reset, ať tu nejsou duplicity)
  hiveIds = {}
  for _, apiary in pairs(Apiaries) do
    for _, hive in pairs(apiary.hives) do
      table.insert(hiveIds, hive.id)
    end
  end

  CreateThread(function()
    while true do
      Wait(10000)
      SimulateChunkOfHives()
      if currentHiveIndex > #hiveIds then
        FlushDirtyHives()
        currentHiveIndex = 1
        debugf('[aprts_bee] Cyklus simulace dokončen. Změny uloženy.')
      end
    end
  end)
end

function SimulateChunkOfHives()
  local now = nowSec()

  for _ = 1, hivesPerTick do
    if currentHiveIndex > #hiveIds then break end

    local hiveId = hiveIds[currentHiveIndex]
    currentHiveIndex = currentHiveIndex + 1

    local hive, apiaryID, apiary = getHive(hiveId)
    if not hive or not apiary then goto continue end

    -- časové škálování s min/max limitem
    local lastTickSec = toSecMaybeMs(hive.last_tick) or now
    local rawDays = (now - lastTickSec) / 86400
    local days = math.min(
      math.max(rawDays, (Config.Sim and Config.Sim.MinDeltaDays) or 1/24),
      (Config.Sim and Config.Sim.MaxDeltaDays) or 0.5
    )

    -- samotné zpracování úlu
    processHive(hive, apiary, now, days)

    -- označit k uložení
    markDirty(hiveId)

    ::continue::
  end
end

function FlushDirtyHives()
  if not next(DirtyHives) then return end

  debugf('[aprts_bee] Ukládání %d změněných úlů do DB...', tableCount(DirtyHives))
  local queries = {}

  for hiveId, _ in pairs(DirtyHives) do
    local hive, apiaryID, apiary = getHive(hiveId)
    if hive then
      local lastTickSec = toSecMaybeMs(hive.last_tick) or os.time()

      -- korektní NULL pro last_treatment_at
      local tempTs = hive.last_treatment_at and toSecMaybeMs(hive.last_treatment_at) or nil
      local lastTreatmentTs = (tempTs and tempTs > 0) and tempTs or nil

      table.insert(queries, {
        query = [[UPDATE aprts_bee_hives SET
          state=?, substate=?, population=?, stores_honey_json=?, stores_wax=?,
          frames_total=?, frames_capped=?, super_count=?, disease_progress=?,
          mite_level=?, rain_state=?, last_tick=FROM_UNIXTIME(?), bee_genetics=?, queen_uid=?,
          last_treatment_at=FROM_UNIXTIME(?), nectar_balance=?
        WHERE id = ?]],
        values = {
          hive.state, hive.substate, math.floor(hive.population or 0), hive.stores_honey_json or '{}',
          hive.stores_wax or 0, hive.frames_total or 10, hive.frames_capped or 0, hive.super_count or 0,
          hive.disease_progress or 0, hive.mite_level or 0, hive.rain_state or 0, lastTickSec,
          hive.bee_genetics and json.encode(hive.bee_genetics) or nil, hive.queen_uid, lastTreatmentTs,
          hive.nectar_balance or 0, hiveId
        }
      })
    else
      debugf('[aprts_bee] Chyba: Nelze uložit úl %d, protože nebyl nalezen v paměti.', hiveId)
    end
  end

  if #queries > 0 then
    MySQL:transaction_async(queries, function(success)
      if success then
        debugf('[aprts_bee] Uloženo %d změněných úlů do DB.', #queries)
      else
        print('[aprts_bee] CHYBA při ukládání úlů do DB! Zkontroluj konzoli výše pro detaily.')
      end
    end)
  end
  DirtyHives = {}
end

---------------------------------------------------------------------
-- BONUS: helper pro ruční přidání/odebrání úlu ze seznamu
---------------------------------------------------------------------
function RemoveHiveFromSimulation(hiveId)
  for i, id in ipairs(hiveIds) do
    if id == hiveId then table.remove(hiveIds, i); break end
  end
end

-- Konec refaktoru + oprav
