extends SceneTree

## How it works:
## - Loads the configured entry scene and production mining scene.
## - Instantiates mining long enough for code-owned signal wiring to run.
## - Verifies the composition root's required gameplay dependencies.
## - Resolves one real terrain dig through the production TerrainManager.
## - Confirms damaged terrain restores byte-exactly without replaying history.
## - Exits nonzero on any failed contract so agents get a fast merge gate.
## - This intentionally stays small; detailed behavior remains in local_tests.
## - The invariant is that a parseable game can complete one mining mutation.

const MINING_SCENE: PackedScene = preload(
	"res://Scenes/mining/mining_proof.tscn"
)
const TREASURE_HUNTER_APPEARANCE: CharacterAppearance = preload(
	"res://resources/encounters/treasure_hunter_character_appearance.tres"
)
const TREASURE_HUNTER_FIRST_SEQUENCE: CutsceneSequence = preload(
	"res://resources/cinematics/sequences/treasure_hunter_first_sequence.tres"
)
const TREASURE_HUNTER_TREASURE_SEQUENCE: CutsceneSequence = preload(
	"res://resources/cinematics/sequences/treasure_hunter_treasure_sequence.tres"
)
const TREASURE_HUNTER_TREASURE_CONVERSATION: DialogueConversation = preload(
	"res://resources/dialogue/treasure_hunter_treasure_conversation.tres"
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
	var impact_camera := game_root.get_node_or_null(
		"MiningScene/ImpactCamera"
	) as Camera2D
	var dialogue_director := game_root.get_node_or_null(
		"DialogueDirector"
	) as DialogueDirector
	var scene_wiring := game_root.get_node_or_null(
		"MiningScene/Systems/SceneWiring"
	) as MiningSceneWiring
	var mining_controller := game_root.get_node_or_null(
		"MiningScene/Systems/MiningController"
	) as MiningController
	var encounter_controller := game_root.get_node_or_null(
		"MiningScene/Systems/UpgradeEncounterController"
	) as DepthEncounterController
	var gem_outcrop_field := game_root.get_node_or_null(
		"MiningScene/GemOutcropField"
	) as GemOutcropField
	var miner_rig := game_root.get_node_or_null(
		"MiningScene/MinerRig"
	) as MinerRig
	var hud := game_root.get_node_or_null(
		"MiningScene/HUD"
	) as MiningHud
	var timing_window := game_root.get_node_or_null(
		"MiningScene/HUD/TimingWindow"
	) as TimingWindowTask
	var main_menu := game_root.get_node_or_null(
		"MainMenuLayer/MainMenu"
	) as GameMainMenu
	var run_state := root.get_node_or_null("GameState") as RunState
	var audio_handler := root.get_node_or_null(
		"AudioHandler"
	) as PlayerAudioHandler

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
	# The title camera is wider than gameplay. Cover its real world-space bottom
	# and keep the cinematic bars out until Start, or the menu exposes grey.
	if impact_camera != null and not is_zero_approx(impact_camera.zoom.y):
		var visible_world_bottom := (
			impact_camera.get_screen_center_position().y
			+ root.get_visible_rect().size.y
				* 0.5 / absf(impact_camera.zoom.y)
		)
		var loaded_world_bottom := (
			terrain_manager.config.mining_face_screen_y
			+ (
				float(
					(terrain_renderer._loaded_last_chunk + 1)
					* terrain_manager.config.chunk_height_cells
				)
				- terrain_renderer._current_view_y
			) * terrain_manager.config.terrain_cell_world_size
		)
		_expect(
			loaded_world_bottom >= visible_world_bottom,
			"Title camera must not see below the streamed terrain."
		)
	_expect(
		dialogue_director != null
		and dialogue_director.cinematic_frame != null
		and dialogue_director.cinematic_frame.is_closed(),
		"Title menu must keep the cinematic bars off the live terrain."
	)
	# Sculpt streaming now expands eight authored cells per packed byte. Compare
	# complete representative rows to the authoritative resource so the faster
	# bulk path cannot reverse bit order or change protected-floor collision.
	var sculpt_placements := terrain_manager.get_sculpt_placements()
	_expect(
		not sculpt_placements.is_empty(),
		"Terrain smoke verification requires one authored sculpt."
	)
	if not sculpt_placements.is_empty():
		var sculpt: CutsceneTerrainSculpt = sculpt_placements[0].sculpt
		var logical_mask := (
			terrain_renderer._get_sculpt_logical_mask_image(sculpt, -1)
		)
		var logical_mask_matches := logical_mask != null
		var sample_rows := PackedInt32Array([
			0,
			sculpt.grid_size.y >> 1,
			sculpt.grid_size.y - 1,
		])
		if logical_mask_matches:
			for local_y in sample_rows:
				for local_x in range(sculpt.grid_size.x):
					var expected_solid := sculpt.is_solid_local(
						Vector2i(local_x, local_y)
					)
					var actual_solid := (
						logical_mask.get_pixel(local_x, local_y).a >= 0.5
					)
					if actual_solid != expected_solid:
						logical_mask_matches = false
						break
				if not logical_mask_matches:
					break
		_expect(
			logical_mask_matches,
			"Bulk sculpt decoding changed the authored logical room mask."
		)
	_expect(run_state != null, "GameState autoload must exist.")
	_expect(audio_handler != null, "AudioHandler autoload must exist.")
	_expect(
		mining_controller._game_state == run_state,
		"SceneWiring must inject GameState into MiningController."
	)
	_expect(
		encounter_controller != null
		and encounter_controller._game_state == run_state,
		"SceneWiring must inject GameState into DepthEncounterController."
	)
	_expect(
		gem_outcrop_field != null
		and run_state != null
		and gem_outcrop_field._save_game == run_state.save_game,
		"SceneWiring must inject SaveGame into GemOutcropField."
	)
	_expect(
		hud != null
		and run_state != null
		and hud._save_game == run_state.save_game,
		"SceneWiring must inject SaveGame into MiningHud."
	)
	_expect(
		main_menu != null
		and run_state != null
		and main_menu._save_game == run_state.save_game,
		"SceneWiring must inject SaveGame into GameMainMenu."
	)
	_expect(
		miner_rig != null and miner_rig._audio_handler == audio_handler,
		"SceneWiring must inject AudioHandler into MinerRig."
	)
	_expect(
		timing_window != null
		and timing_window._audio_handler == audio_handler,
		"SceneWiring must inject AudioHandler into TimingWindowTask."
	)
	_expect(
		TREASURE_HUNTER_APPEARANCE.pose_set != null
		and TREASURE_HUNTER_APPEARANCE.pose_set.has_pose(&"idle")
		and TREASURE_HUNTER_APPEARANCE.pose_set.has_pose(&"walk")
		and TREASURE_HUNTER_APPEARANCE.pose_set.has_pose(&"hit")
		and TREASURE_HUNTER_APPEARANCE.pose_set.has_pose(&"no_pickaxe"),
		"Treasure Hunter must provide idle, walk, hit, and no-pickaxe poses."
	)
	var has_mining_contact_pose := false
	for beat: CutsceneBeat in TREASURE_HUNTER_FIRST_SEQUENCE.beats:
		if beat.kind == CutsceneBeat.Kind.POSE and beat.pose == &"hit":
			has_mining_contact_pose = true
			break
	_expect(
		has_mining_contact_pose,
		"Treasure Hunter's first arrival must show his mining contact pose."
	)
	_expect(
		not TREASURE_HUNTER_TREASURE_CONVERSATION.lines.is_empty()
		and TREASURE_HUNTER_TREASURE_CONVERSATION.lines[-1].speaker_pose
			== &"no_pickaxe",
		"Treasure Hunter must give up his pickaxe on the handoff line."
	)
	var exits_without_pickaxe := false
	for beat: CutsceneBeat in TREASURE_HUNTER_TREASURE_SEQUENCE.beats:
		if (
			beat.kind == CutsceneBeat.Kind.MOVE
			and beat.target_marker == &"Exit"
			and beat.pose == &"no_pickaxe"
		):
			exits_without_pickaxe = true
			break
	_expect(
		exits_without_pickaxe,
		"Treasure Hunter must leave and reach the cafe without his pickaxe."
	)
	_expect(
		run_state != null
		and run_state.depth_changed.is_connected(
			scene_wiring._on_run_depth_changed
		),
		"Run progress must fan out through SceneWiring."
	)
	_expect(
		main_menu != null
		and main_menu.start_requested.is_connected(
			scene_wiring._on_start_requested
		),
		"Starting a run must cross the searchable SceneWiring boundary."
	)
	_expect(
		run_state != null
		and run_state.save_game != null
		and timing_window != null
		and run_state.save_game.settings_applied.is_connected(
			timing_window.set_bounce_muted
		),
		"Saved bounce settings must route explicitly to TimingWindowTask."
	)

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
	# Drain only the bounded production scheduler, then retire and restore the
	# impacted chunk. This catches stale or lossy snapshot changes; detailed
	# timing remains in the non-blocking terrain benchmark so smoke stays fast.
	var impact_chunk_index := terrain_renderer._world_row_to_chunk(
		impact_cell.y
	)
	for _terrain_frame in range(64):
		terrain_renderer._process(1.0 / 60.0)
		if terrain_renderer._compressed_chunk_snapshots.has(
			impact_chunk_index
		):
			break
	var has_terrain_snapshot := (
		terrain_renderer._compressed_chunk_snapshots.has(
			impact_chunk_index
		)
	)
	_expect(
		has_terrain_snapshot,
		"Settled damaged terrain must produce a bounded review snapshot."
	)
	if (
		has_terrain_snapshot
		and terrain_renderer._active_chunks.has(impact_chunk_index)
	):
		var original_mask_data: Array[PackedByteArray] = []
		for mask_image: Image in terrain_renderer._active_chunks[
			impact_chunk_index
		].mask_images:
			original_mask_data.append(mask_image.get_data())
		terrain_renderer._unload_chunk(impact_chunk_index)
		terrain_renderer._load_chunk(impact_chunk_index)
		var restored_images: Array[Image] = terrain_renderer._active_chunks[
			impact_chunk_index
		].mask_images
		for layer_index in range(original_mask_data.size()):
			_expect(
				restored_images[layer_index].get_data()
					== original_mask_data[layer_index],
				(
					"Review snapshot restore must preserve every byte "
					+ "of terrain layer %d."
				) % layer_index
			)

	game_root.queue_free()
	await process_frame


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)
