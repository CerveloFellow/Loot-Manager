-- modules/ItemScore.lua
local mq = require('mq')

local ItemScore = {}

-- Class-specific stat weights
local CLASS_WEIGHTS = {
    Warrior = {
        AC = 10, HP = 8, Attack = 8, Haste = 6, HeroicSTR = 9, HeroicSTA = 8,
        STR = 4, STA = 4, Avoidance = 6, Shielding = 5, StunResist = 4,
        DamageShieldMitigation = 3, AGI = 3, HeroicAGI = 10, DEX = 2, HeroicDEX = 7,
        Endurance = 3, EnduranceRegen = 3, HPRegen = 4, DamageRatio = 100, DMGBonus = 8
    },
    Cleric = {
        Mana = 10, ManaRegen = 9, WIS = 8, HeroicWIS = 8, AC = 5, HP = 5,
        HealAmount = 7, SpellDamage = 3, Haste = 2, HeroicSTA = 6, HeroicWIS = 5, STA = 3,
        Shielding = 4, svMagic = 3, HeroicSvMagic = 3, Clairvoyance = 6, DamageRatio = 50
    },
    Paladin = {
        AC = 8, HP = 7, Mana = 6, ManaRegen = 5, STR = 5, HeroicSTR = 7,
        STA = 5, HeroicSTA = 7, WIS = 4, HeroicWIS = 6, Attack = 8, Haste = 5,
        Shielding = 5, HealAmount = 4, Avoidance = 4, Endurance = 4, EnduranceRegen = 4, 
        DamageRatio = 90, DMGBonus = 8, HeroicDEX = 6, HeroicAGI = 8
    },
    Ranger = {
        STR = 6, HeroicSTR = 6, DEX = 5, HeroicDEX = 7, Attack = 7, Haste = 6,
        Accuracy = 5, HP = 6, AC = 5, STA = 5, HeroicSTA = 5, AGI = 4, HeroicAGI = 8,
        WIS = 3, HeroicWIS = 3, Mana = 4, ManaRegen = 3, Avoidance = 4,
        Endurance = 5, EnduranceRegen = 5, DamageRatio = 120, DMGBonus = 8
    },
    Shadowknight = {
        AC = 8, HP = 7, STR = 6, HeroicSTR = 7, STA = 5, HeroicSTA = 5,
        Attack = 6, Haste = 5, INT = 4, HeroicINT = 4, Mana = 5, ManaRegen = 4,
        Shielding = 5, SpellDamage = 3, Avoidance = 4, Endurance = 4, EnduranceRegen = 4, 
        DamageRatio = 90, DMGBonus = 8, HeroicDEX = 6, HeroicAGI = 8
    },
    Druid = {
        Mana = 10, ManaRegen = 9, WIS = 8, HeroicWIS = 8, HP = 4, AC = 3,
        HealAmount = 6, SpellDamage = 5, Haste = 2, STA = 3, HeroicSTA = 5,
        svMagic = 3, HeroicSvMagic = 3, Clairvoyance = 6, DamageRatio = 40,
        HeroicDEX = 6, HeroicAGI = 8
    },
    Monk = {
        STR = 6, HeroicSTR = 7, DEX = 5, HeroicDEX = 7, Attack = 8, Haste = 7,
        HP = 6, AC = 4, STA = 5, HeroicSTA = 6, AGI = 7, HeroicAGI = 9,
        Avoidance = 6, Accuracy = 5, StrikeThrough = 5, Endurance = 6, EnduranceRegen = 6, 
        DamageRatio = 120, DMGBonus = 8
    },
    Bard = {
        Mana = 7, ManaRegen = 6, CHA = 5, HeroicCHA = 4, HP = 5, AC = 4,
        STR = 4, DEX = 4, AGI = 4, Haste = 5, Attack = 5, STA = 4,
        Avoidance = 4, Endurance = 5, EnduranceRegen = 5, svMagic = 3, 
        DamageRatio = 80, DMGBonus = 5, HeroicDEX = 7, HeroicAGI = 8, HeroicSTR = 7
    },
    Rogue = {
        STR = 6, HeroicSTR = 8, DEX = 8, HeroicDEX = 8, AGI = 7, HeroicAGI = 7,
        Attack = 8, Haste = 7, Accuracy = 6, HP = 6, AC = 4, STA = 5, HeroicSTA = 5,
        Avoidance = 5, StrikeThrough = 6, Endurance = 6, EnduranceRegen = 6, 
        DamageRatio = 120, DMGBonus = 8
    },
    Shaman = {
        Mana = 10, ManaRegen = 9, WIS = 8, HeroicWIS = 8, HP = 5, AC = 4,
        HealAmount = 6, SpellDamage = 5, STA = 4, HeroicSTA = 4, Haste = 3,
        Shielding = 3, svMagic = 3, HeroicSvMagic = 3, Clairvoyance = 6, DamageRatio = 50,
        HeroicWIS = 5
    },
    Necromancer = {
        Mana = 10, ManaRegen = 9, INT = 8, HeroicINT = 8, HP = 4, AC = 2,
        SpellDamage = 7, STA = 3, HeroicSTA = 5, Haste = 2, svMagic = 3,
        HeroicSvMagic = 3, Clairvoyance = 6, DoTShielding = 4, DamageRatio = 20
    },
    Wizard = {
        Mana = 10, ManaRegen = 9, INT = 8, HeroicINT = 8, HP = 3, AC = 2,
        SpellDamage = 8, STA = 3, HeroicSTA = 5, Haste = 2, svMagic = 3,
        HeroicSvMagic = 3, Clairvoyance = 7, DamageRatio = 20
    },
    Magician = {
        Mana = 10, ManaRegen = 9, INT = 8, HeroicINT = 8, HP = 3, AC = 2,
        SpellDamage = 7, STA = 3, HeroicSTA = 5, Haste = 2, svMagic = 3,
        HeroicSvMagic = 3, Clairvoyance = 6, DamageRatio = 20
    },
    Enchanter = {
        Mana = 10, ManaRegen = 9, INT = 8, HeroicINT = 8, CHA = 6, HeroicCHA = 6,
        HP = 3, AC = 2, SpellDamage = 5, STA = 3, HeroicSTA = 5, Haste = 2,
        svMagic = 3, HeroicSvMagic = 3, Clairvoyance = 7, DamageRatio = 20
    },
    Beastlord = {
        STR = 5, HeroicSTR = 5, DEX = 4, HeroicDEX = 4, Attack = 6, Haste = 5,
        HP = 6, AC = 5, STA = 5, HeroicSTA = 5, WIS = 6, HeroicWIS = 6,
        Mana = 7, ManaRegen = 6, AGI = 5, HeroicAGI = 6, Avoidance = 4,
        HealAmount = 4, Endurance = 5, EnduranceRegen = 5, DamageRatio = 70, DMGBonus = 6
    },
    Berserker = {
        STR = 7, HeroicSTR = 8, DEX = 6, HeroicDEX = 7, Attack = 8, Haste = 7,
        HP = 7, AC = 6, STA = 6, HeroicSTA = 6, AGI = 5, HeroicAGI = 9,
        Avoidance = 4, Accuracy = 6, StrikeThrough = 6, Endurance = 7, EnduranceRegen = 7, 
        DamageRatio = 120, DMGBonus = 8
    },
    Default = {
        HP = 5, AC = 5, Mana = 3, STR = 3, STA = 3, AGI = 3, DEX = 3,
        WIS = 3, INT = 3, CHA = 3, HeroicSTR = 3, HeroicSTA = 3, HeroicAGI = 3,
        HeroicDEX = 3, HeroicWIS = 3, HeroicINT = 3, HeroicCHA = 3,
        Attack = 4, Haste = 4, DamageRatio = 80
    }
}

