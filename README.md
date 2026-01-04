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

#### **Use Warp / Use Nav Toggle**
- Manually toggle between Warp and Nav movement modes
- Overrides the `useWarp` setting in the INI file temporarily

#### **Clear Shared List**
- Clears all items from the Loot Window
- Use this to reset the shared item list

---

## Workflow Example

**After clearing a group of mobs:**

1. **Start with your main character:**
   - Select your driver/main character
   - Click "Loot"
   - Wait for looting to complete

2. **Proceed through other characters:**
   - Select the next character
   - Click "Loot"
   - Repeat for each character
   - *(Optional: Run multiple characters simultaneously, though this increases the chance of corpse window errors)*

3. **Handle shared items:**
   - Review items in the Loot Window (items other group members can use)
   - For each item:
     - Select the appropriate character
     - Select the item from the list
     - Click "Queue Shared Item"
   - Once all items are assigned:
     - Select a character
     - Click "Get Shared Item(s)"
     - Repeat for all characters with queued items

4. **Verify completion:**
   - Use `/g mlru` to check for unlooted corpses across all characters
   - Manually handle any problematic corpses if needed

---

## Chat Commands

| Command | Description |
|---------|-------------|
| `/g mlru` | Reports unlooted corpse count for each group member |

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

**Planned Fix:** Implement an internal item list with unique IDs for each item instance.

### Corpse Window Access
Characters occasionally fail to open corpse windows despite #corpsefix commands and retry logic.

**Workarounds:**
- Check unlooted corpses: `/g mlru`
- Manual looting: `/target t <corpseId>`, `/warp t`, `/loot`
- Retry the Loot or Get Shared Item(s) command
- For detailed info: `/ti` (shows unlooted corpses for that character)

### Looting Reliability
Corpse interaction can be inconsistent due to game mechanics and timing issues. The script includes retry logic and error handling, but manual intervention may occasionally be needed.

---

## Troubleshooting

**Script won't start:**
- Ensure INI file exists (run once to auto-generate)
- Check MacroQuest Lua folder path
- Verify file permissions

**Characters won't loot:**
- Verify movement plugin (Warp or Nav) is loaded
- Check `useWarp` setting matches your plugin
- Ensure characters are in the same zone
- Try toggling Warp/Nav mode

**Items not appearing in Loot Window:**
- Verify item is not in ItemsToIgnore
- Check if item meets value thresholds
- Reload INI file if recently modified

**Corpse can't be opened:**
- Use `/g mlru` to identify problematic corpses
- Try manual looting commands
- Re-run the Loot command for that character

---

## Development Status

This is an **active development project**. While functional, expect occasional bugs and ongoing improvements.

### Planned Features
- Enhanced duplicate item handling
- Improved corpse access reliability
- Additional filtering options
- Performance optimizations

---

## Feedback & Contributions

Contributions, bug reports, and feature requests are welcome!

- **Issues:** [GitHub Issues](https://github.com/CerveloFellow/Loot-Manager/issues)
- **Contributions:** Fork the repository and submit pull requests

If you're comfortable with Lua and want to contribute directly, contact the repository owner for access.

---

## License

This project is provided as-is for the MacroQuest community. Use at your own risk.

---

**Happy looting!** 🎮✨
