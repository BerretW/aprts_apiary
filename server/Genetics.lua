
Genetics = {}
function Genetics.GenerateRandomGenetics()
    return {
        productivity = math.random(20, 60), -- Základní královny jsou průměrné
        aggression   = math.random(40, 90), -- Divoké včely jsou agresivní
        fertility    = math.random(30, 70),
        resilience   = math.random(10, 50),
        adaptability = math.random(10, 50),
        lifespan     = math.random(80, 120) -- Počet cyklů
    }
end

function Genetics.Mutate(parentGenes)
    local mutationRate = 5 -- Maximální odchylka +/- 5 bodů
    local newGenes = {}

    for k, v in pairs(parentGenes) do
        if k ~= "generation" then
            local change = math.random(-mutationRate, mutationRate)
            local newVal = v + change
            
            -- Ošetření limitů 1-100
            if newVal < 1 then newVal = 1 end
            if newVal > 100 then newVal = 100 end
            
            newGenes[k] = newVal
        end
    end

    -- Občasná "Šťastná mutace" (Rare proc) - bonus k náhodnému statu
    if math.random(1, 20) == 1 then
        local stats = {"productivity", "fertility", "resilience", "adaptability"}
        local luckyStat = stats[math.random(#stats)]
        newGenes[luckyStat] = newGenes[luckyStat] + math.random(5, 15)
        if newGenes[luckyStat] > 100 then newGenes[luckyStat] = 100 end
    end

    newGenes.generation = (parentGenes.generation or 1) + 1
    newGenes.lifespan = math.random(80, 120) -- Reset životnosti pro dceru

    return newGenes
end
