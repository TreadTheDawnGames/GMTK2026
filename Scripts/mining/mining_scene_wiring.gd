class_name MiningSceneWiring
extends Node

## Connects the mining scene's cross-system signals in one searchable place.

## Which terrain stratum the miner's feet are seated against. Zero is the
## foreground layer: the ground the player sees him standing on.
const MINER_FLOOR_LAYER_INDEX: int = 0

@export_category("Mining")
@export var mining_controller: MiningController
@export var timing_bridge: TimingBridge
@export var view_controller: ViewController
@export var terrain_manager: TerrainManager
@export var terrain_renderer: TerrainLayerRenderer
@export var miner_rig: MinerRig
@export var hit_particles: MiningHitParticles
@export var gem_outcrop_field: GemOutcropField
@export var impact_smoke: MiningImpactSmoke
@export var impact_spark: ImpactSpark
@export var combo_vignette: ComboImpactVignette
@export var dig_number_presenter: DigNumberPresenter
@export var impact_shake: ImpactShake
@export var pickaxe_reward_celebration: PickaxeRewardCelebration
@export var pickaxe_progression: PickaxeProgression
@export var encounter_progression: EncounterProgression
@export var cinematic_flow: MiningCinematicFlow
@export var run_timeline: RunTimeline
@export var coffee_speed_boost: CoffeeSpeedBoost
@export var rat_colony_followers: RatColonyFollowers

@export_category("Opening")
## The menu is an overlay on this scene, so starting a run is one signal
## crossing from the interface to the opening sequence rather than a scene load.
@export var main_menu: GameMainMenu
@export var run_intro_controller: RunIntroController

@export_category("Escalation")
@export var combo_director: ComboDirector
#@export var music_director: MusicDirector
@export var combo_tier_punch: ComboTierPunch

@export_category("Landing Impact")
## Dirt thrown from the soles when the miner lands on an authored encounter
## floor. Read as a cell count by the shared hit particles, so raising it
## throws more pieces; the particle system's own caps still bound the total.
@export_range(0, 32, 1) var landing_impact_cells: int = 6
## Drives piece speed and smoke size, the way a combo does on a pickaxe hit.
@export_range(0.0, 1.0, 0.05) var landing_impact_strength: float = 0.55
@export_range(0.0, 4.0, 0.05) var landing_impact_debris_multiplier: float = 1.0

@export_category("Interface")
@export var hud: MiningHud
@export var playtime_reveal: PlaytimeReveal
@export var timing_window: TimingWindowTask
@export var timing_bar_feedback: TimingBarFeedback
@export var depth_review_control: DepthReviewControl
@export var encounter_controller: DepthEncounterController
@export var dialogue_director: DialogueDirector
@export var final_encounter_controller: FinalEncounterController
@export var credits_overlay: CreditsOverlay

@onready var _game_state: RunState = (
	get_node_or_null("/root/GameState") as RunState
)
@onready var _audio_handler: PlayerAudioHandler = (
	get_node_or_null("/root/AudioHandler") as PlayerAudioHandler
)
@onready var _music_manager: Node = get_node("/root/MusicManager")


