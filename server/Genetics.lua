Genetics = {}

-- Vygenerování náhodné královny (divoká)
function Genetics.GenerateRandomGenetics()
    return {
        productivity = math.random(30, 60) / 100, -- 0.3 až 0.6
        aggression = math.random(10, 50) / 100,   -- 0.1 až 0.5
        hardiness = math.random(20, 70) / 100,    -- Odolnost vůči nemocem
        generation = 1
    }
end

-- Mutace při rojení nebo nové generaci
function Genetics.Mutate(parentGenes)
    local mutationRate = 0.05 -- 5% změna
    
    local newGenes = {
        productivity = parentGenes.productivity + (math.random() * mutationRate * 2 - mutationRate),
        aggression = parentGenes.aggression + (math.random() * mutationRate * 2 - mutationRate),
        hardiness = parentGenes.hardiness + (math.random() * mutationRate * 2 - mutationRate),
        generation = parentGenes.generation + 1
    }

    -- Clamp hodnoty 0.0 - 1.0
    for k, v in pairs(newGenes) do
        if k ~= "generation" then
            if v < 0.01 then newGenes[k] = 0.01 end
            if v > 1.0 then newGenes[k] = 1.0 end
        end
    end

    return newGenes
end

return Genetics