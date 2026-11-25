# Changelog

## 1.6.0 - 2026-11-25

- Layout editor: every setting is now available in the editor, per element. Click an element and the dialog shows its settings:
  - Minimap: size, border, border scale and offset, rotation, auto zoom out, combat transparency, compass, right and middle click actions.
  - Header: above or below the map, gap, full width, fade, hide addon compartment.
  - Coordinates: show, position. Zoom buttons: visibility. Day/night and instance difficulty: show. Addon compartment: hide.
  - Addon button collector: all window and button settings.
  - Movable elements keep their size and layer sliders on top.
- Map and header can be selected but not dragged (Blizzard's Edit Mode places them); right click on them resets their settings.
- The dialog grows with the selected element's settings and uses Blizzard's sliders, dropdowns and checkboxes.

## 1.5.0 - 2026-11-25

- Layout editor: size and layer per element.
  - Mouse wheel over an element changes its size (50 to 200 %), Shift + mouse wheel its layer (in front of or behind other elements, -10 to +10).
  - The dialog shows the selected element with size and layer sliders (Blizzard's slider with steppers) and a button to reset just that element.
  - Right click resets position, size and layer of an element; "Reset all" resets everything.
- New option: hide Blizzard's addon compartment (Minimap section). The SquareMap button already collects the actual minimap buttons, so the compartment mostly lists the same addons twice.

## 1.4.1 - 2026-11-25

- Fixed: "An action was blocked in combat because of taint from SquareMap - Button:SetPassThroughButtons()" from quest pins on the world map. The world map was still run from addon code in two places:
  - The "World map" click action opened the map from addon code, so the whole map refresh ran tainted. The action is removed; settings that used it are set to "Nothing". The M key opens the map as before.
  - Dragging the resize grip refits the map canvas from addon code. Afterwards SquareMap now offers a UI reload, after which Blizzard applies the saved size itself, untainted. The grip is disabled in combat.
- The blocked-action message is printed only once per function and session, and says when the world map was changed from addon code in this session.

## 1.4.0 - 2026-11-25

- New: layout editor for the minimap (`/sqm layout`, SquareMap > Actions > Edit layout, or as a click action on the map). Drag the mail icon, crafting orders, tracking, calendar, clock, addon compartment, instance difficulty, zoom buttons, day/night indicator, expansion summary, event button, coordinates and the addon button collector anywhere around the map.
  - Selection boxes use Blizzard's Edit Mode art; the dialog uses Blizzard's dialog frame.
  - Snapping to a 4 px grid, the centre lines and the map edges (can be turned off).
  - Right click on an element puts it back; "Reset all" restores the default layout.
  - Hidden elements (no mail, outside instances, ...) are shown faded so they can be placed too.
  - Positions are stored relative to the map size, so a layout keeps its shape when the map is resized. Elements moved out of the header free their room for the zone name.

## 1.3.2 - 2026-11-25

- Fixed: "An action was blocked because of taint from SquareMap - IsUserOAuthed()" in the settings window (Social > Discord, or search results). The settings list reuses its control frames across all categories; the button controls on the SquareMap page tainted them, and Blizzard's Discord button later reused one. The buttons (choose buttons, button order, reset) now sit on their own page, SquareMap > Actions, built from SquareMap's own frames.

## 1.3.1 - 2026-11-25

- Fixed: sharing a map pin (shift-click) showed "SquareMap has been blocked from an action" for CopyToClipboard(). The world map module ran Blizzard's map code from addon code on every open (canvas refit for the custom size, switching to the cave map), and pins created meanwhile were tainted.
  - The custom window size is now set right after Blizzard sets its own size, so Blizzard refits the canvas itself in secure code. Only a live drag of the grip still refits from addon code.
  - Opening the map no longer switches to the cave map; Blizzard's map already does that inside a cave.
  - Zooming into cave maps is now opt-in (World map options), with a note about the taint.

## 1.3.0 - 2026-11-25

- World map caves, reworked: instead of drawing caves into the zone map, zooming in over a cave (one more scroll at the closest zoom) opens Blizzard's cave map, and one more scroll out at the widest zoom goes back to the zone. Opening the map inside a cave shows the cave map.
- Fixed: the world map resize grip was hard to grab. Blizzard's border frame lay over it, so only a pixel outside the frame reacted. The grip now sits above the border and has a larger hit area.

## 1.2.0 - 2026-11-25

- World map, reworked after feedback:
  - New: caves and buildings. When you zoom into a zone map, the cave and building maps of that zone are drawn into it, and they fade in while zooming.
  - New: resize grip at the bottom right of the windowed map. It changes the window size, not the UI scale, so text keeps its size. Right click on the grip restores the default size.
  - Removed the seamless zoom between maps and the scale slider.

## 1.1.0 - 2026-11-25

- New: world map improvements, built on Blizzard's own map with hooks only.
  - Seamless zoom: at the closest zoom, one more scroll opens the zone, cave or dungeon map under the cursor. At the widest zoom, one more scroll goes up one map.
  - Scale for the windowed world map.
  - Player and cursor coordinates under the map.

## 1.0.6 - 2026-11-25

- The click actions are back: tracking menu, calendar and world map, plus a new "SquareMap options" action. The blocked popup turned out to come from the ping listener (fixed in 1.0.5), not from these actions. The world map is not opened in combat, because the game blocks that.
- Right click opens the tracking menu again, also for settings that 1.0.1 to 1.0.5 had reset to the ping.

## 1.0.5 - 2026-11-25

- Fixed: "SquareMap has been blocked from an action only available to the Blizzard UI" at login. SquareMap listened for minimap pings (to show who pinged), and registering that ping callback is reserved for Blizzard code in this client. The "show who pings" feature is removed.

## 1.0.4 - 2026-11-25

- Removed the "tracking menu" click action: opened from addon code, the menu's entries (which cast tracking spells) are tainted and get blocked. Use the tracking button in the header instead. Saved settings fall back to the ping.
- Diagnostics: the blocked message shows the SquareMap version.

## 1.0.3 - 2026-11-25

- Diagnostics: when the game blocks an action from SquareMap, the blocked function is named in chat.
- Diagnostics: the message also lists the last SquareMap calls before the block.

## 1.0.2 - 2026-11-25

- New: the header (zone name, clock, calendar) stretches over the full width of the map. The option "Full width header" turns it off. With the full header the mail icon sits in the map corner.
- Fixed: in Edit Mode the selection box was much larger than the square map, and the map sat off center. The minimap frame now hugs the map and its header, and the map is centered in it.
- Fixed: the addon button window was too short for the frame art when it held a single row, so the side edges stuck out above and below the frame. The window now measures the frame corners and keeps the buttons centered.

## 1.0.1 - 2026-11-25

- Fixed: the addon button window stayed empty. LibDBIcon pins its buttons to a fixed strata, so they were drawn behind the window.
- Fixed: "SquareMap has been blocked from an action only available to the Blizzard UI". SquareMap no longer replaces the minimap click handler (it only adds to it), no longer runs Blizzard layout code itself, no longer overwrites the global popup table and never collects Blizzard's own frames.
- New: header position (above or below the map) and header distance. The header now sits right on the map frame; mail moves next to the header and the addon compartment next to the calendar so nothing hangs over the map.
- New: drag buttons inside the addon button window to rearrange them. The order is saved; "Sort by name" in the options restores the alphabetical order.
- Removed the calendar and world map click actions: opening those panels from addon code spreads taint. Saved settings fall back to the default.

## 1.0.0 - 2026-11-25

First release.

- Square minimap built on Blizzard's own minimap, with all of its buttons and indicators.
- Frame styles from Blizzard's nine-slice art, size, frame thickness and distance.
- Addon button collector with a Blizzard-styled window, grid or list layout and a button picker.
- Extras: ping names, instance info, north marker, auto zoom out, header on mouseover, combat opacity,
  mouse button actions, key bindings, addon compartment entry.
- Options in the game's settings window, German and English.