## Establishes every signal that crosses a mining subsystem boundary.
func _ready() -> void:
	if _game_state == null or _audio_handler == null:
		push_error(
			"MiningSceneWiring requires GameState and AudioHandler autoloads."
		)
		return
	mining_controller.set_run_state(_game_state)
	encounter_controller.set_run_state(_game_state)
	gem_outcrop_field.set_save_game(_game_state.save_game)
	main_menu.set_save_game(_game_state.save_game)
	hud.set_save_game(_game_state.save_game)
	miner_rig.set_audio_handler(_audio_handler)
	timing_window.set_audio_handler(_audio_handler)
	_connect_once(
		main_menu.start_requested,
		_on_start_requested
	)
	_connect_once(
		_game_state.depth_changed,
		_on_run_depth_changed
	)
	_connect_once(
		_game_state.run_reset,
		mining_controller._on_run_reset
	)
	_connect_once(
		_game_state.run_reset,
		encounter_progression._on_run_reset
	)
	_connect_once(
		_game_state.run_reset,
		run_timeline._on_run_reset
	)
	_connect_once(
		_game_state.run_reset,
		credits_overlay._on_run_reset
	)
	_connect_once(
		_game_state.run_reset,
		encounter_controller._on_run_reset
	)
	_connect_once(
		_game_state.run_reset,
		coffee_speed_boost._on_run_reset
	)
	_connect_once(
		_game_state.run_reset,
		rat_colony_followers._on_run_reset
	)
	_connect_once(
		terrain_manager.terrain_damaged,
		gem_outcrop_field._on_terrain_damaged
	)
	_connect_once(
		_game_state.run_reset,
		gem_outcrop_field.clear_gems
	)
	_connect_once(
		cinematic_flow.flow_finished,
		run_timeline._on_cinematic_flow_finished
	)
	_connect_once(
		cinematic_flow.flow_finished,
		encounter_controller._on_cinematic_flow_finished
	)
	_connect_once(
		run_timeline.run_time_changed,
		hud._on_run_time_changed
	)
	_connect_once(
		run_timeline.run_time_changed,
		playtime_reveal._on_run_time_changed
	)
	_connect_once(
		miner_rig.impact_contact,
		_on_miner_impact_contact
	)
	_connect_once(
		miner_rig.swing_finished,
		mining_controller.finish_swing
	)
	_connect_once(
		timing_bridge.attempt_resolved,
		mining_controller.resolve_attempt
	)
	_connect_once(
		timing_bridge.impact_candidates_changed,
		mining_controller._on_impact_candidates_changed
	)
	_connect_once(
		encounter_controller.encounter_completed,
		encounter_progression._on_encounter_completed
	)
	_connect_once(
		mining_controller.dig_presentation_started,
		terrain_renderer._on_dig_presentation_started
	)
	_connect_once(
		mining_controller.dig_visuals_preparation_started,
		terrain_renderer._on_dig_visuals_preparation_started
	)
	_connect_once(
		mining_controller.dig_visuals_preparation_requested,
		terrain_renderer._on_dig_visuals_preparation_requested
	)
	_connect_once(
		view_controller.landing_reached,
		_on_miner_landing_grounding,
		Object.CONNECT_DEFERRED
	)
	_connect_once(
		view_controller.landing_reached,
		encounter_controller._on_landing_reached,
		Object.CONNECT_DEFERRED
	)
	_connect_once(
		cinematic_flow.camera_focus_requested,
		_on_cinematic_camera_focus_requested
	)
	_connect_once(
		cinematic_flow.camera_released,
		view_controller.release_encounter_focus
	)
	_connect_once(
		terrain_manager.view_position_changed,
		terrain_renderer._on_view_position_changed
	)
	_connect_once(
		terrain_manager.view_position_changed,
		credits_overlay._on_view_position_changed
	)
	_connect_once(
		terrain_manager.view_position_changed,
		gem_outcrop_field._on_view_position_changed
	)
	_connect_once(
		terrain_manager.view_position_changed,
		encounter_controller._on_view_position_changed
	)
	_connect_once(
		mining_controller.impact_resolved,
		hit_particles.play_at_impact
	)
	_connect_once(
		mining_controller.impact_resolved,
		impact_smoke.play_at_impact
	)
	_connect_once(
		mining_controller.impact_resolved,
		impact_spark.play_at_impact
	)
	_connect_once(
		mining_controller.impact_resolved,
		combo_vignette.play_at_impact
	)
	# One escalation model feeds every presenter below, so the music, the
	# camera punch, and the mix all agree on which step the run is on.
	_connect_once(
		mining_controller.mine_resolved,
		combo_director._on_mine_resolved
	)
	_connect_once(
		timing_window.streak_ended,
		combo_director._on_streak_ended
	)
	_connect_once(
		pickaxe_progression.upgrade_granted,
		combo_director._on_upgrade_granted
	)
	_connect_once(
		pickaxe_progression.upgrade_granted,
		pickaxe_reward_celebration.play_for_upgrade
	)
	_connect_once(
		coffee_speed_boost.boost_awarded,
		combo_director._on_coffee_boost_awarded
	)
	_connect_once(
		encounter_controller.rat_colony_support_requested,
		combo_director._on_rat_colony_support_requested
	)
	_connect_once(
		_game_state.run_reset,
		combo_director._on_run_reset
	)
	_connect_once(
		combo_director.intensity_changed,
		Callable(_music_manager, &"_on_intensity_changed")
	)
	_connect_once(
		combo_director.combo_tier_changed,
		Callable(_music_manager, &"_on_combo_tier_changed")
	)
	_connect_once(
		combo_director.streak_lost,
		Callable(_music_manager, &"_on_streak_lost")
	)
	_connect_once(
		_game_state.run_reset,
		Callable(_music_manager, &"_on_run_reset")
	)
	_connect_once(
		combo_director.combo_tier_changed,
		combo_tier_punch._on_combo_tier_changed
	)
	_connect_once(
		_game_state.run_reset,
		combo_tier_punch._on_run_reset
	)
	_connect_once(
		_game_state.save_game.settings_applied,
		timing_window.set_bounce_muted
	)
	# A lost streak gives the darkened frame straight back instead of letting it
	# decay, so the release reads as part of losing the combo.
	_connect_once(
		mining_controller.mine_missed,
		combo_vignette.release
	)
	_connect_once(
		timing_window.pressed,
		timing_bar_feedback._on_timing_pressed
	)
	_connect_once(
		mining_controller.dig_number_requested,
		dig_number_presenter.show_dig_number_at_impact
	)
	_connect_once(
		mining_controller.impact_resolved,
		impact_shake.play_at_impact
	)
	_connect_once(
		mining_controller.impact_resolved,
		rat_colony_followers._on_player_impact_resolved
	)
	_connect_once(
		mining_controller.mine_missed,
		miner_rig.play_miss
	)
	_connect_once(
		mining_controller.swing_requested,
		miner_rig.play_success
	)
	_connect_once(
		mining_controller.mine_resolved,
		encounter_controller._on_final_breakthrough_mined
	)
	_connect_once(
		dialogue_director.conversation_finished,
		encounter_controller._on_conversation_finished
	)
	_connect_once(
		dialogue_director.conversation_finished,
		run_intro_controller._on_conversation_finished
	)
	_connect_once(
		dialogue_director.line_presented,
		encounter_controller._on_dialogue_line_presented
	)
	_connect_once(
		encounter_controller.final_encounter_reached,
		final_encounter_controller.show_finale
	)
	_connect_once(
		final_encounter_controller.run_reset_requested,
		_game_state.reset_run
	)
	_connect_once(
		encounter_controller.coffee_speed_boost_requested,
		coffee_speed_boost.award_boost
	)
	_connect_once(
		encounter_controller.rat_colony_support_requested,
		rat_colony_followers.activate_followers
	)
	_connect_once(
		credits_overlay.credits_completed,
		encounter_controller._on_credits_completed
	)
	_connect_once(
		depth_review_control.review_scroll_requested,
		view_controller.scroll_review
	)
	_connect_once(
		depth_review_control.return_requested,
		view_controller.return_to_miner
	)
	_connect_once(
		view_controller.review_started,
		depth_review_control._on_review_started
	)
	_connect_once(
		view_controller.miner_view_reached,
		depth_review_control._on_miner_view_reached
	)
	_connect_once(
		view_controller.miner_screen_offset_changed,
		miner_rig.set_screen_offset
	)
	_connect_once(
		encounter_controller.character_stage_strike_requested,
		_on_character_stage_strike_requested
	)
	_connect_once(
		rat_colony_followers.presentation_strike_requested,
		_on_character_stage_strike_requested
	)
	_connect_once(
		encounter_controller.character_stage_rock_break_requested,
		_on_character_stage_rock_break_requested
	)
	_connect_once(
		encounter_controller.stampede_rumble_started,
		impact_shake.begin_sustained
	)
	_connect_once(
		encounter_controller.stampede_rumble_finished,
		impact_shake.end_sustained
	)
	timing_window.set_bounce_muted(_game_state.save_game.mute_bounce)
	_on_run_depth_changed(_game_state.depth)


