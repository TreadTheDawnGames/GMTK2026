extends SceneTree

## How it works:
## - Loads the configured entry scene and production mining scene.
## - Instantiates mining long enough for code-owned signal wiring to run.
## - Verifies the composition root's required gameplay dependencies.
## - Resolves one real terrain dig through the production TerrainManager.
## - Exits nonzero on any failed contract so agents get a fast merge gate.
## - This intentionally stays small; detailed behavior remains in local_tests.
## - The invariant is that a parseable game can complete one mining mutation.

const MINING_SCENE: PackedScene = preload(
	"res://Scenes/mining/mining_proof.tscn"
)

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_verify_entry_scene()
	await _verify_mining_scene()
	if _failures.is_empty():
		print("SMOKE_VERIFY_PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("SMOKE_VERIFY_FAIL: %s" % failure)
	quit(1)


func _verify_entry_scene() -> void:
	var entry_scene_path := ProjectSettings.get_setting(
		"application/run/main_scene",
		""
	) as String
	_expect(
		not entry_scene_path.is_empty(),
		"application/run/main_scene must be configured."
	)
	if entry_scene_path.is_empty():
		return
	_expect(
		ResourceLoader.exists(entry_scene_path, "PackedScene"),
		"Configured entry scene must resolve: %s" % entry_scene_path
	)
	var entry_scene := ResourceLoader.load(
		entry_scene_path,
		"PackedScene"
	) as PackedScene
	_expect(
		entry_scene != null,
		"Configured entry scene must parse: %s" % entry_scene_path
	)


func _verify_mining_scene() -> void:
	var game_root := MINING_SCENE.instantiate()
	root.add_child(game_root)
	await process_frame
	await process_frame

	var mining_scene := game_root.get_node_or_null("MiningScene")
	var terrain_manager := game_root.get_node_or_null(
		"MiningScene/TerrainManager"
	) as TerrainManager
	var terrain_renderer := game_root.get_node_or_null(
		"MiningScene/TerrainLayerRenderer"
	) as TerrainLayerRenderer
	var scene_wiring := game_root.get_node_or_null(
		"MiningScene/Systems/SceneWiring"
	) as MiningSceneWiring
	var mining_controller := game_root.get_node_or_null(
		"MiningScene/Systems/MiningController"
	) as MiningController

	_expect(mining_scene != null, "MiningScene root must exist.")
	_expect(terrain_manager != null, "TerrainManager must exist.")
	_expect(terrain_renderer != null, "TerrainLayerRenderer must exist.")
	_expect(scene_wiring != null, "MiningSceneWiring must exist.")
	_expect(mining_controller != null, "MiningController must exist.")
	if (
		terrain_manager == null
		or terrain_renderer == null
		or scene_wiring == null
		or mining_controller == null
	):
		game_root.queue_free()
		await process_frame
		return

	_expect(
		scene_wiring.terrain_manager == terrain_manager,
		"SceneWiring must reference the production TerrainManager."
	)
	_expect(
		scene_wiring.terrain_renderer == terrain_renderer,
		"SceneWiring must reference the production TerrainLayerRenderer."
	)
	_expect(
		scene_wiring.mining_controller == mining_controller,
		"SceneWiring must reference the production MiningController."
	)
	_expect(
		terrain_manager.view_position_changed.is_connected(
			terrain_renderer._on_view_position_changed
		),
		"View changes must be wired to terrain streaming."
	)
	var music_manager := root.get_node_or_null("MusicManager")
	_expect(music_manager != null, "MusicManager autoload must exist.")
	if music_manager != null:
		_expect(
			scene_wiring.combo_director.intensity_changed.is_connected(
				Callable(music_manager, &"_on_intensity_changed")
			),
			"Combo intensity must be wired to the music manager."
		)

	var impact_cell := Vector2i(
		terrain_manager.config.terrain_width_cells / 2,
		terrain_manager.config.initial_surface_row
	)
	var was_solid := terrain_manager.is_solid_cell(impact_cell)
	var dig_result := terrain_manager.dig_tunnel(impact_cell, 1, 0)
	_expect(was_solid, "Smoke-test impact cell must begin solid.")
	_expect(
		dig_result.cells_removed > 0,
		"One production dig must remove terrain."
	)
	_expect(
		not terrain_manager.is_solid_cell(impact_cell),
		"Removed terrain must become logically open."
	)

	game_root.queue_free()
	await process_frame


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)
