@tool
class_name DepthCharacterEncounter
extends Resource

## How it works:
## - depth_from_surface places this encounter's mineable tunnel floor.
## - An optional chamber-height override enlarges this encounter's arrival fall.
## - Terrain generation opens the resolved chamber above that floor.
## - Crossing the tunnel ceiling starts the authored conversation and stage.
## - stage_scene optionally adds actor movement, props, and line-driven cues.
## - occurs_at_run_bottom pins the final encounter to any configured run length.
## - The invariant is that large hits cannot skip an encounter threshold.
## @tool because the cutscene editor resolves encounter depth and authored room
## data in editor context; non-tool resources become placeholder instances.

@export var encounter_id: StringName
## Stable story identity; repeated visits reuse the same presenter.
@export var actor_id: StringName
@export_range(1, 1_000_000, 1) var depth_from_surface: int = 1_000
## Zero uses the schedule's shared chamber height. A positive value enlarges
## only this arrival, so one tall discovery does not move every cutscene ceiling.
@export_range(0, 2_000, 1) var chamber_height_rows_override: int = 0
## Gathers the stable cast roster when this depth-authored chamber is entered.
@export var gathers_cast: bool = false
## Resolves this encounter to zero remaining depth for any run length.
@export var occurs_at_run_bottom: bool = false
@export var appearance: CharacterAppearance
@export var conversation: DialogueConversation
## Optional inherited CharacterEncounterStage scene for actor/prop choreography.
@export var stage_scene: PackedScene
## Optional timeline played by the stage during its opening choreography.
@export var sequence: CutsceneSequence
## Whether that timeline actually drives this encounter at runtime.
##
## Off by default, and deliberately separate from `sequence` being set, because
## every encounter in the project already carries a generated placeholder
## timeline. Those were authored as starting points and no run has ever played
## one: switching them all on at once would replace the choreography each stage
## has been tuned to, and their DIALOGUE beats would run the conversation a
## second time on top of the one the schedule starts.
##
## Turn it on for an encounter whose timeline has genuinely been authored. The
## stage then owns the whole shot - movement, poses, and asking for dialogue at
## the beat it belongs to - and the schedule stops starting the conversation
## itself.
@export var plays_authored_timeline: bool = false
## Reveals an already-present actor and set before the miner lands. Reserve this
## for discoveries during the fall, not visitors who enter after landing.
@export var prestage_before_landing: bool = false
## Optional per-shot framing. Negative values preserve the shared presentation
## defaults, so one room can use more height without moving every encounter.
@export_range(-1.0, 0.82, 0.01) var cinematic_focus_viewport_y_ratio: float = -1.0
@export_range(-1.0, 0.4, 0.01) var cinematic_bar_height_ratio: float = -1.0
## Recedes the completed room by this share of the viewport, then holds that
## frame until a new mining target changes the followed terrain cell.
@export_range(0.0, 0.2, 0.01) var post_cinematic_recession_ratio: float = 0.0
## Used only when story text should remain encrypted in source control.
@export var encrypted_conversation: EncryptedDialogueConversation
@export var speaker_slot: StringName
## Optional collectible granted once after dialogue. Author it using
## res://resources/pickaxes/pickaxe_authoring.md. Production mining and timing
## behavior belongs to the corresponding EncounterProgressionLevel.
@export var pickaxe_reward: PickaxeDefinition
## Requests the canonical persistent coffee speed reward after dialogue.
@export var grants_coffee_speed_boost: bool = false
## Starts bounded rat-colony support after dialogue.
@export var starts_rat_colony_support: bool = false
## Holds this encounter until the non-blocking credits presentation completes.
@export var requires_credits_complete: bool = false
## Opens the chamber through its right wall for authored choreography.
@export var opens_right_exit: bool = false
## Dresses this room's floor as walked-on ground from entry through first mining.
##
## Off by default, so every existing encounter draws exactly as before. On, and
## DepthEncounterController asks TerrainLayerRenderer for the shared trodden
## floor at this encounter's own floor line before the miner falls into view.
## The renderer seals the presentation while the shot owns it, then the first
## ordinary mining impact releases that seal so the real mask cracks the same
## floor instead of replacing it with a separate effect.
##
## It is a shared service rather than one room's dressing - the settings live on
## the renderer and any encounter can opt in - so turning this on is the whole
## cost of using it.
@export var dresses_trodden_floor: bool = false
## Lights this room's floor as a horizontal plane while the shot is running.
##
## Off by default, so every existing encounter draws exactly as before. On, and
## DepthEncounterController asks TerrainLayerRenderer for the shared ground stack
## at this encounter's own floor line - the lit top face, its far edge, the cut
## face below it, and the bounce band on rock standing on it - and clears it when
## the shot releases.
##
## This is the 2.5D read the world surface gets for free and every room below it
## went without: a side-on shot has no horizontal surfaces, so undressed floor
## reads as a wall the cast stand in front of. It is separate from
## `dresses_trodden_floor` because form and dressing are separate choices.
@export var lights_floor_as_plane: bool = false
## Optional screen-space depth between the Miner and this encounter's cast.
##
## Negative preserves the established shared staging: gathering encounters use
## the cafe depth and ordinary encounters share the cast's floor line. A
## non-negative value lets one room move only the Miner toward the camera while
## its visitor remains on the authored rear plane.
@export_range(-1.0, 128.0, 1.0) var miner_cutscene_depth_offset_pixels: float = -1.0
## Replaces this encounter's procedural chamber with an authored sculpted room.
## Leave it null and terrain generation is unchanged.
@export var terrain_sculpt: CutsceneTerrainSculpt


## Returns the gameplay depth where this character waits.
func resolve_depth(total_run_depth: int) -> int:
	if occurs_at_run_bottom:
		return total_run_depth
	return depth_from_surface


## Returns this arrival's authored height or the schedule default.
func resolve_chamber_height_rows(default_height_rows: int) -> int:
	if chamber_height_rows_override > 0:
		return chamber_height_rows_override
	return maxi(default_height_rows, 1)


## Resolves this room's Miner depth without changing legacy encounter staging.
func resolve_miner_cutscene_depth_offset(
	default_offset_pixels: float
) -> float:
	if miner_cutscene_depth_offset_pixels >= 0.0:
		return miner_cutscene_depth_offset_pixels
	return maxf(default_offset_pixels, 0.0)
