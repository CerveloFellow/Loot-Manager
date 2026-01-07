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
        self.debugPrint(string.format("Received shared item message - Raw types: corpseId=%s (%s), itemId=%s (%s)", 
            tostring(message.corpseId), type(message.corpseId),
            tostring(message.itemId), type(message.itemId)))
        
        -- Normalize corpseId and itemId to numbers to prevent type mismatch issues
        -- Actor serialization can sometimes convert numbers to strings
        local normalizedCorpseId = tonumber(message.corpseId)
        local normalizedItemId = tonumber(message.itemId)
        
        -- Debug: Warn if type conversion was needed
        if type(message.corpseId) ~= "number" then
            self.debugPrint(string.format("WARNING: corpseId arrived as %s, converted to number %s", 
                type(message.corpseId), normalizedCorpseId))
        end
        if type(message.itemId) ~= "number" then
            self.debugPrint(string.format("WARNING: itemId arrived as %s, converted to number %s", 
                type(message.itemId), normalizedItemId))
        end
        
        self.debugPrint(string.format("Handling shared item: %s (ID: %s) from corpse %s", 
            message.itemName, normalizedItemId, normalizedCorpseId))
        
        local item = {
            corpseId = normalizedCorpseId,
            itemId = normalizedItemId,
            itemName = message.itemName,
            itemLink = message.itemLink
        }

        if next(self.listboxSelectedOption) == nil then
            self.listboxSelectedOption = {
                corpseId = normalizedCorpseId,
                itemId = normalizedItemId,
                itemName = message.itemName
            }
            self.debugPrint("Set listboxSelectedOption to first shared item")
        end
        
        -- Debug: Log the key being used for multipleUseTable
        self.debugPrint(string.format("Inserting into multipleUseTable with key: %s (type: %s)", 
            normalizedCorpseId, type(normalizedCorpseId)))
        
        utils.multimapInsert(self.multipleUseTable, normalizedCorpseId, item)
    end
    
    -- Debug function to dump the entire multipleUseTable state
    function self.debugDumpSharedItems()
        self.debugPrint("===== SHARED ITEMS TABLE DUMP =====")
        local totalItems = 0
        for corpseId, items in pairs(self.multipleUseTable) do
            self.debugPrint(string.format("  Corpse KEY: %s (type: %s)", tostring(corpseId), type(corpseId)))
            for idx, item in ipairs(items) do
                totalItems = totalItems + 1
                self.debugPrint(string.format("    [%d] itemName=%s, itemId=%s (type: %s), item.corpseId=%s (type: %s)", 
                    idx, 
                    item.itemName, 
                    tostring(item.itemId), type(item.itemId),
                    tostring(item.corpseId), type(item.corpseId)))
                
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
                mq.cmdf("/g %s", value.itemLink)
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
        
        for i = 1, itemCount do
            self.checkInventorySpace()
            
            mq.delay(self.delays.corpseItemWait, function() return mq.TLO.Corpse.Item(i).ID() end)
            local corpseItem = mq.TLO.Corpse.Item(i)
            local isSharedItem = utils.contains(config.itemsToShare, corpseItem.Name())

            if itemEvaluator.shouldLoot(config, utils, corpseItem) and (not isSharedItem) then
                self.debugPrint(string.format("Item %d (%s) should be looted", i, corpseItem.Name()))
                self.lootItem(corpseItem, i)
            else
                if (itemEvaluator.groupMembersCanUse(corpseItem) > 1 or isSharedItem) and 
                   (not itemEvaluator.skipItem(config, utils, corpseItem)) then
                    self.debugPrint(string.format("Item %d (%s) is a shared item", i, corpseItem.Name()))
                    mq.cmdf("/g Shared Item: "..corpseItem.ItemLink('CLICKABLE')())
                    
                    -- COMPREHENSIVE DEBUG: Log ALL relevant IDs to diagnose mismatch
                    local actualTargetId = mq.TLO.Target.ID() or 0
                    local actualLootCorpseId = mq.TLO.Corpse.ID() or 0
                    
                    self.debugPrint(string.format("=== SHARED ITEM DEBUG ==="))
                    self.debugPrint(string.format("  corpseObject.ID (passed in): %s", tostring(corpseObject.ID)))
                    self.debugPrint(string.format("  mq.TLO.Target.ID() (current target): %s", tostring(actualTargetId)))
                    self.debugPrint(string.format("  mq.TLO.Corpse.ID() (loot window): %s", tostring(actualLootCorpseId)))
                    self.debugPrint(string.format("  Item: %s (ID: %s)", corpseItem.Name(), tostring(corpseItem.ID())))
                    
                    -- Check for any mismatches
                    if actualTargetId ~= corpseObject.ID then
                        self.debugPrint(string.format("  *** MISMATCH: Target changed! Expected %s, got %s", 
                            corpseObject.ID, actualTargetId))
                    end
                    if actualLootCorpseId ~= corpseObject.ID then
                        self.debugPrint(string.format("  *** MISMATCH: Loot window is for different corpse! Expected %s, got %s", 
                            corpseObject.ID, actualLootCorpseId))
                    end
                    if actualTargetId ~= actualLootCorpseId then
                        self.debugPrint(string.format("  *** MISMATCH: Target (%s) != Loot window (%s)", 
                            actualTargetId, actualLootCorpseId))
                    end
                    self.debugPrint(string.format("========================="))
                    
                    -- FIXED: Use the ACTUAL loot window corpse ID, not the passed-in corpseObject.ID
                    -- This ensures we record the correct corpse that actually has the item
                    local correctCorpseId = actualLootCorpseId or corpseObject.ID
                    
                    -- SAFETY CHECK: Don't broadcast if corpseId is 0 or nil (corpse despawned)
                    if not correctCorpseId or correctCorpseId == 0 then
                        self.debugPrint("WARNING: Invalid corpseId (0 or nil), skipping shared item broadcast")
                        goto continue_item_loop
                    end
                    
                    -- FIXED: Add to local list first (works for solo and grouped)
                    local sharedItemMessage = {
                        corpseId = correctCorpseId,
                        itemId = corpseItem.ID(),
                        itemName = corpseItem.Name(),
                        itemLink = corpseItem.ItemLink('CLICKABLE')()
                    }
                    self.handleSharedItem(sharedItemMessage)
                    
                    -- Broadcast to group (if in group)
                    self.debugPrint(string.format("Broadcasting shared item to group: corpseId=%s, itemId=%s", 
                        correctCorpseId, corpseItem.ID()))
                    actorManager.broadcastShareItem(
                        correctCorpseId,
                        corpseItem.ID(), 
                        corpseItem.Name(), 
                        corpseItem.ItemLink('CLICKABLE')()
                    )
                    
                    -- NEW: Check for upgrades
                    local upgradeInfo = self.itemScore.evaluateItemForUpgrade(corpseItem)
                    if upgradeInfo then
                        self.debugPrint(string.format("Item %s is an upgrade: +%.1f%% for %s", 
                            corpseItem.Name(), upgradeInfo.improvement, upgradeInfo.slotName))
                        
                        local found = false
                        for _, existingUpgrade in ipairs(self.upgradeList) do
                            if existingUpgrade.corpseId == corpseObject.ID and 
                               existingUpgrade.itemId == corpseItem.ID() then
                                existingUpgrade.slotName = upgradeInfo.slotName
                                existingUpgrade.improvement = upgradeInfo.improvement
                                self.debugPrint(string.format("Updated existing upgrade entry for %s", corpseItem.Name()))
                                found = true
                                break
                            end
                        end
                        
                        if not found then
                            local newUpgrade = {
                                corpseId = corpseObject.ID,
                                itemId = corpseItem.ID(),
                                itemName = corpseItem.Name(),
                                slotName = upgradeInfo.slotName,
                                improvement = upgradeInfo.improvement
                            }
                            table.insert(self.upgradeList, newUpgrade)
                            self.debugPrint(string.format("Added new upgrade entry for %s: %.1f%% for %s", 
                                corpseItem.Name(), newUpgrade.improvement, newUpgrade.slotName))
                        end
                    end
                end
            end
            ::continue_item_loop::
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
    
    function self.processQueuedItemsInCorpse(items, corpseItemCount)
        self.debugPrint(string.format("Processing queued items in corpse - %d items in corpse", corpseItemCount))
        
        for i = 1, corpseItemCount do
            local idx2, tbl = next(items)
            
            while idx2 do
                local nextIdx2 = next(items, idx2)
                
                self.checkInventorySpace()
                
                mq.delay(self.delays.corpseItemWait, function() return mq.TLO.Corpse.Item(i).ID() end)
                local corpseItem = mq.TLO.Corpse.Item(i)
                local localItemId = corpseItem.ID()
                
                if tostring(localItemId) == tostring(tbl.itemId) then
                    self.debugPrint(string.format("Found queued item match: %s", corpseItem.Name()))
                    self.lootItem(corpseItem, i)
                    
                    if mq.TLO.Cursor then
                        mq.cmdf("/autoinventory")
                    end
                    mq.delay(self.delays.autoInventory, function() return not mq.TLO.Cursor() end)

                    self.debugPrint(string.format("Removing queued item idx2: %s", tostring(idx2)))
                    items[idx2] = nil
                end
                
                idx2 = nextIdx2
                if idx2 then
                    tbl = items[idx2]
                end
            end
        end
    end
    
    function self.lootQueuedItems()
        if not self.myQueuedItems then
            self.myQueuedItems = {}
            self.debugPrint("No items in queue to loot")
            return
        end

        self.debugPrint("Starting to loot queued items")
        local idx, items = next(self.myQueuedItems)
        
        while idx do
            local nextIdx = next(self.myQueuedItems, idx)
            self.debugPrint(string.format("Processing corpse %s from queue", tostring(idx)))
            
            if not self.openCorpse(idx) then
                self.debugPrint(string.format("Failed to open corpse %s, skipping", tostring(idx)))
                idx = nextIdx
                if idx then
                    items = self.myQueuedItems[idx]
                end
                goto continue
            end
            
            local corpseItemCount = tonumber(mq.TLO.Corpse.Items()) or 0
            
            if corpseItemCount == 0 then
                self.debugPrint("Corpse is empty")
                self.closeLootWindow()
                idx = nextIdx
                if idx then
                    items = self.myQueuedItems[idx]
                end
                goto continue
            end

            self.processQueuedItemsInCorpse(items, corpseItemCount)
            self.closeLootWindow()
            
            self.debugPrint(string.format("Removing corpse %s from queue", tostring(idx)))
            self.myQueuedItems[idx] = nil
            
            idx = nextIdx
            if idx then
                items = self.myQueuedItems[idx]
            end
            
            ::continue::
        end
        
        self.debugPrint("Finished looting all queued items")
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
        local spawnCount = mq.TLO.SpawnCount("npccorpse radius 200 zradius 20")()
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
    
    function self.queueItem(line, groupMemberName, corpseId, itemId)
        local myName = tostring(mq.TLO.Me.Name())
        
        if groupMemberName ~= myName then
            return
        end
        
        self.debugPrint(string.format("Queueing item %s from corpse %s for %s", 
            itemId, corpseId, groupMemberName))
        
        mq.cmdf("/g " .. myName .. " is adding itemId(" .. itemId .. ") and corpseId(" .. corpseId .. ") to my loot queue")
        
        local queuedItem = {
            corpseId = corpseId,
            itemId = itemId
        }

        utils.multimapInsert(self.myQueuedItems, corpseId, queuedItem)

        for idx, items in pairs(self.multipleUseTable) do
            if tostring(idx) == tostring(corpseId) then
                for idx2, tbl in pairs(items) do
                    if tostring(tbl.itemId) == tostring(itemId) then
                        table.remove(items, idx2)
                        self.debugPrint("Removed item from multipleUseTable")
                    end
                end
            end
        end
    end
    
    return self
end

return LootManager