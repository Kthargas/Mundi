<p align="center">
  <img src="docs/logo.png" alt="Mundi logo" width="128" height="128">
</p>

<h1 align="center">Mundi</h1>

<p align="center"><em>The Map, but squared</em></p>

<p align="center">
  A square minimap for <strong>World of Warcraft: Forever</strong> that looks like Blizzard made it,<br>
  with one button that collects all addon minimap buttons into a window.
</p>

---

## What it does

Mundi keeps Blizzard's own minimap and only changes what has to change for a square map. Everything the
game puts around the minimap stays where you expect it: zone name, clock, calendar, tracking menu, mail,
addon compartment, day and night indicator, coordinates, zoom buttons and the mouse-wheel zoom. Edit Mode
still moves and scales the minimap.

The only own file is the Mundi logo. The frame is drawn from Blizzard's own nine-slice art (the same pieces used by
dialogs, tooltips and panels), the windows use Blizzard's frame templates and the options live in the game's
own settings window (Esc > Options > AddOns > Mundi, with the pages Header, Addon buttons, World map, Resource alert and Actions).

### Minimap
- Square map, size 140 to 400 pixels.
- Frame styles from the game's art: gold dialog frame (default), tooltip, metal, simple metal or a thin line.
  Thickness and distance can be tuned.
- Zoom buttons in the lower right corner: on mouseover (like Blizzard), always or never.
- Show coordinates (Blizzard setting, also reachable here; the map always keeps north up, rotation is switched off), coordinates below or
  inside the map.
- Works with LibDBIcon: addons that are not collected place their buttons on the square edge.

### World map

- Caves (opt-in): scroll in once more at the closest zoom over a cave to open its map, scroll out once more to return. Switching maps from an addon taints the world map, so this is off by default; inside a cave Blizzard's map opens on the cave anyway.
- Resize grip at the bottom right of the windowed map (window size, not UI scale; right click resets). After resizing, Mundi offers a UI reload so Blizzard applies the size itself without taint.
- Player and cursor coordinates under the map.
- Fade the map while moving (Blizzard's setting, reachable from Mundi's options).
- Level ranges: next to the zone name under the cursor and in the middle of every zone on a continent map, coloured by your level like quests. Both can be switched off.

### Resource alert (opt-in)
- Sound and message when the minimap shows a herb, an ore or a treasure your tracking finds (Find Herbs, Find Minerals, Find Treasure), with the direction (north, southeast, ...).
- The game has no list of the tracking dots, so Mundi asks the minimap what lies under every point of the map (`Minimap:UpdateMouseoverAtPoint` and `C_TooltipInfo.GetMinimapMouseover`), a few dozen points per frame. The map does not move and the mouse is untouched. It only scans while one of the finders is on and not in combat, by default only while you move.
- Scan interval, sound, message on screen or in chat, repeat time.
- Report everything except your group and quest progress, or only names from a list: `/mundi alert add Mithril`, `/mundi alert ignore <name>`, `/mundi alert list`. `/mundi alert test` scans once and prints every name it reads.

### Addon button collector
- One classic minimap button with the Mundi logo (or a bag, gears, scroll, map or chest) collects the buttons of other addons (LibDBIcon buttons and other named
  buttons on the minimap). Map pins of Questie, HandyNotes, GatherMate and similar are left alone.
- Left click opens a window with the buttons, right click opens the options, shift + right click opens the
  button picker, drag moves the button along the edge of the map.
- Window: Blizzard panel with title or compact tooltip style, one button per row with its name, button
  size, spacing, next to the button or free to drag, close after a click, close when the mouse leaves,
  closes with Escape.
- Drag the buttons inside the window to rearrange them; the order is saved. Buttons that stay on the
  minimap keep their own LibDBIcon dragging along the edge.
- Button picker: choose which buttons are collected and which stay on the minimap.
- `/mundi add <FrameName>` collects a button the automatic search did not catch.

### Extras
- Instance info (group size and difficulty) in dungeons and raids, since Forever has no difficulty banner.
- Auto zoom out after a few seconds.
- Header (zone, clock, calendar, buttons) only on mouseover; mail stays visible.
- Lower opacity in combat.
- Right and middle click on the map: tracking menu, calendar, addon button window, layout editor, options or just the Blizzard ping.
- Header text fields with tooltips and clicks: gold of all your characters and this session's gain, latency and addon memory, durability per item (click: character), free slots per bag (click: bags), local and server time (click: calendar).
- Instance info tooltip with your saved instances (bosses killed, time to reset).
- Own settings per character (optional).
- Header: one bar with a square field at each end and three text fields in between. Each field holds one function (tracking, calendar, day/night, addon compartment or the Mundi addon button) as a bare icon that is part of the header; everything else stays a normal, movable element. The text fields show zone name, clock, local or server time, gold, latency, frame rate, coordinates, durability or free bag slots. The header background can be hidden.
- Layout editor (`/mundi layout`): drag every minimap button and display (mail, tracking, calendar, clock, zoom, ...) to any spot around the map, change its size (mouse wheel) and layer (Shift + mouse wheel), and change every setting of the map, header and other elements right there, with Blizzard's Edit Mode look.
- Optionally hide Blizzard's addon compartment, which mostly duplicates the collected buttons.
- Key bindings for the addon button window and the options; entry in the addon compartment.

## Installation

Copy this folder into `World of Warcraft\_forever_\Interface\AddOns\` and name it `Mundi`
(the folder name has to match `Mundi.toc`).

## Commands

| Command | What it does |
| --- | --- |
| `/mundi` | Open the options (Esc > Options > AddOns > Mundi) |
| `/mundi alert` | Resource alert on or off; `add`, `remove`, `ignore`, `unignore`, `list`, `test` (see `/mundi alert help`) |
| `/mundi help` | List all commands |
| `/mundi layout` | Open the layout editor |
| `/mundi buttons` | Show or hide the addon button window |
| `/mundi manage` | Choose which addon buttons are collected |
| `/mundi scan` | Search for addon buttons again |
| `/mundi add <FrameName>` | Collect a button by its frame name |
| `/mundi reset` | Reset all settings (asks first) |

## Languages

German and English.

## License

MIT, see [LICENSE](LICENSE).
