-- modules/LootManager.lua
local mq = require('mq')

local LootManager = {}

function LootManager.new(config, utils, itemEvaluator, corpseManager, navigation, actorManager, itemScore)
    local self = {
        multipleUseTable = {},
        myQueuedItems = {},
        listboxSelectedOption = {},
        lootedCorpses = {},
        upgradeList = {},  -- NEW: Track upgrades for this character
        config = config,
        utils = utils,
        itemEvaluator = itemEvaluator,
        corpseManager = corpseManager,
        navigation = navigation,
        actorManager = actorManager,
        itemScore = itemScore,  -- NEW: ItemScore module
        debugEnabled = false,  -- Toggle for debug printing
        delays = {
            windowClose = 50,
            itemLoot = 250,
            quantityAccept = 100,
            corpseTarget = 100,
            corpseOpen = 1500,          -- OPTIMIZED: Reduced from 5000 (97% of opens are instant)
            corpseFix = 1000,
            lootCommand = 250,
            corpseItemWait = 500,       -- OPTIMIZED: Reduced from 3000 (items load instantly)
            postNavigation = 300,
            postNavigationRetry = 250,
            autoInventory = 250,
            stickOff = 250,
            warpMovement = 250,
            navigationMovement = 2000
        }
    }
    
    -- Debug print function
    function self.debugPrint(message)
        if self.debugEnabled then
            print(string.format("[LootManager]: %s", message))
        end
    end
    
    -- Function to toggle debug mode
    function self.setDebug(enabled)
        self.debugEnabled = enabled
        if enabled then
            print("[LootManager]: Debug mode ENABLED")
        else
            print("[LootManager]: Debug mode DISABLED")
        end
    end
    
    function self.verifyTarget(corpseId)
        -- Check if Target exists (not nil) and ID matches
        return mq.TLO.Target() and mq.TLO.Target.ID() == corpseId
    end
    
    function self.corpseStillExists(corpseId)
        -- Check if corpse spawn still exists before attempting to loot
        -- This prevents wasting time on despawned corpses
        local spawn = mq.TLO.Spawn(corpseId)
        if spawn and spawn.ID() and spawn.ID() > 0 then
            -- Double-check it's actually a corpse
            if spawn.Type() == "Corpse" then
                return true
            end
        end
        return false
    end

    function self.isWindowOpen(windowName)
        return mq.TLO.Window(windowName).Open()
    end

    function self.isWindowClosed(windowName)
        return not mq.TLO.Window(windowName).Open()
    end

    function self.handleSharedItem(message)
        -- Debug: Log raw message types to detect serialization issues
        self.debugPrint(string.format("Received shared item message - Raw types: corpseId=%s (%s), itemId=%s (%s), count=%s", 
            tostring(message.corpseId), type(message.corpseId),
            tostring(message.itemId), type(message.itemId),
            tostring(message.count)))
        
        -- Normalize corpseId and itemId to numbers to prevent type mismatch issues
        -- Actor serialization can sometimes convert numbers to strings
        local normalizedCorpseId = tonumber(message.corpseId)
        local normalizedItemId = tonumber(message.itemId)
        local normalizedCount = tonumber(message.count) or 1
        
        -- Debug: Warn if type conversion was needed
        if type(message.corpseId) ~= "number" then
            self.debugPrint(string.format("WARNING: corpseId arrived as %s, converted to number %s", 
                type(message.corpseId), normalizedCorpseId))
        end
        if type(message.itemId) ~= "number" then
            self.debugPrint(string.format("WARNING: itemId arrived as %s, converted to number %s", 
                type(message.itemId), normalizedItemId))
        end
        
        self.debugPrint(string.format("Handling shared item: %s (ID: %s) from corpse %s, isLore: %s, count: %d", 
            message.itemName, normalizedItemId, normalizedCorpseId, tostring(message.isLore), normalizedCount))
        
        local item = {
            corpseId = normalizedCorpseId,
            itemId = normalizedItemId,
            itemName = message.itemName,
            itemLink = message.itemLink,
            isLore = message.isLore or false,
            count = normalizedCount
        }

        if next(self.listboxSelectedOption) == nil then
            self.listboxSelectedOption = {
                corpseId = normalizedCorpseId,
                itemId = normalizedItemId,
                itemName = message.itemName,
                isLore = message.isLore or false
            }
            self.debugPrint("Set listboxSelectedOption to first shared item")
        end
        
        -- Debug: Log the key being used for multipleUseTable
        self.debugPrint(string.format("Inserting into multipleUseTable with key: %s (type: %s), count: %d", 
            normalizedCorpseId, type(normalizedCorpseId), normalizedCount))
        
        local insertResult = utils.multimapInsert(self.multipleUseTable, normalizedCorpseId, item)
        self.debugPrint(string.format("multimapInsert result: %s", tostring(insertResult)))
    end
    
    -- Debug function to dump the entire multipleUseTable state
    function self.debugDumpSharedItems()
        self.debugPrint("===== SHARED ITEMS TABLE DUMP =====")
        local totalItems = 0
        for corpseId, items in pairs(self.multipleUseTable) do
            self.debugPrint(string.format("  Corpse KEY: %s (type: %s)", tostring(corpseId), type(corpseId)))
            for idx, item in ipairs(items) do
                totalItems = totalItems + 1
                self.debugPrint(string.format("    [%d] itemName=%s, itemId=%s (type: %s), item.corpseId=%s (type: %s), count=%d, isLore=%s", 
                    idx, 
                    item.itemName, 
                    tostring(item.itemId), type(item.itemId),
                    tostring(item.corpseId), type(item.corpseId),
                    item.count or 1,
                    tostring(item.isLore)))
                
                -- Check for mismatch between key and stored corpseId
                if corpseId ~= item.corpseId then
                    self.debugPrint(string.format("    *** MISMATCH DETECTED! Key=%s, item.corpseId=%s ***", 
                        tostring(corpseId), tostring(item.corpseId)))
                end
            end
        end
        self.debugPrint(string.format("===== Total: %d items across %d corpses =====", 
            totalItems, self.tableLength(self.multipleUseTable)))
    end
    
    -- Helper to count table entries
    function self.tableLength(t)
        local count = 0
        for _ in pairs(t) do count = count + 1 end
        return count
    end
    
    function self.printMultipleUseItems()
        self.debugPrint("Printing multiple use items to group")
        mq.cmdf("/g List of items that can be used by members of your group")
        for corpseId, valueList in pairs(self.multipleUseTable) do
            for _, value in ipairs(valueList) do
                local countStr = ""
                if (value.count or 1) > 1 then
                    countStr = string.format(" x%d", value.count)
                end
                mq.cmdf("/g %s%s", value.itemLink, countStr)
            end
        end
        
        -- NEW: Print upgrade information after item list (no delay needed)
        self.printUpgradeList()
    end
    
    -- NEW: Function to print upgrade list
    function self.printUpgradeList(itemName)
        self.debugPrint(string.format("printUpgradeList called - upgradeList has %d items", #self.upgradeList))
    
        if #self.upgradeList == 0 then
            self.debugPrint("No upgrades in list, returning")
            return
        end
        
        local myName = mq.TLO.Me.Name()
        
        for _, upgrade in ipairs(self.upgradeList) do
            -- Skip this upgrade if itemName is provided and doesn't match
            if itemName and upgrade.itemName ~= itemName then
                self.debugPrint(string.format("Skipping upgrade for %s (filtering for %s)", 
                    upgrade.itemName, itemName))
                goto continue
            end
            
            self.debugPrint(string.format("Processing upgrade - improvement = %s (type: %s)", 
                tostring(upgrade.improvement), type(upgrade.improvement)))
            
            local improvementStr = ""
            if upgrade.improvement >= 999 then
                improvementStr = "NEW/Empty"
            else
                improvementStr = string.format("+%.1f%%", upgrade.improvement)
            end
            
            mq.cmdf("/g %s wants %s for %s (%s)", 
                myName, upgrade.itemName, upgrade.slotName, improvementStr)
            
            ::continue::
        end
    end
    
    function self.isLooted(corpseId)
        return utils.contains(self.lootedCorpses, corpseId)
    end
    
    function self.checkInventorySpace()
        local slotsRemaining = mq.TLO.Me.FreeInventory() - config.defaultSlotsToKeepFree
        
        self.debugPrint(string.format("Checking inventory space: %d slots remaining", slotsRemaining))
        
        if slotsRemaining < 1 then
            mq.cmdf("/beep")
            mq.cmdf('/g ' .. mq.TLO.Me.Name() .. " inventory is Full!")
            self.debugPrint("Inventory is FULL!")
        end
    end
    
    function self.closeLootWindow()
        if mq.TLO.Window("LootWnd").Open() then
            self.debugPrint("Closing loot window")
            mq.cmdf("/notify LootWnd LW_DoneButton leftmouseup")
            mq.delay(self.delays.windowClose, function() return self.isWindowClosed("LootWnd") end)
        end
    end
    
    function self.lootItem(corpseItem, slotIndex)
        self.debugPrint(string.format("Looting item: %s from slot %d", corpseItem.Name(), slotIndex))
        mq.cmdf('/g '..mq.TLO.Me.Name().." is looting ".. corpseItem.ItemLink('CLICKABLE')())
        mq.cmdf("/shift /itemnotify loot%d rightmouseup", slotIndex)
        mq.delay(self.delays.itemLoot)
        
        if self.isWindowOpen("QuantityWnd") then
            self.debugPrint("Quantity window opened, accepting")
            mq.cmdf("/notify QuantityWnd QTYW_Accept_Button leftmouseup")
            mq.delay(self.delays.quantityAccept, function() return self.isWindowClosed("QuantityWnd") end)
        end
    end
    
    function self.lootCorpse(corpseObject, isMaster)
        self.debugPrint(string.format("Starting to loot corpse ID: %s", corpseObject.ID))
        
        -- OPTIMIZATION: Final check that corpse still exists before attempting to target
        if not self.corpseStillExists(corpseObject.ID) then
            self.debugPrint(string.format("Corpse ID %s despawned before looting, skipping", corpseObject.ID))
            table.insert(self.lootedCorpses, corpseObject.ID)
            return
        end
        
        mq.cmdf("/target id %d", corpseObject.ID)
        mq.delay(self.delays.corpseTarget, function() return self.verifyTarget(corpseObject.ID) end)
        mq.cmdf("/loot")
        mq.delay(self.delays.corpseOpen, function() return self.isWindowOpen("LootWnd") end)

        local retryCount = 0
        local maxRetries = 5

        if (self.isWindowClosed("LootWnd")) then
            self.debugPrint("Loot window failed to open, retrying...")
            while retryCount < maxRetries do
                if retryCount > 3 then
                    self.debugPrint("Using corpsefix command")
                    mq.cmdf("/say #corpsefix")
                end
                mq.delay(self.delays.corpseFix)
                navigation.navigateToCorpse(self.config, corpseObject.ID)
                mq.cmdf("/loot")
                mq.delay(self.delays.lootCommand, function() return self.isWindowOpen("LootWnd") end)
                retryCount = retryCount + 1
                
                if self.isWindowOpen("LootWnd") then
                    self.debugPrint("Loot window opened after retry")
                    break
                end
            end
            
            if retryCount >= maxRetries and self.isWindowClosed("LootWnd") then
                self.debugPrint("Failed to open loot window after max retries, will retry later")
                return "retry"
            end
        end

        if((mq.TLO.Target.ID() or 0)==0) then
            self.debugPrint("Target lost, marking corpse as looted")
            table.insert(self.lootedCorpses, corpseObject.ID)
            return
        end

        -- Verify we still have the correct target (should always be true since we only /target once)
        if mq.TLO.Target.ID() ~= corpseObject.ID then
            self.debugPrint(string.format("WARNING: Target mismatch! Expected %s, got %s. This should not happen.",
                corpseObject.ID, mq.TLO.Target.ID()))
            table.insert(self.lootedCorpses, corpseObject.ID)
            self.closeLootWindow()
            return
        end
        
        self.debugPrint(string.format("Looting from corpse ID: %s", corpseObject.ID))
        
        -- CRITICAL FIX: Verify that the LOOT WINDOW is showing the corpse we intended to loot
        -- mq.TLO.Target.ID() = what we targeted
        -- mq.TLO.Corpse.ID() = whose loot window is actually open (can be different!)
        local lootWindowCorpseId = mq.TLO.Corpse.ID()
        if lootWindowCorpseId ~= corpseObject.ID then
            self.debugPrint(string.format("*** LOOT WINDOW MISMATCH! Target=%s, LootWindow=%s ***", 
                corpseObject.ID, lootWindowCorpseId))
            self.debugPrint("The /loot command opened a different corpse's loot window! Will retry later.")
            -- Close this wrong window
            self.closeLootWindow()
            -- Return 'retry' to signal caller to add corpse back to the table
            return "retry"
        end
        
        local itemCount = tonumber(mq.TLO.Corpse.Items()) or 0
        self.debugPrint(string.format("Corpse has %d items", itemCount))
        
        -- COMPREHENSIVE CORPSE CONTENTS DUMP
        -- Log all items on this corpse for debugging
        if itemCount > 0 then
            local actualTargetId = mq.TLO.Target.ID() or 0
            local actualCorpseId = mq.TLO.Corpse.ID() or 0
            self.debugPrint(string.format("=== CORPSE CONTENTS DUMP ==="))
            self.debugPrint(string.format("  corpseObject.ID (intended): %s", tostring(corpseObject.ID)))
            self.debugPrint(string.format("  mq.TLO.Target.ID(): %s", tostring(actualTargetId)))
            self.debugPrint(string.format("  mq.TLO.Corpse.ID(): %s", tostring(actualCorpseId)))
            self.debugPrint(string.format("  Corpse Name: %s", mq.TLO.Target.CleanName() or "unknown"))
            self.debugPrint(string.format("  Item Count: %d", itemCount))
            for idx = 1, itemCount do
                local item = mq.TLO.Corpse.Item(idx)
                if item and item.ID() then
                    self.debugPrint(string.format("  [%d] %s (ID: %s)", idx, item.Name() or "nil", tostring(item.ID())))
                else
                    self.debugPrint(string.format("  [%d] <nil or no ID>", idx))
                end
            end
            self.debugPrint(string.format("============================="))
        end
        
        if itemCount == 0 then
            self.debugPrint(string.format("Corpse %s has no items (already looted by another player), marking as looted", corpseObject.ID))
            table.insert(self.lootedCorpses, corpseObject.ID)
            self.closeLootWindow()
            return
        end
        
        -- Get the actual loot window corpse ID (use this for all operations)
        local actualLootCorpseId = mq.TLO.Corpse.ID() or 0
        local correctCorpseId = actualLootCorpseId or corpseObject.ID
        
        -- SAFETY CHECK: Don't process if corpseId is 0 or nil (corpse despawned)
        if not correctCorpseId or correctCorpseId == 0 then
            self.debugPrint("WARNING: Invalid corpseId (0 or nil), skipping corpse")
            self.closeLootWindow()
            return
        end
        
        -- PHASE 1: Build temporary table of all items on corpse
        -- This allows us to count duplicates before broadcasting
        local tempSharedItems = {}  -- Key: itemId, Value: {item data with count}
        local itemsToLoot = {}      -- List of {slot, corpseItem} to loot
        
        self.debugPrint("=== PHASE 1: Building item inventory ===")
        
        for i = 1, itemCount do
            mq.delay(self.delays.corpseItemWait, function() return mq.TLO.Corpse.Item(i).ID() end)
            local corpseItem = mq.TLO.Corpse.Item(i)
            
            if not corpseItem or not corpseItem.ID() then
                self.debugPrint(string.format("Slot %d: Invalid item, skipping", i))
                goto continue_phase1
            end
            
            local itemId = corpseItem.ID()
            local itemName = corpseItem.Name()
            local isSharedItem = utils.contains(config.itemsToShare, itemName)
            
            if itemEvaluator.shouldLoot(config, utils, corpseItem) and (not isSharedItem) then
                -- Item should be looted by this character
                self.debugPrint(string.format("Slot %d: %s - will loot", i, itemName))
                table.insert(itemsToLoot, {slot = i, item = corpseItem})
            elseif (itemEvaluator.groupMembersCanUse(corpseItem) > 1 or isSharedItem) and 
                   (not itemEvaluator.skipItem(config, utils, corpseItem)) then
                -- Shared item - add to temp table with count
                if tempSharedItems[itemId] then
                    -- Duplicate item, increment count
                    tempSharedItems[itemId].count = tempSharedItems[itemId].count + 1
                    self.debugPrint(string.format("Slot %d: %s - shared item (duplicate, count now %d)", 
                        i, itemName, tempSharedItems[itemId].count))
                else
                    -- New shared item
                    tempSharedItems[itemId] = {
                        itemId = itemId,
                        itemName = itemName,
                        itemLink = corpseItem.ItemLink('CLICKABLE')(),
                        isLore = corpseItem.Lore() or false,
                        count = 1,
                        corpseItem = corpseItem  -- Keep reference for upgrade check
                    }
                    self.debugPrint(string.format("Slot %d: %s - shared item (count 1)", i, itemName))
                end
            else
                self.debugPrint(string.format("Slot %d: %s - skipped", i, itemName))
            end
            
            ::continue_phase1::
        end
        
        -- PHASE 2: Loot items that this character should take
        self.debugPrint("=== PHASE 2: Looting items ===")
        
        for _, lootEntry in ipairs(itemsToLoot) do
            self.checkInventorySpace()
            self.lootItem(lootEntry.item, lootEntry.slot)
        end
        
        -- PHASE 3: Process and broadcast shared items with counts
        self.debugPrint("=== PHASE 3: Processing shared items ===")
        
        for itemId, sharedItem in pairs(tempSharedItems) do
            self.debugPrint(string.format("Processing shared item: %s (ID: %d, count: %d, isLore: %s)", 
                sharedItem.itemName, itemId, sharedItem.count, tostring(sharedItem.isLore)))
            
            -- Check if this item is already in multipleUseTable (another character already reported it)
            local alreadyReported = false
            if self.multipleUseTable[correctCorpseId] then
                for _, existingItem in ipairs(self.multipleUseTable[correctCorpseId]) do
                    if existingItem.itemId == itemId then
                        alreadyReported = true
                        self.debugPrint(string.format("Item %s already reported on corpse %s, updating count from %d to %d", 
                            sharedItem.itemName, correctCorpseId, existingItem.count, sharedItem.count))
                        -- Update the count to the latest value (last count wins)
                        existingItem.count = sharedItem.count
                        break
                    end
                end
            end
            
            if not alreadyReported then
                -- First time seeing this item - announce and broadcast
                if sharedItem.count > 1 then
                    mq.cmdf("/g Shared Item: %s x%d", sharedItem.itemLink, sharedItem.count)
                else
                    mq.cmdf("/g Shared Item: %s", sharedItem.itemLink)
                end
                
                -- Build message for local handling and broadcast
                local sharedItemMessage = {
                    corpseId = correctCorpseId,
                    itemId = itemId,
                    itemName = sharedItem.itemName,
                    itemLink = sharedItem.itemLink,
                    isLore = sharedItem.isLore,
                    count = sharedItem.count
                }
                
                -- Add to local table
                self.handleSharedItem(sharedItemMessage)
                
                -- Broadcast to group with count
                self.debugPrint(string.format("Broadcasting shared item to group: corpseId=%s, itemId=%s, count=%d, isLore=%s", 
                    correctCorpseId, itemId, sharedItem.count, tostring(sharedItem.isLore)))
                actorManager.broadcastShareItem(
                    correctCorpseId,
                    itemId, 
                    sharedItem.itemName, 
                    sharedItem.itemLink,
                    sharedItem.isLore,
                    sharedItem.count
                )
            end
            
            -- ALWAYS check for upgrades (even if item was already reported by another character)
            local upgradeInfo = self.itemScore.evaluateItemForUpgrade(sharedItem.corpseItem)
            if upgradeInfo then
                self.debugPrint(string.format("Item %s is an upgrade: +%.1f%% for %s", 
                    sharedItem.itemName, upgradeInfo.improvement, upgradeInfo.slotName))
                
                local found = false
                for _, existingUpgrade in ipairs(self.upgradeList) do
                    if existingUpgrade.corpseId == correctCorpseId and 
                       existingUpgrade.itemId == itemId then
                        existingUpgrade.slotName = upgradeInfo.slotName
                        existingUpgrade.improvement = upgradeInfo.improvement
                        self.debugPrint(string.format("Updated existing upgrade entry for %s", sharedItem.itemName))
                        found = true
                        break
                    end
                end
                
                if not found then
                    local newUpgrade = {
                        corpseId = correctCorpseId,
                        itemId = itemId,
                        itemName = sharedItem.itemName,
                        slotName = upgradeInfo.slotName,
                        improvement = upgradeInfo.improvement
                    }
                    table.insert(self.upgradeList, newUpgrade)
                    self.debugPrint(string.format("Added new upgrade entry for %s: %.1f%% for %s", 
                        sharedItem.itemName, newUpgrade.improvement, newUpgrade.slotName))
                end
            end
        end
        
        table.insert(self.lootedCorpses, corpseObject.ID)
        self.debugPrint(string.format("Finished looting corpse %s, marked as looted", corpseObject.ID))
        self.closeLootWindow()
    end
    
    function self.openCorpse(corpseId)
        self.debugPrint(string.format("Opening corpse ID: %s", corpseId))
        
        mq.cmdf("/target id %d", corpseId)
        mq.delay(self.delays.corpseTarget, function() return self.verifyTarget(corpseId) end)
        
        if (mq.TLO.Target.ID() or 0) == 0 then
            print("ERROR: Failed to target corpse ID: " .. tostring(corpseId))
            self.debugPrint("Failed to target corpse")
            return false
        end
        
        navigation.navigateToCorpse(self.config, corpseId)
        
        mq.cmdf("/loot")
        mq.delay(self.delays.corpseOpen, function() return self.isWindowOpen("LootWnd") end)
        local retryCount = 0
        local retryMax = 5

        while self.isWindowClosed("LootWnd") and (retryCount < retryMax) do
            if retryCount > 3 then
                self.debugPrint("Using corpsefix after multiple retries")
                mq.cmdf("/say #corpsefix")
            end
            mq.delay(self.delays.corpseFix)  
            navigation.navigateToCorpse(self.config, corpseId)
            mq.cmdf("/loot")
            mq.delay(self.delays.corpseOpen, function() return self.isWindowOpen("LootWnd") end)
            retryCount = retryCount + 1
        end

        if retryCount >= retryMax then
            self.debugPrint("Failed to open corpse after max retries")
            mq.cmdf("/g Could not loot targeted corpse, skipping.")
            return false
        end
        
        self.debugPrint("Successfully opened corpse")
        return true
    end
    
    -- Loot all queued items for a single corpse in a single pass
    -- Returns a table of results: { {itemId=X, itemName=S, expectedCount=N, actualLooted=M}, ... }
    function self.lootAllQueuedItemsFromCorpse(corpseId, queuedItems)
        local results = {}
        local corpseItemCount = tonumber(mq.TLO.Corpse.Items()) or 0
        
        self.debugPrint(string.format("Looting %d queued item types from corpse %s (corpse has %d items)", 
            #queuedItems, tostring(corpseId), corpseItemCount))
        
        if corpseItemCount == 0 then
            self.debugPrint("Corpse is empty, returning empty results")
            for _, queuedItem in ipairs(queuedItems) do
                table.insert(results, {
                    itemId = queuedItem.itemId,
                    itemName = queuedItem.itemName,
                    expectedCount = queuedItem.count or 1,
                    actualLooted = 0
                })
            end
            return results
        end
        
        -- Build a list of what we need to loot: {queuedItem, remaining count, looted count}
        local itemsToLoot = {}
        for _, queuedItem in ipairs(queuedItems) do
            table.insert(itemsToLoot, {
                queuedItem = queuedItem,
                remaining = queuedItem.count or 1,
                looted = 0
            })
        end
        
        -- Process each queued item, scanning corpse fresh each time
        -- This handles slot index shifting after each loot
        for _, lootEntry in ipairs(itemsToLoot) do
            self.debugPrint(string.format("Looking for item: %s (ID: %s)", 
                lootEntry.queuedItem.itemName, tostring(lootEntry.queuedItem.itemId)))
            
            while lootEntry.remaining > 0 do
                self.checkInventorySpace()
                
                -- Re-query corpse item count (may have changed after previous loot)
                local currentCorpseItemCount = tonumber(mq.TLO.Corpse.Items()) or 0
                
                if currentCorpseItemCount == 0 then
                    self.debugPrint("Corpse is now empty, stopping")
                    break
                end
                
                self.debugPrint(string.format("Scanning %d corpse slots for itemId %s", 
                    currentCorpseItemCount, tostring(lootEntry.queuedItem.itemId)))
                
                -- Scan corpse to find this item
                local foundSlot = nil
                for i = 1, currentCorpseItemCount do
                    mq.delay(self.delays.corpseItemWait, function() return mq.TLO.Corpse.Item(i).ID() end)
                    local corpseItem = mq.TLO.Corpse.Item(i)
                    
                    if corpseItem and corpseItem.ID() then
                        local localItemId = corpseItem.ID()
                        
                        self.debugPrint(string.format("  Slot %d: %s (ID: %s) - looking for %s", 
                            i, corpseItem.Name() or "unknown", tostring(localItemId), tostring(lootEntry.queuedItem.itemId)))
                        
                        if localItemId == lootEntry.queuedItem.itemId then
                            self.debugPrint(string.format("Found queued item %s at slot %d", 
                                corpseItem.Name(), i))
                            foundSlot = i
                            break
                        end
                    end
                end
                
                if not foundSlot then
                    -- Item not found on corpse, stop looking for more of this item
                    self.debugPrint(string.format("Could not find %s on corpse", 
                        lootEntry.queuedItem.itemName))
                    break
                end
                
                -- Loot the item from the found slot
                local corpseItem = mq.TLO.Corpse.Item(foundSlot)
                local itemNameToLoot = corpseItem.Name()
                local preCount = tonumber(mq.TLO.Corpse.Items()) or 0
                
                self.lootItem(corpseItem, foundSlot)
                
                -- Wait a moment for the loot to process
                mq.delay(500)
                
                -- Check if item was looted by seeing if corpse item count decreased
                -- or if the item is no longer at that slot
                local postCount = tonumber(mq.TLO.Corpse.Items()) or 0
                local itemStillThere = false
                
                -- Re-scan to see if the item is still on the corpse
                for i = 1, postCount do
                    local checkItem = mq.TLO.Corpse.Item(i)
                    if checkItem and checkItem.ID() == lootEntry.queuedItem.itemId then
                        itemStillThere = true
                        break
                    end
                end
                
                if not itemStillThere then
                    -- Item was successfully looted (no longer on corpse)
                    lootEntry.looted = lootEntry.looted + 1
                    lootEntry.remaining = lootEntry.remaining - 1
                    
                    self.debugPrint(string.format("SUCCESS: Looted %s (%d/%d) - item no longer on corpse", 
                        lootEntry.queuedItem.itemName, lootEntry.looted, lootEntry.queuedItem.count or 1))
                    
                    -- Handle cursor if item ended up there
                    if mq.TLO.Cursor() then
                        mq.cmdf("/autoinventory")
                        mq.delay(self.delays.autoInventory, function() return not mq.TLO.Cursor() end)
                    end
                else
                    -- Item is still on corpse - loot failed
                    self.debugPrint(string.format("FAILED: %s - item still on corpse after loot attempt", 
                        lootEntry.queuedItem.itemName))
                    break
                end
            end
        end
        
        -- Build results from our tracking table
        for _, lootEntry in ipairs(itemsToLoot) do
            local expectedCount = lootEntry.queuedItem.count or 1
            local actualLooted = lootEntry.looted
            
            table.insert(results, {
                itemId = lootEntry.queuedItem.itemId,
                itemName = lootEntry.queuedItem.itemName,
                expectedCount = expectedCount,
                actualLooted = actualLooted
            })
            
            -- Report if we couldn't find all expected items
            if actualLooted < expectedCount then
                local myName = mq.TLO.Me.Name()
                mq.cmdf("/g %s could not find %s (expected %d, found %d) on corpse %d", 
                    myName, lootEntry.queuedItem.itemName or "item", expectedCount, actualLooted, corpseId)
                self.debugPrint(string.format("WARNING: %s - Expected %d, only looted %d", 
                    lootEntry.queuedItem.itemName, expectedCount, actualLooted))
            end
        end
        
        return results
    end
    
    function self.lootQueuedItems()
        if not self.myQueuedItems or not next(self.myQueuedItems) then
            self.debugPrint("No items in queue to loot")
            return
        end

        local myName = mq.TLO.Me.Name()
        self.debugPrint("Starting to loot queued items")
        mq.cmdf("/g %s is starting to loot queued items", myName)
        
        -- Save starting location
        local startingLocation = {
            X = mq.TLO.Me.X(),
            Y = mq.TLO.Me.Y(),
            Z = mq.TLO.Me.Z(),
            timeToWait = "2s"
        }
        self.debugPrint(string.format("Starting location: X=%.2f, Y=%.2f, Z=%.2f", 
            startingLocation.X, startingLocation.Y, startingLocation.Z))
        
        -- Turn off stick if active
        local stickState = false
        if mq.TLO.Stick.Active() then
            self.debugPrint("Turning off stick")
            stickState = true
            mq.cmdf("/stick off")
        end
        mq.delay(self.delays.stickOff)
        
        -- Build corpse table from myQueuedItems keys
        local corpseTable = {}
        for corpseId, _ in pairs(self.myQueuedItems) do
            table.insert(corpseTable, { ID = corpseId })
        end
        
        self.debugPrint(string.format("Built corpse table with %d unique corpses from queue", #corpseTable))
        
        -- Tracking variables
        local corpsesProcessed = 0
        local corpsesLooted = 0
        local corpsesDespawned = 0
        local corpsesFailed = 0
        local retryCount = {}
        local maxRetries = 3
        
        -- Process corpses with retry logic (similar to doLoot)
        while #corpseTable > 0 do
            -- Get next corpse (using simple removal from end for efficiency)
            local currentCorpse = table.remove(corpseTable)
            local corpseId = currentCorpse.ID
            
            self.debugPrint(string.format("Processing corpse %s from queue (%d remaining)", 
                tostring(corpseId), #corpseTable))
            mq.cmdf("/g %s: Processing queued items from corpse %d", myName, corpseId)
            
            corpsesProcessed = corpsesProcessed + 1
            
            -- Check if corpse still exists
            if not self.corpseStillExists(corpseId) then
                corpsesDespawned = corpsesDespawned + 1
                self.debugPrint(string.format("Corpse %s no longer exists (despawned)", corpseId))
                
                -- Report failure for all items on this corpse
                if self.myQueuedItems[corpseId] then
                    for _, queuedItem in pairs(self.myQueuedItems[corpseId]) do
                        mq.cmdf("/g %s: Corpse %d despawned, could not loot %s", 
                            myName, corpseId, queuedItem.itemName or "item")
                    end
                    -- Remove items from queue since corpse is gone
                    self.myQueuedItems[corpseId] = nil
                end
                goto continue_corpse
            end
            
            -- Navigate to corpse
            local navSuccess = navigation.navigateToCorpse(self.config, corpseId)
            
            if not navSuccess then
                self.debugPrint(string.format("Failed to navigate to corpse %s", corpseId))
                retryCount[corpseId] = (retryCount[corpseId] or 0) + 1
                
                if retryCount[corpseId] <= maxRetries then
                    self.debugPrint(string.format("Adding corpse %s back to table for retry (%d/%d)", 
                        corpseId, retryCount[corpseId], maxRetries))
                    table.insert(corpseTable, currentCorpse)
                else
                    self.debugPrint(string.format("Corpse %s exceeded max retries for navigation", corpseId))
                    corpsesFailed = corpsesFailed + 1
                    -- Report failure but keep items in queue (user might want to retry manually)
                    if self.myQueuedItems[corpseId] then
                        for _, queuedItem in pairs(self.myQueuedItems[corpseId]) do
                            mq.cmdf("/g %s: Failed to reach corpse %d for %s after %d retries", 
                                myName, corpseId, queuedItem.itemName or "item", maxRetries)
                        end
                    end
                end
                goto continue_corpse
            end
            
            -- Try to open corpse
            if not self.openCorpse(corpseId) then
                self.debugPrint(string.format("Failed to open corpse %s", corpseId))
                retryCount[corpseId] = (retryCount[corpseId] or 0) + 1
                
                if retryCount[corpseId] <= maxRetries then
                    self.debugPrint(string.format("Adding corpse %s back to table for retry (%d/%d)", 
                        corpseId, retryCount[corpseId], maxRetries))
                    table.insert(corpseTable, currentCorpse)
                else
                    self.debugPrint(string.format("Corpse %s exceeded max retries for opening", corpseId))
                    corpsesFailed = corpsesFailed + 1
                    if self.myQueuedItems[corpseId] then
                        for _, queuedItem in pairs(self.myQueuedItems[corpseId]) do
                            mq.cmdf("/g %s: Failed to open corpse %d for %s after %d retries", 
                                myName, corpseId, queuedItem.itemName or "item", maxRetries)
                        end
                    end
                end
                goto continue_corpse
            end
            
            -- Verify loot window is for the correct corpse
            local lootWindowCorpseId = mq.TLO.Corpse.ID()
            if lootWindowCorpseId ~= corpseId then
                self.debugPrint(string.format("Loot window mismatch! Expected %s, got %s", 
                    corpseId, lootWindowCorpseId))
                self.closeLootWindow()
                
                retryCount[corpseId] = (retryCount[corpseId] or 0) + 1
                if retryCount[corpseId] <= maxRetries then
                    self.debugPrint(string.format("Adding corpse %s back to table for retry (%d/%d)", 
                        corpseId, retryCount[corpseId], maxRetries))
                    table.insert(corpseTable, currentCorpse)
                else
                    self.debugPrint(string.format("Corpse %s exceeded max retries (loot window mismatch)", corpseId))
                    corpsesFailed = corpsesFailed + 1
                    if self.myQueuedItems[corpseId] then
                        for _, queuedItem in pairs(self.myQueuedItems[corpseId]) do
                            mq.cmdf("/g %s: Loot window issues for corpse %d, could not loot %s", 
                                myName, corpseId, queuedItem.itemName or "item")
                        end
                    end
                end
                goto continue_corpse
            end
            
            -- Successfully opened correct corpse - loot all queued items
            local queuedItems = self.myQueuedItems[corpseId]
            if queuedItems and #queuedItems > 0 then
                local lootResults = self.lootAllQueuedItemsFromCorpse(corpseId, queuedItems)
                
                -- Process results - remove successfully looted items from queue
                for _, result in ipairs(lootResults) do
                    if result.actualLooted > 0 then
                        -- Find and update/remove the item from myQueuedItems
                        for idx, queuedItem in ipairs(self.myQueuedItems[corpseId]) do
                            if queuedItem.itemId == result.itemId then
                                local remaining = (queuedItem.count or 1) - result.actualLooted
                                if remaining <= 0 then
                                    -- Fully looted, remove from queue
                                    table.remove(self.myQueuedItems[corpseId], idx)
                                    self.debugPrint(string.format("Removed %s from queue (fully looted)", 
                                        result.itemName))
                                else
                                    -- Partially looted, update count
                                    queuedItem.count = remaining
                                    self.debugPrint(string.format("Updated %s in queue (remaining: %d)", 
                                        result.itemName, remaining))
                                end
                                break
                            end
                        end
                    end
                end
                
                -- Clean up empty corpse entry
                if self.myQueuedItems[corpseId] and #self.myQueuedItems[corpseId] == 0 then
                    self.myQueuedItems[corpseId] = nil
                    self.debugPrint(string.format("Removed empty queue entry for corpse %s", corpseId))
                end
                
                corpsesLooted = corpsesLooted + 1
            end
            
            self.closeLootWindow()
            
            ::continue_corpse::
        end
        
        -- Summary
        self.debugPrint("========================================")
        self.debugPrint("QUEUED LOOTING SESSION COMPLETE")
        self.debugPrint(string.format("Corpses processed:       %d", corpsesProcessed))
        self.debugPrint(string.format("Corpses looted:          %d", corpsesLooted))
        self.debugPrint(string.format("Corpses despawned:       %d", corpsesDespawned))
        self.debugPrint(string.format("Corpses failed (retry):  %d", corpsesFailed))
        self.debugPrint("========================================")
        
        -- Check if any items remain in queue
        local remainingItems = 0
        for cId, items in pairs(self.myQueuedItems) do
            remainingItems = remainingItems + #items
        end
        if remainingItems > 0 then
            self.debugPrint(string.format("WARNING: %d items still in queue (failed to loot)", remainingItems))
            mq.cmdf("/g %s: %d queued items could not be looted", myName, remainingItems)
        end
        
        -- Return to starting location
        self.debugPrint("Returning to starting location")
        navigation.navigateToLocation(self.config, startingLocation.X, startingLocation.Y, startingLocation.Z)
        mq.delay(startingLocation.timeToWait)
        
        -- Restore stick state
        if stickState then
            self.debugPrint("Restoring stick state")
            mq.cmdf("/stick on")
        end
        
        mq.cmdf("/g %s is done looting queued items", myName)
        self.debugPrint("Finished looting queued items")
    end
    
    function self.doLoot(isMaster)
        self.debugPrint("Starting doLoot process")
        
        local startingLocation = {
            X = mq.TLO.Me.X(),
            Y = mq.TLO.Me.Y(),
            Z = mq.TLO.Me.Z(),
            timeToWait = "2s",
            arrivalDistance = 5
        }
        
        self.debugPrint(string.format("Starting location: X=%.2f, Y=%.2f, Z=%.2f", 
            startingLocation.X, startingLocation.Y, startingLocation.Z))
        
        local stickState = false
        self.myQueuedItems = {}
        self.listboxSelectedOption = {}

        mq.cmdf("/g " .. mq.TLO.Me.Name() .. " has started looting")
        
        if mq.TLO.Stick.Active() then
            self.debugPrint("Turning off stick")
            stickState = true
            mq.cmdf("/stick off")
        end
        
        mq.delay(self.delays.stickOff)
        
        -- VERBOSE DEBUG: Track SpawnCount vs corpseTable
        local spawnCount = mq.TLO.SpawnCount("npccorpse radius 200 zradius 30")()
        self.debugPrint(string.format("========================================"))
        self.debugPrint(string.format("STARTING CORPSE SCAN"))
        self.debugPrint(string.format("SpawnCount query returned: %d", spawnCount))
        
        local corpseTable = corpseManager.getCorpseTable(spawnCount)
        
        self.debugPrint(string.format("========================================"))
        self.debugPrint(string.format("CORPSE TABLE BUILT"))
        self.debugPrint(string.format("SpawnCount said: %d corpses exist", spawnCount))
        self.debugPrint(string.format("Table contains:  %d corpses", #corpseTable))
        if spawnCount ~= #corpseTable then
            self.debugPrint(string.format("⚠ MISMATCH: %d corpses were filtered out!", spawnCount - #corpseTable))
        end
        self.debugPrint(string.format("========================================"))

        local corpsesProcessed = 0
        local corpsesLooted = 0
        local corpsesDespawned = 0
        local corpsesSkipped = 0
        local corpsesFailed = 0   -- Corpses that exceeded max retries
        local retryCount = {}  -- Track retries per corpse ID
        local maxRetries = 3   -- Max retries before giving up on a corpse

        while #corpseTable > 0 do
            local currentCorpse
            self.debugPrint(string.format("Corpses Remaining in table: %d", #corpseTable))
            currentCorpse, corpseTable = corpseManager.getRandomCorpse(corpseTable)
            
            if currentCorpse and currentCorpse.ID and not self.isLooted(currentCorpse.ID) then
                corpsesProcessed = corpsesProcessed + 1
                
                -- OPTIMIZATION: Check if corpse still exists before attempting to loot
                -- This prevents wasting time on corpses that despawned (were looted by others)
                if not self.corpseStillExists(currentCorpse.ID) then
                    corpsesDespawned = corpsesDespawned + 1
                    self.debugPrint(string.format("Corpse ID %s no longer exists (despawned), skipping", currentCorpse.ID))
                    -- Mark as looted so we don't try again
                    table.insert(self.lootedCorpses, currentCorpse.ID)
                    goto continue
                end
                
                self.debugPrint(string.format("Processing corpse ID: %s (Processed: %d, Looted: %d, Despawned: %d)", 
                    currentCorpse.ID, corpsesProcessed, corpsesLooted, corpsesDespawned))
                local navSuccess = navigation.navigateToCorpse(self.config, currentCorpse.ID)
                
                if navSuccess then
                    self.debugPrint("Successfully navigated to corpse")
                    local lootResult = self.lootCorpse(currentCorpse, isMaster)
                    if lootResult == "retry" then
                        -- Loot window opened for wrong corpse, add back to table for retry
                        retryCount[currentCorpse.ID] = (retryCount[currentCorpse.ID] or 0) + 1
                        if retryCount[currentCorpse.ID] <= maxRetries then
                            self.debugPrint(string.format("Adding corpse %s back to table for retry (%d/%d)", 
                                currentCorpse.ID, retryCount[currentCorpse.ID], maxRetries))
                            table.insert(corpseTable, currentCorpse)
                        else
                            self.debugPrint(string.format("Corpse %s exceeded max retries (%d), marking as looted", 
                                currentCorpse.ID, maxRetries))
                            table.insert(self.lootedCorpses, currentCorpse.ID)
                            corpsesFailed = corpsesFailed + 1
                        end
                    elseif lootResult ~= false then  -- nil or true = success
                        corpsesLooted = corpsesLooted + 1
                    end
                else
                    self.debugPrint(string.format("Failed to navigate to corpse ID: %s, will retry", tostring(currentCorpse.ID)))
                    -- Add back to table for retry (same logic as loot window mismatch)
                    retryCount[currentCorpse.ID] = (retryCount[currentCorpse.ID] or 0) + 1
                    if retryCount[currentCorpse.ID] <= maxRetries then
                        self.debugPrint(string.format("Adding corpse %s back to table for retry (%d/%d)", 
                            currentCorpse.ID, retryCount[currentCorpse.ID], maxRetries))
                        table.insert(corpseTable, currentCorpse)
                    else
                        self.debugPrint(string.format("Corpse %s exceeded max retries (%d), marking as looted", 
                            currentCorpse.ID, maxRetries))
                        table.insert(self.lootedCorpses, currentCorpse.ID)
                        corpsesFailed = corpsesFailed + 1
                    end
                end
            else
                corpsesSkipped = corpsesSkipped + 1
                self.debugPrint(string.format("Corpse already looted or invalid (skipped count: %d)", corpsesSkipped))
            end
            
            ::continue::
        end
        
        self.debugPrint("========================================")
        self.debugPrint("LOOTING SESSION COMPLETE")
        self.debugPrint(string.format("Initial SpawnCount:      %d", spawnCount))
        self.debugPrint(string.format("Corpses in table:        %d", #corpseTable))
        self.debugPrint(string.format("Corpses processed:       %d", corpsesProcessed))
        self.debugPrint(string.format("Corpses looted:          %d", corpsesLooted))
        self.debugPrint(string.format("Corpses despawned:       %d", corpsesDespawned))
        self.debugPrint(string.format("Corpses skipped:         %d", corpsesSkipped))
        self.debugPrint(string.format("Corpses failed (retry):  %d", corpsesFailed))
        self.debugPrint(string.format("Unaccounted for:         %d", spawnCount - corpsesLooted - corpsesDespawned - corpsesSkipped - corpsesFailed))
        self.debugPrint("========================================")
        
        self.debugPrint("Returning to starting location")
        navigation.navigateToLocation(self.config, startingLocation.X, startingLocation.Y, startingLocation.Z)
        mq.delay(startingLocation.timeToWait)
        
        mq.cmdf("/g " .. mq.TLO.Me.Name() .. " is done Looting")
        self.debugPrint("Looting complete")
    end
    
    -- Queue an item for this character to loot
    -- Called via event when another player sends: /g mlqi <memberName> <corpseId> <itemId> <itemName> <isLore>
    function self.queueItem(line, groupMemberName, corpseId, itemId, itemName, isLore)
        local myName = tostring(mq.TLO.Me.Name())
        
        if groupMemberName ~= myName then
            return
        end
        
        -- Convert isLore string to boolean
        local isLoreItem = (isLore == "1" or isLore == "true")
        
        self.debugPrint(string.format("Queueing item %s (%s) from corpse %s for %s, isLore: %s", 
            itemName or itemId, itemId, corpseId, groupMemberName, tostring(isLoreItem)))
        
        -- Lore item checks
        if isLoreItem then
            -- Check if we already own this lore item
            if utils.ownItem(itemName) then
                mq.cmdf("/g %s already owns %s (Lore item - inventory or bank)", myName, itemName)
                self.debugPrint(string.format("Rejected lore item %s - already owned", itemName))
                return
            end
            
            -- Check if we already have this lore item queued
            for cId, items in pairs(self.myQueuedItems) do
                for _, qItem in pairs(items) do
                    if qItem.itemName == itemName then
                        mq.cmdf("/g %s already has %s queued (Lore item)", myName, itemName)
                        self.debugPrint(string.format("Rejected lore item %s - already queued", itemName))
                        return
                    end
                end
            end
        end
        
        mq.cmdf("/g %s is adding %s from corpse %d to loot queue", myName, itemName or ("itemId " .. itemId), tonumber(corpseId))
        
        -- Check if we already have this item queued from this corpse
        local normalizedCorpseId = tonumber(corpseId)
        local normalizedItemId = tonumber(itemId)
        
        if self.myQueuedItems[normalizedCorpseId] then
            for _, qItem in pairs(self.myQueuedItems[normalizedCorpseId]) do
                if qItem.itemId == normalizedItemId then
                    -- Already have this item queued, increment count (unless lore)
                    if not isLoreItem then
                        qItem.count = (qItem.count or 1) + 1
                        self.debugPrint(string.format("Incremented queue count for %s to %d", itemName, qItem.count))
                        return
                    end
                end
            end
        end
        
        -- New item, add to queue
        local queuedItem = {
            corpseId = normalizedCorpseId,
            itemId = normalizedItemId,
            itemName = itemName,
            isLore = isLoreItem,
            count = 1
        }

        if not self.myQueuedItems[normalizedCorpseId] then
            self.myQueuedItems[normalizedCorpseId] = {}
        end
        table.insert(self.myQueuedItems[normalizedCorpseId], queuedItem)
        self.debugPrint(string.format("Added %s to queue with count 1", itemName))
    end
    
    -- Decrement count in multipleUseTable, remove if count reaches 0
    -- Returns true if successful, false if item not found
    function self.decrementSharedItemCount(corpseId, itemId)
        local normalizedCorpseId = tonumber(corpseId)
        local normalizedItemId = tonumber(itemId)
        
        if not self.multipleUseTable[normalizedCorpseId] then
            self.debugPrint(string.format("decrementSharedItemCount: corpseId %s not found", corpseId))
            return false
        end
        
        for idx, item in ipairs(self.multipleUseTable[normalizedCorpseId]) do
            if item.itemId == normalizedItemId then
                item.count = (item.count or 1) - 1
                self.debugPrint(string.format("Decremented %s count to %d", item.itemName, item.count))
                
                if item.count <= 0 then
                    table.remove(self.multipleUseTable[normalizedCorpseId], idx)
                    self.debugPrint(string.format("Removed %s from multipleUseTable (count reached 0)", item.itemName))
                    
                    -- Clean up empty corpse entries
                    if #self.multipleUseTable[normalizedCorpseId] == 0 then
                        self.multipleUseTable[normalizedCorpseId] = nil
                        self.debugPrint(string.format("Removed empty corpse entry %s", corpseId))
                    end
                end
                return true
            end
        end
        
        self.debugPrint(string.format("decrementSharedItemCount: itemId %s not found in corpse %s", itemId, corpseId))
        return false
    end
    
    -- Remove an item from upgradeList when someone loots it
    -- Called via mq.event when any character broadcasts: "<name> is looting <itemName>"
    function self.removeFromUpgradeList(line, looterName, itemName)
        -- Strip trailing single quote if present (from group message format)
        if itemName and string.sub(itemName, -1) == "'" then
            itemName = string.sub(itemName, 1, -2)
        end
        
        if not itemName or itemName == "" then
            return
        end
        
        local removedCount = 0
        
        -- Iterate backwards to safely remove while iterating
        for i = #self.upgradeList, 1, -1 do
            if self.upgradeList[i].itemName == itemName then
                self.debugPrint(string.format("Removing %s from upgradeList (looted by %s)", 
                    itemName, looterName))
                table.remove(self.upgradeList, i)
                removedCount = removedCount + 1
            end
        end
        
        if removedCount > 0 then
            self.debugPrint(string.format("Removed %d entries for %s from upgradeList", removedCount, itemName))
        end
    end
    
    return self
end


return LootManager
