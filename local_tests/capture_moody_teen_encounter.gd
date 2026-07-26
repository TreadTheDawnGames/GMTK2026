extends SceneTree

## How it works:
## - Instantiates the real inherited stage and keeps editor previews alive.
## - Inserts Moody Teen only into an in-memory copy of the shipped schedule.
## - The production terrain manager, four-stratum renderer, and floor shader draw.
## - Captures fall discovery, settled two-shot, first impact, and F3 parity.
## - The invariant is that capture setup never writes the shared schedule.
##
## Run with:
##   godot --rendering-driver opengl3 --path . --script res://local_tests/capture_moody_teen_encounter.gd

const STAGE_SCENE: PackedScene = preload(
	"res://Scenes/cinematics/moody_teen_encounter_stage.tscn"
)
const ENCOUNTER: DepthCharacterEncounter = preload(
	"res://resources/encounters/moody_teen_first_encounter.tres"
)
const SCHEDULE: DepthEncounterConfig = preload(
	"res://resources/encounters/depth_encounter_config.tres"
)
const OUTPUT_DIRECTORY: String = "user://moody_teen_capture"
const VIEWPORT_SIZE := Vector2i(1152, 648)
const MINER_STAGE_X: float = -176.0
const FALL_CAMERA_Y: float = -200.0
const SETTLE_FRAMES: int = 30
const FLOOR_WORLD_Y: float = float(38 + 5000) * 8.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	)
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var stage := STAGE_SCENE.instantiate()
	var preview := stage.get_node_or_null(^"EditorTerrainPreview")
	if preview == null:
		push_error("Moody Teen stage has no production terrain preview.")
		quit(1)
		return
	preview.remove_in_running_game = false
	preview.encounter_config = _make_capture_schedule()
	for child in stage.get_children():
		if child.get_script() == null:
			continue
		if "remove_in_running_game" in child and child != preview:
			child.remove_in_running_game = false
	viewport.add_child(stage)

	var camera := Camera2D.new()
	viewport.add_child(camera)
	camera.make_current()
	preview.build_preview()
	preview.terrain_renderer.set_trodden_floor(true, FLOOR_WORLD_Y)
	var letterbox := _add_letterbox(viewport)

	for _settle_frame in range(SETTLE_FRAMES):
		await process_frame

	var captured := 0
	captured += 1 if await _capture(
		viewport,
		camera,
		Vector2(MINER_STAGE_X, FALL_CAMERA_Y),
		"01_fall_discovery.png"
	) else 0
	captured += 1 if await _capture(
		viewport,
		camera,
		Vector2(MINER_STAGE_X, 0.0),
		"02_settled_stare.png"
	) else 0

	# A real test impact through the production preview demonstrates that the
	# authored cave remains mineable rather than being a decorative backdrop.
	preview.dig_at_world_position(Vector2(MINER_STAGE_X, -544.0))
	for _impact_frame in range(10):
		await process_frame
	captured += 1 if await _capture(
		viewport,
		camera,
		Vector2(MINER_STAGE_X, -320.0),
		"03_first_impact.png"
	) else 0

	preview.terrain_renderer.set("_show_logical_overlay", true)
	preview.terrain_renderer.queue_redraw()
	print(
		"MOODY_TEEN_CAPTURE: F3 overlay=%s"
		% preview.terrain_renderer.get("_show_logical_overlay")
	)
	captured += 1 if await _capture(
		viewport,
		camera,
		Vector2(MINER_STAGE_X, 0.0),
		"04_f3_logical_parity.png"
	) else 0
	preview.terrain_renderer.set("_show_logical_overlay", false)
	preview.terrain_renderer.queue_redraw()

	# The actor does not depart, so the closing handoff intentionally matches
	# the settled composition rather than inventing an extra gesture.
	captured += 1 if await _capture(
		viewport,
		camera,
		Vector2(MINER_STAGE_X, 0.0),
		"05_closing_handoff.png"
	) else 0

	_resize_capture(viewport, letterbox, Vector2i(960, 720))
	for _resize_frame in range(10):
		await process_frame
	captured += 1 if await _capture(
		viewport,
		camera,
		Vector2(MINER_STAGE_X, 0.0),
		"11_4x3_settled.png"
	) else 0
	_resize_capture(viewport, letterbox, Vector2i(1680, 720))
	for _resize_frame in range(10):
		await process_frame
	captured += 1 if await _capture(
		viewport,
		camera,
		Vector2(MINER_STAGE_X, 0.0),
		"12_21x9_settled.png"
	) else 0

	var preview_error: String = preview.get_preview_error()
	if not preview_error.is_empty():
		push_error("Preview reported: %s" % preview_error)
	print(
		"MOODY_TEEN_CAPTURE: %d frames in %s"
		% [captured, ProjectSettings.globalize_path(OUTPUT_DIRECTORY)]
	)
	quit(0 if captured == 7 and preview_error.is_empty() else 1)


func _make_capture_schedule() -> DepthEncounterConfig:
	var schedule := SCHEDULE.duplicate(true) as DepthEncounterConfig
	var encounters: Array[DepthCharacterEncounter] = []
	for encounter in schedule.encounters:
		encounters.append(encounter)
	encounters.insert(4, ENCOUNTER)
	schedule.encounters = encounters
	return schedule


func _capture(
	viewport: SubViewport,
	camera: Camera2D,
	camera_position: Vector2,
	file_name: String
) -> bool:
	camera.position = camera_position
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	if image == null:
		push_error("Nothing rendered for %s." % file_name)
		return false
	var output_path := "%s/%s" % [OUTPUT_DIRECTORY, file_name]
	if image.save_png(output_path) != OK:
		push_error("Could not write %s." % output_path)
		return false
	return true


func _add_letterbox(viewport: SubViewport) -> CanvasLayer:
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	viewport.add_child(overlay)
	for is_top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		overlay.add_child(bar)
	_resize_capture(viewport, overlay, viewport.size)
	return overlay


func _resize_capture(
	viewport: SubViewport,
	letterbox: CanvasLayer,
	size: Vector2i
) -> void:
	viewport.size = size
	var bar_height := float(size.y) * 0.14
	var bars := letterbox.get_children()
	for index in range(bars.size()):
		var bar := bars[index] as ColorRect
		bar.size = Vector2(float(size.x), bar_height)
		bar.position = Vector2(
			0.0,
			0.0 if index == 0 else float(size.y) - bar_height
		)
