-- modules/GUI.lua
local mq = require('mq')
local imgui = require('ImGui')

local GUI = {}

function GUI.new(lootManager, actorManager, utils)
    local self = {
        radioSelectedOption = 0,
        groupMemberSelected = mq.TLO.Me.Name(),
        lootManager = lootManager,
        actorManager = actorManager,
        utils = utils,
        groupMemberCorpseStats = {}  -- Track unlooted corpse counts per member
    }
    
    function self.initializeDefaults()
        if self.radioSelectedOption == nil then
            self.radioSelectedOption = 0
            local firstMember = mq.TLO.Group.Member(0).Name()
            if firstMember and firstMember ~= "" then
                self.groupMemberSelected = firstMember
            else
                local myName = mq.TLO.Me.Name()
                self.groupMemberSelected = myName or "Unknown"
            end
        end
        
        if lootManager.listboxSelectedOption == nil and next(lootManager.multipleUseTable) ~= nil then
            lootManager.listboxSelectedOption = {}
        end
    end
    
    -- NEW: Function to get color based on unlooted corpse percentage
    function self.getCorpseStatusColor(memberName)
        local stats = self.groupMemberCorpseStats[memberName]
        
        if not stats or stats.totalCorpses == 0 then
            return 1.0, 1.0, 1.0, 1.0  -- White (no corpses or no data)
        end
        
        local unlootedPercent = (stats.unlootedCorpses / stats.totalCorpses) * 100
        
        if unlootedPercent >= 67 then
            return 1.0, 0.0, 0.0, 1.0  -- Red (67-100%)
        elseif unlootedPercent >= 34 then
            return 1.0, 0.65, 0.0, 1.0  -- Orange (34-66%)
        elseif unlootedPercent >= 1 then
            return 1.0, 1.0, 0.0, 1.0  -- Yellow (1-33%)
        else
            return 1.0, 1.0, 1.0, 1.0  -- White (0%)
        end
    end
    
    -- NEW: Handler for receiving corpse stats from other group members
    function self.handleCorpseStats(message)
        if message.senderName then
            self.groupMemberCorpseStats[message.senderName] = {
                totalCorpses = message.totalCorpses or 0,
                unlootedCorpses = message.unlootedCorpses or 0
            }
        end
    end
    
    -- NEW: Update local corpse stats
    function self.updateLocalCorpseStats()
        local myName = mq.TLO.Me.Name()
        if not myName then return end
        
        local totalCorpses = mq.TLO.SpawnCount("npccorpse radius 200 zradius 30")() or 0
        local unlootedCount = 0
        
        if totalCorpses > 0 then
            for i = 1, totalCorpses do
                local spawn = mq.TLO.NearestSpawn(i, "npccorpse radius 200 zradius 30")
                if spawn and spawn.ID() and spawn.ID() > 0 then
                    local corpseId = spawn.ID()
                    local isLooted = false
                    
                    for _, lootedId in ipairs(lootManager.lootedCorpses) do
                        if corpseId == lootedId then
                            isLooted = true
                            break
                        end
                    end
                    
                    if not isLooted then
                        unlootedCount = unlootedCount + 1
                    end
                end
            end
        end
        
        self.groupMemberCorpseStats[myName] = {
            totalCorpses = totalCorpses,
            unlootedCorpses = unlootedCount
        }
    end
    
    function self.everyoneLoot()
        mq.cmdf("/dgga /mlml")
    end
    
    function self.executePeerLoot()
        local myName = mq.TLO.Me.Name()
        if not myName then
            print("ERROR: Unable to get character name")
            return
        end
        
        if self.groupMemberSelected == myName then
            mq.cmdf("/mlml")
        else
            mq.cmdf("/dex %s /mlml", self.groupMemberSelected)
        end
    end
    
    function self.executeQueueItem()
        if not lootManager.listboxSelectedOption or 
           not lootManager.listboxSelectedOption.corpseId or 
           not lootManager.listboxSelectedOption.itemId then
            print("No item selected to queue")
            return
        end
        
        local selectedItem = lootManager.listboxSelectedOption
        local isLore = selectedItem.isLore or false
        local itemName = selectedItem.itemName or "Unknown"
        
        -- Lore item validation on the sender side
        -- The receiver will also validate, but we can give immediate feedback here
        if isLore then
            -- Check if selected member is self and we already own it
            local myName = mq.TLO.Me.Name()
            if self.groupMemberSelected == myName then
                if utils and utils.ownItem and utils.ownItem(itemName) then
                    mq.cmdf("/g Cannot queue %s - %s already owns this Lore item", itemName, myName)
                    print(string.format("Cannot queue %s - you already own this Lore item", itemName))
                    return
                end
            end
        end
        
        -- Send queue command with itemName and isLore flag
        -- Format: mlqi <memberName> <corpseId> <itemId> "<itemName>" <isLore>
        -- Item name is quoted to handle spaces
        local isLoreStr = isLore and "1" or "0"
        mq.cmdf("/g mlqi %s %d %d \"%s\" %s", 
            self.groupMemberSelected, 
            selectedItem.corpseId, 
            selectedItem.itemId,
            itemName,
            isLoreStr)

        -- Decrement count in multipleUseTable (remove if count reaches 0)
        lootManager.decrementSharedItemCount(selectedItem.corpseId, selectedItem.itemId)
        
        -- Update listboxSelectedOption if the item was removed
        -- Find the next available item to select
        local foundNewSelection = false
        for corpseId, items in pairs(lootManager.multipleUseTable) do
            for _, tbl in ipairs(items) do
                lootManager.listboxSelectedOption = {
                    corpseId = corpseId,
                    itemId = tbl.itemId,
                    itemName = tbl.itemName,
                    isLore = tbl.isLore
                }
                foundNewSelection = true
                break
            end
            if foundNewSelection then break end
        end
        
        if not foundNewSelection then
            lootManager.listboxSelectedOption = {}
        end
    end
    
    function self.executeLootItems()
        local myName = mq.TLO.Me.Name()
        if not myName then
            print("ERROR: Unable to get character name")
            return
        end
        
        if self.groupMemberSelected == myName then
            mq.cmdf("/mlli")
        else
            mq.cmdf("/dex %s /mlli", self.groupMemberSelected)
        end
    end
    
    function self.executeReportUnlootedCorpses()
        mq.cmdf("/g /mlru")
    end
    
    function self.renderActionButtons()
        ImGui.SetWindowFontScale(0.7)
        
        imgui.SameLine()
        if imgui.Button("Everyone Loot") then
            self.everyoneLoot()
        end

        imgui.SameLine()
        if imgui.Button("Loot") then
            self.executePeerLoot()
        end
        
        imgui.SameLine()
        if imgui.Button("Queue Shared Item") then
            self.executeQueueItem()
        end

        imgui.SameLine()
        if imgui.Button("Get Shared Item(s)") then
            self.executeLootItems()
        end

        imgui.SameLine()
        if imgui.Button("Clear Shared List") then
            lootManager.multipleUseTable = {}
            lootManager.listboxSelectedOption = {}
            lootManager.upgradeList = {}
            actorManager.broadcastClearSharedList()
            mq.cmdf("/g Shared loot list cleared")
        end
        
        ImGui.SetWindowFontScale(1.0)
    end
    
