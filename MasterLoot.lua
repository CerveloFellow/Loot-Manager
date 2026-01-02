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
local ItemScore = require('modules/ItemScore')  -- NEW
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
    ItemScore  -- NEW: Pass ItemScore module
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

-- Initialize GUI
local GUI = GUIModule.new(LootManager, ActorManager)

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
mq.bind("/mlpu", LootManager.printUpgradeList)  -- NEW: Print upgrades command

-- Register events
mq.event('peerLootItem', "#*#mlqi #1# #2# #3#'", LootManager.queueItem)
mq.event('reportUnlooted', '#*#mlru#*#', Commands.reportUnlootedCorpses)

-- Register GUI
ImGui.Register('masterLootGui', GUI.createGUI())

-- Main loop
while openGUI do
    mq.doevents()
    mq.delay(1)
end

print("MasterLoot script ended")