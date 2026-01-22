-- modules/ItemEvaluator.lua
local mq = require('mq')

local ItemEvaluator = {}

function ItemEvaluator.groupMembersCanUse(corpseItem)
    local count = 0
    
    if corpseItem.NoDrop() or corpseItem.NoTrade() then
        for i = 1, corpseItem.Classes() do
            for j = 0, mq.TLO.Group.Members() do
                if corpseItem.Class(i).Name() == mq.TLO.Group.Member(j).Class() then
                    count = count + 1
                end
            end
        end
    end

    return count
end

function ItemEvaluator.skipItem(config, utils, corpseItem)
    if config.itemsToIgnore and utils.contains(config.itemsToIgnore, corpseItem.Name()) then
        print("Item to ignore - Skip: " .. corpseItem.Name())
        return true
    end
    return false
end

function ItemEvaluator.shouldLoot(config, utils, corpseItem, debug)
    debug = debug or false
    
    if debug then print("=== Evaluating item: " .. corpseItem.Name() .. " ===") end
    
    -- Check if it's a shared item
    if config.itemsToShare and utils.contains(config.itemsToShare, corpseItem.Name()) then
        if debug then print("Item to share - Skip: " .. corpseItem.Name()) end
        return false
    else
        if debug then print("Item not in share list - Continue") end
    end

    -- Check if player can use the item
    if config.itemsToIgnore and utils.contains(config.itemsToIgnore, corpseItem.Name()) then
        if debug then print("Item to ignore - Skip: " .. corpseItem.Name()) end
        return false
    else
        if debug then print("Item not in ignore list - Continue") end
    end

    -- Check items to keep list (early check for explicit keeps)
    if utils.contains(config.itemsToKeep, corpseItem.Name()) then
        if debug then print("Item in keep list - Looting: " .. corpseItem.Name()) end
        return true
    else
        if debug then print("Item not in keep list - Continue") end
    end

    if corpseItem.CanUse() then
        if debug then print("Player can use this item - Continue") end
        
        -- Skip lore items we already own
        if corpseItem.Lore() and utils.ownItem(corpseItem.Name()) then
            if debug then print("Lore Item and I own it - Skip: " .. corpseItem.Name()) end
            return false
        else
            if debug then 
                if corpseItem.Lore() then
                    print("Lore item but don't own it - Continue")
                else
                    print("Not a lore item - Continue")
                end
            end
        end
        
        -- Skip No Drop/No Trade items multiple group members can use
        if (corpseItem.NoDrop() or corpseItem.NoTrade()) and 
           (ItemEvaluator.groupMembersCanUse(corpseItem) > 1) then
            if debug then print("Item is No Drop/No Trade and multiple group members can use, skipping: " .. corpseItem.Name()) end
            mq.cmdf('/g ***' .. corpseItem.ItemLink('CLICKABLE')() .. '*** can be used by multiple classes')
            return false
        else
            if debug then 
                if corpseItem.NoDrop() or corpseItem.NoTrade() then
                    print("Item is No Drop/No Trade but only usable by this player - Continue")
                else
                    print("Item is tradeable - Continue")
                end
            end
        end
        
        -- Loot wearable items
        if corpseItem.WornSlots() > 0 then
            if debug then print("Item has " .. corpseItem.WornSlots() .. " worn slot(s) - Checking slots") end
            for i = 1, corpseItem.WornSlots() do
                if corpseItem.WornSlot(i).ID() < 23 then
                    if debug then print("Item is wearable slot item (Slot ID: " .. corpseItem.WornSlot(i).ID() .. ") - Looting: " .. corpseItem.Name()) end
                    return true
                else
                    if debug then print("Worn slot " .. i .. " ID (" .. corpseItem.WornSlot(i).ID() .. ") >= 23 - Continue") end
                end
            end
            if debug then print("No valid worn slots found - Continue") end
        else
            if debug then print("Item has no worn slots - Continue") end
        end
    else
        if debug then print("Player cannot use this item - Continue") end
    end
    
    -- Loot valuable items
    if (corpseItem.Value() or 0) > config.lootSingleMinValue then
        if debug then print("Value greater than single item min value - Looting: " .. corpseItem.Name() .. " (Value: " .. (corpseItem.Value() or 0) .. ", Min: " .. config.lootSingleMinValue .. ")") end
        return true
    else
        if debug then print("Value (" .. (corpseItem.Value() or 0) .. ") not greater than min value (" .. config.lootSingleMinValue .. ") - Continue") end
    end
    
    -- Loot valuable stackables
    if corpseItem.Stackable() then
        if debug then print("Item is stackable - Checking value") end
        if (corpseItem.Value() or 0) >= config.lootStackableMinValue then
            if debug then print("Value greater than or equal to stacked item min value - Looting: " .. corpseItem.Name() .. " (Value: " .. (corpseItem.Value() or 0) .. ", Min: " .. config.lootStackableMinValue .. ")") end
            return true
        else
            if debug then print("Stackable value (" .. (corpseItem.Value() or 0) .. ") less than min value (" .. config.lootStackableMinValue .. ") - Continue") end
        end
    else
        if debug then print("Item is not stackable - Continue") end
    end
    
    
    if debug then print("No matching criteria - Skip: " .. corpseItem.Name()) end
    if debug then print("=== End evaluation ===") end
    return false
end

return ItemEvaluator
