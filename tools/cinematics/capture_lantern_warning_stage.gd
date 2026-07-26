extends SceneTree

## How it works:
## - Instantiates Encounter 5's real stage and production terrain preview.
## - Captures wide, landing, dialogue, fade, handoff, parity, and 4:3 frames.
## - ENCOUNTER_5_CAPTURE_DIR routes private evidence outside the repository.
## - The stage is never modified; temporary alpha and overlay state are local.
## - The invariant is that every frame uses the shipped sculpt and renderer.

const STAGE_SCENE: PackedScene = preload(
	"res://Scenes/cinematics/lantern_warning_encounter_stage.tscn"
)
const DEFAULT_OUTPUT_DIRECTORY: String = "user://encounter_5_capture"
const WIDE_VIEWPORT_SIZE := Vector2i(1152, 648)
const FOUR_THREE_VIEWPORT_SIZE := Vector2i(1024, 768)
const MINER_STAGE_X: float = -176.0
const CONVERSATION_MIDPOINT_X: float = -95.8
const DIALOGUE_ZOOM := Vector2(1.4, 1.4)
const SETTLE_FRAMES: int = 30

var _output_directory: String
var _viewport: SubViewport
var _stage: Node2D
var _camera: Camera2D
var _preview: CinematicTerrainPreview
var _top_bar: ColorRect
var _bottom_bar: ColorRect


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_output_directory = OS.get_environment("ENCOUNTER_5_CAPTURE_DIR")
	if _output_directory.is_empty():
		_output_directory = ProjectSettings.globalize_path(
			DEFAULT_OUTPUT_DIRECTORY
		)
	DirAccess.make_dir_recursive_absolute(_output_directory)
	_build_capture_stage()
	for _settle_frame in range(SETTLE_FRAMES):
		await process_frame

	var captured := 0
	captured += int(await _capture(
		"01_wide_discovery.png",
		Vector2(MINER_STAGE_X, -24.0),
		Vector2(0.9, 0.9)
	))
	captured += int(await _capture(
		"02_landing.png",
		Vector2(MINER_STAGE_X, 0.0),
		Vector2.ONE
	))
	captured += int(await _capture(
		"03_dialogue.png",
		Vector2(CONVERSATION_MIDPOINT_X, 0.0),
		DIALOGUE_ZOOM
	))
	_set_keeper_and_bench_alpha(0.5)
	captured += int(await _capture(
		"04_closing_mid_fade.png",
		Vector2(CONVERSATION_MIDPOINT_X, 0.0),
		DIALOGUE_ZOOM
	))
	_set_keeper_and_bench_alpha(0.0)
	captured += int(await _capture(
		"05_closing_handoff.png",
		Vector2(MINER_STAGE_X, 0.0),
		Vector2.ONE
	))
	_set_keeper_and_bench_alpha(1.0)
	_set_logical_overlay(true)
	captured += int(await _capture(
		"06_f3_parity.png",
		Vector2(MINER_STAGE_X, 0.0),
		Vector2.ONE
	))
	_set_logical_overlay(false)
	_resize_viewport(FOUR_THREE_VIEWPORT_SIZE)
	captured += int(await _capture(
		"07_dialogue_4_3.png",
		Vector2(CONVERSATION_MIDPOINT_X, 0.0),
		DIALOGUE_ZOOM
	))

	var preview_error := _preview.get_preview_error()
	if not preview_error.is_empty():
		push_error("Encounter 5 preview reported: %s" % preview_error)
	print(
		"ENCOUNTER_5_CAPTURE: %d/7 frames in %s"
		% [captured, _output_directory]
	)
	quit(0 if captured == 7 and preview_error.is_empty() else 1)


func _build_capture_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.size = WIDE_VIEWPORT_SIZE
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	_stage = STAGE_SCENE.instantiate()
	_preview = _stage.get_node(^"EditorTerrainPreview") as CinematicTerrainPreview
	_preview.remove_in_running_game = false
	for child in _stage.get_children():
		if child.get_script() == null:
			continue
		if "remove_in_running_game" in child and child != _preview:
			child.remove_in_running_game = false
	_viewport.add_child(_stage)
	_camera = Camera2D.new()
	_viewport.add_child(_camera)
	_camera.make_current()
	_preview.build_preview()
	_add_letterbox()


func _capture(
	file_name: String,
	camera_position: Vector2,
	camera_zoom: Vector2
) -> bool:
	_camera.position = camera_position
	_camera.zoom = camera_zoom
	await process_frame
	await process_frame
	var image := _viewport.get_texture().get_image()
	if image == null:
		push_error("Nothing rendered for %s." % file_name)
		return false
	var output_path := _output_directory.path_join(file_name)
	if image.save_png(output_path) != OK:
		push_error("Could not write %s." % output_path)
		return false
	return true


func _set_keeper_and_bench_alpha(alpha: float) -> void:
	var keeper := _stage.get_node(^"cloak_lantern") as CanvasItem
	var bench := _stage.get_node(^"PropMarkers/Bench") as CanvasItem
	keeper.modulate.a = alpha
	bench.modulate.a = alpha


func _set_logical_overlay(enabled: bool) -> void:
	_preview.terrain_renderer._show_logical_overlay = enabled
	_preview.terrain_renderer.queue_redraw()


func _resize_viewport(size: Vector2i) -> void:
	_viewport.size = size
	var bar_height := float(size.y) * 0.14
	_top_bar.size = Vector2(float(size.x), bar_height)
	_top_bar.position = Vector2.ZERO
	_bottom_bar.size = Vector2(float(size.x), bar_height)
	_bottom_bar.position = Vector2(0.0, float(size.y) - bar_height)


func _add_letterbox() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	_viewport.add_child(overlay)
	_top_bar = ColorRect.new()
	_bottom_bar = ColorRect.new()
	for bar in [_top_bar, _bottom_bar]:
		bar.color = Color.BLACK
		overlay.add_child(bar)
	_resize_viewport(WIDE_VIEWPORT_SIZE)
