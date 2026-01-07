-- modules/ActorManager.lua
local mq = require('mq')
local actors = require('actors')

local ActorManager = {}
ActorManager.actorMailbox = nil
ActorManager.handleShareItem = nil
ActorManager.handleCorpseStats = nil  -- Handler for corpse statistics
ActorManager.lootManagerInstance = nil  -- NEW: Store reference to LootManager instance

function ActorManager.broadcastClearSharedList()
    local groupSize = (mq.TLO.Group.GroupSize() or 0) - 1
    
    if groupSize >= 0 then
        for i = 0, groupSize do
            local memberName = mq.TLO.Group.Member(i).Name()
            
            if memberName and memberName ~= mq.TLO.Me.Name() then
                local message = {
                    type = 'clearSharedList'
                }
                
                if ActorManager.actorMailbox then
                    ActorManager.actorMailbox:send({to=memberName}, message)
                end
            end
        end
    end
end

function ActorManager.initialize(lootManager)
    -- Store reference to lootManager for use in message handling
    ActorManager.lootManagerInstance = lootManager
    
    ActorManager.actorMailbox = actors.register('masterloot', function(message)
        local actualMessage = message
        if type(message) == "userdata" then
            local success, result = pcall(function() return message() end)
            if success and type(result) == "table" then
                actualMessage = result
            else
                return
            end
        end
        
        if type(actualMessage) == "table" then
            if actualMessage.type == 'shareItem' then
                if ActorManager.handleShareItem then
                    ActorManager.handleShareItem(actualMessage)
                end
            elseif actualMessage.type == 'clearSharedList' then
                -- Use the stored lootManager reference
                if ActorManager.lootManagerInstance then
                    ActorManager.lootManagerInstance.multipleUseTable = {}
                    ActorManager.lootManagerInstance.listboxSelectedOption = {}
                    ActorManager.lootManagerInstance.upgradeList = {}
                    print(mq.TLO.Me.Name()..": Shared loot list cleared by group leader")
                end
            elseif actualMessage.type == 'corpseStats' then
                if ActorManager.handleCorpseStats then
                    ActorManager.handleCorpseStats(actualMessage)
                end
            elseif actualMessage.type == 'requestCorpseStats' then
                -- Calculate and send back our corpse stats
                local totalCorpses = mq.TLO.SpawnCount("npccorpse radius 200 zradius 20")() or 0
                local unlootedCount = 0
                
                if totalCorpses > 0 and ActorManager.lootManagerInstance then
                    for i = 1, totalCorpses do
                        local spawn = mq.TLO.NearestSpawn(i, "npccorpse radius 200 zradius 20")
                        if spawn and spawn.ID() and spawn.ID() > 0 then
                            local corpseId = spawn.ID()
                            local isLooted = false
                            
                            for _, lootedId in ipairs(ActorManager.lootManagerInstance.lootedCorpses) do
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
                
                -- Send stats back to requester
                if actualMessage.requesterName then
                    ActorManager.sendCorpseStats(actualMessage.requesterName, totalCorpses, unlootedCount)
                end
            end
        end
    end)
    
    if ActorManager.actorMailbox then
        print("Actor mailbox registered: masterloot")
    end
end

function ActorManager.setHandleShareItem(handlerFunc)
    ActorManager.handleShareItem = handlerFunc
end

function ActorManager.setHandleCorpseStats(handlerFunc)
    ActorManager.handleCorpseStats = handlerFunc
end

function ActorManager.broadcastShareItem(corpseId, itemId, itemName, itemLink, isLore, count)
    local groupSize = (mq.TLO.Group.GroupSize() or 0) - 1
    
    if groupSize >= 0 then
        for i = 0, groupSize do
            local memberName = mq.TLO.Group.Member(i).Name()
            
            if memberName and memberName ~= mq.TLO.Me.Name() then
                local message = {
                    type = 'shareItem',
                    corpseId = corpseId,
                    itemId = itemId,
                    itemName = itemName,
                    itemLink = itemLink,
                    isLore = isLore or false,
                    count = count or 1
                }
                
                if ActorManager.actorMailbox then
                    ActorManager.actorMailbox:send({to=memberName}, message)
                end
            end
        end
    end
end

-- Function to broadcast corpse statistics to a specific member
function ActorManager.sendCorpseStats(targetMember, totalCorpses, unlootedCorpses)
    local myName = mq.TLO.Me.Name()
    if not myName or not targetMember then return end
    
    local message = {
        type = 'corpseStats',
        senderName = myName,
        totalCorpses = totalCorpses,
        unlootedCorpses = unlootedCorpses
    }
    
    if ActorManager.actorMailbox then
        ActorManager.actorMailbox:send({to=targetMember}, message)
    end
end

-- Function to request corpse stats from all group members
function ActorManager.requestCorpseStats(corpseManager, lootedCorpses)
    local groupSize = (mq.TLO.Group.GroupSize() or 0) - 1
    local myName = mq.TLO.Me.Name()
    
    if groupSize >= 0 then
        for i = 0, groupSize do
            local memberName = mq.TLO.Group.Member(i).Name()
            
            if memberName and memberName ~= myName then
                local message = {
                    type = 'requestCorpseStats',
                    requesterName = myName
                }
                
                if ActorManager.actorMailbox then
                    ActorManager.actorMailbox:send({to=memberName}, message)
                end
            end
        end
    end
end

return ActorManager