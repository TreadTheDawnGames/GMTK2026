# Spaceship authoring

Open `ship_builder.tscn` to edit the current base ship. This is a manually authored scene: there is no procedural ship generation.

Drag reusable `.tscn` sections from `scenes/ship/sections/` into `ShipBuilder`. Every section snaps to the 16-pixel source-art grid in the editor. Move complete section instances and align matching cyan connection markers; connected artwork should meet at the marker without overlapping.

Available sections include the main hull, cargo room, crew room, airlock room, horizontal hallway, vertical hallway, and a right-to-down hallway corner. Duplicate or inherit a section scene when another connector layout is needed.

Drag `objectives/task_placeholder.tscn` into a ship section to mark a future task location. It fits inside one 32-pixel in-game grid cell, and its `WorkPoint` marker is ready to become the crew navigation target when task behavior is added.

Each section owns a `NavigationRegion2D` covering the complete bounds of its artwork. Walls are intentionally ignored for this prototype, so the entire visible module is walkable. At runtime, `ShipBuilder` creates short navigation links wherever compatible cyan markers occupy the same position. Task behavior is not part of this builder yet.

The source art uses a 16-pixel base grid. Keep texture filtering set to Nearest when adding sprites from the sheets. Open `spaceship_pack_gallery.tscn` to view every imported source sheet.

The playable `spaceship_level.tscn` adds MRdiabetes and MrDpwnSyndrome. Left-click selects a crew member, Shift+left-click adds or removes crew from the selection, and right-click issues a navigation order. Pan with WASD, arrow keys, or middle-mouse drag; zoom with the mouse wheel.