## Resets shared run state before handing the live title shot to its intro.
func _on_start_requested() -> void:
	_game_state.reset_run()
	run_intro_controller.begin_run()


## Fans one authoritative progress change into its explicit read-only consumers.
func _on_run_depth_changed(depth: int) -> void:
	credits_overlay._on_depth_changed(depth)
	encounter_controller._on_depth_changed(depth)
	hud.show_run_progress(
		depth,
		_game_state.remaining_depth,
		_game_state.distance_since_thief,
		_game_state.has_reached_thief
	)
	timing_window.show_displayed_distance(_game_state.displayed_distance)


## Frames the authored sole instead of the abstract mining-row coordinate.
func _on_cinematic_camera_focus_requested() -> void:
	var screen_offset := view_controller.get_miner_screen_offset()
	var current_offset_y := (
		0.0 if is_nan(screen_offset.y) else screen_offset.y
	)
	view_controller.focus_miner_for_encounter(
		miner_rig.get_cinematic_foot_screen_position().y
			- current_offset_y
	)


## Resolves impact with the side used by the visible swing.
func _on_miner_impact_contact(screen_position: Vector2) -> void:
	mining_controller.resolve_impact(
		screen_position,
		miner_rig.get_facing_direction()
	)


## Gives staged character strikes the same bounded production feedback.
func _on_character_stage_strike_requested(
	screen_position: Vector2
) -> void:
	_play_cinematic_strike_feedback(screen_position)


