-- modules/Utils.lua
local mq = require('mq')

local Utils = {}

function Utils.contains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

function Utils.ownItem(itemName)
    local invCount = mq.TLO.FindItemCount('=' .. itemName)() or 0
    local bankCount = mq.TLO.FindItemBankCount('=' .. itemName)() or 0
    return (invCount + bankCount) > 0
end

-- Insert into multimap with count
-- If item already exists, updates to the new count (last count wins)
-- Returns: "inserted" if new entry, "updated" if count was changed, "unchanged" if same count
function Utils.multimapInsert(map, key, value)
    if map[key] == nil then
        map[key] = {}
    end
    
    -- Check if item already exists (same itemId)
    for _, v in pairs(map[key]) do
        if v.itemId == value.itemId then
            -- Item exists - update to new count (last count wins)
            local oldCount = v.count or 1
            local newCount = value.count or 1
            if oldCount ~= newCount then
                v.count = newCount
                return "updated"
            end
            return "unchanged"
        end
    end
    
    -- New item, ensure count is set
    value.count = value.count or 1
    table.insert(map[key], value)
    return "inserted"
end

function Utils.printTable(tbl, indent)
    indent = indent or 0
    local toprint = string.rep(" ", indent) .. "{\n"
    indent = indent + 2

    for k, v in pairs(tbl) do
        toprint = toprint .. string.rep(" ", indent)
        
        if type(k) == "number" then
            toprint = toprint .. "[" .. k .. "] = "
        elseif type(k) == "string" then
            toprint = toprint .. k .. " = "
        end

        if type(v) == "table" then
            toprint = toprint .. Utils.printTable(v, indent + 2) .. ",\n"
        elseif type(v) == "string" then
            toprint = toprint .. "\"" .. v .. "\",\n"
        else
            toprint = toprint .. tostring(v) .. ",\n"
        end
    end

    toprint = toprint .. string.rep(" ", indent - 2) .. "}"
    return toprint
end

return Utils