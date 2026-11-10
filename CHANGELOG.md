# Changelog

Player-visible UnrealUI changes, newest first. Keep every bullet short, clear and focused on what changes for the player.

## [Unreleased]

### Fixed

- Unit frames show their authored health readout again until a side is changed: the 0.12.0 defaults had forced a bare percentage everywhere, hiding the target frame's exact value. Untouched settings migrate automatically; the health text dropdowns gain a "Default" choice.
- Unit frame health and power text set to "value" or "percentage" now updates with every health/power event instead of once a second.

## [0.12.0] - 2026-10-31

### Added

- Bag and bank items that begin a quest show a small quest mark.
- Nameplate aura icons can use any plate corner with an adjustable gap.
- Edit mode has a Scale (%) slider for unit frames, trackers, cast bars and more.
- Unit frames can show health and power as percentage, value or nothing on each bar side, from the Unit Frames settings and edit mode.
- Font size of the unit frame health and power text can be chosen.
- Unit frame health and power text can be limited to when the cursor is over the frame.
- Unit frames have an "Abbreviate numbers" option (4200 -> 4.2k), on by default.
- New option to show or hide the target-of-target frame.
- The pet frame has its own 2D/3D portrait option.
- Classic-wow and modern-wow action bars have a "Slot background" option.
- Party frames have one icon size option in percent for buffs, debuffs and HoTs.
- New raid frames: Retail-style cells by raid group with class health, power, heals, HoTs, debuffs, dispel highlights and a settings page.
- Party frames have a "Raid-style frames" option, in every theme, that draws the party with the same cells.
- `/uui raid` previews the raid frames (`/uui raid test` with 40 random members) and `/uui party test` shows a fake party with auras, HoTs and incoming heals.
- The status and online-count overlays can be switched off in edit mode or on a new Status overlay settings page, which also picks each readout.
- In edit mode, anchors snap to the screen centre and to other anchors' edges and centres, with a red guide line, even with Magnet off.
- The bags, bank and saved bank have a Scale (%) slider on the Bags settings page.
- The bag header has a gear button that opens the Bags settings page.
- The bag, bank and saved bank can be resized from their bottom-right corner (the two banks share one size); `/uui reset` restores the default size.
- Custom bag and bank categories on the Bags settings page, with priority, all/any item rules and a manual item list.
- New Chat settings page with its own background switch and idle and hover background opacity.
- New Minimap settings page with a scale slider and options to hide the zone panel and zoom buttons.
- The Inspect window has arrows to step through your target and nearby party members, and shows its Honor tab again.

### Changed

- The micro bar and Tracked Bars "Size" sliders are now "Scale (%)", like the other anchors; your size is kept.
- Edit mode windows and their confirmation popups use the metal frame, red close button and game settings controls in every theme.
- Closing an anchor's settings panel in edit mode keeps the anchor selected; click it to reopen the panel.
- The action bar "Hide Slot Background" option is now "Slot border" (ticked shows the border).
- The font dropdown shows each font name in its own font.
- Game Settings search now looks inside every Unreal UI page and lists only the pages with a match.
- The modern-wow minimap zone name background is now one text line tall.
- The modern-wow pet frame text is smaller and stays inside its bars.
- The minimap button and chat text-shadow options moved from General to the new Minimap and Chat pages.
- Modern-wow unit frame right-click menus use the Retail-style menu background.

### Fixed

- Modern WoW red buttons (game menu and others) no longer show a 1px gap near their right end.
- The Game Settings window keeps the same size at any UI scale, so its text stays readable at the minimum scale.
- Dragging the Game Settings window or scrolling its Bags page no longer freezes the game.
- Unit frames now draw above the action bars where they overlap.
- The nameplate Name and Health text font size sliders now change the text with the default font too.
- In edit mode, cast bar anchors no longer cover the edit and anchor settings panels.
- All sliders, including Game Settings and the colour picker, follow the mouse as soon as you press them.
- The durability readout now also updates on the client's inventory alert event.
- Modern WoW unit frames draw the power bar text above the frame border.

