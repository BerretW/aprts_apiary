-----------------------------------------------------------------------
-- COMMANDS
-----------------------------------------------------------------------

RegisterCommand(Config.Commands.TestApiary, function(source, args)
    if source == 0 then return end
    -- CreateNewApiary je nyní globální, takže to bude fungovat
    CreateNewApiary(source, "small")
end)

RegisterCommand(Config.Commands.TestQueen, function(source, args)
    if source == 0 then return end
    local genes = Genetics.GenerateRandomGenetics()
    local metadata = {
        label = "Včelí Královna",
        genetics = genes,
        description = "Divoká královna"
    }
    VORP_INV:addItem(source, Config.Items.Queen, 1, metadata)
end)