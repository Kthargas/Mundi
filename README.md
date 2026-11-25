<h1 align="center">SquareMap</h1>

<p align="center">
  A square minimap for <strong>World of Warcraft: Forever</strong> that looks like Blizzard made it,<br>
  with one button that collects all addon minimap buttons into a window.
</p>

---

## What it does

SquareMap keeps Blizzard's own minimap and only changes what has to change for a square map. Everything the
game puts around the minimap stays where you expect it: zone name, clock, calendar, tracking menu, mail,
addon compartment, day and night indicator, coordinates, zoom buttons and the mouse-wheel zoom. Edit Mode
still moves and scales the minimap.

No custom textures are shipped. The frame is drawn from Blizzard's own nine-slice art (the same pieces used by
dialogs, tooltips and panels), the windows use Blizzard's frame templates and the options live in the game's
own settings window.

### Minimap
- Square map, size 140 to 400 pixels.
- Frame styles from the game's art: gold dialog frame (default), tooltip, metal, simple metal or a thin line.
  Thickness and distance can be tuned.
- Zoom buttons in the lower right corner: on mouseover (like Blizzard), always or never.
- Rotate the minimap and show coordinates (Blizzard settings, also reachable here), coordinates below or
  inside the map.
- Works with LibDBIcon: addons that are not collected place their buttons on the square edge.

### World map

- Caves (opt-in): scroll in once more at the closest zoom over a cave to open its map, scroll out once more to return. Switching maps from an addon taints the world map, so this is off by default; inside a cave Blizzard's map opens on the cave anyway.
- Resize grip at the bottom right of the windowed map (window size, not UI scale; right click resets).
- Player and cursor coordinates under the map.

### Addon button collector
- One classic minimap button collects the buttons of other addons (LibDBIcon buttons and other named
  buttons on the minimap). Map pins of Questie, HandyNotes, GatherMate and similar are left alone.
- Left click opens a window with the buttons, right click opens the options, shift + right click opens the
  button picker, drag moves the button along the edge of the map.
- Window: Blizzard panel with title or compact tooltip style, grid or list (icon and name), columns, button
  size, spacing, next to the button or free to drag, close after a click, close when the mouse leaves,
  closes with Escape.
- Drag the buttons inside the window to rearrange them; the order is saved. Buttons that stay on the
  minimap keep their own LibDBIcon dragging along the edge.
- Button picker: choose which buttons are collected and which stay on the minimap.
- `/sqm add <FrameName>` collects a button the automatic search did not catch.

### Extras
- Instance info (group size and difficulty) in dungeons and raids, since Forever has no difficulty banner.
- North marker on the edge while the minimap rotates.
- Auto zoom out after a few seconds.
- Header (zone, clock, calendar, buttons) only on mouseover; mail stays visible.
- Lower opacity in combat.
- Right and middle click on the map: tracking menu, calendar, world map, addon button window, options or just the Blizzard ping.
- Key bindings for the addon button window and the options; entry in the addon compartment.

## Installation

Copy this folder into `World of Warcraft\_forever_\Interface\AddOns\` and name it `SquareMap`
(the folder name has to match `SquareMap.toc`).

## Commands

| Command | What it does |
| --- | --- |
| `/sqm` | Open the options (Esc > Options > AddOns > SquareMap) |
| `/sqm buttons` | Show or hide the addon button window |
| `/sqm manage` | Choose which addon buttons are collected |
| `/sqm scan` | Search for addon buttons again |
| `/sqm add <FrameName>` | Collect a button by its frame name |
| `/sqm atlas` | List which Blizzard art pieces this client knows (for bug reports) |
| `/sqm reset` | Reset all settings |

## Languages

German and English.

## License

MIT, see [LICENSE](LICENSE).