## [0.11.1] - 2026-10-22

### Changed

- The Key Bindings settings page is adapted to the latest client version.

### Fixed

- Fixed a crash when changing settings menu page.

## [0.11.0] - 2026-10-20

### Added

- New Nameplates settings pages: General, Health, Target and Raid Marks; every option works in every theme.
- Nameplates: width, height and vertical offset sliders, plus name and health text font sizes.
- Nameplates: show or hide hostile and friendly plates.
- Nameplates: health text format, position and number abbreviation.
- Nameplates: hide health bars by unit type, or keep them on the target and damaged units.
- Nameplates: fade opacity for non-targets, target zoom and a target outline with a custom colour.
- Nameplates: reaction outlines, and raid mark position, size and offset.
- Nameplates: long name abbreviation, and the target plate drawn above the others.
- Nameplates: combo points on the target plate.
- Nameplates: class-coloured player bars and names, and a guild name line (your own guild in green).
- Nameplates: totems can hide their health or show an icon; critters can hide their health.

### Changed

- Improved the pet interface.
- Nameplate colour is now based on the unit's reaction (hostile, neutral or friendly).
- Party, raid and guild members show as friendly on nameplates.
- Modern WoW nameplates now show names.

## [0.10.4] - 2026-10-19

### Added

- Add custom nameplate.
- Add debuff and castbar on nameplate.

### Changed

- Nameplate show the metrics.
- Pet interface show loyalty icon and available skill points.

## [0.10.3] - 2026-10-17

### Added

- Add more Fonts you can change from the addon settings.

### Changed

- When increasing the UI scale, UI anchor won't get outside the screen.

### Fixed

- Fix the UI for the new client update 2432.

## [0.10.2] - 2026-10-05

### Added

- Added performance monitoring page in the settings.

### Fixed

- Fixed persistent cursor when changing map zone.

### Removed

- Removed black background on each side of the worldmap.

## [0.10.1] - 2026-09-30

### Added

- Added tracked bars for player auras.
- Added a new HD minimap arrow.
- Added a 3D portrait option for the Classic WoW theme.

### Changed

- Optimised crafting interface size.
- Reworked reputation interface for Modern WoW.
- Improved 3D preview offset with the Modern WoW theme.
- Bag windows now stay above all HUD elements after the last client update.
- Modern theme can now disable the portrait or choose between 2D and 3D.

### Fixed

- Fixed Micro Bar background.
- Fixed portrait after the last client update.
- Fixed the social interface close button with Modern WoW and Classic WoW themes after the last client update.
- Fixed addon game settings flickering when moving windows.

## [0.10.0] - 2026-09-29

### Added

- New character interface with a side panel showing all stats.
- Added the Equipment Manager.
- Added HUD effects for low health and loss of control.
- Added a gold coin icon to junk items in bags when talking to a merchant.
- Added profession icons to the microbar.
- New minimap for the modern-WoW theme.
- Added reagent search to the crafting interface.
- New HD rare/elite unit frame textures for the modern-WoW theme.
- New HD party frame textures for the modern-WoW theme.

### Changed

- Improved the microbar.
- Special bags in unified bags are now split.
- Items related to special bags now appear in those bags with a category-based side view.
- Improved interface textures for the modern-WoW theme.
- Buffs and debuffs are now split in Edit Mode.
- Improved the bag bar for modern-WoW with some fixes.
- Improved Edit Mode with size options for more anchors.
- Trainer entries now use colored names for available, unavailable, and already known.

### Fixed

- Fixed class-colored health bars on the player frame.
- Fixed item name alignment on the merchant interface in the modern theme.

### Removed

- Removed slot backgrounds from the extra action bar and added a border to Bar 1.

## [0.9.2] - 2026-09-25

### Added

- Added crafting filters for difficulty and having all reagents.
- Added a recipe search bar to the crafting interface.
- Added charges to the Rogue poison buff (need a test).
- Added a search bar to bags and the bank.
- Added an empty slot in bags category-based view.
- Added more detailed categories to bags category-based view.