-- Slot ID to friendly name mapping
local SLOT_NAMES = {
    [0] = 'Charm', [1] = 'Left Ear', [2] = 'Head', [3] = 'Face',
    [4] = 'Right Ear', [5] = 'Neck', [6] = 'Shoulder', [7] = 'Arms',
    [8] = 'Back', [9] = 'Left Wrist', [10] = 'Right Wrist', [11] = 'Ranged',
    [12] = 'Hands', [13] = 'Main Hand', [14] = 'Off Hand', [15] = 'Left Finger',
    [16] = 'Right Finger', [17] = 'Chest', [18] = 'Legs', [19] = 'Feet',
    [20] = 'Waist', [21] = 'Power Source', [22] = 'Ammo'
}

-- Function to get stat value from item
local function GetStatValue(item, statName)
    if not item then return 0 end
    
    local success, value = pcall(function() return item[statName]() end)
    if success and value then
        local numValue = tonumber(value)
        if numValue then return numValue end
        if value == true then return 1 end
    end
    
    local success2, value2 = pcall(function() return item[statName] end)
    if success2 and value2 and type(value2) ~= "userdata" then
        local numValue = tonumber(value2)
        if numValue then return numValue end
    end
    
    return 0
end

-- Function to calculate weighted score for an item
local function CalculateScore(item, weights)
    if not item then return 0 end
    
    local score = 0
    for statName, weight in pairs(weights) do
        if statName ~= 'DamageRatio' then
            local value = GetStatValue(item, statName)
            if value > 0 then
                score = score + (value * weight)
            end
        end
    end
    
    local damage = GetStatValue(item, 'Damage')
    local delay = GetStatValue(item, 'ItemDelay')

    if damage > 0 and delay > 0 then
        local damageRatio = damage / delay
        local damageRatioWeight = weights.DamageRatio or 80
        score = score + (damageRatio * damageRatioWeight)
    end
    
    return score
