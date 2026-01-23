-- modules/LootState.lua
-- Shared state container for all loot-related modules

local LootState = {}

function LootState.new()
    return {
        -- Tracking looted corpses (used by /mlml)
        lootedCorpses = {},
        
        -- Shared items table (displayed in GUI listbox)
        multipleUseTable = {},
        listboxSelectedOption = {},
        
        -- Queue for items assigned to this character
        myQueuedItems = {},
        
        -- Upgrade tracking
        upgradeList = {},
        
        -- Find mode state
        findMode = false,
        findStrings = {},
        
        -- E3 toggle tracking
        e3LootWasEnabled = false,
        
        -- Scan mode state (new feature)
        scanMode = false,
        assignedCorpses = {},      -- Corpse IDs assigned to this character for scanning
        scanFailures = {},          -- Corpses that failed to scan
        scanItemCount = 0,          -- Count of items found during scan
        scanCorpseCount = 0,        -- Count of corpses scanned
    }
end

return LootState
