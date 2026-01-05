-- modules/Navigation.lua
local mq = require('mq')

local Navigation = {}

function Navigation.navigateToLocation(config, x, y, z)
    -- Validate coordinates before attempting navigation
    if not x or not y or not z then
        print("ERROR: Invalid coordinates - x:" .. tostring(x) .. " y:" .. tostring(y) .. " z:" .. tostring(z))
        return false
    end
    
    if config.useWarp then
        mq.cmdf("/warp loc %f %f %f", y, x, z)
    else
        mq.cmdf("/squelch /nav locxyz %d %d %d", x, y, z)
    end
    
    return true
end

function Navigation.navigateToCorpse(config, corpseId)
    if not corpseId then
        print("ERROR: Invalid corpseId: "..tostring(corpseId))
        return false
    else
        if config.useWarp then
            mq.cmdf("/target id %d", corpseId)
            mq.delay(100)
            mq.cmdf("/warp t")
        else
            mq.cmdf("/target id %d", corpseId)
            mq.delay(100)
            mq.cmdf("/navigate Target")
        end
    end

    return true
end

return Navigation