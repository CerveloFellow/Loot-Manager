-- modules/GUI.lua
local mq = require('mq')
local imgui = require('ImGui')

local GUI = {}

function GUI.new(lootManager, actorManager)
    local self = {
        radioSelectedOption = 0,
        groupMemberSelected = mq.TLO.Me.Name(),
        lootManager = lootManager,
        actorManager = actorManager
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
                
                ImGui.SetWindowFontScale(0.7)
                if imgui.RadioButton(memberName, isActive) then
                    self.radioSelectedOption = i
                    self.groupMemberSelected = memberName
                end
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
        end

        if imgui.Button("Print Unlooted\nCorpses") then
            self.executeReportUnlootedCorpses()
        end
        imgui.EndGroup()
        ImGui.SetWindowFontScale(1.0)
    end
    
    function self.createGUI()
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