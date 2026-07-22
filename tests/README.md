# Ship navigation tests

Run the permanent ship navigation coverage and crew traversal check from the project root:

```powershell
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/ship_navigation_test.gd
```

The import pass keeps generated Godot resources and global script classes current. The test verifies every navigation polygon in every authored ship section, checks the expected transition count, and drives both real crew members from their authored spawn points through the longest ship routes.
