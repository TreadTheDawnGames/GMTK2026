extends SceneTree

## Proves a cutscene's cast is drawn above every terrain stratum while the
## ordinary buried Miner remains between the first two.
##
## The previous test asserted that Layer 1 covered cutscene feet. The final
## Encounter 9 ruling explicitly reverses that: people and props stand on the
## shader surface and Layer 1 may not overlap them. Mining remains unchanged.
##
## Both are compared against whatever the terrain profile's strata actually draw
## at. Those numbers live in a different file and nothing else ties them together:
## add a stratum, or renumber the existing ones, and the cast quietly ends up on
## the wrong side of the rock with no error anywhere. Too far forward and they are
## pasted on top of the ground; too far back and they are simply gone behind the
## dirt.
##
## The invariant is that cutscene order is strictly above the frontmost stratum,
## while buried order remains strictly between the two frontmost strata.

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
	# Cutscenes and mining deliberately use different planes. The held tableau is
	# fully readable above Layer 1; the active mining shaft retains its occlusion.
	if cutscene_order <= frontmost_terrain_z:
		_failures.append(
			(
				"Cutscene cast order %d is not above the foreground stratum at "
				+ "%d, so Layer 1 would overlap the authored shader tableau."
			) % [cutscene_order, frontmost_terrain_z]
		)
	# Both ends of the Miner's own mining order remain asserted, because this
	# visual correction must not flatten ordinary digging.
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
