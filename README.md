# ProFusion Loot Manager

A MacroQuest (MQNext) Lua utility designed to streamline master looting for multiboxing groups running with E3.

**Repository:** [https://github.com/CerveloFellow/Loot-Manager](https://github.com/CerveloFellow/Loot-Manager)  
**Main File:** `MasterLoot.lua`

---

## Overview

ProFusion Loot Manager eliminates the tedious process of manually looting corpses across multiple characters. Whether you're clearing zones or farming gear, this tool automates and centralizes loot distribution, significantly reducing the time spent on post-combat cleanup.

**Key Benefits:**
- Automated corpse looting across all group members
- Intelligent item distribution based on class/race requirements
- Centralized loot window for shared items
- Configurable value thresholds and item filters
- Support for both warp and navigation movement

---

## Installation

1. **Clone or Download** this repository
2. **Place the MasterLoot.lua file** in your MacroQuest `/lua` folder
3. **Install all of the modules files** in a lua/modules/ folder
4. **Start the script** with:
   ```
   /lua run MasterLoot
   ```
5. On first run, a configuration file (`MasterLoot.ini`) will be created with default settings

---

## Configuration

The script uses an INI file for configuration. If the file doesn't exist on first run, it will be auto-generated with default values and the script will exit. Simply restart the script after the INI is created.

### INI File Structure

#### **[ItemsToKeep]**
Items in this section are **always looted** by any character using Master or Peer Looting, regardless of other settings.

```ini
[ItemsToKeep]
Item1=Diamond
Item2=Blue Diamond
Item3=Platinum Fire Wedding Ring
```

#### **[ItemsToShare]**
Items in this section are **never auto-looted**. They appear in the Loot Window for manual assignment using "Queue Item" and "Get Shared Item(s)".

```ini
[ItemsToShare]
Item1=Fishbone Earring
Item2=Scimitar of the Ykesha
```

#### **[ItemsToIgnore]**
Items in this section are **completely ignored** and will never be looted or displayed.

```ini
[ItemsToIgnore]
Item1=Cloth Cap
Item2=Rusty Dagger
```

#### **[Settings]**
Configurable options for the loot manager behavior.

| Setting | Type | Description |
|---------|------|-------------|
| `useWarp` | true/false | `true` = Use MQ2MMOWarp commands to warp to corpses<br>`false` = Use MQ2Nav to navigate to corpses |
| `LootStackableMinValue` | integer | Minimum value (in copper) for stackable items to be looted |
| `LootSingleMinValue` | integer | Minimum value (in copper) for single items to be looted |

**Example:**
```ini
[Settings]
useWarp=true
LootStackableMinValue=100
LootSingleMinValue=500
```

---

## Features & Usage

### Main Window Controls

### Character Radio Button ###
- The color of the character represents the precent of corpses the character has unlooted(White=0%, Yellow=1% to 33%, Orange=34% to 66%, Red=67% to 100%)
  
#### **Loot Button**
- Select a group member using the radio buttons
- Click "Loot" to have that character loot all unlooted corpses
- The character will only loot:
  - Items no one else can use
  - Items that can be traded between group members
  - Items matching the INI criteria (value thresholds, ItemsToKeep, etc.)
- Items that other characters can use appear in the Loot Window for assignment

#### **Queue Shared Item**
- Select an item from the Loot Window
- Select a character with the radio buttons
- Click "Queue Shared Item" to assign that item to the character
- Multiple items can be queued to multiple characters before sending them to loot

#### **Get Shared Item(s)**
- Commands the selected character to loot all items queued for them
- Character will navigate to the appropriate corpses and loot assigned items

#### **Reload INI**
- Reloads the INI file without restarting the script
- Useful when you modify settings on the fly

#### **Everyone Loot**
- All characters will start looting
- 
#### **Clear Shared List**
- Clears all items from the Loot Window
- Use this to reset the shared item list
- Clears all upgrade items from the characters upgrade list

#### **Print Item Links**
- Clicking this button will print out links in /g for all items that are in the shared window
- After all of the items are printed, all characters will print out to /g the items that are upgrades for the, the slot they are upgraded and the percent that the item is better than the currently equipped item

#### **Print Unlooted Corpses**
- Pressing this button will show the number of unlooted corpses for any characters.  Characters with zero unlooted corpses will not respond.

#### **Show Upgrade for Selected Item**
- If you have an item from the shared list selected and press this button, if the item is an upgrade for a character, they will respond with the item name, slot and percent that the item is better
---

## Workflow Example

**After clearing a group of mobs:**

1. **Have Everyone Loot Until All Corpses are Looted:**
   - I usually start with having everyone loot.  Corpse looting is buggy, and characters often can't loot a corpse on the first attempt.  Use Everyone Loot or select a character to loot until everyone has looted all corpses.
   - A character will not know if an item is an upgrade unless they've come across it while looting, so it's important that all characters have looted all corpses if you want the upgrade to work correctly.

2. **Handle shared items:**
   - Print item links or select an individual item to have characters respond if the item is an upgrade for them
   - Assign the item to a character by selecting the character(radio button) and the item(list box window)
   - You can assign multiple items to a character before sending them off to loot them.
   - Once all the items you want to loot have been queued up, click the Get Shared Item(s) link to direct that character to loot the item.

---

## Requirements

- **MacroQuest (MQNext)**
- **One of the following movement plugins:**
  - **MQ2MMOWarp** (for warp movement)
  - **MQ2Nav** (for navigation movement)

---

## Known Issues

### Duplicate Shared Items
When a single corpse contains multiple instances of the same item that can be used by group members, only one instance appears in the Loot Window due to ImGui Listbox limitations.

### Some items report twice
There's a bug I'm working on where a character incorrectly reports which corpse the item is on, and the item shows up in the list box twice on different corpses.  

### Corpse Window Access
Characters occasionally fail to open corpse windows despite #corpsefix commands and retry logic.  #corpsefix is used on retries but this can be annoying when all characters are looting, so I've toned down how much it's used.

### Shared Items
Shared items are not removed from all windows when they are assigned from one character via the Queue button.  Assigning the item removes the item from whoever clicked the button, but does not remove it from the other characters window.

The upgrade list for characters does not clear out an item that has been looted until you press the Clear button.

---

## Development Status

This is an **active development project**. While functional, expect occasional bugs and ongoing improvements.

### Planned Features
- Enhanced duplicate item handling
- Removing items from all list boxes when queued
- Removing items from all upgradeLists when someone loots the item
  
---

## Feedback & Contributions

Contributions, bug reports, and feature requests are welcome!

- **Issues:** [GitHub Issues](https://github.com/CerveloFellow/Loot-Manager/issues)
- **Contributions:** Fork the repository and submit pull requests

If you're comfortable with Lua and want to contribute directly, contact the repository owner for access.

---

**Happy looting!** 🎮✨
