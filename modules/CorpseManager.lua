-- modules/CorpseManager.lua
local mq = require('mq')

local CorpseManager = {}
CorpseManager.config = nil  -- Store config reference

-- Initialize with config reference
function CorpseManager.initialize(config)
    CorpseManager.config = config
end

-- Helper to build spawn search string with configured radius values
function CorpseManager.getSpawnSearchString()
    local radius = CorpseManager.config and CorpseManager.config.lootRadius or 250
    local zRadius = CorpseManager.config and CorpseManager.config.lootZRadius or 30
    return string.format("npccorpse radius %d zradius %d", radius, zRadius)
end

function CorpseManager.getCorpseTable(numCorpses)
    local corpseTable = {}
    local searchString = CorpseManager.getSpawnSearchString()
    
    print(string.format("[CorpseManager] ===== BUILDING CORPSE TABLE ====="))
    print(string.format("[CorpseManager] SpawnCount returned: %d corpses", numCorpses))
    print(string.format("[CorpseManager] Search string: %s", searchString))
    
    local skipped = {
        noSpawn = 0,
        noID = 0,
        invalidID = 0
    }
    
    for i = 1, numCorpses do
        local spawn = mq.TLO.NearestSpawn(i, searchString)
        
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
    local invalidIndices = {}  -- Track corpses that no longer exist
    
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
        else
            -- Corpse no longer exists - mark for removal
            table.insert(invalidIndices, i)
        end
    end
    
    -- Remove invalid corpses from table (in reverse order to preserve indices)
    for i = #invalidIndices, 1, -1 do
        table.remove(corpseTable, invalidIndices[i])
    end
    
    -- Recalculate nearestIndex if we removed items before it
    if nearestIndex > 0 then
        -- Adjust index based on how many items were removed before it
        local adjustment = 0
        for _, invalidIdx in ipairs(invalidIndices) do
            if invalidIdx < nearestIndex then
                adjustment = adjustment + 1
            end
        end
        nearestIndex = nearestIndex - adjustment
        
        if nearestIndex > 0 and nearestIndex <= #corpseTable then
            local nearest = table.remove(corpseTable, nearestIndex)
            return nearest, corpseTable
        end
    end
    
    -- No valid corpses found - table should now be empty or contain only invalid ones
    -- If we removed all invalid ones and table is empty, return nil
    -- If table still has items but none were valid, they were all removed above
    return nil, corpseTable
end

return CorpseManager