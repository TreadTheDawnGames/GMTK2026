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

	if cutscene_order <= frontmost_terrain_z:
		_failures.append(
			(
				"Cutscene cast order %d does not clear the frontmost terrain "
				+ "stratum at %d, so every cutscene would play behind the rock."
			) % [cutscene_order, frontmost_terrain_z]
		)
	# Mining and cutscenes deliberately stand him on different strata: down in the
	# dig while he works, lifted clear of it while a shot holds on him. Both ends
	# of that are asserted, because a single number satisfying one and not the
	# other is exactly how this goes wrong.
	if buried_order >= frontmost_terrain_z:
		_failures.append(
			(
				"Buried order %d is not behind the foreground stratum at %d, so "
				+ "the miner would stop reading as being down in his dig."
			) % [buried_order, frontmost_terrain_z]
		)
	var second_stratum_z := _get_second_stratum_z(profile)
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
