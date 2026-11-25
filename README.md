<p align="center">
  <img src="docs/logo.png" alt="Mundi logo" width="128" height="128">
</p>

<h1 align="center">Mundi</h1>

<p align="center"><em>The Map, but squared</em> · formerly SquareMap</p>

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
own settings window (Esc > Options > AddOns > Mundi, with the pages Header, Addon buttons, World map and Actions).

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
- Header: one bar with a square field at each end and three text fields in between. Each field holds one function (tracking, calendar, day/night, addon compartment or the Mundi addon button) as a bare icon that is part of the header; everything else stays a normal, movable element. The text fields show zone name, clock, local or server time, gold, latency, frame rate, coordinates, durability or free bag slots. The header background can be hidden.
- Layout editor (`/mundi layout`): drag every minimap button and display (mail, tracking, calendar, clock, zoom, ...) to any spot around the map, change its size (mouse wheel) and layer (Shift + mouse wheel), and change every setting of the map, header and other elements right there, with Blizzard's Edit Mode look.
- Optionally hide Blizzard's addon compartment, which mostly duplicates the collected buttons.
- Key bindings for the addon button window and the options; entry in the addon compartment.

## Installation

Copy this folder into `World of Warcraft\_forever_\Interface\AddOns\` and name it `Mundi`
(the folder name has to match `Mundi.toc`).

### Coming from SquareMap

Mundi is the new name of SquareMap. Delete the old `SquareMap` folder from `Interface\AddOns` (if it is still
there, Mundi switches it off and asks for a reload). To keep your settings, rename
`WTF\Account\<ACCOUNT>\SavedVariables\SquareMap.lua` to `Mundi.lua` before you log in; Mundi takes them over.
Key bindings have to be set again, and the command is now `/mundi`.

## Commands

| Command | What it does |
| --- | --- |
| `/mundi` | Open the options (Esc > Options > AddOns > Mundi) |
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
