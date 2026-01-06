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
        debugEnabled = true,  -- Toggle for debug printing
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
        self.debugPrint(string.format("Handling shared item: %s (ID: %s) from corpse %s", 
            message.itemName, message.itemId, message.corpseId))
        
        local item = {
            corpseId = message.corpseId,
            itemId = message.itemId,
            itemName = message.itemName,
            itemLink = message.itemLink
        }

        if next(self.listboxSelectedOption) == nil then
            self.listboxSelectedOption = {
                corpseId = message.corpseId,
                itemId = message.itemId,
                itemName = message.itemName
            }
            self.debugPrint("Set listboxSelectedOption to first shared item")
        end
        
        utils.multimapInsert(self.multipleUseTable, message.corpseId, item)
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
                self.debugPrint("Failed to open loot window after max retries")
                return
            end
        end

        if((mq.TLO.Target.ID() or 0)==0) then
            self.debugPrint("Target lost, marking corpse as looted")
            table.insert(self.lootedCorpses, corpseObject.ID)
            return
        end

        -- Get the actual corpse ID we're looting from
        local actualCorpseId = mq.TLO.Target.ID()
        self.debugPrint(string.format("Looting from actual corpse ID: %s", actualCorpseId))
        
        local itemCount = tonumber(mq.TLO.Corpse.Items()) or 0
        self.debugPrint(string.format("Corpse has %d items", itemCount))
        
        if itemCount == 0 then
            self.debugPrint("No items in corpse")
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
                    
                    -- FIXED: Add to local list first (works for solo and grouped)
                    local sharedItemMessage = {
                        corpseId = actualCorpseId,
                        itemId = corpseItem.ID(),
                        itemName = corpseItem.Name(),
                        itemLink = corpseItem.ItemLink('CLICKABLE')()
                    }
                    self.handleSharedItem(sharedItemMessage)
                    
                    -- Broadcast to group (if in group)
                    actorManager.broadcastShareItem(
                        actualCorpseId,
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
                            if existingUpgrade.corpseId == actualCorpseId and 
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
                                corpseId = actualCorpseId,
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
        end
        
        table.insert(self.lootedCorpses, actualCorpseId)
        self.debugPrint(string.format("Finished looting corpse %s, marked as looted", actualCorpseId))
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
        
        local corpseTable = corpseManager.getCorpseTable(mq.TLO.SpawnCount("npccorpse radius 200 zradius 20")())
        self.debugPrint(string.format("Found %d corpses in range", #corpseTable))

        while #corpseTable > 0 do
            local currentCorpse
            self.debugPrint(string.format("Corpses Remaining: %d", #corpseTable))
            currentCorpse, corpseTable = corpseManager.getRandomCorpse(corpseTable)
            
            if currentCorpse and currentCorpse.ID and not self.isLooted(currentCorpse.ID) then
                -- OPTIMIZATION: Check if corpse still exists before attempting to loot
                -- This prevents wasting time on corpses that despawned (were looted by others)
                if not self.corpseStillExists(currentCorpse.ID) then
                    self.debugPrint(string.format("Corpse ID %s no longer exists (despawned), skipping", currentCorpse.ID))
                    -- Mark as looted so we don't try again
                    table.insert(self.lootedCorpses, currentCorpse.ID)
                    goto continue
                end
                
                self.debugPrint(string.format("Processing corpse ID: %s", currentCorpse.ID))
                local navSuccess = navigation.navigateToCorpse(self.config, currentCorpse.ID)
                
                if navSuccess then
                    self.debugPrint("Successfully navigated to corpse")
                    self.lootCorpse(currentCorpse, isMaster)
                else
                    self.debugPrint(string.format("Failed to navigate to corpse ID: %s", tostring(currentCorpse.ID)))
                end
            else
                self.debugPrint("Corpse already looted or invalid")
            end
            
            ::continue::
        end
        
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