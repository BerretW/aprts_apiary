Config = {}

Config.Debug = true
Config.UpdateInterval = 60000 * 10 -- 10 minut (zrychli pro testování)
Config.SaveInterval = 60000 * 30 

-- HROZBY A PÉČE
Config.SwarmPopulation = 8000 -- Populace, kdy se úl může vyrojit
Config.QueenLifespan = 100 -- Kolik "cyklů" (UpdateInterval) královna vydrží (cca 16 herních hodin při 10min intervalu)
Config.SmokerDuration = 60000 * 5 -- Jak dlouho (ms) jsou včely klidné po použití kouřáku (5 min)

Config.Commands = {
    TestApiary = "testapiary", 
    TestQueen = "testqueen"    
}

Config.Items = {
    HiveSmall = "hive_small",
    Queen = "bee_queen",
    FrameEmpty = "frame_empty",
    FrameFull = "frame_full",
    -- NOVÉ ITEMY (musíš je mít v DB items)
    Smoker = "tool_smoker",         -- Kouřák
    SugarWater = "sugar_water",     -- Krmení na zimu
    Medicine = "bee_medicine",      -- Lék
    HoneyJar = "honey_jar",         -- Výsledný produkt
    Wax = "beeswax"                 -- Vedlejší produkt
}

Config.InventoryPrefix = "beehive_"

Config.HiveStats = {
    small = { slots = 4, modifier = 1.0 }
}

Config.Seasons = {
    ["SUMMER"] = { temp = 30, floraBonus = 1.5 },
    ["WINTER"] = { temp = -5, floraBonus = 0.0 }
}

-- Nemoci a jejich dopady
Config.Diseases = {
    ["mites"] = { label = "Roztoči", damage = 10 } -- Ubírá 10 zdraví za cyklus
}

-- Lokace pro zpracování medu (Medomet)
Config.ExtractorLocations = {
    vector3(1234.56, -1234.56, 42.0) -- ZMĚNIT NA REÁLNÉ SOUŘADNICE! (např. nějaký stůl ve městě)
}