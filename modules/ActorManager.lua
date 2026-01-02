-- modules/ActorManager.lua
local mq = require('mq')
local actors = require('actors')

local ActorManager = {}
ActorManager.actorMailbox = nil
ActorManager.handleShareItem = nil

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
                print(mq.TLO.Me.Name()..": Shared loot list cleared by group leader")
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

return ActorManager