-- MasterLoot.lua (Main Entry Point)
local mq = require('mq')
local ImGui = require('ImGui')

-- Import modules (use forward slashes for Lua require)
local Config = require('modules/Config')
local Utils = require('modules/Utils')
local INIManager = require('modules/INIManager')
local Navigation = require('modules/Navigation')
local ItemEvaluator = require('modules/ItemEvaluator')
local CorpseManager = require('modules/CorpseManager')
local ActorManager = require('modules/ActorManager')
local ItemScore = require('modules/ItemScore')
local LootManagerModule = require('modules/LootManager')
local CommandsModule = require('modules/Commands')
local GUIModule = require('modules/GUI')

-- ============================================================================
-- Main Script Initialization
-- ============================================================================
local openGUI = true

print("LootUtil has been started")
print("INI file location: " .. Config.iniFile)

-- Load configuration from INI
INIManager.loadConfig(Config)

-- Initialize LootManager (now with ItemScore)
local LootManager = LootManagerModule.new(
    Config,
    Utils,
    ItemEvaluator,
    CorpseManager,
    Navigation,
    ActorManager,
    ItemScore
)

-- Initialize Actor System
ActorManager.initialize(LootManager)
ActorManager.setHandleShareItem(LootManager.handleSharedItem)

-- Initialize Commands
local Commands = CommandsModule.new(
    Config,
    Utils,
    ItemEvaluator,
    CorpseManager,
    LootManager,
    INIManager
)

-- Initialize GUI (now with Utils for lore checking)
local GUI = GUIModule.new(LootManager, ActorManager, Utils)

-- Register corpse stats handler
ActorManager.setHandleCorpseStats(GUI.handleCorpseStats)

-- Set loot options
mq.cmdf("/lootnodrop never")

-- Register commands
mq.bind("/mlml", Commands.masterLoot)
mq.bind("/mlli", LootManager.lootQueuedItems)
mq.bind("/mlsl", Commands.stopScript)
mq.bind("/ti", Commands.testItem)
mq.bind("/tcl", Commands.testCorpse)
mq.bind("/tis", Commands.testShared)
mq.bind("/mlrc", Commands.reloadConfig)
mq.bind("/mlru", Commands.reportUnlootedCorpses)
mq.bind("/mlpm", LootManager.printMultipleUseItems)
mq.bind("/mlpu", LootManager.printUpgradeList)

-- NEW: Register find loot command
-- Usage: /mlfind "search string" - searches all corpses for items matching substring
mq.bind("/mlfind", Commands.findLoot)

-- Register events
-- Updated pattern: mlqi <memberName> <corpseId> <itemId> "<itemName>" <isLore>
-- Item name is quoted to handle spaces
mq.event('peerLootItem', '#*#mlqi #1# #2# #3# "#4#" #5#', LootManager.queueItem)
mq.event('reportUnlooted', '#*#mlru#*#', Commands.reportUnlootedCorpses)
-- When someone loots an item, remove it from all characters' upgrade lists
mq.event('itemLooted', '#1# is looting #2#', LootManager.removeFromUpgradeList)

-- Register GUI
ImGui.Register('masterLootGui', GUI.createGUI())

-- Print available commands on startup
print("=== MasterLoot Commands ===")
print("/mlml       - Master loot all corpses")
print("/mlfind     - Find and loot items matching search string(s)")
print("              Usage: /mlfind \"astrial\" \"hermit\" \"celestial\"")
print("              Usage: /mlfind sword")
print("/mlli       - Loot queued items")
print("/mlrc       - Reload configuration")
print("/mlru       - Report unlooted corpses")
print("/mlpm       - Print multiple use items")
print("/mlpu       - Print upgrade list")
print("===========================")

-- Main loop
while openGUI do
    mq.doevents()
    mq.delay(1)
end

print("MasterLoot script ended")