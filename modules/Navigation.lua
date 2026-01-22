-- modules/Navigation.lua (OPTIMIZED v2)
-- Changes in v2:
--   - Reduced targetVerifyMax from 500 to 400
--   - Reduced warpDelay from 150 to 100
local mq = require('mq')

local delay = {
    warpDelay = 100,           -- v2: Reduced from 150
    navDelay = 2000,
    targetDelay = 50,
    targetVerifyMax = 400      -- v2: Reduced from 500
}
local Navigation = {}

-- Check if we have the correct target (not just distance)
local function hasTarget(corpseId)
    if not corpseId then
        return false
    end
    local targetId = mq.TLO.Target.ID()
    return targetId and targetId == corpseId
end

local function atCorpse(corpseId)
    if not corpseId then
        return false
    end
    
    -- First verify we have the correct target
    if not hasTarget(corpseId) then
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

-- Quick check if spawn exists (for early bailout)
local function spawnExists(corpseId)
    if not corpseId then return false end
    local spawn = mq.TLO.Spawn(corpseId)
    return spawn and spawn.ID() and spawn.ID() > 0
end

function Navigation.navigateToLocation(config, x, y, z)
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
    end
    
    -- Early check if corpse still exists
    if not spawnExists(corpseId) then
        return false, "despawned"
    end
    
    if config.useWarp then
        -- Target the corpse
        mq.cmdf("/target id %d", corpseId)
        
        -- Wait specifically for target to be acquired (not distance)
        mq.delay(delay.targetVerifyMax, function() return hasTarget(corpseId) end)
        
        -- CRITICAL: Verify target before warping
        if not hasTarget(corpseId) then
            -- Target failed - corpse may have despawned or be out of range
            -- Check if it still exists
            if not spawnExists(corpseId) then
                return false, "despawned"
            end
            -- Corpse exists but couldn't target - try again
            mq.cmdf("/target id %d", corpseId)
            mq.delay(delay.targetVerifyMax, function() return hasTarget(corpseId) end)
            
            if not hasTarget(corpseId) then
                return false, "target_failed"
            end
        end
        
        -- Now safe to warp
        mq.cmdf("/warp t")
        mq.delay(delay.warpDelay, function() return atCorpse(corpseId) end)
    else
        mq.cmdf("/target id %d", corpseId)
        mq.delay(delay.targetVerifyMax, function() return hasTarget(corpseId) end)
        
        if not hasTarget(corpseId) then
            if not spawnExists(corpseId) then
                return false, "despawned"
            end
            return false, "target_failed"
        end
        
        mq.cmdf("/navigate Target")
        mq.delay(delay.navDelay, function() return atCorpse(corpseId) end)
    end

    return true
end

return Navigation