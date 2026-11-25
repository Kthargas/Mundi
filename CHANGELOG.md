# Changelog

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