function self.renderGroupMemberSelection()
    local groupSize = (mq.TLO.Group.GroupSize() or 0) - 1
    local myName = mq.TLO.Me.Name()

    -- If not grouped, show only self
    if groupSize < 0 then
        local isActive = (self.radioSelectedOption == 0)
        
        -- Get color based on corpse status
        local r, g, b, a = self.getCorpseStatusColor(myName)
        
        ImGui.SetWindowFontScale(0.7)
        imgui.PushStyleColor(ImGuiCol.Text, r, g, b, a)
        
        if imgui.RadioButton(myName, isActive) then
            self.radioSelectedOption = 0
            self.groupMemberSelected = myName
        end
        
        imgui.PopStyleColor()
        ImGui.SetWindowFontScale(1.0)
    else
        -- Show all group members
        for i = 0, groupSize do
            local memberName = mq.TLO.Group.Member(i).Name()
            local isActive = (self.radioSelectedOption == i)
            
            -- Get color based on corpse status
            local r, g, b, a = self.getCorpseStatusColor(memberName)
            
            ImGui.SetWindowFontScale(0.7)
            imgui.PushStyleColor(ImGuiCol.Text, r, g, b, a)
            
            if imgui.RadioButton(memberName, isActive) then
                self.radioSelectedOption = i
                self.groupMemberSelected = memberName
            end
            
            imgui.PopStyleColor()
            ImGui.SetWindowFontScale(1.0)
            
            if i < groupSize then
                imgui.SameLine()
            end
        end
    end
