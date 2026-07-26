extends SceneTree

## Proves a cutscene's cast is drawn in the rock they are standing in, on the
## same stratum the miner occupies while he is digging.
##
## Cutscenes used to lift the whole cast clear of every stratum so a held shot
## showed whole characters. Zephan's direction reversed that: the cast belong in
## the ground the way the player does, with their feet covered, rather than being
## cut out in front of it. So the cutscene order and the mining order now name the
## same stratum, and this check tests that they still do.
##
## Both are compared against whatever the terrain profile's strata actually draw
## at. Those numbers live in a different file and nothing else ties them together:
## add a stratum, or renumber the existing ones, and the cast quietly ends up on
## the wrong side of the rock with no error anywhere. Too far forward and they are
## pasted on top of the ground; too far back and they are simply gone behind the
## dirt.
##
## The invariant is that both orders sit strictly between the two frontmost
## strata: behind the foreground layer, in front of the one it stands on.

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
	# Mining and cutscenes deliberately stand the cast on the SAME stratum now, so
	# both orders get the same pair of assertions rather than opposite ones.
	if cutscene_order >= frontmost_terrain_z:
		_failures.append(
			(
				"Cutscene cast order %d is not behind the foreground stratum at "
				+ "%d, so the cast would be pasted on top of the ground instead "
				+ "of standing in it."
			) % [cutscene_order, frontmost_terrain_z]
		)
	if cutscene_order <= second_stratum_z:
		_failures.append(
			(
				"Cutscene cast order %d is not in front of the second stratum at "
				+ "%d, so every cutscene would play behind the rock."
			) % [cutscene_order, second_stratum_z]
		)
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
