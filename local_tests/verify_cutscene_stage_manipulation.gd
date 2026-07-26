extends SceneTree

## How it works:
## - Builds a small stage with two actor previews and one composed prop.
## - Exercises Cast selection, group alignment/distribution, and undo.
## - Uses a deterministic sculpt preview to prove all selected origins floor snap.
## - Captures the three movement-authoring requests and checks stage coordinates.
## The invariant is that staging tools mutate scene-node positions only through
## one undo action and never reinterpret child sprites as independent props.


class TestTerrainPreview extends CinematicTerrainPreview:
	func global_position_to_sculpt_local(global_point: Vector2) -> Vector2:
		return global_point

	func sculpt_local_to_global_position(local_cell: Vector2) -> Vector2:
		return local_cell


var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var stage := CharacterEncounterStage.new()
	var prop_root := Node2D.new()
	prop_root.name = &"PropMarkers"
	stage.add_child(prop_root)

	var actor_a := _make_actor(&"actor_a", Vector2(0.0, 2.0))
	var actor_b := _make_actor(&"actor_b", Vector2(20.0, 4.0))
	stage.add_child(actor_a)
	stage.add_child(actor_b)
	var prop := Node2D.new()
	prop.name = &"Table"
	prop.position = Vector2(100.0, 6.0)
	prop_root.add_child(prop)
	var prop_target := Marker2D.new()
	prop_target.name = &"TableDestination"
	prop_root.add_child(prop_target)

	var preview := TestTerrainPreview.new()
	stage.add_child(preview)
	var sculpt := CutsceneTerrainSculpt.new()
	sculpt.grid_size = Vector2i(128, 24)
	sculpt.anchor_offset_cells = Vector2i(0, -12)
	sculpt.protected_floor_rows = 3
	sculpt.fill_all(false)

	var context := CutsceneEditorContext.new()
	context.stage = stage
	context.preview = preview
	context.sculpt = sculpt
	context.scene_root = stage
	context.sequence = CutsceneSequence.new()

	var history := UndoRedo.new()
	var panel := CutsceneCastPanel.new()
	var timeline := CutsceneTimelinePanel.new()
	timeline.set_context(context)
	panel.set_standalone_test_undo_redo(history)
	panel.set_context(context)
	panel.set_selected_stage_nodes([actor_a, actor_b, prop])

	_expect(
		context.get_stage_props() == [prop],
		"Only direct composed prop roots, not target markers, should move."
	)
	_expect(
		panel.align_selected(CutsceneCastPanel.AlignMode.LEFT) == 2,
		"Left alignment should move the two objects right of the anchor."
	)
	_expect_positions_x(context, [actor_a, actor_b, prop], 0.0)
	history.undo()
	_expect_vector(actor_b.position, Vector2(20.0, 4.0), "Alignment undo")
	_expect_vector(prop.position, Vector2(100.0, 6.0), "Prop alignment undo")

	panel.set_selected_stage_nodes([actor_a, actor_b, prop])
	_expect(
		panel.distribute_selected(
			CutsceneCastPanel.DistributeAxis.HORIZONTAL
		) == 1,
		"Horizontal distribution should move only the middle object."
	)
	_expect_vector(actor_b.position, Vector2(50.0, 4.0), "Distributed middle")
	history.undo()

	panel.set_selected_stage_nodes([actor_a, actor_b, prop])
	actor_a.position.y = 13.0
	_expect(
		panel.snap_selected_to_floor() == 3,
		"Every selected origin, including one inside rock, should floor snap."
	)
	for node in [actor_a, actor_b, prop]:
		_expect(
			is_equal_approx(
				context.get_stage_local_position(node).y,
				12.0
			),
			"%s did not snap to logical row 12." % node.name
		)
	history.undo()
	actor_a.position.y = 2.0

	var starts: Array[Dictionary] = []
	var destinations: Array[Dictionary] = []
	var creations: Array[Dictionary] = []
	context.movement_start_position_requested.connect(
		func(actor_id: StringName, position: Vector2) -> void:
			starts.append({"actor": actor_id, "position": position})
	)
	context.movement_destination_position_requested.connect(
		func(actor_id: StringName, position: Vector2) -> void:
			destinations.append({"actor": actor_id, "position": position})
	)
	context.movement_beat_creation_requested.connect(
		func(actor_id: StringName, position: Vector2) -> void:
			creations.append({"actor": actor_id, "position": position})
	)
	var actor_a_move := _make_move(&"actor_a")
	var actor_b_move := _make_move(&"actor_b")
	context.sequence.beats = [actor_a_move, actor_b_move]
	timeline._set_selection([actor_a_move, actor_b_move], actor_b_move)
	panel.set_selected_stage_nodes([actor_a, actor_b, prop])
	_expect(
		panel.record_selected_positions_as_start() == 2,
		"Start capture should request one position per selected actor."
	)
	_expect(
		panel.record_selected_positions_as_destination() == 2,
		"Destination capture should request one position per selected actor."
	)
	_expect(
		starts.size() == 2
		and destinations.size() == 2
		and creations.is_empty(),
		"Movement request signals should exclude props."
	)
	_expect(
		starts[0]["actor"] == &"actor_a"
		and starts[0]["position"] == Vector2(0.0, 2.0),
		"Captured movement coordinates must remain stage-local."
	)
	_expect_vector(
		actor_a_move.target_offset,
		Vector2(0.0, 2.0),
		"Actor A grouped destination"
	)
	_expect_vector(
		actor_b_move.target_offset,
		Vector2(20.0, 4.0),
		"Actor B grouped destination"
	)

	# A scrubbed MOVE temporarily places actor A at x=40. Staging that visible
	# position must record undo against its authored x=0, not the preview x=40.
	actor_a_move.target_offset = Vector2(40.0, 2.0)
	timeline._set_scrub_time(1.0, true)
	panel.set_selected_stage_nodes([actor_a, prop])
	_expect(
		panel.align_selected(CutsceneCastPanel.AlignMode.LEFT) == 2,
		"Scrubbed staging should commit both visible targets against base state."
	)
	history.undo()
	timeline._restore_preview_states()
	_expect_vector(actor_a.position, Vector2(0.0, 2.0), "Scrubbed staging undo")
	_expect_vector(prop.position, Vector2(100.0, 6.0), "Scrubbed prop undo")

	panel.set_selected_stage_nodes([actor_a, actor_b, prop])
	_expect(
		panel.create_movements_from_selected_positions() == 2,
		"Create Move should request one beat per selected actor."
	)
	_expect(
		creations.size() == 2,
		"Movement creation signals should exclude props."
	)

	history.clear_history(false)
	panel.free()
	timeline.free()
	stage.free()
	if _failures.is_empty():
		print("CUTSCENE_STAGE_MANIPULATION_VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print(
		"CUTSCENE_STAGE_MANIPULATION_VERIFY: FAIL (%d)"
		% _failures.size()
	)
	quit(1)


func _make_actor(
	actor_id: StringName,
	position: Vector2
) -> CutsceneActorPreview:
	var actor := CutsceneActorPreview.new()
	actor.actor_id = actor_id
	actor.position = position
	return actor


func _make_move(actor_id: StringName) -> CutsceneBeat:
	var beat := CutsceneBeat.new()
	beat.kind = CutsceneBeat.Kind.MOVE
	beat.actor = actor_id
	beat.duration_seconds = 1.0
	beat.target_offset = Vector2(1.0, 1.0)
	return beat


func _expect_positions_x(
	context: CutsceneEditorContext,
	nodes: Array,
	expected_x: float
) -> void:
	for node: Node2D in nodes:
		_expect(
			is_equal_approx(
				context.get_stage_local_position(node).x,
				expected_x
			),
			"%s was not aligned to x=%s." % [node.name, expected_x]
		)


func _expect_vector(
	actual: Vector2,
	expected: Vector2,
	label: String
) -> void:
	_expect(
		actual.is_equal_approx(expected),
		"%s expected %s, got %s." % [label, expected, actual]
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
