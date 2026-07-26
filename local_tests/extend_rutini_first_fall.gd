extends SceneTree

## How it works:
## - Extends Encounter 3's existing cavern upward without replacing its basin.
## - Opens the full 49-column snaking-arrival band from the room's top edge.
## - Small deterministic chips keep the shaft walls irregular rather than boxed.
## - The shared baker derives four depth masks from the revised logical room.
## - Verification rejects blocked arrival columns or an altered landing floor.
## - The invariant is that every possible arrival falls 110 rows to one floor.

const ROOM_PATH: String = (
	"res://resources/cinematics/sculpts/rutini_first_room.tres"
)
const MINING_CONFIG_PATH: String = "res://resources/mining/mining_config.tres"


func _initialize() -> void:
	var sculpt := load(ROOM_PATH) as CutsceneTerrainSculpt
	var mining_config := load(MINING_CONFIG_PATH) as MiningConfig
	if sculpt == null or mining_config == null:
		push_error("Could not load Rotini's first room or mining config.")
		quit(1)
		return
	_extend_fall_throat(sculpt, mining_config.snake_half_span_cells)
	var failure := _get_verification_failure(
		sculpt,
		mining_config.snake_half_span_cells
	)
	if not failure.is_empty():
		push_error("ROTINI_FIRST_FALL_EXTEND_FAIL: %s" % failure)
		quit(1)
		return
	var save_error := ResourceSaver.save(sculpt, ROOM_PATH)
	if save_error != OK:
		push_error("Could not save Rotini's first room: %s" % error_string(save_error))
		quit(1)
		return
	print("ROTINI_FIRST_FALL_EXTEND_PASS rows=%d" % sculpt.get_floor_local_row())
	quit(0)


func _extend_fall_throat(
	sculpt: CutsceneTerrainSculpt,
	half_span_cells: int
) -> void:
	var centre_x := -sculpt.anchor_offset_cells.x
	var floor_row := sculpt.get_floor_local_row()
	sculpt.begin_edit()
	for local_y in range(floor_row):
		var left_chip := maxi(
			roundi(sin(float(local_y) * 0.37) * 2.0),
			0
		)
		var right_chip := maxi(
			roundi(cos(float(local_y) * 0.29 + 0.8) * 2.0),
			0
		)
		for local_x in range(
			centre_x - half_span_cells - left_chip,
			centre_x + half_span_cells + right_chip + 1
		):
			sculpt.set_solid_local(Vector2i(local_x, local_y), false)
	sculpt.end_edit()
	CutsceneSculptBaker.apply_visual_depth_masks(sculpt)


func _get_verification_failure(
	sculpt: CutsceneTerrainSculpt,
	half_span_cells: int
) -> String:
	if sculpt.get_sculpt_error() != "":
		return sculpt.get_sculpt_error()
	var floor_row := sculpt.get_floor_local_row()
	var landing_rows := sculpt.get_landing_local_rows(half_span_cells)
	if landing_rows.size() != half_span_cells * 2 + 1:
		return "The complete snaking-arrival band is not represented."
	var first_x := sculpt.get_landing_first_local_x(half_span_cells)
	for index in range(landing_rows.size()):
		var local_x := first_x + index
		if landing_rows[index] != floor_row:
			return "Column %d does not reach floor row %d." % [local_x, floor_row]
		for local_y in range(floor_row):
			if sculpt.is_solid_local(Vector2i(local_x, local_y)):
				return "Column %d is blocked at row %d." % [local_x, local_y]
	if sculpt.layer_solid_bits.size() != 4:
		return "The extended cavern does not carry four depth masks."
	return ""
