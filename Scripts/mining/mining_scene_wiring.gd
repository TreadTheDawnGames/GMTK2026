class_name MiningSceneWiring
extends Node

## Connects the mining scene's cross-system signals in one searchable place.

@export_category("Run")
@export var run_state: RunState

@export_category("Mining")
@export var mining_controller: MiningController
@export var timing_bridge: TimingBridge
@export var view_controller: ViewController
@export var terrain_manager: TerrainManager
@export var miner_rig: MinerRig
@export var hit_particles: MiningHitParticles
@export var impact_smoke: MiningImpactSmoke
@export var dig_number_presenter: DigNumberPresenter
@export var impact_shake: ImpactShake

@export_category("Interface")
@export var hud: MiningHud
@export var depth_review_control: DepthReviewControl
@export var encounter_controller: DepthEncounterController
@export var dialogue_director: DialogueDirector
@export var departure_choice: DepartureChoice


## Establishes every signal that crosses a mining subsystem boundary.
func _ready() -> void:
	_connect_once(
		run_state.depth_changed,
		encounter_controller._on_depth_changed
	)
	_connect_once(run_state.depth_changed, hud._on_depth_changed)
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
		view_controller.landing_reached,
		encounter_controller._on_landing_reached
	)
	_connect_once(
		terrain_manager.view_y_changed,
		encounter_controller._on_view_y_changed
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
		dialogue_director.conversation_finished,
		encounter_controller._on_conversation_finished
	)
	_connect_once(
		dialogue_director.line_presented,
		encounter_controller._on_dialogue_line_presented
	)
	_connect_once(
		encounter_controller.departure_choice_requested,
		departure_choice.show_choice
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
		miner_rig.set_screen_depth_offset
	)


## Resolves impact with the side used by the visible swing.
func _on_miner_impact_contact(screen_position: Vector2) -> void:
	mining_controller.resolve_impact(
		screen_position,
		miner_rig.get_facing_direction()
	)


## Connects one cross-system signal without duplicating an existing route.
func _connect_once(source_signal: Signal, target: Callable) -> void:
	if not source_signal.is_connected(target):
		source_signal.connect(target)
