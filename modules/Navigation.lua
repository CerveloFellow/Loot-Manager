-- modules/Navigation.lua
local mq = require('mq')

local delay = {
        warpDelay = 250,
        navDelay = 2000,
        targetDelay = 100
}
local Navigation = {}

local function atCorpse(corpseId)
    -- Handle nil corpseId gracefully
    if not corpseId then
        print("WARNING: atCorpse called with nil corpseId")
        return false
    end
    
    local corpse = mq.TLO.Spawn(corpseId)
    if corpse and corpse.ID() then
        local distance = corpse.Distance()
        if distance then
            return distance < 5
        end
    end
    return false
end

function Navigation.navigateToLocation(config, x, y, z)
    -- Validate coordinates before attempting navigation
    if not x or not y or not z then
        print("ERROR: Invalid coordinates - x:" .. tostring(x) .. " y:" .. tostring(y) .. " z:" .. tostring(z))
        return false
    end
    
    if config.useWarp then
        mq.cmdf("/warp loc %f %f %f", y, x, z)
        mq.delay(delay.warpDelay)
    else
        mq.cmdf("/squelch /nav locxyz %d %d %d", x, y, z)
        mq.delay(delay.navDelay)
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
            mq.delay(delay.targetDelay, function() return atCorpse(corpseId) end)
            mq.cmdf("/warp t")
            mq.delay(delay.warpDelay, function() return atCorpse(corpseId) end)
        else
            mq.cmdf("/target id %d", corpseId)
            mq.delay(delay.targetDelay, function() return atCorpse(corpseId) end)
            mq.cmdf("/navigate Target")
            mq.delay(delay.navDelay, function() return atCorpse(corpseId) end)
        end
    end

    return true
end

return Navigation