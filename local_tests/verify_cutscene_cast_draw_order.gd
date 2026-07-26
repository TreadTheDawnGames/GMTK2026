extends SceneTree

## Proves a cutscene's cast is drawn in front of the rock they are standing in.
##
## During ordinary mining the cast layer sits behind the foreground stratum,
## which is what makes the miner read as being down in his dig rather than pasted
## on top of it. A cutscene lifts the whole cast in front of that stratum instead,
## because a shot that holds on two characters has to let you see them.
##
## The lift is a single number, MinerRig.cutscene_draw_order, and the thing it
## has to beat is whatever the terrain profile's frontmost stratum draws at. Those
## two live in different files and nothing has ever tied them together: add a
## stratum, or renumber the existing ones, and every cutscene quietly starts
## playing behind the wall with no error anywhere. That is exactly how it looks
## when it goes wrong - the characters are simply gone behind the dirt.
##
## The invariant is that the cutscene cast order is strictly in front of every
## terrain stratum, and that the resting order is still behind the foreground one.

const MINER_SCENE := preload("res://Scenes/mining/miner_rig.tscn")
const PROFILE_PATH := "res://resources/mining/default_terrain_layer_profile.tres"

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile := load(PROFILE_PATH) as TerrainLayerProfile
	if profile == null:
		push_error("Cast draw order check could not load the terrain profile.")
		quit(1)
		return
	var rig: Node2D = MINER_SCENE.instantiate()
	root.add_child(rig)
	await process_frame

	var frontmost_terrain_z := -2_147_483_648
	for layer_index in range(profile.get_layer_count()):
		frontmost_terrain_z = maxi(
			frontmost_terrain_z,
			profile.get_layer_z_index(layer_index)
		)

	var cutscene_order: int = rig.cutscene_draw_order
	var buried_order: int = rig.buried_draw_order
	print("CAST_DRAW_ORDER frontmost_terrain_z=%d cutscene=%d buried=%d" % [
		frontmost_terrain_z,
		cutscene_order,
		buried_order,
	])

	var second_stratum_z := _get_second_stratum_z(profile)
	# Mining and cutscenes now stand the cast on the SAME stratum, the second one,
	# which is Zephan's direction: the foreground rock closes over a cutscene cast
	# exactly as it closes over the miner while he digs. This used to assert the
	# opposite - that a cutscene cleared every stratum - so the rule reversing is
	# the change, not a check going soft.
	if cutscene_order >= frontmost_terrain_z:
		_failures.append(
			(
				"Cutscene cast order %d is not behind the foreground stratum at "
				+ "%d, so the cast would be pasted on top of the rock the rest of "
				+ "the game sits inside."
			) % [cutscene_order, frontmost_terrain_z]
		)
	if cutscene_order <= second_stratum_z:
		_failures.append(
			(
				"Cutscene cast order %d is not in front of the second stratum at "
				+ "%d, so the cast would be buried behind the layer they stand on."
			) % [cutscene_order, second_stratum_z]
		)
	# Both ends of the miner's own mining order are still asserted, because a
	# single number satisfying one and not the other is exactly how this goes
	# wrong.
	if buried_order >= frontmost_terrain_z:
		_failures.append(
			(
				"Buried order %d is not behind the foreground stratum at %d, so "
				+ "the miner would stop reading as being down in his dig."
			) % [buried_order, frontmost_terrain_z]
		)
	if buried_order <= second_stratum_z:
		_failures.append(
			(
				"Buried order %d is not in front of the second stratum at %d, so "
				+ "he would sink behind the layer he is supposed to stand on."
			) % [buried_order, second_stratum_z]
		)

	rig.queue_free()
	await process_frame
	_report()


## Returns the draw order of the stratum immediately behind the foreground one,
## which is the layer the miner stands on while mining.
func _get_second_stratum_z(profile: TerrainLayerProfile) -> int:
	var orders: Array[int] = []
	for layer_index in range(profile.get_layer_count()):
		orders.append(profile.get_layer_z_index(layer_index))
	orders.sort()
	orders.reverse()
	return orders[1] if orders.size() > 1 else orders[0]


func _report() -> void:

	if _failures.is_empty():
		print("CAST_DRAW_ORDER_VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("CAST_DRAW_ORDER_VERIFY: FAIL (%d)" % _failures.size())
	quit(1)
