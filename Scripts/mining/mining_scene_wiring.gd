class_name MiningSceneWiring
extends Node

## Connects the mining scene's cross-system signals in one searchable place.

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
@export var dig_number_presenter: DigNumberPresenter
@export var impact_shake: ImpactShake
@export var pickaxe_progression: PickaxeProgression
@export var cinematic_flow: MiningCinematicFlow
@export var run_timeline: RunTimeline
@export var layer_breakthrough_controller: LayerBreakthroughController
@export var layer_breakthrough_sequence: LayerBreakthroughSequence
@export var breakthrough_target_highlight: BreakthroughTargetHighlight

@export_category("Interface")
@export var hud: MiningHud
@export var playtime_reveal: PlaytimeReveal
@export var timing_window: TimingWindowTask
@export var depth_review_control: DepthReviewControl
@export var encounter_controller: DepthEncounterController
@export var intro_controller: RunIntroController
@export var dialogue_director: DialogueDirector
@export var departure_choice: DepartureChoice
@export var final_encounter_controller: FinalEncounterController

@onready var _game_state: RunState = RunState.get_global(self)


## Establishes every signal that crosses a mining subsystem boundary.
func _ready() -> void:
	_connect_once(
		_game_state.depth_changed,
		layer_breakthrough_controller._on_depth_changed
	)
	_connect_once(
		layer_breakthrough_controller.arming_changed,
		breakthrough_target_highlight._on_breakthrough_arming_changed
	)
	_connect_once(
		_game_state.depth_changed,
		encounter_controller._on_depth_changed
	)
	_connect_once(_game_state.depth_changed, hud._on_depth_changed)
	_connect_once(
		_game_state.run_reset,
		mining_controller._on_run_reset
	)
	_connect_once(
		_game_state.run_reset,
		run_timeline._on_run_reset
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
		pickaxe_progression.target_unlocks_changed,
		timing_window.set_pickaxe_target_unlocks
	)
	_connect_once(
		mining_controller.dig_presentation_started,
		terrain_renderer._on_dig_presentation_started
	)
	_connect_once(
		view_controller.landing_reached,
		encounter_controller._on_landing_reached
	)
	_connect_once(
		view_controller.landing_reached,
		_on_miner_landing_grounding,
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
		mining_controller.dig_number_requested,
		dig_number_presenter.show_dig_number_at_impact
	)
	_connect_once(
		mining_controller.impact_resolved,
		impact_shake.play_at_impact
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
		layer_breakthrough_controller._on_mine_resolved
	)
	_connect_once(
		view_controller.landing_reached,
		layer_breakthrough_controller._on_landing_reached
	)
	_connect_once(
		dialogue_director.conversation_finished,
		encounter_controller._on_conversation_finished
	)
	_connect_once(
		dialogue_director.conversation_finished,
		intro_controller._on_conversation_finished
	)
	_connect_once(
		dialogue_director.conversation_finished,
		layer_breakthrough_controller._on_conversation_finished
	)
	_connect_once(
		dialogue_director.line_presented,
		encounter_controller._on_dialogue_line_presented
	)
	_connect_once(
		dialogue_director.line_presented,
		intro_controller._on_dialogue_line_presented
	)
	_connect_once(
		dialogue_director.line_presented,
		layer_breakthrough_controller._on_dialogue_line_presented
	)
	_connect_once(
		encounter_controller.departure_choice_requested,
		departure_choice.show_choice
	)
	_connect_once(
		encounter_controller.final_encounter_reached,
		final_encounter_controller.show_finale
	)
	_connect_once(
		departure_choice.keep_digging_selected,
		encounter_controller.continue_after_departure
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
		layer_breakthrough_sequence.rat_strike_requested,
		_on_rat_strike_requested
	)
	_connect_once(
		encounter_controller.character_stage_strike_requested,
		_on_character_stage_strike_requested
	)


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


## Reuses bounded dirt, smoke, and shake feedback for mouse wall strikes.
func _on_rat_strike_requested(screen_position: Vector2) -> void:
	_play_cinematic_strike_feedback(screen_position)


## Gives staged character strikes the same bounded production feedback.
func _on_character_stage_strike_requested(
	screen_position: Vector2
) -> void:
	_play_cinematic_strike_feedback(screen_position)


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


## Seats authored floors on layer one and mined landings on visible layer two.
func _on_miner_landing_grounding(mining_y: int) -> void:
	if terrain_manager.is_authored_landing_floor(mining_y):
		miner_rig.show_intact_floor_grounding()
		return
	var support_screen_y: float = (
		terrain_renderer.get_layer_opening_floor_support_screen_y(
			miner_rig.get_landing_foot_screen_x(),
			mining_y,
			1
		)
	)
	miner_rig.seat_landing_foot_at_screen_y(support_screen_y)


## Connects one cross-system signal without duplicating an existing route.
func _connect_once(
	source_signal: Signal,
	target: Callable,
	flags: int = 0
) -> void:
	if not source_signal.is_connected(target):
		source_signal.connect(target, flags)
