-- modules/CorpseManager.lua
local mq = require('mq')

local CorpseManager = {}

function CorpseManager.getCorpseTable(numCorpses)
    local corpseTable = {}
    
    for i = 1, numCorpses do
        local spawn = mq.TLO.NearestSpawn(i, "npccorpse radius 200 zradius 20")
        
        if spawn and spawn.ID() and spawn.ID() > 0 then
            local x, y, z = spawn.X(), spawn.Y(), spawn.Z()
            
            if x and y and z then
                local corpse = {
                    ID = spawn.ID(),
                    Name = spawn.Name(),
                    Distance = spawn.Distance(),
                    DistanceZ = spawn.DistanceZ(),
                    X = x,
                    Y = y,
                    Z = z
                }
                table.insert(corpseTable, corpse)
            end
        end
    end
    
    return corpseTable
end

function CorpseManager.getRandomCorpse(corpseTable)
    if #corpseTable == 0 then
        return nil, corpseTable
    end
    
    local randomIndex = math.random(1, #corpseTable)
    local randomCorpse = table.remove(corpseTable, randomIndex)
    return randomCorpse, corpseTable
end

function CorpseManager.getNearestCorpse(corpseTable)
    if #corpseTable == 0 then
        return nil, corpseTable
    end
    
    local nearestIndex = 0
    local nearestDistance = 9999
    
    for i = 1, #corpseTable do
        local corpse = corpseTable[i]
        local distance = mq.TLO.Math.Distance(corpse.Y, corpse.X)()
        if distance < nearestDistance then
            nearestIndex = i
            nearestDistance = distance
        end
    end
    
    local nearest = table.remove(corpseTable, nearestIndex)
    return nearest, corpseTable
end

return CorpseManager