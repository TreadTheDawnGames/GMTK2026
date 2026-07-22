# Spaceship authoring

Open `ship_builder.tscn` to edit the current base ship. This is a manually authored scene: there is no procedural ship generation.

`ship_builder.tscn` is the single ship-layout scene. Every section in it owns navigation that follows the section automatically.

Drag reusable `.tscn` sections from `scenes/ship/sections/` into `ShipBuilder`. Every section snaps to an 8-pixel alignment grid in the editor so transparent texture margins can overlap correctly. Move complete section instances and align matching cyan connection markers; connected artwork should meet at the marker without overlapping. The section navigation and connector links update automatically when a section moves.

Available sections include the main hull, cargo room, crew room, airlock room, horizontal hallway, vertical hallway, and a right-to-down hallway corner. Duplicate or inherit a section scene when another connector layout is needed.

Drag `objectives/task_placeholder.tscn` into a ship section to place a typing objective. It fits inside one 32-pixel in-game grid cell. Left-clicking it opens the keyboard typing task, and its `WorkPoint` marker remains available for crew navigation.

Each section owns a `NavigationRegion2D` fitted to the visible, nontransparent silhouette of its artwork. Walls inside that silhouette are intentionally ignored for this prototype. At runtime, `ShipBuilder` creates short navigation links wherever compatible cyan markers occupy the same position.

The source art uses a 16-pixel base grid. Keep texture filtering set to Nearest when adding sprites from the sheets. Open `spaceship_pack_gallery.tscn` to view every imported source sheet.

The playable `spaceship_level.tscn` adds MRdiabetes and MrDpwnSyndrome. Left-click selects a crew member, Shift+left-click adds or removes crew from the selection, and right-click issues a navigation order. Pan with WASD, arrow keys, or middle-mouse drag; zoom with the mouse wheel.
