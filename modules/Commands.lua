-- modules/Commands.lua
local mq = require('mq')

local Commands = {}

function Commands.new(config, utils, itemEvaluator, corpseManager, lootManager, iniManager, corpseScanner)
    local self = {
        loopBoolean = true,
        config = config,
        utils = utils,
        itemEvaluator = itemEvaluator,
        corpseManager = corpseManager,
        lootManager = lootManager,
        iniManager = iniManager,
        corpseScanner = corpseScanner
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
    
    -- NEW: Find loot command - searches corpses for items matching any of the provided substrings
    -- Usage: /mlfind "search1" "search2" "search3" or /mlfind search (single unquoted)
    -- Prefix with + to loot all regardless of ownership: "+immortality"
    function self.findLoot(line)
        local searchStrings = {}
        
        -- MQ passes all arguments as a single string in 'line'
        -- We need to parse it ourselves
        if not line or line == "" then
            print("Usage: /mlfind \"<search string>\" [\"<search string 2>\" ...]")
            print("Prefix with + to loot all (ignore ownership): \"+immortality\"")
            print("Example: /mlfind \"Tome of Power\"")
            print("Example: /mlfind \"astrial\" \"hermit\" \"celestial\"")
            print("Example: /mlfind \"astrial\" \"+immortality\" (loot all immortality items)")
            print("Example: /mlfind sword")
            return
        end
        
        -- Debug: print raw input
        if lootManager.debugEnabled then
            print(string.format("[FindMode] Raw input: '%s'", line))
        end
        
        -- Parse quoted strings (handles both "string" and "+string" inside quotes)
        -- Pattern: "([^"]*)" matches content between double quotes (including empty)
        for quoted in string.gmatch(line, '"([^"]*)"') do
            local trimmed = quoted:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                table.insert(searchStrings, trimmed)
                if lootManager.debugEnabled then
                    print(string.format("[FindMode] Parsed quoted: '%s'", trimmed))
                end
            end
        end
        
        -- Also check for single-quoted strings
        for quoted in string.gmatch(line, "'([^']*)'") do
            local trimmed = quoted:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                table.insert(searchStrings, trimmed)
                if lootManager.debugEnabled then
                    print(string.format("[FindMode] Parsed single-quoted: '%s'", trimmed))
                end
            end
        end
        
        -- If no quoted strings found, treat the whole input as a single search term
        if #searchStrings == 0 then
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                table.insert(searchStrings, trimmed)
                if lootManager.debugEnabled then
                    print(string.format("[FindMode] No quotes found, using whole input: '%s'", trimmed))
                end
            end
        end
        
        if #searchStrings == 0 then
            print("Usage: /mlfind \"<search string>\" [\"<search string 2>\" ...]")
            print("Prefix with + to loot all (ignore ownership): \"+immortality\"")
            print("Example: /mlfind \"astrial\" \"+hermit\" \"celestial\"")
            return
        end
        
        -- Print what we parsed (debug only)
        if lootManager.debugEnabled then
            print(string.format("[FindMode] Parsed %d search terms:", #searchStrings))
            for i, str in ipairs(searchStrings) do
                print(string.format("[FindMode]   [%d] '%s'", i, str))
            end
        end
        
        lootManager.doFindLoot(searchStrings)
    end
    
    -- NEW: Scan corpses command handler
    -- Can be called directly via /mlscan or via event from group chat
    -- Direct: /mlscan CharName 142,156,178
    -- Event: receives (line, charName, corpseIds) from pattern '#*#mlscan #1# #2#'
    function self.scanCorpses(lineOrCharName, charNameOrCorpseIds, corpseIdsOrNil)
        -- Guard: If called with no arguments or empty string, silently return
        -- This can happen during startup when events are registered
        if not lineOrCharName or lineOrCharName == "" then
            return
        end
        
        if corpseScanner then
            local charName, corpseIdStr
            
            -- Determine if called from event (3 args) or bind (1 arg)
            if corpseIdsOrNil then
                -- Called from event: (line, charName, corpseIds)
                charName = charNameOrCorpseIds
                corpseIdStr = corpseIdsOrNil
            elseif charNameOrCorpseIds then
                -- Called with 2 args: (charName, corpseIds) 
                charName = lineOrCharName
                corpseIdStr = charNameOrCorpseIds
            else
                -- Called from bind with single line arg: "CharName 142,156,178"
                charName, corpseIdStr = string.match(lineOrCharName or "", "^(%S+)%s+(.+)$")
            end
            
            if charName and corpseIdStr then
                local combined = charName .. " " .. corpseIdStr
                corpseScanner.handleScanCommand(combined)
            else
                print("[CorpseScanner] ERROR: Invalid /mlscan format. Expected: /mlscan <charName> <corpseId1>,<corpseId2>,...")
            end
        else
            print("[Commands] ERROR: CorpseScanner not initialized")
        end
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