### Changed

- Redesigned the trainer interface for the modern WoW theme.
- Redesigned the merchant interface for the modern WoW theme.
- Bags category-based view now also applies to the bank.
- Improved category columns to reduce the overall window size.
- Special bags now show separately in their own bag slot in category-based view.
- Modern WoW theme now uses the native pet happiness icon.

### Fixed

- Fixed a client freeze when collapsing crafting recipes.
- Fixed the pet spellbook tab.

## [0.9.1] - 2026-09-23

### Added

- New unified game settings interface.

### Changed

- Target frame level and name colors now change based on level difference.
- Keeps bag icons on the HUD in modern WoW when the Bags module is enabled.

## [0.9.0] - 2026-09-21

### Added

- Added Talent Build Advisor.
- Added a new crafting interface for the modern WoW theme.
- Added a Professions tab for the modern WoW theme.
- Added options in Move UI to change the swing bar width and height.
- Added target reaction status to the modern WoW target frame.
- Added an animated icon near the minimap when you have unread letters.
- Added new spell borders to the spellbook for the modern WoW theme.

### Changed

- Deeply reworked the social interface for the modern WoW theme.
- The swing bar now uses WoW Forever textures.
- Redesigned the quest giver interface for the modern WoW theme.
- Action bar spells that require reagents now show how many casts are available based on the reagents in your bags.
- The classic WoW theme talent window now displays all 3 talent panes.
- Improved Move UI edit mode with a new border design.
- Improved the pulse effect for highlighted action bar spells in the modern WoW theme.

### Fixed

- Fixed quest log item rewards sometimes appearing in the wrong position in the classic WoW theme.
- Fixed mouse wheel scrolling in the crafting interface.
- Fixed missing spell highlights sometimes appearing on the wrong action bar tab and position.

## [0.8.0] - 2026-09-19

### Added

- Watch your bank contents from a distance.

### Changed

- Redesigned the combined bag and bank for Classic WoW and modern WoW.
- Redesigned the loot panel with an easing effect when looting items, with loot moving right and fading out.
- Classic WoW theme now uses the modern WoW quest log.
- Improved bag sorting, automatically applied to the category-based view.
- For the Classic WoW theme, Bar 1 now matches the native UI, with an option to disable it in Move UI settings when clicking Bar 1.
- When Bar 1 on the Classic WoW theme is not set as the original UI, the XP bar now uses the modern WoW design.
- Improved 3D portrait loading to avoid textures not yet being loaded.

### Fixed

- Fixed a modern WoW interface bug when switching between the Buyback and Merchant tabs.
- Fixed Highlight Slot accumulating when related to an extra bag.

## [0.7.4] - 2026-09-18

### Added

- Added an option to customize the Classic WoW theme by enabling different modules from Modern WoW.
- Added new talent windows for the Modern theme.
- Added item border colors based on gear rarity in the Inspect interface.
- Added compare tooltips for roll items in parties.

### Changed

- Target of Target in the Classic WoW theme now uses a Classic-style design.
- Gear rarity borders in the Classic WoW theme now display in a Modern WoW style instead of flat borders.
- The Inspect interface design now changes based on your selected theme.
- The Classic WoW theme now includes the Professions tab in the Spellbook.
- The merchant Buyback interface now shows item rarity colors.

### Fixed

- Fixed the interface appearing outside the screen after the latest client update.

## [0.7.3] - 2026-09-17

### Added

- Added merge stacks for bags and bank.
- Added craft item stats to the crafting interface for the modern WoW theme.
- Added item compare tooltips in the crafting interface when available.
- Added a Track Recipe option to the crafting interface for the modern WoW theme, showing reagents on your HUD.

### Changed

- Optimised bags to prevent freezing when moving items.
- Improved the recipes list in the crafting interface for the modern WoW theme, adding colors and better positioning.
- Improved the category-based bag view to add columns when possible.
- Improved bag sorting and category-based view to keep same items beside each other.

