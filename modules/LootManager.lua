-- modules/LootManager.lua (OPTIMIZED v2)
-- Changes in v2:
--   - E3 loot toggle to prevent conflicts
--   - Further reduced delays
--   - Group member collision avoidance
--   - All functions complete
local mq = require('mq')

local LootManager = {}

function LootManager.new(config, utils, itemEvaluator, corpseManager, navigation, actorManager, itemScore)
    local self = {
        multipleUseTable = {},
        myQueuedItems = {},
        listboxSelectedOption = {},
        lootedCorpses = {},
        upgradeList = {},
        config = config,
        utils = utils,
        itemEvaluator = itemEvaluator,
        corpseManager = corpseManager,
        navigation = navigation,
        actorManager = actorManager,
        itemScore = itemScore,
        debugEnabled = false,
        findMode = false,
        findStrings = {},
        e3LootWasEnabled = false,  -- NEW: Track E3 loot state
        delays = {
            windowClose = 50,
            itemLoot = 175,            -- v2: Reduced from 200
            quantityAccept = 75,
            corpseTarget = 50,
            corpseOpen = 700,          -- v2: Reduced from 800
            corpseFix = 400,           -- v2: Reduced from 500
            lootCommand = 125,         -- v2: Reduced from 150
            corpseItemWait = 0,
            postNavigation = 100,      -- v2: Reduced from 150
            postNavigationRetry = 100, -- v2: Reduced from 150
            autoInventory = 125,       -- v2: Reduced from 150
            stickOff = 100,            -- v2: Reduced from 150
            warpMovement = 100,        -- v2: Reduced from 150
            navigationMovement = 2000,
            e3Toggle = 100             -- NEW: Delay after E3 toggle
        }
    }
    
    -- NEW: E3 loot management functions
    function self.disableE3Loot()
        -- Check if E3 loot is currently enabled
        local e3LootStatus = mq.TLO.E3 and mq.TLO.E3.Setting("Misc", "Loot")
        if e3LootStatus and (e3LootStatus() == "TRUE" or e3LootStatus() == "true" or e3LootStatus() == "1") then
            self.e3LootWasEnabled = true
            mq.cmdf("/e3 toggle loot off")
            mq.delay(self.delays.e3Toggle)
            self.debugPrint("[E3] Disabled E3 looting temporarily")
        else
            self.e3LootWasEnabled = false
            self.debugPrint("[E3] E3 looting was already disabled or E3 not present")
        end
    end
    
    function self.restoreE3Loot()
        if self.e3LootWasEnabled then
            mq.cmdf("/e3 toggle loot on")
            mq.delay(self.delays.e3Toggle)
            self.debugPrint("[E3] Re-enabled E3 looting")
            self.e3LootWasEnabled = false
        end
    end
    
    function self.debugPrint(message)
        if self.debugEnabled then
            print(string.format("[LootManager]: %s", message))
        end
    end
    
    function self.setDebug(enabled)
        self.debugEnabled = enabled
        if enabled then
            print("[LootManager]: Debug mode ENABLED")
        else
            print("[LootManager]: Debug mode DISABLED")
        end
    end
    
    function self.verifyTarget(corpseId)
        return mq.TLO.Target() and mq.TLO.Target.ID() == corpseId
    end
    
    function self.corpseStillExists(corpseId)
        local spawn = mq.TLO.Spawn(corpseId)
        if spawn and spawn.ID() and spawn.ID() > 0 then
            if spawn.Type() == "Corpse" then
                return true
            end
        end
        return false
    end
    
    -- NEW: Check if another group member is targeting this corpse
    function self.isCorpseTargetedByGroupMember(corpseId)
        local groupSize = mq.TLO.Group.Members() or 0
        if groupSize == 0 then return false end
        
        for i = 1, groupSize do
            local member = mq.TLO.Group.Member(i)
            if member and member.ID() then
                local memberTarget = member.TargetOfTarget
                if memberTarget and memberTarget.ID() == corpseId then
                    -- Another group member is targeting this corpse
                    return true, member.Name()
                end
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
        local normalizedCorpseId = tonumber(message.corpseId)
        local normalizedItemId = tonumber(message.itemId)
        local normalizedCount = tonumber(message.count) or 1
        
        self.debugPrint(string.format("Handling shared item: %s (ID: %s) from corpse %s, count: %d", 
            message.itemName, normalizedItemId, normalizedCorpseId, normalizedCount))
        
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
        end
        
        utils.multimapInsert(self.multipleUseTable, normalizedCorpseId, item)
    end
    
    function self.tableLength(t)
        local count = 0
        for _ in pairs(t) do count = count + 1 end
        return count
    end
    
    function self.printMultipleUseItems()
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
        self.printUpgradeList()
    end
    
    function self.printUpgradeList(itemName)
        if #self.upgradeList == 0 then
            return
        end
        
        local myName = mq.TLO.Me.Name()
        
        for _, upgrade in ipairs(self.upgradeList) do
            if itemName and upgrade.itemName ~= itemName then
                goto continue
            end
            
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
        
        if slotsRemaining < 1 then
            mq.cmdf("/beep")
            mq.cmdf('/g ' .. mq.TLO.Me.Name() .. " inventory is Full!")
        end
    end
    
    function self.closeLootWindow()
        if mq.TLO.Window("LootWnd").Open() then
            mq.cmdf("/notify LootWnd LW_DoneButton leftmouseup")
            mq.delay(self.delays.windowClose, function() return self.isWindowClosed("LootWnd") end)
        end
    end
    
    function self.lootItem(corpseItem, slotIndex)
        mq.cmdf('/g '..mq.TLO.Me.Name().." is looting ".. corpseItem.ItemLink('CLICKABLE')())
        mq.cmdf("/shift /itemnotify loot%d rightmouseup", slotIndex)
        mq.delay(self.delays.itemLoot)
        
        if self.isWindowOpen("QuantityWnd") then
            mq.cmdf("/notify QuantityWnd QTYW_Accept_Button leftmouseup")
            mq.delay(self.delays.quantityAccept, function() return self.isWindowClosed("QuantityWnd") end)
        end
    end
    
    function self.matchesFindString(itemName)
        if not self.findMode or not self.findStrings or #self.findStrings == 0 then
            return {pattern = "*", lootAll = true}
        end
        if not itemName then
            return nil
        end
        local lowerName = itemName:lower()
        for _, entry in ipairs(self.findStrings) do
            if string.find(lowerName, entry.pattern, 1, true) then
                return entry
            end
        end
        return nil
    end
    
    function self.lootCorpseFindMode(corpseObject)
        if not self.corpseStillExists(corpseObject.ID) then
            return
        end
        
        mq.cmdf("/target id %d", corpseObject.ID)
        mq.delay(self.delays.corpseTarget, function() return self.verifyTarget(corpseObject.ID) end)
        
        if not self.verifyTarget(corpseObject.ID) then
            if not self.corpseStillExists(corpseObject.ID) then
                return
            end
            return "retry"
        end
        
        mq.cmdf("/loot")
        mq.delay(self.delays.corpseOpen, function() return self.isWindowOpen("LootWnd") end)

        local retryCount = 0
        local maxRetries = 5

        if self.isWindowClosed("LootWnd") then
            while retryCount < maxRetries do
                if retryCount > 3 then
                    mq.cmdf("/say #corpsefix")
                end
                mq.delay(self.delays.corpseFix)
                navigation.navigateToCorpse(self.config, corpseObject.ID)
                mq.cmdf("/loot")
                mq.delay(self.delays.lootCommand, function() return self.isWindowOpen("LootWnd") end)
                retryCount = retryCount + 1
                
                if self.isWindowOpen("LootWnd") then
                    break
                end
            end
            
            if retryCount >= maxRetries and self.isWindowClosed("LootWnd") then
                return "retry"
            end
        end

        if (mq.TLO.Target.ID() or 0) == 0 then
            return
        end

        if mq.TLO.Target.ID() ~= corpseObject.ID then
            self.closeLootWindow()
            return
        end
        
        local lootWindowCorpseId = mq.TLO.Corpse.ID()
        if lootWindowCorpseId ~= corpseObject.ID then
            self.closeLootWindow()
            return "retry"
        end
        
        local itemCount = tonumber(mq.TLO.Corpse.Items()) or 0
        
        if itemCount == 0 then
            self.closeLootWindow()
            return
        end
        
        local itemsLooted = 0
        local itemsChecked = 0
        
        self.debugPrint(string.format("[FindMode] === Scanning corpse %d ===", corpseObject.ID))
        
        local keepLooting = true
        while keepLooting do
            keepLooting = false
            local currentItemCount = tonumber(mq.TLO.Corpse.Items()) or 0
            
            for i = 1, currentItemCount do
                local corpseItem = mq.TLO.Corpse.Item(i)
                
                if corpseItem and corpseItem.ID() then
                    local itemName = corpseItem.Name()
                    local itemId = corpseItem.ID()
                    itemsChecked = itemsChecked + 1
                    
                    local matchResult = self.matchesFindString(itemName)
                    
                    if matchResult then
                        local alreadyOwned = utils.ownItem(itemName)
                        local shouldLoot = matchResult.lootAll or not alreadyOwned
                        
                        self.debugPrint(string.format("[FindMode]   [%d] %s (ID:%d) - MATCH on '%s'", 
                            i, itemName, itemId, matchResult.pattern))
                        
                        if shouldLoot then
                            self.checkInventorySpace()
                            self.lootItem(corpseItem, i)
                            itemsLooted = itemsLooted + 1
                            keepLooting = true
                            break
                        else
                            mq.cmdf("/g %s found %s on corpseId(%d) but already owns it", 
                                mq.TLO.Me.Name(), itemName, corpseObject.ID)
                        end
                    else
                        self.debugPrint(string.format("[FindMode]   [%d] %s (ID:%d) - no match", i, itemName, itemId))
                    end
                end
            end
        end
        
        self.debugPrint(string.format("[FindMode] === Corpse %d complete: checked=%d, looted=%d ===", 
            corpseObject.ID, itemsChecked, itemsLooted))
        
        self.closeLootWindow()
        
        return itemsLooted > 0
    end
    
    function self.doFindLoot(searchStrings)
        if not searchStrings or #searchStrings == 0 then
            print("Usage: /mlfind \"<search string>\" [\"<search string 2>\" ...]")
            return
        end
        
        -- Check if already running
        if self.findMode then
            print("[MasterLoot] Find mode already in progress - ignoring new request")
            print("[MasterLoot] Restart MasterLoot to cancel: /lua stop masterloot && /lua run masterloot")
            return
        end
        
        -- NEW: Disable E3 looting to prevent conflicts
        self.disableE3Loot()
        
        self.findMode = true
        self.findStrings = {}
        for _, str in ipairs(searchStrings) do
            local lootAll = false
            local searchStr = str
            
            if string.sub(str, 1, 1) == "+" then
                lootAll = true
                searchStr = string.sub(str, 2)
            end
            
            if searchStr and searchStr ~= "" then
                table.insert(self.findStrings, {
                    pattern = searchStr:lower(),
                    lootAll = lootAll,
                    original = str
                })
            end
        end
        
        mq.cmdf("/g %s is searching corpses for items matching: %s", mq.TLO.Me.Name(), table.concat(searchStrings, ", "))
        
        local startingLocation = {
            X = mq.TLO.Me.X(),
            Y = mq.TLO.Me.Y(),
            Z = mq.TLO.Me.Z(),
            timeToWait = "2s"
        }
        
        local stickState = false
        
        if mq.TLO.Stick.Active() then
            stickState = true
            mq.cmdf("/stick off")
        end
        
        mq.delay(self.delays.stickOff)
        
        -- Use larger radius for find mode (1000 units) to balance coverage with reliability
        -- Zone-wide queries can return nil IDs for very distant corpses
        local spawnCount = mq.TLO.SpawnCount("npccorpse radius 1000")()
        local corpseTable = corpseManager.getCorpseTable(spawnCount)
        
        local corpsesProcessed = 0
        local corpsesWithMatches = 0
        local corpsesDespawned = 0
        local corpsesFailed = 0
        local corpsesSkippedCollision = 0  -- NEW: Track collision skips
        local retryCount = {}
        local maxRetries = 2

        local progressInterval = 25  -- Log progress every 25 corpses
        
        while #corpseTable > 0 do
            local currentCorpse
            self.debugPrint(string.format("[FindMode] Corpses Remaining: %d", #corpseTable))
            
            currentCorpse, corpseTable = corpseManager.getNearestCorpse(corpseTable)
            
            -- SAFEGUARD: If getNearestCorpse returns nil but table isn't empty, something is wrong
            if not currentCorpse then
                if #corpseTable > 0 then
                    print(string.format("[MasterLoot] WARNING: getNearestCorpse returned nil but %d corpses remain - clearing table", #corpseTable))
                    corpseTable = {}  -- Force exit to prevent infinite loop
                end
                break
            end
            
            if currentCorpse and currentCorpse.ID then
                corpsesProcessed = corpsesProcessed + 1
                
                -- Periodic progress report (always visible)
                if corpsesProcessed % progressInterval == 0 then
                    print(string.format("[MasterLoot] Progress: %d corpses processed, %d remaining", 
                        corpsesProcessed, #corpseTable))
                end
                
                if not self.corpseStillExists(currentCorpse.ID) then
                    corpsesDespawned = corpsesDespawned + 1
                    goto continue
                end
                
                -- NEW: Skip if another group member is targeting this corpse
                local isTargeted, targetedBy = self.isCorpseTargetedByGroupMember(currentCorpse.ID)
                if isTargeted then
                    self.debugPrint(string.format("[FindMode] Skipping corpse %d - targeted by %s", 
                        currentCorpse.ID, targetedBy or "group member"))
                    corpsesSkippedCollision = corpsesSkippedCollision + 1
                    -- Track collision retries with same retry counter
                    retryCount[currentCorpse.ID] = (retryCount[currentCorpse.ID] or 0) + 1
                    if retryCount[currentCorpse.ID] <= maxRetries then
                        table.insert(corpseTable, currentCorpse)
                    else
                        self.debugPrint(string.format("[FindMode] Corpse %d exceeded collision retry limit", currentCorpse.ID))
                        corpsesFailed = corpsesFailed + 1
                    end
                    goto continue
                end
                
                local navSuccess, navError = navigation.navigateToCorpse(self.config, currentCorpse.ID)
                
                if navSuccess then
                    local lootResult = self.lootCorpseFindMode(currentCorpse)
                    
                    if lootResult == "retry" then
                        retryCount[currentCorpse.ID] = (retryCount[currentCorpse.ID] or 0) + 1
                        if retryCount[currentCorpse.ID] <= maxRetries then
                            table.insert(corpseTable, currentCorpse)
                        else
                            corpsesFailed = corpsesFailed + 1
                        end
                    elseif lootResult == true then
                        corpsesWithMatches = corpsesWithMatches + 1
                    end
                elseif navError == "despawned" then
                    corpsesDespawned = corpsesDespawned + 1
                else
                    retryCount[currentCorpse.ID] = (retryCount[currentCorpse.ID] or 0) + 1
                    if retryCount[currentCorpse.ID] <= maxRetries then
                        table.insert(corpseTable, currentCorpse)
                    else
                        corpsesFailed = corpsesFailed + 1
                    end
                end
            end
            
            ::continue::
        end
        
        self.findMode = false
        self.findStrings = {}
        
        mq.cmdf("/g %s finished searching - found matches on %d of %d corpses (despawned: %d)", 
            mq.TLO.Me.Name(), corpsesWithMatches, corpsesProcessed, corpsesDespawned)
        
        navigation.navigateToLocation(self.config, startingLocation.X, startingLocation.Y, startingLocation.Z)
        mq.delay(startingLocation.timeToWait)
        
        if stickState then
            mq.cmdf("/stick on")
        end
        
        -- NEW: Re-enable E3 looting
        self.restoreE3Loot()
    end

    function self.lootCorpse(corpseObject, isMaster)
        self.debugPrint(string.format("Starting to loot corpse ID: %s", corpseObject.ID))
        
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

        if mq.TLO.Target.ID() ~= corpseObject.ID then
            self.debugPrint(string.format("WARNING: Target mismatch! Expected %s, got %s.",
                corpseObject.ID, mq.TLO.Target.ID()))
            table.insert(self.lootedCorpses, corpseObject.ID)
            self.closeLootWindow()
            return
        end
        
        local lootWindowCorpseId = mq.TLO.Corpse.ID()
        if lootWindowCorpseId ~= corpseObject.ID then
            self.debugPrint(string.format("*** LOOT WINDOW MISMATCH! Target=%s, LootWindow=%s ***", 
                corpseObject.ID, lootWindowCorpseId))
            self.closeLootWindow()
            return "retry"
        end
        
        local itemCount = tonumber(mq.TLO.Corpse.Items()) or 0
        self.debugPrint(string.format("Corpse has %d items", itemCount))
        
        if itemCount == 0 then
            self.debugPrint(string.format("Corpse %s has no items, marking as looted", corpseObject.ID))
            table.insert(self.lootedCorpses, corpseObject.ID)
            self.closeLootWindow()
            return
        end
        
        local actualLootCorpseId = mq.TLO.Corpse.ID() or 0
        local correctCorpseId = actualLootCorpseId or corpseObject.ID
        
        if not correctCorpseId or correctCorpseId == 0 then
            self.debugPrint("WARNING: Invalid corpseId (0 or nil), skipping corpse")
            self.closeLootWindow()
            return
        end
        
        local tempSharedItems = {}
        local itemsToLoot = {}
        
        for i = 1, itemCount do
            local corpseItem = mq.TLO.Corpse.Item(i)
            
            if not corpseItem or not corpseItem.ID() then
                goto continue_phase1
            end
            
            local itemId = corpseItem.ID()
            local itemName = corpseItem.Name()
            local isSharedItem = utils.contains(config.itemsToShare, itemName)
            
            if itemEvaluator.shouldLoot(config, utils, corpseItem) and (not isSharedItem) then
                table.insert(itemsToLoot, {slot = i, item = corpseItem})
            elseif (itemEvaluator.groupMembersCanUse(corpseItem) > 1 or isSharedItem) and 
                   (not itemEvaluator.skipItem(config, utils, corpseItem)) then
                if tempSharedItems[itemId] then
                    tempSharedItems[itemId].count = tempSharedItems[itemId].count + 1
                else
                    tempSharedItems[itemId] = {
                        itemId = itemId,
                        itemName = itemName,
                        itemLink = corpseItem.ItemLink('CLICKABLE')(),
                        isLore = corpseItem.Lore() or false,
                        count = 1,
                        corpseItem = corpseItem
                    }
                end
            end
            
            ::continue_phase1::
        end
        
        for _, lootEntry in ipairs(itemsToLoot) do
            self.checkInventorySpace()
            self.lootItem(lootEntry.item, lootEntry.slot)
        end
        
        for itemId, sharedItem in pairs(tempSharedItems) do
            local alreadyReported = false
            if self.multipleUseTable[correctCorpseId] then
                for _, existingItem in ipairs(self.multipleUseTable[correctCorpseId]) do
                    if existingItem.itemId == itemId then
                        alreadyReported = true
                        existingItem.count = sharedItem.count
                        break
                    end
                end
            end
            
            if not alreadyReported then
                if sharedItem.count > 1 then
                    mq.cmdf("/g Shared Item: %s x%d", sharedItem.itemLink, sharedItem.count)
                else
                    mq.cmdf("/g Shared Item: %s", sharedItem.itemLink)
                end
                
                local sharedItemMessage = {
                    corpseId = correctCorpseId,
                    itemId = itemId,
                    itemName = sharedItem.itemName,
                    itemLink = sharedItem.itemLink,
                    isLore = sharedItem.isLore,
                    count = sharedItem.count
                }
                
                self.handleSharedItem(sharedItemMessage)
                
                actorManager.broadcastShareItem(
                    correctCorpseId,
                    itemId, 
                    sharedItem.itemName, 
                    sharedItem.itemLink,
                    sharedItem.isLore,
                    sharedItem.count
                )
            end
            
            local upgradeInfo = self.itemScore.evaluateItemForUpgrade(sharedItem.corpseItem)
            if upgradeInfo then
                local found = false
                for _, existingUpgrade in ipairs(self.upgradeList) do
                    if existingUpgrade.corpseId == correctCorpseId and 
                       existingUpgrade.itemId == itemId then
                        existingUpgrade.slotName = upgradeInfo.slotName
                        existingUpgrade.improvement = upgradeInfo.improvement
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
                end
            end
        end
        
        table.insert(self.lootedCorpses, corpseObject.ID)
        self.closeLootWindow()
    end
    
    function self.openCorpse(corpseId)
        self.debugPrint(string.format("Opening corpse ID: %s", corpseId))
        
        mq.cmdf("/target id %d", corpseId)
        mq.delay(self.delays.corpseTarget, function() return self.verifyTarget(corpseId) end)
        
        if (mq.TLO.Target.ID() or 0) == 0 then
            print("ERROR: Failed to target corpse ID: " .. tostring(corpseId))
            return false
        end
        
        navigation.navigateToCorpse(self.config, corpseId)
        
        mq.cmdf("/loot")
        mq.delay(self.delays.corpseOpen, function() return self.isWindowOpen("LootWnd") end)
        local retryCount = 0
        local retryMax = 5

        while self.isWindowClosed("LootWnd") and (retryCount < retryMax) do
            if retryCount > 3 then
                mq.cmdf("/say #corpsefix")
            end
            mq.delay(self.delays.corpseFix)  
            navigation.navigateToCorpse(self.config, corpseId)
            mq.cmdf("/loot")
            mq.delay(self.delays.corpseOpen, function() return self.isWindowOpen("LootWnd") end)
            retryCount = retryCount + 1
        end

        if retryCount >= retryMax then
            mq.cmdf("/g Could not loot targeted corpse, skipping.")
            return false
        end
        
        return true
    end
    
    function self.lootAllQueuedItemsFromCorpse(corpseId, queuedItems)
        local results = {}
        local corpseItemCount = tonumber(mq.TLO.Corpse.Items()) or 0
        
        if corpseItemCount == 0 then
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
        
        local itemsToLoot = {}
        for _, queuedItem in ipairs(queuedItems) do
            table.insert(itemsToLoot, {
                queuedItem = queuedItem,
                remaining = queuedItem.count or 1,
                looted = 0
            })
        end
        
        for _, lootEntry in ipairs(itemsToLoot) do
            while lootEntry.remaining > 0 do
                self.checkInventorySpace()
                
                local currentCorpseItemCount = tonumber(mq.TLO.Corpse.Items()) or 0
                
                if currentCorpseItemCount == 0 then
                    break
                end
                
                local foundSlot = nil
                for i = 1, currentCorpseItemCount do
                    local corpseItem = mq.TLO.Corpse.Item(i)
                    
                    if corpseItem and corpseItem.ID() then
                        if corpseItem.ID() == lootEntry.queuedItem.itemId then
                            foundSlot = i
                            break
                        end
                    end
                end
                
                if not foundSlot then
                    break
                end
                
                local corpseItem = mq.TLO.Corpse.Item(foundSlot)
                self.lootItem(corpseItem, foundSlot)
                
                mq.delay(500)
                
                local postCount = tonumber(mq.TLO.Corpse.Items()) or 0
                local itemStillThere = false
                
                for i = 1, postCount do
                    local checkItem = mq.TLO.Corpse.Item(i)
                    if checkItem and checkItem.ID() == lootEntry.queuedItem.itemId then
                        itemStillThere = true
                        break
                    end
                end
                
                if not itemStillThere then
                    lootEntry.looted = lootEntry.looted + 1
                    lootEntry.remaining = lootEntry.remaining - 1
                    
                    if mq.TLO.Cursor() then
                        mq.cmdf("/autoinventory")
                        mq.delay(self.delays.autoInventory, function() return not mq.TLO.Cursor() end)
                    end
                else
                    break
                end
            end
        end
        
        for _, lootEntry in ipairs(itemsToLoot) do
            table.insert(results, {
                itemId = lootEntry.queuedItem.itemId,
                itemName = lootEntry.queuedItem.itemName,
                expectedCount = lootEntry.queuedItem.count or 1,
                actualLooted = lootEntry.looted
            })
            
            if lootEntry.looted < (lootEntry.queuedItem.count or 1) then
                local myName = mq.TLO.Me.Name()
                mq.cmdf("/g %s could not find %s (expected %d, found %d) on corpse %d", 
                    myName, lootEntry.queuedItem.itemName or "item", 
                    lootEntry.queuedItem.count or 1, lootEntry.looted, corpseId)
            end
        end
        
        return results
    end
    
    function self.lootQueuedItems()
        self.debugPrint("Starting to loot queued items")
        
        if not self.myQueuedItems or not next(self.myQueuedItems) then
            print("No items queued for looting")
            return
        end
        
        -- NEW: Disable E3 looting
        self.disableE3Loot()
        
        local startingLocation = {
            X = mq.TLO.Me.X(),
            Y = mq.TLO.Me.Y(),
            Z = mq.TLO.Me.Z(),
            timeToWait = "2s"
        }
        
        local stickState = false
        if mq.TLO.Stick.Active() then
            stickState = true
            mq.cmdf("/stick off")
        end
        mq.delay(self.delays.stickOff)
        
        for corpseId, queuedItems in pairs(self.myQueuedItems) do
            self.debugPrint(string.format("Processing corpse %s with %d queued items", corpseId, #queuedItems))
            
            if not self.corpseStillExists(corpseId) then
                self.debugPrint(string.format("Corpse %s no longer exists, skipping", corpseId))
                mq.cmdf("/g Corpse %d no longer exists, cannot loot queued items", corpseId)
                goto nextCorpse
            end
            
            local navSuccess = navigation.navigateToCorpse(self.config, corpseId)
            if not navSuccess then
                self.debugPrint(string.format("Failed to navigate to corpse %s", corpseId))
                goto nextCorpse
            end
            
            if not self.openCorpse(corpseId) then
                self.debugPrint(string.format("Failed to open corpse %s", corpseId))
                goto nextCorpse
            end
            
            local results = self.lootAllQueuedItemsFromCorpse(corpseId, queuedItems)
            
            self.closeLootWindow()
            
            ::nextCorpse::
        end
        
        self.myQueuedItems = {}
        
        navigation.navigateToLocation(self.config, startingLocation.X, startingLocation.Y, startingLocation.Z)
        mq.delay(startingLocation.timeToWait)
        
        if stickState then
            mq.cmdf("/stick on")
        end
        
        -- NEW: Re-enable E3 looting
        self.restoreE3Loot()
        
        mq.cmdf("/g %s finished looting queued items", mq.TLO.Me.Name())
    end
    
    function self.queueItem(line, groupMemberName, corpseId, itemId, itemName, isLore)
        local myName = tostring(mq.TLO.Me.Name())
        
        if groupMemberName ~= myName then
            return
        end
        
        local isLoreItem = (isLore == "1" or isLore == "true")
        
        self.debugPrint(string.format("Queueing item %s (%s) from corpse %s for %s, isLore: %s", 
            itemName or itemId, itemId, corpseId, groupMemberName, tostring(isLoreItem)))
        
        if isLoreItem then
            if utils.ownItem(itemName) then
                mq.cmdf("/g %s already owns %s (Lore item - inventory or bank)", myName, itemName)
                return
            end
            
            for cId, items in pairs(self.myQueuedItems) do
                for _, qItem in pairs(items) do
                    if qItem.itemName == itemName then
                        mq.cmdf("/g %s already has %s queued (Lore item)", myName, itemName)
                        return
                    end
                end
            end
        end
        
        mq.cmdf("/g %s is adding %s from corpse %d to loot queue", myName, itemName or ("itemId " .. itemId), tonumber(corpseId))
        
        local normalizedCorpseId = tonumber(corpseId)
        local normalizedItemId = tonumber(itemId)
        
        if self.myQueuedItems[normalizedCorpseId] then
            for _, qItem in pairs(self.myQueuedItems[normalizedCorpseId]) do
                if qItem.itemId == normalizedItemId then
                    if not isLoreItem then
                        qItem.count = (qItem.count or 1) + 1
                    end
                    return
                end
            end
        end
        
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
    end
    
    function self.doLoot(isMaster)
        -- Check if find mode is running
        if self.findMode then
            print("[MasterLoot] Find mode in progress - cannot start loot operation")
            print("[MasterLoot] Restart MasterLoot to cancel: /lua stop masterloot && /lua run masterloot")
            return
        end
        
        self.debugPrint("Starting loot operation, isMaster: " .. tostring(isMaster))
        mq.cmdf("/g " .. mq.TLO.Me.Name() .. " is beginning Loot")
        
        -- NEW: Disable E3 looting
        self.disableE3Loot()
        
        local startingLocation = {
            X = mq.TLO.Me.X(),
            Y = mq.TLO.Me.Y(),
            Z = mq.TLO.Me.Z(),
            timeToWait = "2s"
        }
        
        local stickState = false
        if mq.TLO.Stick.Active() then
            stickState = true
            mq.cmdf("/stick off")
        end
        mq.delay(self.delays.stickOff)
        
        local spawnCount = mq.TLO.SpawnCount("npccorpse radius 500 zradius 30")()
        local corpseTable = corpseManager.getCorpseTable(spawnCount)
        
        local corpsesProcessed = 0
        local corpsesLooted = 0
        local corpsesDespawned = 0
        local corpsesSkipped = 0
        local corpsesFailed = 0
        local retryCount = {}
        local maxRetries = 3
        local progressInterval = 25  -- Log progress every 25 corpses

        while #corpseTable > 0 do
            local currentCorpse
            currentCorpse, corpseTable = corpseManager.getNearestCorpse(corpseTable)
            
            -- SAFEGUARD: If getNearestCorpse returns nil but table isn't empty, something is wrong
            if not currentCorpse then
                if #corpseTable > 0 then
                    print(string.format("[MasterLoot] WARNING: getNearestCorpse returned nil but %d corpses remain - clearing table", #corpseTable))
                    corpseTable = {}  -- Force exit to prevent infinite loop
                end
                break
            end
            
            if currentCorpse and currentCorpse.ID and not self.isLooted(currentCorpse.ID) then
                corpsesProcessed = corpsesProcessed + 1
                
                -- Periodic progress report (always visible)
                if corpsesProcessed % progressInterval == 0 then
                    print(string.format("[MasterLoot] Progress: %d corpses processed, %d remaining", 
                        corpsesProcessed, #corpseTable))
                end
                
                if not self.corpseStillExists(currentCorpse.ID) then
                    corpsesDespawned = corpsesDespawned + 1
                    table.insert(self.lootedCorpses, currentCorpse.ID)
                    goto continue
                end
                
                -- NEW: Skip if another group member is targeting this corpse
                local isTargeted, targetedBy = self.isCorpseTargetedByGroupMember(currentCorpse.ID)
                if isTargeted then
                    self.debugPrint(string.format("Skipping corpse %d - targeted by %s", 
                        currentCorpse.ID, targetedBy or "group member"))
                    -- Track collision retries with same retry counter
                    retryCount[currentCorpse.ID] = (retryCount[currentCorpse.ID] or 0) + 1
                    if retryCount[currentCorpse.ID] <= maxRetries then
                        table.insert(corpseTable, currentCorpse)
                    else
                        self.debugPrint(string.format("Corpse %d exceeded collision retry limit", currentCorpse.ID))
                        table.insert(self.lootedCorpses, currentCorpse.ID)
                        corpsesFailed = corpsesFailed + 1
                    end
                    goto continue
                end
                
                local navSuccess, navError = navigation.navigateToCorpse(self.config, currentCorpse.ID)
                
                if navSuccess then
                    local lootResult = self.lootCorpse(currentCorpse, isMaster)
                    
                    if lootResult == "retry" then
                        retryCount[currentCorpse.ID] = (retryCount[currentCorpse.ID] or 0) + 1
                        if retryCount[currentCorpse.ID] <= maxRetries then
                            table.insert(corpseTable, currentCorpse)
                        else
                            table.insert(self.lootedCorpses, currentCorpse.ID)
                            corpsesFailed = corpsesFailed + 1
                        end
                    else
                        corpsesLooted = corpsesLooted + 1
                    end
                elseif navError == "despawned" then
                    corpsesDespawned = corpsesDespawned + 1
                    table.insert(self.lootedCorpses, currentCorpse.ID)
                else
                    retryCount[currentCorpse.ID] = (retryCount[currentCorpse.ID] or 0) + 1
                    if retryCount[currentCorpse.ID] <= maxRetries then
                        table.insert(corpseTable, currentCorpse)
                    else
                        table.insert(self.lootedCorpses, currentCorpse.ID)
                        corpsesFailed = corpsesFailed + 1
                    end
                end
            else
                corpsesSkipped = corpsesSkipped + 1
            end
            
            ::continue::
        end
        
        navigation.navigateToLocation(self.config, startingLocation.X, startingLocation.Y, startingLocation.Z)
        mq.delay(startingLocation.timeToWait)
        
        if stickState then
            mq.cmdf("/stick on")
        end
        
        -- NEW: Re-enable E3 looting
        self.restoreE3Loot()
        
        mq.cmdf("/g " .. mq.TLO.Me.Name() .. " is done Looting")
    end
    
    function self.decrementSharedItemCount(corpseId, itemId)
        local normalizedCorpseId = tonumber(corpseId)
        local normalizedItemId = tonumber(itemId)
        
        if not self.multipleUseTable[normalizedCorpseId] then
            return false
        end
        
        for idx, item in ipairs(self.multipleUseTable[normalizedCorpseId]) do
            if item.itemId == normalizedItemId then
                item.count = (item.count or 1) - 1
                
                if item.count <= 0 then
                    table.remove(self.multipleUseTable[normalizedCorpseId], idx)
                    
                    if #self.multipleUseTable[normalizedCorpseId] == 0 then
                        self.multipleUseTable[normalizedCorpseId] = nil
                    end
                end
                return true
            end
        end
        
        return false
    end
    
    function self.removeFromUpgradeList(line, looterName, itemName)
        if itemName and string.sub(itemName, -1) == "'" then
            itemName = string.sub(itemName, 1, -2)
        end
        
        if not itemName or itemName == "" then
            return
        end
        
        for i = #self.upgradeList, 1, -1 do
            if self.upgradeList[i].itemName == itemName then
                table.remove(self.upgradeList, i)
            end
        end
    end
    
    function self.debugDumpSharedItems()
        print("===== SHARED ITEMS (multipleUseTable) =====")
        if not self.multipleUseTable or not next(self.multipleUseTable) then
            print("  (empty)")
        else
            for corpseId, items in pairs(self.multipleUseTable) do
                print(string.format("  Corpse %s:", tostring(corpseId)))
                for _, item in ipairs(items) do
                    print(string.format("    - %s (ID:%s) x%d %s", 
                        item.itemName or "Unknown", 
                        tostring(item.itemId),
                        item.count or 1,
                        item.isLore and "[LORE]" or ""))
                end
            end
        end
    end
    
    return self
end

return LootManager