## Opens real rock where a staged strike landed, for a character mining their way
## into a room.
##
## Terrain is reached from here rather than from the stage that asked, because
## this file is the cross-system boundary and a cutscene stage owns actors, props
## and local effects only. The feedback for the same strike has already played
## through the signal above; this is the half that removes the wall.
func _on_character_stage_rock_break_requested(
	screen_position: Vector2,
	radius_cells: int
) -> void:
	# screen_to_terrain_position answers in world units; the terrain call takes
	# cells, the same unit dig_tunnel takes.
	var terrain_position := terrain_manager.screen_to_terrain_position(
		screen_position
	)
	var cell_size := float(terrain_manager.config.terrain_cell_world_size)
	terrain_manager.break_presentation_pocket(
		Vector2i(
			floori(terrain_position.x / cell_size),
			floori(terrain_position.y / cell_size)
		),
		radius_cells
	)


func _play_cinematic_strike_feedback(screen_position: Vector2) -> void:
	hit_particles.play_at_impact(
		screen_position,
		1,
		0.2,
		0.45,
		1
	)
	impact_smoke.play_at_impact(
		screen_position,
		1,
		0.2,
		0.45,
		1
	)
	impact_shake.play_at_impact(
		screen_position,
		1,
		0.15,
		0.0,
		1
	)
	impact_spark.play_at_impact(
		screen_position,
		1,
		0.2,
		0.45,
		1
	)


## Seats authored floors on layer one and mined landings on visible layer two.
func _on_miner_landing_grounding(mining_y: int) -> void:
	# The first landing below the run's starting row is the moment he stops
	# standing on the surface and starts standing in the hole, which is what
	# decides whether the foreground stratum draws over him.
	if mining_y > terrain_manager.config.initial_surface_row:
		miner_rig.leave_surface_draw_order()
	if terrain_manager.is_authored_landing_floor(mining_y):
		miner_rig.show_intact_floor_grounding()
		# An encounter floor is the frame a cutscene opens on, so kicking dirt
		# out of his soles here is what makes him read as having hit the ground
		# rather than being placed on it. The run's own starting surface is
		# excluded: he begins standing there and never falls onto it.
		if mining_y != terrain_manager.config.initial_surface_row:
			_play_landing_impact_feedback()
		return
	var support_screen_y: float = (
		terrain_renderer.get_layer_opening_floor_support_screen_y(
			miner_rig.get_landing_foot_screen_x(),
			mining_y,
			# Layer one, the same stratum the cast is placed against. This read
			# layer two from when the profile lowered the foreground over a
			# chamber floor; with that reveal off, sampling behind the visible
			# ground seated the miner below the floor he is standing on.
			MINER_FLOOR_LAYER_INDEX
		)
	)
	miner_rig.seat_landing_foot_at_screen_y(support_screen_y)


## Bursts dirt out of the miner's soles and jolts the camera when he lands on
## an encounter floor. It reuses the bounded pickaxe-hit debris rather than
## adding a second particle system, so it costs one hit's worth of pieces and
## honours the existing web caps.
##
## Deliberately no impact smoke: that system anchors a rising plume to the
## swing side and the open space beside a fresh cut, and a landing has neither
## a swing side nor a cut. Feeding it one would drift the plume into solid rock.
func _play_landing_impact_feedback() -> void:
	var foot_position := miner_rig.get_landing_foot_screen_position()
	hit_particles.play_at_impact(
		foot_position,
		landing_impact_cells,
		landing_impact_strength,
		landing_impact_debris_multiplier,
		0
	)
	impact_shake.play_at_impact(
		foot_position,
		landing_impact_cells,
		landing_impact_strength,
		0.0,
		0
	)
	impact_spark.play_at_impact(
		foot_position,
		landing_impact_cells,
		landing_impact_strength,
		1.0,
		0
	)


## Connects one cross-system signal without duplicating an existing route.
func _connect_once(
	source_signal: Signal,
	target: Callable,
	flags: int = 0
) -> void:
	if not source_signal.is_connected(target):
		source_signal.connect(target, flags)
