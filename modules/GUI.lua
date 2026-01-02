-- modules/GUI.lua
local mq = require('mq')
local imgui = require('ImGui')

local GUI = {}

function GUI.new(lootManager, actorManager)
    local self = {
        radioSelectedOption = 0,
        groupMemberSelected = mq.TLO.Me.Name(),
        lootManager = lootManager,
        actorManager = actorManager,
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
        
        local totalCorpses = mq.TLO.SpawnCount("npccorpse radius 200 zradius 10")() or 0
        local unlootedCount = 0
        
        if totalCorpses > 0 then
            for i = 1, totalCorpses do
                local spawn = mq.TLO.NearestSpawn(i, "npccorpse radius 200 zradius 10")
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
        
        mq.cmdf("/g mlqi %s %d %d", 
            self.groupMemberSelected, 
            lootManager.listboxSelectedOption.corpseId, 
            lootManager.listboxSelectedOption.itemId)

        for idx, items in pairs(lootManager.multipleUseTable) do
            if tostring(idx) == tostring(lootManager.listboxSelectedOption.corpseId) then
                for idx2, tbl in pairs(items) do
                    if tostring(tbl.itemId) == tostring(lootManager.listboxSelectedOption.itemId) then
                        table.remove(items, idx2)
                    end
                end
            end
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
        if imgui.Button("Reload INI") then
            mq.cmdf("/mlrc")
        end

        imgui.SameLine()
        if imgui.Button("Everyone Loot") then
            self.everyoneLoot()
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

        if groupSize >= 0 then
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

        local itemHeight = imgui.GetTextLineHeightWithSpacing()
        local height = -itemHeight*2

        if imgui.BeginListBox("", 0, height) then
            for idx, items in pairs(lootManager.multipleUseTable) do
                for idx2, tbl in ipairs(items) do
                    local isSelected = false
                    
                    if lootManager.listboxSelectedOption == nil then
                        isSelected = true
                        lootManager.listboxSelectedOption = tbl
                    else
                        isSelected = (lootManager.listboxSelectedOption.itemId == tbl.itemId) and 
                                    (lootManager.listboxSelectedOption.corpseId == idx) 
                    end

                    local selectableText = string.format("%s (%d)", tbl.itemName, idx)
                    if imgui.Selectable(selectableText, isSelected) then
                        lootManager.listboxSelectedOption = tbl
                    end
                    
                    if isSelected then
                        imgui.SetItemDefaultFocus()
                    end
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
        imgui.EndGroup()
        ImGui.SetWindowFontScale(1.0)
    end
    
    function self.createGUI()
        local lastStatsUpdate = 0
        local statsUpdateInterval = 3  -- Update every 3 seconds
        
        return function(open)
            local main_viewport = imgui.GetMainViewport()
            imgui.SetNextWindowPos(main_viewport.WorkPos.x + 800, main_viewport.WorkPos.y + 20, ImGuiCond.Once)
            imgui.SetNextWindowSize(475, 245, ImGuiCond.Always)
            
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