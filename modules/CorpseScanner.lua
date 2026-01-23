-- modules/CorpseScanner.lua
-- Handles the "Scan All Corpses" feature - scans assigned corpses and shares ALL items found

local mq = require('mq')

local CorpseScanner = {}

function CorpseScanner.new(config, utils, lootState, navigation, actorManager, lootManager)
    local self = {
        config = config,
        utils = utils,
        lootState = lootState,
        navigation = navigation,
        actorManager = actorManager,
        lootManager = lootManager,  -- For core utilities like openCorpse, closeLootWindow
        debugEnabled = false,
        delays = {
            corpseOpen = 700,
            windowClose = 50,
        },
        -- Local scan state (used instead of lootState if lootState is nil)
        scanMode = false,
        scanFailures = {},
        scanItemCount = 0,
        scanCorpseCount = 0,
    }
    
    -- Helper to get/set scan state (uses lootState if available, otherwise local)
    function self.getScanState()
        if self.lootState then
            return self.lootState
        else
            return self
        end
    end
    
    function self.debugPrint(message)
        if self.debugEnabled then
            print(string.format("[CorpseScanner]: %s", message))
        end
    end
    
    function self.setDebug(enabled)
        self.debugEnabled = enabled
    end
    
    -- Parse the /mlscan command: /mlscan <charName> <corpseId1>,<corpseId2>,...
    function self.parseAssignment(line)
        if not line or line == "" then
            return nil, nil
        end
        
        -- Expected format: "CharName 142,156,178,183"
        local charName, corpseListStr = string.match(line, "^(%S+)%s+(.+)$")
        
        if not charName or not corpseListStr then
            print("[CorpseScanner] ERROR: Invalid /mlscan format. Expected: /mlscan <charName> <corpseId1>,<corpseId2>,...")
            return nil, nil
        end
        
        -- Parse comma-separated corpse IDs
        local corpseIds = {}
        for idStr in string.gmatch(corpseListStr, "([^,]+)") do
            local id = tonumber(idStr)
            if id then
                table.insert(corpseIds, id)
            end
        end
        
        return charName, corpseIds
    end
    
    -- Check if this assignment is for me
    function self.isAssignmentForMe(charName)
        local myName = mq.TLO.Me.Name()
        return charName == myName
    end
    
    -- Scan a single corpse and add ALL items to shared list
    -- Returns: true (success), false (permanent failure), "retry" (temporary failure)
    function self.scanCorpse(corpseId)
        self.debugPrint(string.format("Scanning corpse ID: %d", corpseId))
        
        -- Check if corpse still exists
        if not lootManager.corpseStillExists(corpseId) then
            self.debugPrint(string.format("Corpse %d despawned, adding to failures", corpseId))
            table.insert(self.getScanState().scanFailures, {id = corpseId, reason = "despawned"})
            return false
        end
        
        -- Navigate to corpse
        local navSuccess, navError = navigation.navigateToCorpse(self.config, corpseId)
        if not navSuccess then
            self.debugPrint(string.format("Failed to navigate to corpse %d: %s", corpseId, navError or "unknown"))
            if navError == "despawned" then
                table.insert(self.getScanState().scanFailures, {id = corpseId, reason = "despawned"})
                return false
            end
            return "retry"
        end
        
        -- Open the corpse with retry and corpsefix logic (same as mlml)
        if not lootManager.openCorpse(corpseId) then
            self.debugPrint(string.format("Failed to open corpse %d, retrying with corpsefix", corpseId))
            local retryCount = 0
            local maxRetries = 5
            
            while retryCount < maxRetries do
                if retryCount > 3 then
                    self.debugPrint("Using corpsefix command")
                    mq.cmdf("/say #corpsefix")
                end
                mq.delay(self.delays.corpseOpen)
                navigation.navigateToCorpse(self.config, corpseId)
                mq.cmdf("/loot")
                mq.delay(self.delays.corpseOpen)
                retryCount = retryCount + 1
                
                if mq.TLO.Window("LootWnd").Open() then
                    self.debugPrint("Loot window opened after retry")
                    break
                end
            end
            
            if retryCount >= maxRetries and not mq.TLO.Window("LootWnd").Open() then
                self.debugPrint(string.format("Failed to open corpse %d after max retries", corpseId))
                return "retry"
            end
        end
        
        -- Get item count
        local itemCount = tonumber(mq.TLO.Corpse.Items()) or 0
        self.debugPrint(string.format("Corpse %d has %d items", corpseId, itemCount))
        
        if itemCount == 0 then
            lootManager.closeLootWindow()
            return true
        end
        
        -- Track items by itemId for aggregation
        local itemsOnCorpse = {}
        
        -- Scan all items
        for i = 1, itemCount do
            local corpseItem = mq.TLO.Corpse.Item(i)
            
            if corpseItem and corpseItem.ID() then
                local itemId = corpseItem.ID()
                local itemName = corpseItem.Name()
                local itemLink = corpseItem.ItemLink('CLICKABLE')()
                local isLore = corpseItem.Lore() or false
                
                -- Aggregate by itemId
                if itemsOnCorpse[itemId] then
                    itemsOnCorpse[itemId].count = itemsOnCorpse[itemId].count + 1
                else
                    itemsOnCorpse[itemId] = {
                        itemId = itemId,
                        itemName = itemName,
                        itemLink = itemLink,
                        isLore = isLore,
                        count = 1
                    }
                end
                
                self.getScanState().scanItemCount = self.getScanState().scanItemCount + 1
            end
        end
        
        -- Broadcast each unique item (with count) to group
        for itemId, item in pairs(itemsOnCorpse) do
            -- Broadcast via group chat for remote characters
            if item.count > 1 then
                mq.cmdf("/g Shared Item: %s x%d", item.itemLink, item.count)
            else
                mq.cmdf("/g Shared Item: %s", item.itemLink)
            end
            
            -- Also broadcast via Actor for local characters
            actorManager.broadcastShareItem(
                corpseId,
                item.itemId,
                item.itemName,
                item.itemLink,
                item.isLore,
                item.count
            )
            
            -- Add to our own multipleUseTable
            local sharedItemMessage = {
                corpseId = corpseId,
                itemId = item.itemId,
                itemName = item.itemName,
                itemLink = item.itemLink,
                isLore = item.isLore,
                count = item.count
            }
            lootManager.handleSharedItem(sharedItemMessage)
        end
        
        lootManager.closeLootWindow()
        self.getScanState().scanCorpseCount = self.getScanState().scanCorpseCount + 1
        
        return true
    end
    
    -- Main scan function - processes assigned corpses
    function self.doScan(corpseIds)
        if not corpseIds or #corpseIds == 0 then
            print("[CorpseScanner] No corpses assigned to scan")
            return
        end
        
        local myName = mq.TLO.Me.Name()
        mq.cmdf("/g %s starting scan of %d corpses", myName, #corpseIds)
        
        -- Reset scan state
        self.getScanState().scanMode = true
        self.getScanState().scanFailures = {}
        self.getScanState().scanItemCount = 0
        self.getScanState().scanCorpseCount = 0
        
        -- Disable E3 looting if active
        lootManager.disableE3Loot()
        
        -- Save starting location
        local startingLocation = {
            X = mq.TLO.Me.X(),
            Y = mq.TLO.Me.Y(),
            Z = mq.TLO.Me.Z(),
        }
        
        -- Turn off stick if active
        local stickState = false
        if mq.TLO.Stick.Active() then
            stickState = true
            mq.cmdf("/stick off")
        end
        mq.delay(100)
        
        -- Build a working table of corpses to process (allows retry)
        local corpseTable = {}
        for _, corpseId in ipairs(corpseIds) do
            table.insert(corpseTable, corpseId)
        end
        
        local retryCount = {}
        local maxRetries = 2
        
        -- Process corpses with retry logic
        while #corpseTable > 0 do
            local corpseId = table.remove(corpseTable, 1)
            local result = self.scanCorpse(corpseId)
            
            if result == "retry" then
                retryCount[corpseId] = (retryCount[corpseId] or 0) + 1
                if retryCount[corpseId] <= maxRetries then
                    self.debugPrint(string.format("Retrying corpse %d (attempt %d)", corpseId, retryCount[corpseId]))
                    table.insert(corpseTable, corpseId)
                else
                    self.debugPrint(string.format("Corpse %d failed after %d retries", corpseId, maxRetries))
                    table.insert(self.getScanState().scanFailures, {id = corpseId, reason = "max_retries"})
                end
            end
        end
        
        -- Return to starting location
        navigation.navigateToLocation(self.config, startingLocation.X, startingLocation.Y, startingLocation.Z)
        mq.delay("2s")
        
        -- Restore stick if it was active
        if stickState then
            mq.cmdf("/stick on")
        end
        
        -- Re-enable E3 looting
        lootManager.restoreE3Loot()
        
        -- Report results
        self.reportResults()
        
        self.getScanState().scanMode = false
    end
    
    -- Report scan results
    function self.reportResults()
        local myName = mq.TLO.Me.Name()
        
        -- Summary message
        mq.cmdf("/g %s scanned %d corpses, found %d items", 
            myName, self.getScanState().scanCorpseCount, self.getScanState().scanItemCount)
        
        -- Report failures if any
        if #self.getScanState().scanFailures > 0 then
            local failedIds = {}
            for _, failure in ipairs(self.getScanState().scanFailures) do
                table.insert(failedIds, tostring(failure.id))
            end
            mq.cmdf("/g %s could not scan corpses: %s", myName, table.concat(failedIds, ", "))
        end
    end
    
    -- Handle /mlscan command
    function self.handleScanCommand(line)
        local charName, corpseIds = self.parseAssignment(line)
        
        if not charName or not corpseIds then
            return
        end
        
        if not self.isAssignmentForMe(charName) then
            self.debugPrint(string.format("Scan assignment for %s, not me", charName))
            return
        end
        
        self.debugPrint(string.format("Received scan assignment: %d corpses", #corpseIds))
        self.doScan(corpseIds)
    end
    
    -- Master coordinator function - divides corpses among group and sends assignments
    function self.coordinateScan()
        local myName = mq.TLO.Me.Name()
        local groupSize = (mq.TLO.Group.GroupSize() or 1)
        
        -- Build corpse table - use large radius (1000) to balance coverage with reliability
        -- Zone-wide queries can return nil IDs for very distant corpses
        local spawnCount = mq.TLO.SpawnCount("npccorpse radius 1000")()
        
        if spawnCount == 0 then
            mq.cmdf("/g No corpses found to scan")
            return
        end
        
        -- Get all corpse IDs
        local allCorpses = {}
        for i = 1, spawnCount do
            local spawn = mq.TLO.NearestSpawn(i, "npccorpse radius 1000")
            if spawn and spawn.ID() and spawn.ID() > 0 then
                table.insert(allCorpses, spawn.ID())
            end
        end
        
        mq.cmdf("/g %s coordinating scan of %d corpses among %d group members", 
            myName, #allCorpses, groupSize)
        
        -- Build list of group member names
        local members = {}
        for i = 0, groupSize - 1 do
            local memberName = mq.TLO.Group.Member(i).Name()
            if memberName then
                table.insert(members, memberName)
            end
        end
        
        -- If no group members found, just use self
        if #members == 0 then
            members = {myName}
        end
        
        -- Divide corpses among members
        local corpsesPerMember = math.ceil(#allCorpses / #members)
        
        for i, memberName in ipairs(members) do
            local startIdx = ((i - 1) * corpsesPerMember) + 1
            local endIdx = math.min(i * corpsesPerMember, #allCorpses)
            
            if startIdx <= #allCorpses then
                local assignedIds = {}
                for j = startIdx, endIdx do
                    table.insert(assignedIds, allCorpses[j])
                end
                
                -- Send assignment via group chat
                local idList = table.concat(assignedIds, ",")
                mq.cmdf("/g mlscan %s %s", memberName, idList)
                
                self.debugPrint(string.format("Assigned corpses %d-%d to %s", startIdx, endIdx, memberName))
            end
        end
    end
    
    return self
end

return CorpseScanner