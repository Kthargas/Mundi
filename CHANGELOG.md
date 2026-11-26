# Changelog

## 1.1.0 - 2026-11-26

### Resource alert
- New, off by default: sound and message (screen or chat) when the minimap shows a herb, an ore or anything else your tracking finds, with its direction.
- Reads the minimap's tooltip by moving the invisible map under the cursor for a few frames, so the map blinks briefly. Only while the cursor rests on the game world, never in combat or during mouselook, by default only while moving.
- Options page "Resource alert" (method, interval, sound, repeat time, filter) and `/mundi alert` (on/off, `add`, `remove`, `ignore`, `unignore`, `list`, `test`).

## 1.0.0 - 2026-11-25

First release.

### Minimap
- Square minimap (140 to 400 pixels) that keeps all of Blizzard's own elements: zone name, clock, calendar, tracking, mail, addon compartment, day and night, coordinates, zoom buttons and mouse-wheel zoom. Edit Mode still moves and scales it.
- Frame styles from Blizzard's own art (gold dialog frame, tooltip, metal, simple metal, thin line) with thickness and distance.
- Zoom buttons on mouseover, always or never; auto zoom out; lower opacity in combat.
- Right and middle click actions: tracking menu, calendar, addon button window, layout editor, options or Blizzard's ping.
- Instance info (group size and difficulty) with a tooltip of your saved instances.

### Header
- One bar with a square field at each end (tracking, calendar, day/night, addon compartment or Mundi's addon button) and three text fields: zone name, clock, local or server time, gold, latency, frame rate, coordinates, durability or free bag slots.
- Tooltips and clicks on the text fields: gold of all your characters and this session's gain (click: bags), latency, bandwidth and addon memory, durability per item (click: character), free slots per bag (click: bags), local and server time (click: calendar).
- Header only on mouseover (mail stays visible), header background can be hidden.

### Layout editor
- `/mundi layout`: drag every minimap element to any spot around the map, change its size and layer, switch single elements off and change every setting right there, in Blizzard's Edit Mode look.

### Addon button collector
- One minimap button collects the buttons of other addons into a window (Blizzard panel or compact tooltip style), with drag to reorder, a button picker and `/mundi add <FrameName>` for buttons the search misses.

### World map
- Level ranges: next to the zone name under the cursor and in the middle of every zone on a continent map, coloured by your level like quests.
- Resize grip for the windowed map, player and cursor coordinates under the map, fade while moving.
- Optional: scroll into cave maps at the closest zoom.

### General
- Options in the game's own settings (Esc > Options > AddOns > Mundi), own settings per character (optional), key bindings, addon compartment entry, English and German.
