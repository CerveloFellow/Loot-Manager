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
    local itemCount = mq.TLO.FindItemCount('=' .. itemName)()
    return itemCount > 0
end

function Utils.multimapInsert(map, key, value)
    if map[key] == nil then
        map[key] = {}
    end
    
    for _, v in pairs(map[key]) do
        if v.itemId == value.itemId then
            return false
        end
    end
    
    table.insert(map[key], value)
    return true
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