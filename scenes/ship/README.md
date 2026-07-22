# Spaceship authoring

Open `spaceship_pack_gallery.tscn` to see every imported source sheet at nearest-neighbor scale.

`spaceship_prefab.tscn` is the current playable ship. It uses a region of the original ship-structure sheet, an authored `NavigationRegion2D`, a player spawn marker, and a crew spawn area. Duplicate the prefab before making a different ship layout, then adjust the `ShipArtwork` region and redraw the navigation polygon in Godot's 2D editor.

The source art uses a 16-pixel base grid. Keep texture filtering set to Nearest when adding sprites from the sheets.
