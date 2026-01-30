-- modules/INIManager.lua
local mq = require('mq')

local INIManager = {}

function INIManager.loadItemList(config, section)
    local items = {}
    local index = 1
    
    while true do
        local item = mq.TLO.Ini.File(config.iniFile).Section(section).Key('Item' .. index).Value()
        if item == nil or item == 'NULL' or item == '' then
            break
        end
        table.insert(items, item)
        index = index + 1
    end
    
    return items
end

function INIManager.saveItemList(config, section, items)
    -- Clear existing items
    local index = 1
    while true do
        local existing = mq.TLO.Ini.File(config.iniFile).Section(section).Key('Item' .. index).Value()
        if existing == nil or existing == 'NULL' or existing == '' then
            break
        end
        mq.cmdf('/ini "%s" "%s" "Item%d"', config.iniFile, section, index)
        index = index + 1
    end
    
    -- Write new items
    for i, item in ipairs(items) do
        mq.cmdf('/ini "%s" "%s" "Item%d" "%s"', config.iniFile, section, i, item)
    end
    
    print(string.format("Saved %d items to [%s]", #items, section))
end

function INIManager.loadSettings(config)
    -- Load UseWarp setting
    local useWarpValue = mq.TLO.Ini.File(config.iniFile).Section('Settings').Key('UseWarp').Value()
    
    if useWarpValue ~= nil and useWarpValue ~= 'NULL' and useWarpValue ~= '' then
        config.useWarp = (useWarpValue == 'true' or useWarpValue == '1')
        print(string.format("Loaded UseWarp setting: %s", tostring(config.useWarp)))
    else
        INIManager.saveSettings(config)
    end
    
    -- Load lootStackableMinValue
    local stackableValue = mq.TLO.Ini.File(config.iniFile).Section('Settings').Key('LootStackableMinValue').Value()
    
    if stackableValue ~= nil and stackableValue ~= 'NULL' and stackableValue ~= '' then
        config.lootStackableMinValue = tonumber(stackableValue)
        print(string.format("Loaded LootStackableMinValue: %d", config.lootStackableMinValue))
    else
        INIManager.saveSettings(config)
    end
    
    -- Load lootSingleMinValue
    local singleValue = mq.TLO.Ini.File(config.iniFile).Section('Settings').Key('LootSingleMinValue').Value()
    
    if singleValue ~= nil and singleValue ~= 'NULL' and singleValue ~= '' then
        config.lootSingleMinValue = tonumber(singleValue)
        print(string.format("Loaded LootSingleMinValue: %d", config.lootSingleMinValue))
    else
        INIManager.saveSettings(config)
    end
    
    -- Load LootRadius
    local radiusValue = mq.TLO.Ini.File(config.iniFile).Section('Settings').Key('LootRadius').Value()
    
    if radiusValue ~= nil and radiusValue ~= 'NULL' and radiusValue ~= '' then
        config.lootRadius = tonumber(radiusValue)
        print(string.format("Loaded LootRadius: %d", config.lootRadius))
    else
        INIManager.saveSettings(config)
    end
    
    -- Load LootZRadius
    local zRadiusValue = mq.TLO.Ini.File(config.iniFile).Section('Settings').Key('LootZRadius').Value()
    
    if zRadiusValue ~= nil and zRadiusValue ~= 'NULL' and zRadiusValue ~= '' then
        config.lootZRadius = tonumber(zRadiusValue)
        print(string.format("Loaded LootZRadius: %d", config.lootZRadius))
    else
        INIManager.saveSettings(config)
    end
end

function INIManager.saveSettings(config)
    mq.cmdf('/ini "%s" "Settings" "UseWarp" "%s"', config.iniFile, tostring(config.useWarp))
    mq.cmdf('/ini "%s" "Settings" "LootStackableMinValue" "%d"', config.iniFile, config.lootStackableMinValue)
    mq.cmdf('/ini "%s" "Settings" "LootSingleMinValue" "%d"', config.iniFile, config.lootSingleMinValue)
    mq.cmdf('/ini "%s" "Settings" "LootRadius" "%d"', config.iniFile, config.lootRadius)
    mq.cmdf('/ini "%s" "Settings" "LootZRadius" "%d"', config.iniFile, config.lootZRadius)
    
    print(string.format("Saved UseWarp setting: %s", tostring(config.useWarp)))
    print(string.format("Saved LootStackableMinValue: %d", config.lootStackableMinValue))
    print(string.format("Saved LootSingleMinValue: %d", config.lootSingleMinValue))
    print(string.format("Saved LootRadius: %d", config.lootRadius))
    print(string.format("Saved LootZRadius: %d", config.lootZRadius))
end

function INIManager.initializeINI(config)
    local fileExists = mq.TLO.Ini.File(config.iniFile).Section('ItemsToKeep').Key('Item1').Value()
    
    if fileExists == nil or fileExists == 'NULL' or fileExists == '' then
        print("INI file not found or empty, creating with default values...")
        
        local defaultKeep = {
            'Green Stone of Minor Advancement',
            'Frosty Stone of Hearty Advancement',
            'Fiery Stone of Incredible Advancement',
            'Moneybags - Bag of Platinum Pieces',
            'Moneybags - Heavy Bag of Platinum!',
            "Unidentified Item",
            "Epic Gemstone of Immortality"
        }
        INIManager.saveItemList(config, 'ItemsToKeep', defaultKeep)
        
        local defaultShare = {
            "Ancient Elvish Essence", "Ancient Life's Stone", "Astrial Mist", 
            "Book of Astrial-1", "Book of Astrial-2", "Book of Astrial-6", 
            "Bottom Piece of Astrial", "Bottom Shard of Astrial", 
            "celestial ingot", "celestial temper", "Center Shard of Astrial", 
            "Center Splinter of Astrial", "Death's Soul", "Elemental Infused Elixir", 
            "Epic Gemstone of Immortality", "Fallen Star", "Hermits Lost Chisel", 
            "hermits lost Forging Hammer", "Left Shard of Astrial", 
            "Overlords Anguish Stone", "Right Shard of Astrial", 
            "Testimony of the Lords", "The Horadric Lexicon", "The Lost Foci", 
            "Token of Discord", "Tome of Power: Anguish", "Tome of Power: Hole", 
            "Tome of Power: Kael", "Tome of Power: MPG", "Tome of Power: Najena", 
            "Tome of Power: Riftseekers", "Tome of Power: Sleepers", 
            "Tome of Power: Veeshan", "Top Splinter of Astrial", "Warders Guise"
        }
        INIManager.saveItemList(config, 'ItemsToShare', defaultShare)
        
        local defaultIgnore = { "Rusty Shortsword" }
        INIManager.saveItemList(config, 'ItemsToIgnore', defaultIgnore)
    end
end

function INIManager.loadConfig(config)
    INIManager.initializeINI(config)
    
    config.itemsToKeep = INIManager.loadItemList(config, 'ItemsToKeep')
    config.itemsToShare = INIManager.loadItemList(config, 'ItemsToShare')
    config.itemsToIgnore = INIManager.loadItemList(config, 'ItemsToIgnore')
    INIManager.loadSettings(config)
    
    print(string.format("Loaded %d items to keep", #config.itemsToKeep))
    print(string.format("Loaded %d items to share", #config.itemsToShare))
    print(string.format("Loaded %d items to ignore", #config.itemsToIgnore))
end

function INIManager.reloadConfig(config)
    print("Reloading configuration from INI file...")
    INIManager.loadConfig(config)
    mq.cmdf('/g Configuration reloaded from INI file')
end

return INIManager