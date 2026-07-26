extends SceneTree

## How it works:
## - Loads the configured entry scene and production mining scene.
## - Instantiates mining long enough for code-owned signal wiring to run.
## - Verifies the composition root's required gameplay dependencies.
## - Resolves one real terrain dig through the production TerrainManager.
## - Confirms damaged terrain restores byte-exactly without replaying history.
## - Checks fractional review travel, encounter stops, and upward preloading.
## - Guards the sample-neutral shader path that smooths buried cut contours.
## - Confirms a real dig starts one bounded allocation-free crush transition.
## - Exits nonzero on any failed contract so agents get a fast merge gate.
## - This intentionally stays small; detailed behavior remains in local_tests.
## - The invariant is that a parseable game can complete one mining mutation.

const MINING_SCENE: PackedScene = preload(
	"res://Scenes/mining/mining_proof.tscn"
)
const TREASURE_HUNTER_APPEARANCE: CharacterAppearance = preload(
	"res://resources/encounters/treasure_hunter_character_appearance.tres"
)
const ROTINI_APPEARANCE: CharacterAppearance = preload(
	"res://resources/encounters/rutini_character_appearance.tres"
)
const MOODY_TEEN_APPEARANCE: CharacterAppearance = preload(
	"res://resources/encounters/moody_teen_character_appearance.tres"
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
const THIEF_ENCRYPTED_DIALOGUE: EncryptedDialogueConversation = preload(
	"res://resources/dialogue/thief_encrypted_dialogue.tres"
)
const OPENING_SURFACE_CONVERSATION: DialogueConversation = preload(
	"res://resources/dialogue/opening_surface_conversation.tres"
)

var _failures: Array[String] = []
var _presented_line_indices: PackedInt32Array = PackedInt32Array()
var _finished_conversation_ids: Array[StringName] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_verify_headless_history_isolation()
	_verify_entry_scene()
	# Headless smoke cannot judge antialiased pixels. Protect the implementation
	# choice instead: buried contours use the existing raw mask taps for a
	# continuous direction and depth-scaled derivative AA, so smoothing cannot
	# silently regress into extra Web texture samples or a denser terrain mask.
	var terrain_shader_source := FileAccess.get_file_as_string(
		"res://Shaders/terrain_layer.gdshader"
	)
	_expect(
		terrain_shader_source.contains("cut_aa_half_width")
		and terrain_shader_source.contains(
			"neighbor_alpha.z - neighbor_alpha.w"
		)
		and terrain_shader_source.contains(
			"neighbor_alpha.x - neighbor_alpha.y"
		),
		"Buried terrain contours must retain sample-neutral derivative smoothing."
	)
	_expect(
		terrain_shader_source.contains("impact_crush_timing")
		and terrain_shader_source.contains(
			"mask_sample = mix(vec4(1.0), mask_sample, crush_reveal)"
		),
		"Mining impacts must retain the sample-neutral crushed-mask transition."
	)
	# Same reasoning for the mining dust: headless cannot judge whether a cloud
	# shimmers, so protect the three choices that stopped it. The noise domain is
	# measured in world pixels recovered from the instance transform, so a lobe
	# growing or stretching no longer re-scales its own field; the fine octaves
	# fade out by screen footprint instead of aliasing; and the tone bands are
	# softened by their own derivative instead of being hard-stepped.
	var smoke_shader_source := FileAccess.get_file_as_string(
		"res://Shaders/mining_smoke.gdshader"
	)
	_expect(
		smoke_shader_source.contains("MODEL_MATRIX")
		and smoke_shader_source.contains("quad_half_size")
		and smoke_shader_source.contains("cell_span")
		and smoke_shader_source.contains("fwidth"),
		"Mining dust must keep its world-anchored, derivative-aware noise field."
	)
	await _verify_mining_scene()
	_verify_finale_text_resolves()
	if _failures.is_empty():
		print("SMOKE_VERIFY_PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("SMOKE_VERIFY_FAIL: %s" % failure)
	quit(1)


## Prevents local/CI verification from counting as somebody playing the game.
func _verify_headless_history_isolation() -> void:
	if DisplayServer.get_name() != "headless":
		return
	var player_history := root.get_node_or_null(
		"/root/PlayerHistory"
	) as PlayerHistoryRecord
	_expect(
		player_history != null,
		"PlayerHistory autoload must exist for the Thief finale."
	)
	if player_history == null:
		return
	# This specifically guards the benchmark isolation fix: a headless process
	# must not dirty or flush the real user://player_history.cfg on shutdown.
	_expect(
		not player_history.is_processing()
		and not player_history._is_dirty,
		"Headless verification must leave PlayerHistory persistence idle."
	)


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
	_expect(
		MOODY_TEEN_APPEARANCE.texture != null
		and MOODY_TEEN_APPEARANCE.texture.resource_path
			== "res://Assets/Characters/moody_teen/moody_teen.png"
		and MOODY_TEEN_APPEARANCE.horizontal_frames == 1
		and MOODY_TEEN_APPEARANCE.frame == 0
		and MOODY_TEEN_APPEARANCE.art_faces_left,
		"Moody Teen must use Ayden's supplied single-frame character art."
	)
	_expect(
		ROTINI_APPEARANCE.texture != null
		and ROTINI_APPEARANCE.texture.resource_path
			== "res://Assets/Characters/mice/mouse_grey.png",
		"Rotini must use Jared's approved gray rat asset."
	)
	var opening_uses_mr_sitts := (
		OPENING_SURFACE_CONVERSATION.validate().is_empty()
		and OPENING_SURFACE_CONVERSATION.participants.size() == 1
		and OPENING_SURFACE_CONVERSATION.participants[0].slot
			== &"newspaper_reader"
		and OPENING_SURFACE_CONVERSATION.participants[0].display_name
			== "Mr. Sitts"
	)
	for line in OPENING_SURFACE_CONVERSATION.lines:
		opening_uses_mr_sitts = (
			opening_uses_mr_sitts
			and line != null
			and line.speaker_slot == &"newspaper_reader"
		)
	_expect(
		opening_uses_mr_sitts,
		"The surface conversation must present every line as Mr. Sitts."
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
	var run_intro_controller := game_root.get_node_or_null(
		"MiningScene/Systems/RunIntroController"
	) as RunIntroController
	var cutscene_action_presenter := game_root.get_node_or_null(
		"MiningScene/Systems/SceneWiring/CutsceneActionPresenter"
	) as CutsceneActionPresenter
	var arrival_sequence := game_root.get_node_or_null(
		"MiningScene/ArrivalIntro"
	) as ArrivalIntroSequence
	var mining_controller := game_root.get_node_or_null(
		"MiningScene/Systems/MiningController"
	) as MiningController
	var view_controller := game_root.get_node_or_null(
		"MiningScene/Systems/ViewController"
	) as ViewController
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
	var timing_bar_feedback := game_root.get_node_or_null(
		"MiningScene/HUD/TimingBarFeedback"
	) as TimingBarFeedback
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
	_expect(
		cutscene_action_presenter != null,
		"CutsceneActionPresenter must exist under the composition root."
	)
	_expect(mining_controller != null, "MiningController must exist.")
	_expect(view_controller != null, "ViewController must exist.")
	_expect(
		timing_bar_feedback != null,
		"TimingBarFeedback must exist under the mining HUD."
	)
	if timing_bar_feedback != null:
		timing_bar_feedback.combo_bar.value = 4.0
		timing_bar_feedback._on_streak_ended(4)
		timing_bar_feedback._process(
			timing_bar_feedback.combo_loss_step_seconds * 0.5
		)
		_expect(
			is_equal_approx(timing_bar_feedback.combo_bar.value, 4.0),
			"Lost combo bar must hold until its first decay step."
		)
		timing_bar_feedback._process(
			timing_bar_feedback.combo_loss_step_seconds * 0.5
		)
		_expect(
			is_equal_approx(timing_bar_feedback.combo_bar.value, 3.0),
			"Lost combo bar must turn off exactly one segment per step."
		)
		timing_bar_feedback._process(
			timing_bar_feedback.combo_loss_step_seconds * 3.0
		)
		_expect(
			is_zero_approx(timing_bar_feedback.combo_bar.value),
			"Lost combo bar must finish its stepped decay at zero."
		)
	if (
		terrain_manager == null
		or terrain_renderer == null
		or scene_wiring == null
		or mining_controller == null
		or view_controller == null
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
	if dialogue_director != null:
		var art_conversation := DialogueConversation.new()
		art_conversation.conversation_id = &"smoke_textbox_art"
		var expected_textures: Dictionary[StringName, Texture2D] = {
			&"miner": dialogue_director.sparky_textbox_texture,
			&"treasure_hunter": dialogue_director.zeb_textbox_texture,
			&"rutini": dialogue_director.rotini_textbox_texture,
			&"coffee_cat": dialogue_director.quibble_textbox_texture,
			&"cheese_girl": dialogue_director.coco_textbox_texture,
			&"moody_teen": dialogue_director.ayden_textbox_texture,
			&"newspaper_reader": dialogue_director.mr_sitts_textbox_texture,
		}
		for speaker_slot: StringName in expected_textures:
			var participant := DialogueParticipant.new()
			participant.slot = speaker_slot
			participant.display_name = str(speaker_slot)
			art_conversation.participants.append(participant)
		var opening_participant := DialogueParticipant.new()
		opening_participant.slot = &"opening_voice"
		opening_participant.display_name = "..."
		art_conversation.participants.append(opening_participant)
		var art_line := DialogueLine.new()
		art_line.speaker_slot = &"miner"
		art_line.text = "Textbox art smoke check."
		art_conversation.lines.append(art_line)
		var previous_pause_gameplay := dialogue_director.pause_gameplay
		var previous_auto_frame := dialogue_director.auto_frame_conversations
		dialogue_director.pause_gameplay = false
		dialogue_director.auto_frame_conversations = false
		for speaker_slot: StringName in expected_textures:
			art_line.speaker_slot = speaker_slot
			var art_started := dialogue_director.start_conversation(
				art_conversation
			)
			_expect(
				art_started
				and dialogue_director.textbox_art.visible
				and not dialogue_director.fallback_panel.visible
				and not dialogue_director.speaker_label.visible
				and is_equal_approx(
					dialogue_director.bottom_panel.size.y,
					173.0
				)
				and dialogue_director.textbox_art.stretch_mode
					== TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				and absf(
					(
						dialogue_director.bottom_panel.size.x
						/ dialogue_director.bottom_panel.size.y
					)
					-
					(
						float(
							expected_textures[speaker_slot].get_width()
						)
						/ float(
							expected_textures[speaker_slot].get_height()
						)
					)
				) < 0.01
				and is_equal_approx(
					dialogue_director.body_label.custom_minimum_size.y,
					dialogue_director.art_body_minimum_height
				)
				and (
					dialogue_director.body_label.get_theme_font_size(
						"normal_font_size"
					)
					== dialogue_director.art_body_font_size
				)
				and (
					dialogue_director.textbox_art.texture
					== expected_textures[speaker_slot]
				),
				"Dialogue slot '%s' must use its authored textbox art."
				% speaker_slot
			)
			if art_started:
				dialogue_director.finish_conversation()
		art_line.speaker_slot = &"opening_voice"
		var fallback_started := dialogue_director.start_conversation(
			art_conversation
		)
		_expect(
			fallback_started
			and not dialogue_director.textbox_art.visible
			and dialogue_director.fallback_panel.visible
			and dialogue_director.speaker_label.visible
			and is_equal_approx(
				dialogue_director.body_label.custom_minimum_size.y,
				dialogue_director.fallback_body_minimum_height
			)
			and (
				dialogue_director.body_label.get_theme_font_size(
					"normal_font_size"
				)
				== dialogue_director.fallback_body_font_size
			)
			and is_equal_approx(
				dialogue_director.bottom_panel.size.x,
				dialogue_director.dialogue_root.size.x
					- dialogue_director.fallback_panel_horizontal_margin * 2.0
			),
			"Speakers without supplied art must retain the readable fallback."
		)
		if fallback_started:
			dialogue_director.finish_conversation()
		dialogue_director.pause_gameplay = previous_pause_gameplay
		dialogue_director.auto_frame_conversations = previous_auto_frame
		_verify_dialogue_line_ranges(dialogue_director)
	# Sculpt streaming now expands eight authored cells per packed byte. Compare
	# complete representative rows to the authoritative resource so the faster
	# bulk path cannot reverse bit order or change protected-floor collision.
	var sculpt_placements := terrain_manager.get_sculpt_placements()
	_expect(
		not sculpt_placements.is_empty(),
		"Terrain smoke verification requires one authored sculpt."
	)
	if not sculpt_placements.is_empty():
		var cheese_encounter := (
			terrain_manager.encounter_config.encounters[0]
		)
		var shared_chamber_height := (
			terrain_manager.encounter_config.chamber_height_rows
		)
		var cheese_chamber_height := (
			cheese_encounter.resolve_chamber_height_rows(
				shared_chamber_height
			)
		)
		_expect(
			cheese_chamber_height == shared_chamber_height * 3,
			"Cheese Girl's arrival fall must remain three times the shared height."
		)
		var sculpt: CutsceneTerrainSculpt = sculpt_placements[0].sculpt
		var ceiling_local_row := (
			sculpt.get_floor_local_row() - cheese_chamber_height
		)
		var pre_cutscene_layers_are_intact := ceiling_local_row >= 0
		for local_y in range(maxi(ceiling_local_row, 0)):
			for local_x in range(sculpt.grid_size.x):
				var local_cell := Vector2i(local_x, local_y)
				if not sculpt.is_solid_local(local_cell):
					pre_cutscene_layers_are_intact = false
					break
				for layer_index in range(
					sculpt.layer_solid_bits.size()
				):
					if not sculpt.is_layer_solid_local(
						layer_index,
						local_cell
					):
						pre_cutscene_layers_are_intact = false
						break
				if not pre_cutscene_layers_are_intact:
					break
			if not pre_cutscene_layers_are_intact:
				break
		_expect(
			pre_cutscene_layers_are_intact,
			"Cheese Girl's sculpt must not overwrite intact layered terrain "
				+ "before its cutscene ceiling."
		)
		var reachable_fall_is_clear := true
		var first_entry_x := sculpt.get_landing_first_local_x(
			terrain_manager.config.snake_half_span_cells
		)
		var last_entry_x := mini(
			first_entry_x
				+ terrain_manager.config.snake_half_span_cells * 2,
			sculpt.grid_size.x - 1
		)
		var clear_fall_last_row := (
			sculpt.get_floor_local_row()
			- DepthEncounterController.LANDING_FLOOR_TOLERANCE_ROWS
		)
		for local_y in range(
			ceiling_local_row,
			clear_fall_last_row + 1
		):
			for local_x in range(first_entry_x, last_entry_x + 1):
				if sculpt.is_solid_local(Vector2i(local_x, local_y)):
					reachable_fall_is_clear = false
					break
			if not reachable_fall_is_clear:
				break
		_expect(
			reachable_fall_is_clear,
			"Cheese Girl's enlarged cavern must keep every reachable fall "
				+ "column clear until the landing tolerance."
		)
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
	if miner_rig != null:
		var requested_support_y := (
			miner_rig.landing_foot_anchor.global_position.y + 10.0
		)
		miner_rig.seat_landing_foot_at_screen_y(requested_support_y)
		_expect(
			is_equal_approx(
				miner_rig.landing_foot_anchor.global_position.y,
				requested_support_y + miner_rig.grounding_overlap_y
			),
			"MinerRig must overlap sampled terrain instead of floating above it."
		)
		_expect(
			miner_rig.surface_grounding_offset_y == -8.0
			and miner_rig.intact_floor_grounding_offset_y == -8.0,
			"MinerRig static surface footing must match its visible sole."
		)
		miner_rig.show_intact_floor_grounding()
	_expect(
		timing_window != null
		and timing_window._audio_handler == audio_handler,
		"SceneWiring must inject AudioHandler into TimingWindowTask."
	)
	_expect(
		run_intro_controller != null
		and arrival_sequence != null
		and run_intro_controller.arrival_sequence == arrival_sequence
		and run_intro_controller.arrival_sequence._audio_handler
			== audio_handler,
		"SceneWiring must inject AudioHandler into ArrivalIntroSequence."
	)
	if arrival_sequence != null:
		_expect(
			run_intro_controller.hold_after_reveal_seconds >= 0.6
				and arrival_sequence.bus_arrival_seconds >= 3.0
				and arrival_sequence.bus_settle_seconds >= 0.3
				and arrival_sequence.miner_exit_delay_seconds >= 0.4
				and arrival_sequence.hold_before_dialogue_seconds >= 0.3
				and arrival_sequence.bus_departure_seconds >= 3.0,
			"Surface arrival must preserve its deliberate bus pacing."
		)
		_expect(
			not arrival_sequence.bus.visible,
			"Surface arrival must keep the bus out of the title shot."
		)
		arrival_sequence._show_click_to_mine_art = true
		arrival_sequence._set_bus_travel_art(1)
		var desktop_right_art_is_valid := (
			arrival_sequence.bus_sprite.texture
				== arrival_sequence.bus_side_right_click_texture
			and arrival_sequence.bus_sprite.position
				== arrival_sequence.side_right_click_sprite_offset
			and arrival_sequence.bus_sprite.scale == Vector2(0.44, 0.44)
			and arrival_sequence._active_wheel_uvs
				== arrival_sequence.side_right_click_wheel_uvs
		)
		arrival_sequence._set_bus_travel_art(-1)
		_expect(
			desktop_right_art_is_valid
				and arrival_sequence.bus_sprite.texture
					== arrival_sequence.bus_side_left_click_texture,
			"Desktop travel must use directional Click to Mine bus art."
		)
		arrival_sequence._show_click_to_mine_art = false
		arrival_sequence._set_bus_travel_art(1)
		var touch_right_art_is_valid := (
			arrival_sequence.bus_sprite.texture
				== arrival_sequence.bus_side_right_texture
		)
		arrival_sequence._set_bus_travel_art(-1)
		_expect(
			touch_right_art_is_valid
				and arrival_sequence.bus_sprite.texture
					== arrival_sequence.bus_side_left_texture,
			"Touch travel must retain the clean directional bus art."
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
	if encounter_controller != null:
		_verify_authored_bounces(encounter_controller)
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
	if encounter_controller != null and cutscene_action_presenter != null:
		_expect(
			encounter_controller.character_stage_camera_action_requested
				.is_connected(
					cutscene_action_presenter.present_camera_action
				),
			"Typed cutscene camera actions must cross SceneWiring."
		)
		_expect(
			encounter_controller.character_stage_audio_action_requested
				.is_connected(
					cutscene_action_presenter.present_audio_action
				),
			"Typed cutscene audio actions must cross SceneWiring."
		)
		_expect(
			encounter_controller.character_stage_vfx_action_requested
				.is_connected(
					cutscene_action_presenter.present_vfx_action
				),
			"Typed cutscene VFX actions must cross SceneWiring."
		)
		_expect(
			scene_wiring.cinematic_flow.flow_finished.is_connected(
				cutscene_action_presenter.reset_presentation
			),
			"Cutscene actions must reset when cinematic flow actually ends."
		)
		_expect(
			not encounter_controller.encounter_completed.is_connected(
				cutscene_action_presenter.reset_presentation
			),
			"Cutscene actions must survive closing presentation until flow ends."
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
	var impact_chunk_index := terrain_renderer._world_row_to_chunk(
		impact_cell.y
	)
	var impact_chunk: TerrainLayerRenderer.TerrainChunkVisual = (
		terrain_renderer._active_chunks.get(impact_chunk_index)
	)
	var impact_crush_is_active := false
	if impact_chunk != null:
		for layer_index in range(impact_chunk.layer_sprites.size()):
			var material := (
				impact_chunk.layer_sprites[layer_index].material
				as ShaderMaterial
			)
			var crush_timing: Vector2 = material.get_shader_parameter(
				&"impact_crush_timing"
			)
			if crush_timing.y > 0.0:
				impact_crush_is_active = true
				break
	_expect(
		impact_crush_is_active
		and terrain_renderer._active_impact_crush_count > 0,
		"A production dig must start one bounded terrain crush transition."
	)
	# Expire the fixed deadlines directly instead of sleeping for the authored
	# 90 ms. This keeps the branch gate deterministic and proves cleanup cannot
	# leave a shader transition active without making the suite wait in real time.
	if impact_chunk != null:
		for layer_index in range(
			impact_chunk.impact_crush_deadlines_usec.size()
		):
			if (
				impact_chunk.impact_crush_deadlines_usec[layer_index]
				> 0
			):
				impact_chunk.impact_crush_deadlines_usec[layer_index] = (
					Time.get_ticks_usec() - 1
				)
	terrain_renderer._process(0.0)
	var impact_crush_retired := (
		terrain_renderer._active_impact_crush_count == 0
	)
	if impact_chunk != null:
		for layer_index in range(impact_chunk.layer_sprites.size()):
			var material := (
				impact_chunk.layer_sprites[layer_index].material
				as ShaderMaterial
			)
			var crush_timing: Variant = material.get_shader_parameter(
				&"impact_crush_timing"
			)
			impact_crush_retired = (
				impact_crush_retired
				and (
					crush_timing == null
					or crush_timing == Vector2.ZERO
				)
			)
	_expect(
		impact_crush_retired,
		"Expired terrain crush transitions must retire without timers."
	)
	# Drain only the bounded production scheduler, then retire and restore the
	# impacted chunk. This catches stale or lossy snapshot changes; detailed
	# timing remains in the non-blocking terrain benchmark so smoke stays fast.
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

	_verify_review_camera(
		view_controller,
		terrain_manager,
		terrain_renderer
	)
	_verify_impact_smoke(
		game_root.get_node_or_null(
			"MiningScene/MiningImpactSmoke"
		) as MiningImpactSmoke
	)
	game_root.queue_free()
	await process_frame


## Guards the two dust contracts a still frame cannot show.
##
## Mining at the lobe cap used to reset the puff receiving each strike to a full
## lifetime, which snapped a half-faded puff back to full opacity: continuous
## digging read as the dust flickering brighter rather than thickening. A strike
## may now only top a puff up by a bounded share of its life.
##
## The shader also flattens a puff against rock it is touching, and it decides
## that from the confinement the open-space scan measures, so that value has to
## stay inside the 0..1 range custom data can carry.
func _verify_impact_smoke(smoke: MiningImpactSmoke) -> void:
	_expect(smoke != null, "MiningImpactSmoke must exist in the mining scene.")
	if smoke == null:
		return
	var impact_position := Vector2(
		smoke.terrain_manager.config.terrain_screen_center_x,
		smoke.terrain_manager.config.mining_face_screen_y
	)
	# Dust must be leaving the rock the moment it appears. Buoyancy alone takes
	# about half a second to overcome a fresh puff's own growth, and for that
	# half second the drawn shape spread downward off the strike; the detailed
	# frame-by-frame check is local_tests/trace_smoke_rise.gd.
	smoke.play_at_impact(impact_position, 40, 0.5, 1.0, 1)
	_expect(
		smoke._cloud != null
		and not smoke._cloud.lobes.is_empty()
		and smoke._cloud.lobes[0].velocity.y <= -smoke.initial_rise_speed * 0.9,
		"A puff must be born already rising, not waiting for buoyancy."
	)

	var lobe_budget := smoke.maximum_lobes
	if OS.has_feature("web"):
		lobe_budget = mini(lobe_budget, smoke.web_maximum_lobes)
	for _fill_index in range(lobe_budget + 2):
		smoke.play_at_impact(impact_position, 40, 0.5, 1.0, 1)
	_expect(
		smoke._cloud != null and smoke._cloud.lobes.size() == lobe_budget,
		"Repeated strikes must fill to the lobe cap and stop there."
	)
	if smoke._cloud == null or smoke._cloud.lobes.is_empty():
		return

	# Take a puff most of the way through its life, then strike it again.
	var fading_lobe: MiningImpactSmoke.SmokeLobe = smoke._cloud.lobes[0]
	for lobe in smoke._cloud.lobes:
		lobe.remaining_lifetime = lobe.total_lifetime * 0.1
	var life_before := fading_lobe.remaining_lifetime
	smoke.play_at_impact(impact_position, 40, 0.5, 1.0, 1)
	var largest_life_ratio := 0.0
	var confinement_stays_normalised := true
	for lobe in smoke._cloud.lobes:
		largest_life_ratio = maxf(
			largest_life_ratio,
			lobe.remaining_lifetime / maxf(lobe.total_lifetime, 0.001)
		)
		if lobe.wall_confinement < 0.0 or lobe.wall_confinement > 1.0:
			confinement_stays_normalised = false
	_expect(
		largest_life_ratio <= 0.1 + smoke.lobe_refresh_share + 0.001,
		(
			"A strike at the lobe cap must top a fading puff up by at most "
			+ "lobe_refresh_share, not reset it (life went to %.2f from %.2f)."
		) % [largest_life_ratio, life_before / fading_lobe.total_lifetime]
	)
	_expect(
		confinement_stays_normalised,
		"Measured wall confinement must stay inside the 0..1 custom data range."
	)


## Proves the finale's lines still finish themselves.
##
## The Thief's conversation is the only text in the game that is incomplete on
## disk: it carries {tokens} resolved against the player's lifetime record when
## each line is presented. Break that and nothing errors - the game's last scene
## simply shows literal braces to somebody eight hours in. This is the cheap
## check that it still resolves; local_tests/verify_thief_finale.gd is the
## thorough one.
func _verify_finale_text_resolves() -> void:
	var conversation := THIEF_ENCRYPTED_DIALOGUE.decrypt_conversation()
	_expect(
		conversation != null,
		"The Thief finale conversation must decrypt."
	)
	if conversation == null:
		return
	var empty_history := PlayerHistoryRecord.new()
	for line_index in range(conversation.lines.size()):
		var line: DialogueLine = conversation.lines[line_index]
		_expect(
			DialogueTokens.resolve(line.text, empty_history).find("{") < 0,
			"Finale line %d leaves an unresolved token." % line_index
		)
	empty_history.free()


## Exercises the review contracts through the production config and renderer.
func _verify_review_camera(
	view_controller: ViewController,
	terrain_manager: TerrainManager,
	terrain_renderer: TerrainLayerRenderer
) -> void:
	var config := terrain_manager.config
	var original_target := Vector2i(view_controller.target_view_position)
	var review_depth := (
		config.initial_surface_row
		+ terrain_manager.encounter_config.encounters[0].resolve_depth(
			config.total_run_depth
		)
		+ 120
	)
	view_controller.follow_mining_position(
		Vector2i(original_target.x, review_depth)
	)
	view_controller.snap_follow_to_target()
	var view_before_scroll := view_controller.current_view_y
	view_controller.scroll_review(-0.5)
	var expected_fractional_target := (
		view_before_scroll
		- config.review_scroll_pixels_per_step
			* 0.5 / float(config.terrain_cell_world_size)
	)
	_expect(
		is_equal_approx(
			view_controller._review_target_y,
			expected_fractional_target
		),
		"Review input must preserve fractional wheel travel in viewport pixels."
	)
	view_controller._move_review_view(1.0 / 60.0)
	var moved_pixels := (
		(view_before_scroll - view_controller.current_view_y)
		* float(config.terrain_cell_world_size)
	)
	_expect(
		moved_pixels > 0.0
		and moved_pixels
			< config.review_scroll_pixels_per_step * 0.5,
		"One review frame must move smoothly instead of snapping to its target."
	)

	var encounter_floor_y := float(
		config.initial_surface_row
		+ terrain_manager.encounter_config.encounters[0].resolve_depth(
			config.total_run_depth
		)
	)
	var encounter_view_y := (
		encounter_floor_y
		- (
			root.get_visible_rect().size.y
				* view_controller.encounter_focus_viewport_y_ratio
			- config.mining_face_screen_y
		) / float(config.terrain_cell_world_size)
	)
	var near_encounter_y := (
		encounter_view_y
		+ config.review_cutscene_snap_distance_pixels
			* 0.5 / float(config.terrain_cell_world_size)
	)
	view_controller.current_view_y = near_encounter_y
	view_controller._review_target_y = near_encounter_y
	view_controller._review_snap_target_y = NAN
	view_controller._review_idle_seconds = (
		config.review_cutscene_snap_delay_seconds
	)
	view_controller._last_review_scroll_direction = -1.0
	view_controller._move_review_view(0.0)
	_expect(
		is_equal_approx(
			view_controller._review_target_y,
			encounter_view_y
		),
		"Idle upward review must settle onto a visited encounter framing."
	)
	view_controller.current_view_y = encounter_view_y
	view_controller._review_snap_target_y = encounter_view_y
	view_controller.scroll_review(-0.25)
	_expect(
		is_nan(view_controller._review_snap_target_y)
		and view_controller._review_target_y < encounter_view_y,
		"Fresh review input must release an encounter stop immediately."
	)

	var deep_view_y := 5_000.0
	terrain_manager.set_view_position(
		Vector2(view_controller.current_view_x, deep_view_y)
	)
	var viewport_height := root.get_visible_rect().size.y
	var visible_world_top := 0.0
	var active_camera := root.get_camera_2d()
	if active_camera != null and not is_zero_approx(active_camera.zoom.y):
		visible_world_top = (
			active_camera.get_screen_center_position().y
			- viewport_height * 0.5 / absf(active_camera.zoom.y)
		)
	var top_world_y := (
		deep_view_y
		+ (
			visible_world_top - config.mining_face_screen_y
		) / float(config.terrain_cell_world_size)
	)
	var first_visible_chunk := maxi(
		floori(top_world_y / float(config.chunk_height_cells)),
		0
	)
	_expect(
		terrain_renderer._loaded_first_chunk
			== maxi(
				first_visible_chunk - config.preload_chunks_above,
				0
			),
		"Upward review must preload terrain before it reaches the top edge."
	)

	view_controller.follow_mining_position(original_target)
	view_controller.snap_follow_to_target()


## Confirms a timeline can present an inclusive subset without renumbering lines.
func _verify_dialogue_line_ranges(dialogue_director: DialogueDirector) -> void:
	_presented_line_indices.clear()
	_finished_conversation_ids.clear()
	if not dialogue_director.line_presented.is_connected(
		_on_smoke_line_presented
	):
		dialogue_director.line_presented.connect(_on_smoke_line_presented)
	if not dialogue_director.conversation_finished.is_connected(
		_on_smoke_conversation_finished
	):
		dialogue_director.conversation_finished.connect(
			_on_smoke_conversation_finished
		)
	var started := dialogue_director.start_conversation(
		TREASURE_HUNTER_TREASURE_CONVERSATION,
		true,
		Vector2i(1, 2)
	)
	_expect(started, "DialogueDirector must accept a valid timeline line range.")
	if not started:
		return
	dialogue_director.advance()
	dialogue_director.advance()
	_expect(
		_presented_line_indices == PackedInt32Array([1, 2]),
		"Dialogue line ranges must present only their inclusive global indices."
	)
	_expect(
		_finished_conversation_ids == [
			TREASURE_HUNTER_TREASURE_CONVERSATION.conversation_id
		],
		"A ranged dialogue beat must finish through the normal conversation contract."
	)
	dialogue_director.close_cinematic_frame(true)


## Confirms every shipped BOUNCE now has editable, playable motion data.
func _verify_authored_bounces(
	encounter_controller: DepthEncounterController
) -> void:
	var bounce_count := 0
	for encounter in encounter_controller.encounter_config.encounters:
		if encounter == null or encounter.sequence == null:
			continue
		for beat: CutsceneBeat in encounter.sequence.beats:
			if beat == null or beat.kind != CutsceneBeat.Kind.BOUNCE:
				continue
			bounce_count += 1
			_expect(
				beat.duration_seconds > 0.0
				and beat.bounce_count > 0
				and not beat.bounce_offset.is_zero_approx(),
				"Every authored BOUNCE must define duration, cycles, and peak offset."
			)
			var player := CutsceneSequencePlayer.new()
			var actor := Node2D.new()
			player.bind(
				func(actor_id: StringName) -> Node2D:
					return actor if actor_id == beat.actor else null,
				Callable(),
				Callable(),
				null
			)
			var midpoint := (
				beat.start_seconds
				+ beat.duration_seconds / float(beat.bounce_count * 4)
			)
			var state: Dictionary = player.evaluate_at(
				encounter.sequence,
				midpoint
			).get(&"actors", {}).get(beat.actor, {})
			var visual_offset: Vector2 = state.get(
				&"visual_offset",
				Vector2.ZERO
			)
			_expect(
				not visual_offset.is_zero_approx(),
				"Timeline scrub preview must evaluate authored BOUNCE motion."
			)
			player.free()
			actor.free()
	_expect(bounce_count >= 7, "Every current cutscene bounce must stay authored.")


func _on_smoke_line_presented(
	_conversation_id: StringName,
	line_index: int,
	_speaker_slot: StringName,
	_speaker_pose: StringName
) -> void:
	_presented_line_indices.append(line_index)


func _on_smoke_conversation_finished(conversation_id: StringName) -> void:
	_finished_conversation_ids.append(conversation_id)


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)
