Config = {}

Config.Debug = true
Config.UpdateInterval = 60000 * 10 -- 10 minut
Config.SaveInterval = 60000 * 30 -- 30 minut (Auto-save)

-- Admin příkazy
Config.Commands = {
    TestApiary = "testapiary", -- Založí úl na tvé pozici
    TestQueen = "testqueen"    -- Dá ti do inventáře královnu
}

Config.Items = {
    HiveSmall = "hive_small",
    Queen = "bee_queen",
    FrameEmpty = "frame_empty",
    FrameFull = "frame_full"
}

Config.InventoryPrefix = "beehive_"

Config.HiveStats = {
    small = { slots = 4, modifier = 1.0 }
}

Config.Seasons = {
    ["SUMMER"] = { temp = 30, floraBonus = 1.5 },
    ["WINTER"] = { temp = -5, floraBonus = 0.0 }
}