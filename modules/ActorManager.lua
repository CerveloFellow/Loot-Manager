-- modules/ActorManager.lua
local mq = require('mq')
local actors = require('actors')

local ActorManager = {}
ActorManager.actorMailbox = nil
ActorManager.handleShareItem = nil
ActorManager.handleCorpseStats = nil  -- NEW: Handler for corpse statistics

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
                lootManager.multipleUseTable = {}
                lootManager.listboxSelectedOption = {}
                lootManager.upgradeList = {}
                print(mq.TLO.Me.Name()..": Shared loot list cleared by group leader")
            elseif actualMessage.type == 'corpseStats' then
                if ActorManager.handleCorpseStats then
                    ActorManager.handleCorpseStats(actualMessage)
                end
            elseif actualMessage.type == 'requestCorpseStats' then
                -- Calculate and send back our corpse stats
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

function ActorManager.broadcastShareItem(corpseId, itemId, itemName, itemLink)
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
                    itemLink = itemLink
                }
                
                if ActorManager.actorMailbox then
                    ActorManager.actorMailbox:send({to=memberName}, message)
                end
            end
        end
    end
end

-- NEW: Function to broadcast corpse statistics to a specific member
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

-- NEW: Function to request corpse stats from all group members
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