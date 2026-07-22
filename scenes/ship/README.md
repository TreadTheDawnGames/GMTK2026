# Spaceship authoring

Open `spaceship_pack_gallery.tscn` to see every imported source sheet at nearest-neighbor scale.

`spaceship_prefab.tscn` is the current playable ship. It is a tight vertical hull made from independently movable `MainDeck`, `SternCargoDeck`, and `AftCrewDeck` sections. `CargoHallway` and `AftHallway` occupy the exact gaps between sections: the artwork meets at its boundaries without overlapping. The cyan markers show the authored section connections. The scene also contains one continuous `NavigationRegion2D`, a player spawn, room spawn markers, and a crew spawn area.

Duplicate the prefab before making a different ship layout. Move whole section nodes, keep hallways short, align connections on the 16-pixel base grid, and redraw the navigation polygon in Godot's 2D editor after changing the layout.

The source art uses a 16-pixel base grid. Keep texture filtering set to Nearest when adding sprites from the sheets.

The playable `spaceship_level.tscn` adds two selectable starter crew. Left-click selects a crew member, Shift+left-click adds or removes crew from the selection, and right-click issues a navigation order. Pan with WASD, arrow keys, or middle-mouse drag; zoom with the mouse wheel.
