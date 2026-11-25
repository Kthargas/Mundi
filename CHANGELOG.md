# Changelog

## 1.0.1 - 2026-11-25

- Fixed: the addon button window stayed empty. LibDBIcon pins its buttons to a fixed strata, so they were drawn behind the window.
- Fixed: "SquareMap has been blocked from an action only available to the Blizzard UI". SquareMap no longer replaces the minimap click handler (it only adds to it), no longer runs Blizzard layout code itself, no longer overwrites the global popup table and never collects Blizzard's own frames.
- Removed the calendar and world map click actions: opening those panels from addon code spreads taint. Saved settings fall back to the default.

## 1.0.0 - 2026-11-25

First release.

- Square minimap built on Blizzard's own minimap, with all of its buttons and indicators.
- Frame styles from Blizzard's nine-slice art, size, frame thickness and distance.
- Addon button collector with a Blizzard-styled window, grid or list layout and a button picker.
- Extras: ping names, instance info, north marker, auto zoom out, header on mouseover, combat opacity,
  mouse button actions, key bindings, addon compartment entry.
- Options in the game's settings window, German and English.
