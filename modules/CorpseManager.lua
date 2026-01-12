-- modules/CorpseManager.lua
local mq = require('mq')

local CorpseManager = {}

function CorpseManager.getCorpseTable(numCorpses)
    local corpseTable = {}
    
    print(string.format("[CorpseManager] ===== BUILDING CORPSE TABLE ====="))
    print(string.format("[CorpseManager] SpawnCount returned: %d corpses", numCorpses))
    
    local skipped = {
        noSpawn = 0,
        noID = 0,
        invalidID = 0
    }
    
    for i = 1, numCorpses do
        local spawn = mq.TLO.NearestSpawn(i, "npccorpse radius 200 zradius 30")
        
        if not spawn then
            skipped.noSpawn = skipped.noSpawn + 1
            print(string.format("[CorpseManager] Index %d: No spawn returned", i))
        elseif not spawn.ID() then
            skipped.noID = skipped.noID + 1
            print(string.format("[CorpseManager] Index %d: spawn.ID() is nil", i))
        elseif spawn.ID() <= 0 then
            skipped.invalidID = skipped.invalidID + 1
            print(string.format("[CorpseManager] Index %d: spawn.ID() = %d (invalid)", i, spawn.ID()))
        else
            -- Valid corpse - add to table
            local corpse = {
                ID = spawn.ID(),
                Name = spawn.Name()
            }
            table.insert(corpseTable, corpse)
            
            -- Verbose logging for first 10 and last 10
            if i <= 10 or i >= numCorpses - 10 then
                print(string.format("[CorpseManager] Index %d: Added corpse ID %d (%s)", 
                    i, corpse.ID, corpse.Name or "Unknown"))
            end
        end
    end
    
    -- Summary
    local totalSkipped = skipped.noSpawn + skipped.noID + skipped.invalidID
    print(string.format("[CorpseManager] ===== CORPSE TABLE COMPLETE ====="))
    print(string.format("[CorpseManager] Input:   %d (from SpawnCount)", numCorpses))
    print(string.format("[CorpseManager] Added:   %d corpses to table", #corpseTable))
    print(string.format("[CorpseManager] Skipped: %d corpses", totalSkipped))
    
    if totalSkipped > 0 then
        print(string.format("[CorpseManager]   - No spawn object: %d", skipped.noSpawn))
        print(string.format("[CorpseManager]   - No ID: %d", skipped.noID))
        print(string.format("[CorpseManager]   - Invalid ID: %d", skipped.invalidID))
    end
    
    if numCorpses ~= #corpseTable then
        print(string.format("[CorpseManager] ⚠ WARNING: SpawnCount (%d) != Table Size (%d)", 
            numCorpses, #corpseTable))
        print(string.format("[CorpseManager] ⚠ Missing %d corpses!", numCorpses - #corpseTable))
    else
        print(string.format("[CorpseManager] ✓ All spawns added to table"))
    end
    print(string.format("[CorpseManager] ==================================="))
    
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
        -- Query distance on-demand
        local spawn = mq.TLO.Spawn(corpse.ID)
        if spawn and spawn.ID() then
            local distance = spawn.Distance() or 9999
            if distance < nearestDistance then
                nearestIndex = i
                nearestDistance = distance
            end
        end
    end
    
    if nearestIndex > 0 then
        local nearest = table.remove(corpseTable, nearestIndex)
        return nearest, corpseTable
    end
    
    return nil, corpseTable
end

return CorpseManager