### Fixed

- Fixed Shift + Click not linking items from the crafting interface in chat.
- Fixed the UI moving when opening a different interface while Talents were open.

## [0.7.2] - 2026-09-16

### Added

- Added pet frames to the Modern-WoW party frames.

### Changed

- Hunter Auto Shot now works with Auto Attack without needing the Shot spell on the action bar.
- Hunter Auto Attack now switches between melee and ranged attacks more smoothly; if the target is lost, it automatically re-targets the mob.
- Bank bag sorting works again.
- The Modern-WoW Quest Log now shows the quest count.
- Replaced the scrollbar on the skill interface for the Modern-WoW theme.
- The Modern-WoW target frame now shows 3D portraits on the right.
- Extended rare mob/NPC target borders when 3D portraits are enabled.

### Fixed

- Fixed bag sorting, which a previous update had broken while excluding special bags (ammo, herbs, etc.).
- Fixed the Modern-WoW Quest Log going out of view when UnrealQuest is not installed.
- Fixed talent numbers not scrolling with the talent list.
- Fixed a rare issue with incorrect buff timers (needs more testing).

## [0.7.1] - 2026-09-15

### Added

- Added 3D portraits for the Modern and Modern-WoW themes.
- Added a profession interface with the Spellbook.
- Added a new talent interface for the Modern-WoW theme.
- Added an option to hide the Gryphon on Bar 1 for the Modern-WoW theme.

### Changed

- Redesigned the Resurrect Now and Logout interfaces for the Modern-WoW theme.

## [0.7.0] - 2026-09-14

### Added

- New modern WoW theme.

### Changed

- Bag sorting no longer sorts Carquois, and likely other special bags such as Warlock bags.

## [0.6.0] - 2026-09-11

### Added

- Added settings on each highlighted anchor.
- Added an option to change the grid size.
- Added magnet anchors.
- Added a setting to enable or disable anchors.
- Added a fadeout duration setting for tooltips when Follow Cursor is enabled.

### Changed

- Improved Move UI edit mode.
- Connected anchors now move together.
- Improved tooltip behavior.
- Increased tooltip offset when following the cursor to avoid overlapping with mob/NPC tooltips.
- Increased chat background opacity when text shadow is disabled.

## [0.5.1] - 2026-09-07

### Added

- Added target frames for rare, elite, and boss enemies.
- Added actual HP/Power values for mobs and NPCs.
- Added an option to stick the world tooltip near the cursor.
- Added a Target of Target frame for Classic WoW theme.
- Added an option to remove text shadows from chat texts.
- Added more information when hovering over the XP bar.

### Changed

- Move UI now has an anchor for the world tooltip.
- Pet Bar customization is back in settings, with options for slot size and gap.
- The bag sort button now sorts all bags instead of only the main bag.
- Changed favorite item shortcut from Shift + Click to Alt + Click.
- Chat windows now save their position after a reload.

### Fixed

- Fixed item stack numbers in the bank main bag.
- Fixed bank bag sorting.
- Fixed the Pet tab on the character interface.

## [0.5.0] - 2026-09-05

### Added

- Added heal prediction.
- Added HoTs to party frames.
- Added a favorite system for items in bags.
- Added the target castbar for the Classic theme.
- Added local time display to the status overlay.

### Changed

- Party member frames are now grey when the player is offline.
- Party member frames now get darker when out of range.
- Bags can now be moved freely without using UI Move Edit Mode.
- Improved the range slider so the thumb cannot move outside the slider, and clicking the slider moves the thumb to that position.
- Increased player name color contrast on party frames based on class.
- Sellprice and itemCompare now show on loot tooltips.
- Rogue and Druid auras at the top of the player frame no longer overlap with the combo frame.

### Fixed

- Fixed aura timers using a spell's max-rank duration instead of the known rank.
- Fixed aura durations from same-named creature abilities using the player spell duration.
- Fixed the position of unitframe auras for the Classic theme so they now stay at the top of the unitframe.

