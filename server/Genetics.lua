Genetics = {}

function Genetics.GenerateRandomGenetics()
    return {
        productivity = math.random(30, 60) / 100,
        aggression = math.random(10, 50) / 100,
        hardiness = math.random(20, 70) / 100,
        generation = 1,
        lifespan = Config.QueenLifespan or 100 -- NOVÉ: Výchozí životnost
    }
end

function Genetics.Mutate(parentGenes)
    local mutationRate = 0.05
    
    local newGenes = {
        productivity = parentGenes.productivity + (math.random() * mutationRate * 2 - mutationRate),
        aggression = parentGenes.aggression + (math.random() * mutationRate * 2 - mutationRate),
        hardiness = parentGenes.hardiness + (math.random() * mutationRate * 2 - mutationRate),
        generation = parentGenes.generation + 1,
        lifespan = Config.QueenLifespan or 100 -- Reset životnosti pro novou královnu
    }

    for k, v in pairs(newGenes) do
        if k ~= "generation" and k ~= "lifespan" then
            if v < 0.01 then newGenes[k] = 0.01 end
            if v > 1.0 then newGenes[k] = 1.0 end
        end
    end

    return newGenes
end

return Genetics