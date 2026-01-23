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
- Targeted item searching with `/mlfind`
- Zone-wide corpse scanning for item cataloging

---

## Installation

1. **Clone or Download** this repository
2. **Place the MasterLoot.lua file** in your MacroQuest `/lua` folder
3. **Install all of the module files** in a `lua/modules/` folder
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

## Commands

### /mlml - Master Loot
Loots all corpses within range (500 unit radius). Characters will only loot items they can use or items that meet the configured value thresholds.

### /mlfind - Find and Loot Specific Items
Searches all corpses within range (1000 unit radius) for items matching the specified search strings. This is useful for finding specific drops without looting everything.

#### Syntax
```
/mlfind '<search strings>'
```

**IMPORTANT:** When using `/mlfind` with `/dgga` (to run on all characters), you must:
1. Wrap the **entire argument** in single quotes `'...'`
2. Wrap **each search term** in double quotes `"..."`

#### The + Prefix
Adding a `+` before a search term means **"loot all matches even if I already have one"**. Without the `+`, the character will only loot the item if they don't already have it in their inventory or bank.

| Prefix | Behavior |
|--------|----------|
| `"term"` | Only loot if character does not have this item in their inventory or bank. Useful for items like Astrial Shards which are not tradeable and you want every group member to get one. |
| `"+term"` | Loot ALL matching items regardless of whether the character already has one. |

#### Examples

**Search for a single item (simple case):**
```
/mlfind sword
```

**Search for multiple items on all characters:**
```
/dgga /mlfind '"astrial" "hermit" "celestial"'
```
This searches for items containing "astrial", "hermit", or "celestial" in their names. Characters will only loot items they can use.

**Search and loot ALL matching items (even if you already have one):**
```
/dgga /mlfind '"+astrial" "+hermit" "+celestial"'
```
The `+` prefix means every character will loot any matching item, even if they already have one in their inventory or bank. Useful for collecting tradeable items to distribute later.

**Mixed search - some check inventory, some loot-all:**
```
/dgga /mlfind '"astrial" "+immortality" "+advancement"'
```
This will:
- Loot "astrial" items only if the character doesn't already have one (good for no-trade items everyone needs)
- Loot ALL "immortality" items even if the character already has one
- Loot ALL "advancement" items even if the character already has one

**Searching for gems/tradeskill items:**
```
/dgga /mlfind '"+emerald" "+diamond" "+sapphire" "+ruby"'
```

**Common farming pattern:**
```
/dgga /mlfind '"+fallen" "+unidentified" "+hermit" "+bear"'
```

### /mlli - Loot Queued Items
Commands the character to loot all items that have been queued for them via the GUI.

### /mlrc - Reload Configuration
Reloads the INI file without restarting the script.

### /mlru - Report Unlooted Corpses
All characters report how many unlooted corpses are near them.

### /mlpm - Print Multiple Use Items
Prints item links for all items in the shared loot window.

### /mlpu - Print Upgrade List
Characters report which shared items would be upgrades for them.

---

## Features & Usage

### Main Window Controls

#### **Character Radio Buttons**
- The color of each character represents the percentage of corpses the character has not looted:
  - **White** = 0%
  - **Yellow** = 1% to 33%
  - **Orange** = 34% to 66%
  - **Red** = 67% to 100%
  
#### **Everyone Loot**
- All characters will start looting simultaneously

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

#### **Clear Shared List**
- Clears all items from the Loot Window
- Use this to reset the shared item list
- Clears all upgrade items from the characters' upgrade list

#### **Print Item Links**
- Clicking this button will print out links in `/g` (group chat) for all items that are in the shared window
- After all items are printed, all characters will print to `/g` the items that are upgrades for them, the slot they upgrade, and the percentage that the item is better than the currently equipped item

#### **Print Unlooted Corpses**
- Pressing this button will show the number of unlooted corpses for any characters. Characters with zero unlooted corpses will not respond.

#### **Show Upgrades**
- If you have an item from the shared list selected and press this button, characters who would receive an upgrade will respond with the item name, slot, and the percentage that the item is better

#### **Scan All Corpses**
- Scans all corpses within range (1000 unit radius) and adds ALL items found to the shared loot window
- Corpses are divided among group members for faster scanning
- Each character scans their assigned corpses and broadcasts items found
- All characters end up with the same shared item list
- Useful for cataloging loot before deciding who gets what

**How Scan All Corpses Works:**
1. Click the "Scan All Corpses" button
2. The coordinator (whoever clicked) divides corpses among all group members
3. Each character receives their assignment via group chat
4. Characters scan their assigned corpses and broadcast all items found
5. All items appear in the shared loot window on all characters
6. Failed scans are reported at the end

---

## Workflow Example

**After clearing a group of mobs:**

1. **Have Everyone Loot Until All Corpses Are Looted:**
   - I usually start by having everyone loot. Corpse looting is buggy, and characters often can't loot a corpse on the first attempt. Use "Everyone Loot" or select individual characters to loot until everyone has looted all corpses.
   - A character will not know if an item is an upgrade unless they've encountered it while looting, so it's important that all characters have looted all corpses if you want the upgrade feature to work correctly.

2. **Handle Shared Items:**
   - Print item links or select an individual item to have characters respond if the item is an upgrade for them
   - Assign the item to a character by selecting the character (radio button) and the item (list box window)
   - You can assign multiple items to a character before sending them off to loot
   - Once all the items you want to loot have been queued up, click the "Get Shared Item(s)" button to direct that character to loot the items

**Alternative Workflow - Catalog First:**

1. **Use Scan All Corpses:**
   - Click "Scan All Corpses" to catalog everything on all corpses
   - Review the shared item list to see what dropped
   - Assign valuable items to specific characters

2. **Use /mlfind for Targeted Looting:**
   - After assigning shared items, use `/mlfind` to grab specific drops
   - Example: `/dgga /mlfind '"+diamond" "+emerald"'` to grab all gems

---

## Requirements

- **MacroQuest (MQNext)**
- **One of the following movement plugins:**
  - **MQ2MMOWarp** (for warp movement)
  - **MQ2Nav** (for navigation movement)

---

## Known Issues

### Corpse Window Access
Characters occasionally fail to open corpse windows despite `#corpsefix` commands and retry logic. `#corpsefix` is used on retries, but this can be annoying when all characters are looting, so I've reduced how frequently it's used.

### Shared Items
Shared items are not removed from all windows when they are assigned from one character via the Queue button. Assigning the item removes it from whoever clicked the button but does not remove it from other characters' windows.

The upgrade list for characters does not clear out an item that has been looted until you press the Clear button.

### /mlfind Not Responding
If `/mlfind` stops responding after running multiple times, the script may be stuck processing a previous command. Restart the script with `/lua stop masterloot` followed by `/lua run masterloot`.

---

## Development Status

This is an **active development project**. While functional, expect occasional bugs and ongoing improvements.

### Planned Features
- Enhanced duplicate item handling
- Removing items from all list boxes when queued
- Removing items from all upgrade lists when someone loots the item
  
---

## Feedback & Contributions

Contributions, bug reports, and feature requests are welcome!

- **Issues:** [GitHub Issues](https://github.com/CerveloFellow/Loot-Manager/issues)
- **Contributions:** Fork the repository and submit pull requests

If you're comfortable with Lua and want to contribute directly, contact the repository owner for access.

---

**Happy looting!** 🎮✨
