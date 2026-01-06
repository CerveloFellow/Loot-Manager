-- modules/Commands.lua
local mq = require('mq')

local Commands = {}

function Commands.new(config, utils, itemEvaluator, corpseManager, lootManager, iniManager)
    local self = {
        loopBoolean = true,
        config = config,
        utils = utils,
        itemEvaluator = itemEvaluator,
        corpseManager = corpseManager,
        lootManager = lootManager,
        iniManager = iniManager
    }
    
    function self.testShared()
        if mq.TLO.Cursor() then
            local cursorName = mq.TLO.Cursor.Name()
            if cursorName then
                local result = utils.contains(config.itemsToShare, cursorName)
                print("Shared item status: "..tostring(result))
            end
        end
    end
    
    function self.testItem()
        if mq.TLO.Cursor() then
            local cursorName = mq.TLO.Cursor.Name()
            if cursorName then
                local result = itemEvaluator.shouldLoot(config, utils, mq.TLO.Cursor, true)
            end
        end
    end
    
    function self.testCorpse()
        -- Check if loot window is open
        if not mq.TLO.Window("LootWnd").Open() then
            print("ERROR: No corpse is open for looting. Please open a corpse first.")
            mq.cmdf("/g No corpse is open for looting. Please open a corpse first.")
            return
        end
        
        local itemCount = tonumber(mq.TLO.Corpse.Items()) or 0
        
        if itemCount == 0 then
            print("Corpse has no items.")
            mq.cmdf("/g Corpse has no items.")
            return
        end
        
        print(string.format("=== Testing %d items on corpse ===", itemCount))
        mq.cmdf("/g Testing %d items on corpse", itemCount)
        
        for i = 1, itemCount do
            mq.delay("3s", function() return mq.TLO.Corpse.Item(i).ID() end)
            local corpseItem = mq.TLO.Corpse.Item(i)
            
            if corpseItem and corpseItem.ID() then
                print(string.format("\n--- Item %d/%d ---", i, itemCount))
                local shouldLoot = itemEvaluator.shouldLoot(config, utils, corpseItem, true)
                print(string.format("RESULT: %s", shouldLoot and "LOOT" or "SKIP"))
            end
        end
        
        print("=== Corpse test complete ===")
        mq.cmdf("/g Corpse test complete")
    end
    
    function self.stopScript()
        self.loopBoolean = false
    end
    
    function self.reportUnlootedCorpses(line)
        print("[reportUnlootedCorpses] ===== DEBUG START =====")
        
        -- Get spawn count
        local spawnCount = mq.TLO.SpawnCount("npccorpse radius 200 zradius 20")()
        print(string.format("[reportUnlootedCorpses] SpawnCount query returned: %d", spawnCount))
        
        -- Check lootedCorpses size
        print(string.format("[reportUnlootedCorpses] lootedCorpses contains: %d entries", #lootManager.lootedCorpses))
        
        -- Show first 10 entries in lootedCorpses
        print("[reportUnlootedCorpses] First 10 entries in lootedCorpses:")
        for i = 1, math.min(10, #lootManager.lootedCorpses) do
            local entry = lootManager.lootedCorpses[i]
            print(string.format("  [%d] = %s (type: %s)", i, tostring(entry), type(entry)))
        end
        
        -- Get all corpses within radius
        local nearbyCorpses = corpseManager.getCorpseTable(spawnCount)
        print(string.format("[reportUnlootedCorpses] getCorpseTable returned: %d corpses", #nearbyCorpses))
        
        -- Find corpses that are NOT in the looted list
        local unlootedCorpses = {}
        local checkedCount = 0
        
        for i, corpse in ipairs(nearbyCorpses) do
            checkedCount = checkedCount + 1
            local isLooted = false
            local corpseIdNum = tonumber(corpse.ID)  -- Convert to number for comparison
            
            for j, lootedCorpse in ipairs(lootManager.lootedCorpses) do
                local lootedIdNum = tonumber(lootedCorpse)  -- Convert to number for comparison
                
                if corpseIdNum == lootedIdNum then
                    isLooted = true
                    break
                end
            end
            
            if not isLooted then
                print(string.format("[reportUnlootedCorpses] UNLOOTED: Corpse ID %s (type: %s, as number: %s) not found in lootedCorpses",
                    tostring(corpse.ID), type(corpse.ID), tostring(corpseIdNum)))
                table.insert(unlootedCorpses, corpse)
            end
        end
        
        print(string.format("[reportUnlootedCorpses] Checked %d corpses, found %d unlooted", checkedCount, #unlootedCorpses))
        
        -- Print unlooted corpses
        if (#unlootedCorpses > 0) then
            print("[reportUnlootedCorpses] Unlooted corpse IDs:")
            for i, corpse in ipairs(unlootedCorpses) do
                print(string.format("  %s", tostring(corpse.ID)))
            end
            mq.cmdf("/g "..mq.TLO.Me.Name().." unlooted corpses: " .. #unlootedCorpses)
        else
            print("[reportUnlootedCorpses] All corpses are looted!")
            mq.cmdf("/g "..mq.TLO.Me.Name().." all corpses looted!")
        end
        
        print("[reportUnlootedCorpses] ===== DEBUG END =====")
    end
    
    function self.masterLoot()
        lootManager.doLoot(true)
    end
    
    function self.peerLoot()
        lootManager.doLoot(false)
    end
    
    function self.reloadConfig()
        iniManager.reloadConfig(config)
    end
    
    return self
end

return Commands