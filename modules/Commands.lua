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
        -- Get all corpses within radius
        local nearbyCorpses = corpseManager.getCorpseTable(mq.TLO.SpawnCount("npccorpse radius 200 zradius 30")())
        
        -- Find corpses that are NOT in the looted list
        local unlootedCorpses = {}
        for i, corpse in ipairs(nearbyCorpses) do
            local isLooted = false
            for j, lootedCorpse in ipairs(lootManager.lootedCorpses) do
                if corpse.ID == lootedCorpse then
                    isLooted = true
                    break
                end
            end
            
            if not isLooted then
                table.insert(unlootedCorpses, corpse)
            end
        end
        
        -- Print unlooted corpses
        if (#unlootedCorpses > 0) then
            mq.cmdf("/g "..mq.TLO.Me.Name().." unlooted corpses: " .. #unlootedCorpses)
        end
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
    
    -- Debug command to dump the shared items table
    -- Use: /mldebug or bind to a command
    function self.debugDumpSharedItems()
        print("===== SHARED ITEMS DEBUG DUMP =====")
        print(string.format("Character: %s", mq.TLO.Me.Name()))
        
        -- Dump multipleUseTable
        if lootManager.debugDumpSharedItems then
            lootManager.debugDumpSharedItems()
        else
            print("debugDumpSharedItems not available in LootManager")
        end
        
        -- Also dump listboxSelectedOption
        print("")
        print("===== LISTBOX SELECTION =====")
        if lootManager.listboxSelectedOption and next(lootManager.listboxSelectedOption) then
            print(string.format("  Selected: %s", lootManager.listboxSelectedOption.itemName or "nil"))
            print(string.format("  corpseId: %s (type: %s)", 
                tostring(lootManager.listboxSelectedOption.corpseId), 
                type(lootManager.listboxSelectedOption.corpseId)))
            print(string.format("  itemId: %s (type: %s)", 
                tostring(lootManager.listboxSelectedOption.itemId), 
                type(lootManager.listboxSelectedOption.itemId)))
        else
            print("  No item selected")
        end
        
        print("===== END DEBUG DUMP =====")
    end
    
    return self
end

return Commands