end
    
    function self.renderItemListBox()
        imgui.SetNextItemWidth(300)

        -- Calculate available height for the listbox
        local windowHeight = imgui.GetWindowHeight()
        local cursorY = imgui.GetCursorPosY()
        local availableHeight = windowHeight - cursorY - 20  -- Reserve 20 pixels for padding at bottom
        
        -- Build a flat sorted list of all items from all corpses
        local sortedItems = {}
        for corpseId, items in pairs(lootManager.multipleUseTable) do
            for _, tbl in ipairs(items) do
                table.insert(sortedItems, {
                    corpseId = corpseId,
                    itemId = tbl.itemId,
                    itemName = tbl.itemName,
                    itemLink = tbl.itemLink,
                    isLore = tbl.isLore,
                    count = tbl.count or 1
                })
            end
        end
        
        -- Sort alphabetically by itemName (case-insensitive)
        table.sort(sortedItems, function(a, b)
            local nameA = (a.itemName or ""):lower()
            local nameB = (b.itemName or ""):lower()
            return nameA < nameB
        end)
        
        if imgui.BeginListBox("", ImVec2(0,125)) then
            for _, item in ipairs(sortedItems) do
                local isSelected = false
                
                if lootManager.listboxSelectedOption == nil or next(lootManager.listboxSelectedOption) == nil then
                    isSelected = true
                    lootManager.listboxSelectedOption = {
                        corpseId = item.corpseId,
                        itemId = item.itemId,
                        itemName = item.itemName,
                        isLore = item.isLore
                    }
                else
                    isSelected = (lootManager.listboxSelectedOption.itemId == item.itemId) and 
                                (tostring(lootManager.listboxSelectedOption.corpseId) == tostring(item.corpseId))
                end

                -- Format: (count) - ItemName (corpseId) or just ItemName (corpseId) if count is 1
                local itemCount = item.count or 1
                local selectableText
                if itemCount > 1 then
                    selectableText = string.format("(%d) - %s (%d)", itemCount, item.itemName, item.corpseId)
                else
                    selectableText = string.format("%s (%d)", item.itemName, item.corpseId)
                end
                
                -- Add [L] indicator for lore items
                if item.isLore then
                    selectableText = selectableText .. " [L]"
                end
                
                if imgui.Selectable(selectableText, isSelected) then
                    lootManager.listboxSelectedOption = {
                        corpseId = item.corpseId,
                        itemId = item.itemId,
                        itemName = item.itemName,
                        isLore = item.isLore
                    }
                end
                
                if isSelected then
                    imgui.SetItemDefaultFocus()
                end
            end
            imgui.EndListBox()
        end
        
        imgui.SameLine()
        ImGui.SetWindowFontScale(0.7)
        imgui.BeginGroup()
        if imgui.Button("Print Item Links") then
            lootManager.printMultipleUseItems()
            -- Have all characters report their upgrades
            mq.cmdf("/dgga /mlpu")
        end

        if imgui.Button("Print Unlooted\nCorpses") then
            self.executeReportUnlootedCorpses()
        end

        if imgui.Button("Show Upgrades") then
            if lootManager.listboxSelectedOption == nil or lootManager.listboxSelectedOption.itemName == nil then
                print("You must select an item")
            else
                mq.cmdf("/dgga /mlpu \"%s\"", lootManager.listboxSelectedOption.itemName)
            end
        end
        
        imgui.EndGroup()
        ImGui.SetWindowFontScale(1.0)
    end
    
    function self.createGUI()
        local lastStatsUpdate = 0
        local statsUpdateInterval = 3  -- Update every 3 seconds
        
        return function(open)
            local main_viewport = imgui.GetMainViewport()
            imgui.SetNextWindowPos(main_viewport.WorkPos.x + 800, main_viewport.WorkPos.y + 20, ImGuiCond.Once)
            imgui.SetNextWindowSize(425, 225, ImGuiCond.Always)
            
            local show
            open, show = imgui.Begin("Master Looter", open)
            
            if not show then
                imgui.End()
                return open
            end
            
            self.initializeDefaults()
            
            -- Update corpse statistics periodically
            local currentTime = os.time()
            if currentTime - lastStatsUpdate >= statsUpdateInterval then
                self.updateLocalCorpseStats()
                actorManager.requestCorpseStats()
                lastStatsUpdate = currentTime
            end
            
            imgui.PushItemWidth(imgui.GetFontSize() * -12)

            self.renderActionButtons()
            imgui.Separator()
            self.renderGroupMemberSelection()
            imgui.Separator()
            self.renderItemListBox()

            imgui.SameLine()
            imgui.Spacing()
            imgui.PopItemWidth()
            imgui.End()
            
            return open
        end
    end
    
    return self
end

return GUI