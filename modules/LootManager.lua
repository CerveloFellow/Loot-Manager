-- modules/LootManager.lua
local mq = require('mq')

local LootManager = {}

function LootManager.new(config, utils, itemEvaluator, corpseManager, navigation, actorManager)
    local self = {
        multipleUseTable = {},
        myQueuedItems = {},
        listboxSelectedOption = {},
        lootedCorpses = {},
        config = config,
        utils = utils,
        itemEvaluator = itemEvaluator,
        corpseManager = corpseManager,
        navigation = navigation,
        actorManager = actorManager
    }
    
    function self.handleSharedItem(message)
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
        end
        
        utils.multimapInsert(self.multipleUseTable, message.corpseId, item)
    end
    
    function self.printMultipleUseItems()
        mq.cmdf("/g List of items that can be used by members of your group")
        for key, valueList in pairs(self.multipleUseTable) do
            print("Key:", key)
            for _, value in ipairs(valueList) do
                mq.cmdf("/g %s", value.itemLink)
            end
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
            mq.delay(100)
        end
    end
    
    function self.lootItem(corpseItem, slotIndex)
        mq.cmdf('/g '..mq.TLO.Me.Name().." is looting ".. corpseItem.ItemLink('CLICKABLE')())
        mq.cmdf("/shift /itemnotify loot%d rightmouseup", slotIndex)
        mq.delay(300)
        
        if mq.TLO.Window("QuantityWnd").Open() then
            mq.cmdf("/notify QuantityWnd QTYW_Accept_Button leftmouseup")
            mq.delay(250)
        end
    end
    
    function self.lootCorpse(corpseObject, isMaster)
        mq.cmdf("/target id %d", corpseObject.ID)
        mq.delay(300)
        mq.cmdf("/loot")
        
        mq.delay("5s", function() return mq.TLO.Window("LootWnd").Open() end)
        
        local retryCount = 0
        local maxRetries = 1

        if (not mq.TLO.Window("LootWnd").Open()) then
            while retryCount < maxRetries do
                mq.cmdf("/say #corpsefix")
                mq.delay(500)
                mq.cmdf("/warp loc %f %f %f", corpseObject.Y, corpseObject.X, corpseObject.Z)
                retryCount = retryCount + 1
                
                if mq.TLO.Window("LootWnd").Open() then
                    break
                end
            end
            
            if retryCount >= maxRetries and not mq.TLO.Window("LootWnd").Open() then
                return
            end
        end

        if((mq.TLO.Target.ID() or 0)==0) then
            table.insert(self.lootedCorpses, corpseObject.ID)
            return
        end

        -- Get the actual corpse ID we're looting from
        local actualCorpseId = mq.TLO.Target.ID()
        
        local itemCount = tonumber(mq.TLO.Corpse.Items()) or 0
        
        if itemCount == 0 then
            self.closeLootWindow()
            return
        end
        
        for i = 1, itemCount do
            self.checkInventorySpace()
            
            mq.delay("3s", function() return mq.TLO.Corpse.Item(i).ID() end)
            local corpseItem = mq.TLO.Corpse.Item(i)
            local isSharedItem = utils.contains(config.itemsToShare, corpseItem.Name())

            if itemEvaluator.shouldLoot(config, utils, corpseItem) and (not isSharedItem) then
                self.lootItem(corpseItem, i)
            else
                if (itemEvaluator.groupMembersCanUse(corpseItem) > 1 or isSharedItem) and 
                   (not itemEvaluator.skipItem(config, utils, corpseItem)) then
                    mq.cmdf("/g Shared Item: "..corpseItem.ItemLink('CLICKABLE')())
                    
                    -- Use actualCorpseId instead of corpseObject.ID
                    actorManager.broadcastShareItem(
                        actualCorpseId,
                        corpseItem.ID(), 
                        corpseItem.Name(), 
                        corpseItem.ItemLink('CLICKABLE')()
                    )
                end
            end
            
            if mq.TLO.Cursor then
                mq.cmdf("/autoinventory")
            end
        end
        
        -- Use actualCorpseId here too
        table.insert(self.lootedCorpses, actualCorpseId)
        self.closeLootWindow()
        return true
    end
    
    function self.openCorpse(corpseId)
        mq.cmdf("/target id %d", corpseId)
        mq.delay(300)
        
        -- Check if we successfully targeted the corpse
        if (mq.TLO.Target.ID() or 0) == 0 then
            print("ERROR: Failed to target corpse ID: " .. tostring(corpseId))
            return false
        end
        
        -- Get target coordinates and validate them
        local targetX = mq.TLO.Target.X()
        local targetY = mq.TLO.Target.Y()
        local targetZ = mq.TLO.Target.Z()
        
        if not targetX or not targetY or not targetZ then
            print("ERROR: Target coordinates are invalid for corpse ID: " .. tostring(corpseId))
            return false
        end

        if config.useWarp then
            mq.cmdf("/warp loc %f %f %f", targetY, targetX, targetZ)
        else
            mq.cmdf("/squelch /nav target")
        end
        
        mq.delay(300)
        mq.cmdf("/loot")
        
        local retryCount = 0
        local retryMax = 5

        while not mq.TLO.Window("LootWnd").Open() and (retryCount < retryMax) do
            mq.cmdf("/say #corpsefix")
            mq.delay(300)
            
            -- Re-validate coordinates before each retry
            targetX = mq.TLO.Target.X()
            targetY = mq.TLO.Target.Y()
            targetZ = mq.TLO.Target.Z()
            
            if not targetX or not targetY or not targetZ then
                print("ERROR: Lost target during retry for corpse ID: " .. tostring(corpseId))
                return false
            end
            
            if config.useWarp then
                mq.cmdf("/warp loc %f %f %f", targetY, targetX, targetZ)
            else
                mq.cmdf("/squelch /nav target")
            end
            mq.delay(300)
            retryCount = retryCount + 1
        end

        if retryCount >= retryMax then
            mq.cmdf("/g Could not loot targeted corpse, skipping.")
            return false
        end
        
        return true
    end
    
    function self.processQueuedItemsInCorpse(items, corpseItemCount)
        for i = 1, corpseItemCount do
            local idx2, tbl = next(items)
            
            while idx2 do
                local nextIdx2 = next(items, idx2)
                
                self.checkInventorySpace()
                
                mq.delay("3s", function() return mq.TLO.Corpse.Item(i).ID() end)
                local corpseItem = mq.TLO.Corpse.Item(i)
                local localItemId = corpseItem.ID()
                
                if tostring(localItemId) == tostring(tbl.itemId) then
                    self.lootItem(corpseItem, i)
                    
                    if mq.TLO.Cursor then
                        mq.cmdf("/autoinventory")
                    end

                    print("Removing queued item idx2: " .. tostring(idx2))
                    items[idx2] = nil
                    mq.delay(300)
                end
                
                idx2 = nextIdx2
                if idx2 then
                    tbl = items[idx2]
                end
            end
        end
    end
    
    function self.lootQueuedItems()
        -- Ensure myQueuedItems is initialized
        if not self.myQueuedItems then
            self.myQueuedItems = {}
            print("No items in queue to loot")
            return
        end

        local idx, items = next(self.myQueuedItems)
        
        while idx do
            local nextIdx = next(self.myQueuedItems, idx)
            
            if not self.openCorpse(idx) then
                idx = nextIdx
                if idx then
                    items = self.myQueuedItems[idx]
                end
                goto continue
            end
            
            local corpseItemCount = tonumber(mq.TLO.Corpse.Items()) or 0
            
            if corpseItemCount == 0 then
                self.closeLootWindow()
                idx = nextIdx
                if idx then
                    items = self.myQueuedItems[idx]
                end
                goto continue
            end

            self.processQueuedItemsInCorpse(items, corpseItemCount)
            self.closeLootWindow()
            
            print("Removing corpse idx: " .. tostring(idx))
            self.myQueuedItems[idx] = nil
            
            idx = nextIdx
            if idx then
                items = self.myQueuedItems[idx]
            end
            
            ::continue::
        end
    end
    
    function self.doLoot(isMaster)
        local startingLocation = {
            X = mq.TLO.Me.X(),
            Y = mq.TLO.Me.Y(),
            Z = mq.TLO.Me.Z(),
            timeToWait = "2s",
            arrivalDistance = 5
        }
        
        local stickState = false
        self.myQueuedItems = {}
        self.listboxSelectedOption = {}

        mq.cmdf("/g " .. mq.TLO.Me.Name() .. " has started looting")
        
        if mq.TLO.Stick.Active() then
            stickState = true
            mq.cmdf("/stick off")
        end
        
        mq.delay(500)
        
        -- Main looting loop
        local corpseTable = corpseManager.getCorpseTable(mq.TLO.SpawnCount("npccorpse radius 200 zradius 10")())

        while #corpseTable > 0 do
            local currentCorpse
            print("Corpses Remaining: "..tostring(#corpseTable))
            currentCorpse, corpseTable = corpseManager.getRandomCorpse(corpseTable)
            
            if currentCorpse and not self.isLooted(currentCorpse.ID) then
                local navSuccess = navigation.navigateToLocation(
                    config,
                    currentCorpse.X,
                    currentCorpse.Y,
                    currentCorpse.Z
                )
                
                if navSuccess then
                    if config.useWarp then
                        mq.delay(500)
                    else
                        mq.delay("2s")
                    end
                    self.lootCorpse(currentCorpse, isMaster)
                else
                    print("Failed to navigate to corpse ID: " .. currentCorpse.ID)
                end
            end
        end
        
        -- Return to starting location
        navigation.navigateToLocation(config, startingLocation.X, startingLocation.Y, startingLocation.Z)
        mq.delay(startingLocation.timeToWait)
        
        mq.cmdf("/g " .. mq.TLO.Me.Name() .. " is done Looting")
    end
    
    function self.queueItem(line, groupMemberName, corpseId, itemId)
        local myName = tostring(mq.TLO.Me.Name())
        
        if groupMemberName ~= myName then
            return
        end
        
        mq.cmdf("/g " .. myName .. " is adding itemId(" .. itemId .. ") and corpseId(" .. corpseId .. ") to my loot queue")
        
        local queuedItem = {
            corpseId = corpseId,
            itemId = itemId
        }

        utils.multimapInsert(self.myQueuedItems, corpseId, queuedItem)

        -- Remove from multiple use table
        for idx, items in pairs(self.multipleUseTable) do
            if tostring(idx) == tostring(corpseId) then
                for idx2, tbl in pairs(items) do
                    if tostring(tbl.itemId) == tostring(itemId) then
                        table.remove(items, idx2)
                    end
                end
            end
        end
    end
    
    return self
end

return LootManager