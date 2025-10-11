Config = {}
Config.Debug = true

Config.DST = 2
Config.GreenTimeStart = 16
Config.GreenTimeEnd = 23
Config.ActiveTimeStart = 23
Config.ActiveTimeEnd = 3

Config.WebHook = ""
Config.ServerName = 'WestHaven ** Loger'
Config.DiscordColor = 16753920

Config.Jobs = {
    {job = 'police', grade = 1},
    {job = 'doctor', grade = 3}
}

Config.UseBeeFX = true
Config.queen_item = "bee_queen" -- Item pro královnuu
Config.bee_item = "bee_drone"   -- Item pro dělnici a trubce
Config.honey_item = "bee_honey"      -- Item pro med
Config.wax_item = "bee_wax"      -- Item pro vosk
Config.bee_box_item = "bee_box"  -- Item pro úl
Config.super_box_item = "bee_super_box" -- Item pro nástavek
-- [[ Měsíce a sezóny ]]
-- Měsíce jsou 1-12 (leden-prosinec)
Config.Months = {
    [1]  = { name = "Leden",     cold = true,  hot = false, nectarFactor = 0.1, seasonalDiseaseBoost = 0.2 },
    [2]  = { name = "Únor",      cold = true,  hot = false, nectarFactor = 0.2, seasonalDiseaseBoost = 0.15 },
    [3]  = { name = "Březen",    cold = false, hot = false, nectarFactor = 0.6, seasonalDiseaseBoost = 0.1 },
    [4]  = { name = "Duben",     cold = false, hot = false, nectarFactor = 1.0, seasonalDiseaseBoost = 0.05 },
    [5]  = { name = "Květen",    cold = false, hot = false, nectarFactor = 1.5, seasonalDiseaseBoost = 0 },
    [6]  = { name = "Červen",    cold = false, hot = true,  nectarFactor = 1.2, seasonalDiseaseBoost = 0 },
    [7]  = { name = "Červenec",  cold = false, hot = true,  nectarFactor = 1.0, seasonalDiseaseBoost = 0.1 },
    [8]  = { name = "Srpen",     cold = false, hot = true,  nectarFactor = 0.8, seasonalDiseaseBoost = 0.2 },
    [9]  = { name = "Září",      cold = false, hot = false, nectarFactor = 0.6, seasonalDiseaseBoost = 0.25 },
    [10] = { name = "Říjen",     cold = false, hot = false, nectarFactor = 0.3, seasonalDiseaseBoost = 0.3 },
    [11] = { name = "Listopad",  cold = true,  hot = false, nectarFactor = 0.1, seasonalDiseaseBoost = 0.35 },
    [12] = { name = "Prosinec",  cold = true,  hot = false, nectarFactor = 0.05, seasonalDiseaseBoost = 0.4 },
}

-- [[ Agresivita a ochrana ]]
Config.BeeDamage = {
    baseDamage = 2.0,      -- Základní poškození od žihadla
    dotDamage = 1.0,       -- Poškození za sekundu (jed)
    dotDuration = 5000     -- Délka otravy v ms
}

Config.BeeProtection = {
    -- Tagy, které musí mít item, aby byl započítán jako ochrana.
    -- Např. tvůj klobouk v DB bude mít tag 'beekeeping_hat'
    { tag = 'beekeeping_hat', protection = 0.4 },  -- 40% redukce
    { tag = 'beekeeping_suit', protection = 0.5 }, -- 50% redukce
    { tag = 'beekeeping_gloves', protection = 0.1 } -- 10% redukce
    -- Celková ochrana se sčítá, max 1.0 (100%)
}
-- [[ Královny a genetika ]]
Config.Queen = {
    baseLifespanDays = 60,       -- Průměrná délka života královny ve dnech (při lifespan=1.0)
    senescenceStartFrac = 0.8,   -- V jaké části života začne stárnout a klesat plodnost (80%)
    deathChanceAtEnd = 0.05,     -- Denní šance na úmrtí na konci života
    requeenMinDays = 3,          -- Minimální počet dní bez královny pro pokus o přelarvení
    emergencyRequeenChancePerDay = 0.15, -- Základní denní šance na úspěšné přelarvení
    minPopForRequeen = 5000,     -- Minimální počet včel pro pokus o přelarvení
    nectarNeedFactor = 0.5       -- Jaký minimální přísun nektaru je potřeba pro přelarvení
}
-- [[ Divoké královny ]]
Config.WildQueen = {
    awardLimit = 3, -- Max královen za restart pro jednoho hráče
    awardCooldown = 3600, -- Cooldown v sekundách (1 hodina)
    -- Presety pro biomy
    biomePresets = {
        default = { honeyYield = 0.2, aggressiveness = 0.5, diseaseResist = 0.3, swarmTendency = 0.6, coldResist = 0.4, heatResist = 0.4, waxYield = 0.3, queenLifespan = 0.5 },
        forest = { honeyYield = 0.3, diseaseResist = 0.4, coldResist = 0.5 },
        desert = { aggressiveness = 0.6, heatResist = 0.7, swarmTendency = 0.3 },
        swamp = { diseaseResist = 0.6, aggressiveness = 0.7, honeyYield = 0.1 }
    }
}

-- [[ Simulace ]]

-- 🔄 Obecné chování simulace
Config.Sim = {
    TickIntervalMinutes = 15,     -- jak často se volá simulace (informativní)
    MinDeltaDays = 1 / 24,        -- minimální časový krok v dnech (1 hodina)
}

-- 🌦️ Počasí a vlivy prostředí
Config.RainEWMAAlpha = 0.15      -- rychlost „vyprchávání“ deště (EWMA)

-- 🐝 Populační logika
Config.Population = {
    growthFactor = 0.00008,       -- základní růst populace za den (vynásoben nektarem a fertilitou)
    consumptionPerBee = 0.00001,  -- kolik „medu“ včela spotřebuje za den
    beesPerFrame = 2000,          -- kolik včel se vejde do jednoho rámku
    queenlessDecayPerDay = 0.03,  -- úbytek populace za den bez královny (3 %)
    diseaseDecayPerDay = 0.02,    -- úbytek populace za den při nemoci (2 %)
    starvationDecayPerDay = 0.05, -- úbytek populace za den při hladovění (5 %)
}

-- 🍯 Produkce medu
Config.Honey = {
    honeyPerCappedFrame = 2.5,    -- množství medu (v jednotkách) pro jeden zavíčkovaný rámek
}

-- 🍯 Nástavky (supers)
Config.Supers = {
    framesPerSuper = 9,           -- počet rámků na jeden nástavek
}

-- 🐝 Rojení
Config.Swarm = {
    baseChanceScale = 0.3,        -- jak rychle roste šance rojení při přeplnění
    populationFraction = 0.25,    -- kolik % populace odletí při rojení
}

-- 🧬 Genetické faktory (výchozí hodnoty, pokud úl žádné nemá)
Config.DefaultGenetics = {
    fertility = 1.0,              -- násobitel růstu populace
    honeyYield = 0.5,             -- násobitel produkce medu
    coldResist = 0.5,             -- odolnost proti chladu (0–1)
    heatResist = 0.5,             -- odolnost proti horku (0–1)
    diseaseResist = 0.5,          -- odolnost proti nemocem (0–1)
    aggressiveness = 0.5,         -- jak agresivní jsou včely (0–1)
    swarmTendency = 0.5,          -- jak moc mají tendenci se rojit (0–1)
    waxYield = 0.5,               -- násobitel produkce vosku
    queenLifespan = 0.5           -- délka života královny (0–1, kde 1 je 60 dní)
}