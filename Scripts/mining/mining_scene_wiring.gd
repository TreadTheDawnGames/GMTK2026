class_name MiningSceneWiring
extends Node

## Connects the mining scene's cross-system signals in one searchable place.

@export_category("Run")
@export var run_state: RunState
@export var ore_inventory: OreInventoryState

@export_category("Mining")
@export var terrain_manager: TerrainManager
@export var terrain_break_animator: TerrainBreakAnimator
@export var mining_controller: MiningController
@export var timing_bridge: TimingBridge
@export var view_controller: ViewController
@export var miner_rig: MinerRig
@export var hit_particles: MiningHitParticles
@export var impact_shake: ImpactShake

@export_category("Interface")
@export var hud: MiningHud
@export var encounter_controller: DepthEncounterController
@export var dialogue_director: DialogueDirector
@export var aim_mode_prompt: AimModePrompt
@export var aim_controller: MinerAimController


## Establishes every signal that crosses a mining subsystem boundary.
func _ready() -> void:
	_connect_once(
		run_state.depth_changed,
		encounter_controller._on_depth_changed
	)
	_connect_once(run_state.depth_changed, hud._on_depth_changed)
	_connect_once(run_state.run_reset, ore_inventory.reset_inventory)
	_connect_once(
		ore_inventory.inventory_changed,
		hud._on_ore_inventory_changed
	)
	_connect_once(
		terrain_manager.terrain_cells_destroyed,
		terrain_break_animator.play_break_sequence
	)
	_connect_once(
		terrain_break_animator.all_breaks_finished,
		mining_controller.finish_break_sequence
	)
	_connect_once(
		terrain_break_animator.cells_revealed,
		mining_controller.advance_with_breakage
	)
	_connect_once(
		miner_rig.impact_contact,
		mining_controller.resolve_impact
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
		mining_controller.impact_resolved,
		hit_particles.play_at_impact
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
		aim_mode_prompt.mode_selected,
		aim_controller.set_keyboard_aim_enabled
	)


## Connects one cross-system signal without duplicating an existing route.
func _connect_once(source_signal: Signal, target: Callable) -> void:
	if not source_signal.is_connected(target):
		source_signal.connect(target)
