# Ship navigation tests

Run the permanent ship navigation coverage and crew traversal check from the project root:

```powershell
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/ship_navigation_test.gd
godot --headless --path . --script res://tests/ship_selection_test.gd
```

The import pass keeps generated Godot resources and global script classes current. The navigation test verifies every navigation polygon in every authored ship section, checks the expected transition count, and drives both real crew members from their authored spawn points through the longest ship routes. The selection test covers click, drag-box, and Shift-additive crew selection.