## [0.4.0] - 2026-09-04

### Added

- Added an option to use category-based filter bags.
- Added bank and bag sorting. (need a test for bank)
- Added a bag sorting button.
- Added an option to disable the bags UI module.
- Added an anchor in UI edit mode, to move the target-of-target frame.
- Added itemCompare and sellPrice to the loot interface. (need a test)

### Changed

- Auto Attack now only starts when in range, allowing ranged attacks to cast normally.
- Hunter Auto Attack is now progressive: it starts at range, then continues in melee.
- Quest items now have a colored border in bags.
- Unit frame auras now place buffs toward the frame edge and stack debuffs outward.

### Fixed

- Fixed on the spellbook the highest rank option sometimes showing a lower spell rank.

## [0.3.1] - 2026-09-01

### Added

- Added a modern design for talent windows.

### Changed

- Optimization done, ~30% more FPS (need test on different configurations).

### Fixed

- Fixed interface dragging disabling interaction at the top of interfaces.

## [0.3.0] - 2026-08-31

### Added

- Added target castbar.
- Added Auto Attack swing bar.
- Added Mana / Energy tick.
- Added spell pushback on the cast bar.
- Added an option in the spellbook to show only the last rank of a spell.
- Added the gossip icon for quest giver dialogs.
- Added a new combo points design for Rogue and Druid Cat Form.

### Changed

- Spellbook now highlights spells that are not on your action bars.
- Few optimisations done.
- Increased health bar contrast on the target frame.
- Rogue and Druid Cat Form can now choose to display combo points on the player frame or target frame.
- Item name color is now displayed with the color of its rarity.
- ItemCompare no longer overlaps with item tooltips, especially near screen edges.
- Improved windows mover, making interface windows easier to move.

## [0.2.3] - 2026-08-30

### Added

- Added color to item comparisons to show whether stats are better or not.
- Added a Move UI anchor for the original buff/debuff near the minimap.

### Changed

- Loading windows now only show a small loading bar at the top of the screen.
- Improved the EquipCompare visuals.
- Classic-WoW theme now uses the modern theme tooltip to avoid bugs.
- Buffs and debuffs now also appear at the top of your player frame.
- Buffs and debuffs can now be shown or hidden on unit frames and in their native position.

### Fixed

- Fixed bank bags not allowing items to be moved between extra bags.

## [0.2.2] - 2026-08-29

### Added

- Added sell price and itemCompare to quest rewards.
- Added an Auto Attack setting for Rogue and Druid Cat Form while stealthed.
- Added a UI loading bar when logging in due to client limitations; it will be removed with a future client update.
- Added rarity border colors to items in the character and bag frames for the Classic WoW theme.
- Added a new Rogue setting for poison Shift-clicks, disabled by default. (Need test)
- Added the Rogue stance bar, compatible with the Quick Binding tool.

### Changed

- Huge fixes for the Classic WoW theme: main menu, action bars, and unitframes.
- Party leaders now have a star on their frame.
- Increased the party frame font size slightly.
- Quick Binding no longer casts a spell when binding a slot.
- Redesigned the breath bar for the modern theme.
- Redesigned the Release Spirit and Resurrect windows for the modern theme.
- The Pick Lock icon now appears in the bag header when the Rogue knows the skill.

### Fixed

- Fixed interface elements overlapping.
- Fixed the cooldown timer on action bars.

## [0.2.1] - 2026-08-27

### Added

- Added an option to show the pet frame in the party frame.
- Added map coordinates based on your cursor position.
- Added item rarity-colored borders to items in the character panel: green / blue / purple etc. (need a test)
- Added Classic slot borders to bags in the Classic WoW theme.
- Added Quick Binding and an UnrealUI button to the main menu for the Classic WoW theme.

### Changed

- Zone levels are now shown on the map.
- Addon now available in EN / CN / RU / FR.
- Show item prices in tooltips.
- Setting icon is now movable.
- Improved bag windows for the Classic WoW theme.

