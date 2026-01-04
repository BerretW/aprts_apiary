Config = {}

Config.Debug = false
Config.UpdateInterval = 1000 * 10 
Config.SaveInterval = 10000 * 30 

Config.MaxHivesPerApiary = 4 -- NOVÉ: Kolik úlů se vejde na jedno stanoviště
Config.MaxPopulation = 10000 -- Maximální limit populace
-- HROZBY A PÉČE
Config.SwarmPopulation = 8000 
Config.QueenLifespan = 100 
Config.SmokerDuration = 60000 * 5 

Config.Commands = {
    TestApiary = "testapiary", 
    TestQueen = "testqueen"    
}

Config.Items = {
    HiveSmall = "bee_box", -- Tento item se použije i pro "přistavění"
    Queen = "bee_queen",
    FrameEmpty = "frame_empty",
    FrameFull = "frame_full",
    Smoker = "tool_smoker",        
    SugarWater = "sugar_water",     
    Medicine = "bee_medicine",      
    HoneyJar = "bee_honey",         
    Wax = "bee_wax"                 
}

Config.InventoryPrefix = "beehive_"

Config.HiveStats = {
    small = { slots = 4, modifier = 1.0 }
}

Config.Seasons = {
    ["SUMMER"] = { temp = 30, floraBonus = 1.5 },
    ["WINTER"] = { temp = -5, floraBonus = 0.0 }
}

Config.Diseases = {
    ["mites"] = { label = "Roztoči", damage = 10 } 
}

Config.ExtractorLocations = {
    vector3(1234.56, -1234.56, 42.0) 
}