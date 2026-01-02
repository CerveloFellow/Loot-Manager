-- modules/Config.lua
local mq = require('mq')

local Config = {
    defaultAllowCombatLooting = false,
    defaultSlotsToKeepFree = 2,
    lootRadius = 50,
    useWarp = true,
    lootStackableMinValue = 1000,
    lootSingleMinValue = 10000,
    iniFile = mq.configDir .. '/MasterLoot.ini',
    itemsToKeep = {},
    itemsToShare = {},
    itemsToIgnore = {}
}

return Config