### Fixed

- Fixed action bar highlight for the Classic WoW theme.
- Fixed overlap in the Guild interface. (need a test)
- Fixed changing items in the unified bank sometimes causing an error when moving items between bags. (need a test)
- Fixed the mail interface calling action bar keybinds.
- Fixed Curse of Agony not showing on the target. (need a test)
- Fixed Rend and Hamstring not showing in the Classic theme. (need a test)

## [0.2.0] - 2026-08-25

### Added

- Added an option to select the theme style: Modern, Classic WoW, or Modern WoW.
- Added Classic WoW theme style. (still early and need test)
- Added item comparison tooltips on mouseover.
- Added an option to set the unit frame color based on class.
- Added profile management to keep UI settings separate per character on the same account, with profiles that can be applied to any character. (need a test)

### Changed

- UI Edit improvement: magnet elements together and move them pixel by pixel for better grip.
- Improved Party Frame buff/debuff display.
- Improved Unit Frame design.
- Party Frame colors are now based on class.
- Highlighting an extra bag now also highlights its corresponding slot.
- Food and drink no longer trigger the global cooldown.
- Debuffs shown below the Target Bar no longer overlap Target of Target.
- Opening or closing an additional bag now also opens or closes the main player bag. Also fixed for the bank.
- Bandages, potions, and other stackable items now show their quantity on the Action Bar, including items in the bank. (need a test)
- Assigning "-" now shows the panel call "6" on Russian keyboards.
- Improved keybind mapping for AZERTY and QWERTY keyboards.

### Fixed

- Fixed quest reward cells sometimes overlapping.
- Fixed incorrect grey item counts; items without a valid count no longer show a number, including in chat.
- Fixed the sort arrow overlapping the Guild panel. (need a test)

## [0.1.2] - 2026-08-22

### Added

- Added effect durations to buffs and debuffs on the target frame.
- Added tooltip (mousehover) to buffs and debuffs on the target frame.
- Added the Warrior stance bar (need a test).
- Added the happiness/hunger icon to the pet frame. (Need test and screenshot report).
- Added icons and tooltips for resistances in the character interface.
- Added the missing icon to unlearn a profession.
- Added icon on gossip dialog with NPC.

### Changed

- Resting status now shows on the player frame.
- Bank windows now use the same design as player bag windows (fixed the additional bank bags opening player bag).
- Changed the party frame design to match the player and target frames.
- Re-design in modern style the inbox interface.
- Better hides the native UI health bar and level without reintroducing target-change stuttering.

### Fixed

- Fixed a major FPS drop when in a party.
- Fixed Auction House interactions with the action bar.
- Fixed the dropdown component.

## [0.1.1] - 2026-08-21

### Added

- Added a radial effect for Global Cooldown (GCD) visual feedback.
- Added online and zone player counts using a /who scan.
- Added the pet frame (need a test, please report).

### Changed

- Opening chat to type no longer casts the action bar.
- Hearthstone and quest item casts no longer show an icon on the cast bar.

### Fixed

- Fixed stuttering when changing targets.
- Fixed action bar overlapping the interface.
- Fixed Rogue combo points sometimes appearing incorrectly.
- Fixed native Rogue combo points still appearing on the UI (need a test, please report).
- Fixed the cast bar not appearing while fishing.

## [0.1.0] - 2026-08-21

### Changed

- Quick Binding - Assign keybinds by hovering action bar buttons.
- MoveAnything - Move Quest, Character, Social, and other windows freely.
- All interfaces have a modern design, except Bank, Auction House, and Mail.
- Hide action bar backgrounds for a cleaner look.
- Access Bear, Cat, and Travel forms from the Druid bar.
- See rested XP directly on the XP bar.
- Customize Unit Frame health and power colors.
- Keep long names from overflowing Unit Frames.
- Tooltips no longer blink when appearing.
- Unit Frames no longer cover other interfaces.
- Re-sort bar numbers - check all bars in case some spells are missing.