end

-- Function to check if item is wearable (slots 0-22)
local function IsWearable(item)
    if not item or not item.WornSlots then return false end
    
    for i = 1, item.WornSlots() do
        if item.WornSlot(i).ID() < 23 then
            return true
        end
    end
    return false
end

-- Function to check if item skill is 2-handed
local function IsTwoHandedWeapon(item)
    if not item then return false end
    
    local success, itemType = pcall(function() return item.Type() end)
    if success and itemType then
        if string.sub(itemType, 1, 2) == "2H" then
            return true
        end
    end
    
    return false
end

-- Main function to evaluate if item is an upgrade
function ItemScore.evaluateItemForUpgrade(item, minImprovement)
    minImprovement = minImprovement or 1.0
    
    if not item or not IsWearable(item) then
        return nil
    end
    
    local playerClass = mq.TLO.Me.Class.Name()
    local weights = CLASS_WEIGHTS[playerClass] or CLASS_WEIGHTS.Default
    
    local newItemScore = CalculateScore(item, weights)
    
    if not item.CanUse() then
        return nil
    end
    
    local bestUpgrade = nil
    local is2H = IsTwoHandedWeapon(item)
    
    for i = 1, item.WornSlots() do
        local slotID = item.WornSlot(i).ID()
        
        if slotID < 23 then
            local slotName = SLOT_NAMES[slotID] or string.format('Slot %d', slotID)
            local equippedScore = 0
            
            if is2H and slotID == 13 then
                local mainHandItem = mq.TLO.Me.Inventory('mainhand')
                local offHandItem = mq.TLO.Me.Inventory('offhand')
                
                local mainScore = 0
                local offScore = 0
                
                if mainHandItem and mainHandItem.ID() then
                    if mainHandItem.CanUse() then
                        mainScore = CalculateScore(mainHandItem, weights)
                    end
                end
                
                if offHandItem and offHandItem.ID() then
                    if offHandItem.CanUse() then
                        offScore = CalculateScore(offHandItem, weights)
                    end
                end
                
                equippedScore = mainScore + offScore
                slotName = 'Main Hand + Off Hand'
            else
                local equippedItem = mq.TLO.Me.Inventory(slotID)
                
                if equippedItem and equippedItem.ID() then
                    if equippedItem.CanUse() then
                        equippedScore = CalculateScore(equippedItem, weights)
                    end
                end
            end
            
            local improvement = 0
            if equippedScore > 0 then
                improvement = ((newItemScore - equippedScore) / equippedScore) * 100
            elseif newItemScore > 0 then
                improvement = 999
            end
            
            -- Check if this meets minimum improvement threshold
            if improvement >= minImprovement then
                if not bestUpgrade or improvement > bestUpgrade.improvement then
                    bestUpgrade = {
                        slotName = slotName,
                        improvement = improvement
                    }
                end
            end
        end
    end
    
    return bestUpgrade
end

return ItemScore