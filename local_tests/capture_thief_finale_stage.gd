extends SceneTree

## Renders the Thief finale exactly as the game frames it, so the shot can be
## judged by eye instead of by arithmetic.
##
## How it works:
## - Instantiates the real stage and keeps its EditorTerrainPreview alive, which
##   normally deletes itself in a running game. That branch holds a production
##   TerrainManager and TerrainLayerRenderer, so what this draws is the same
##   rock, shader, profile and room mask the game draws. There is no
##   approximation here to drift out of step.
## - Frames it the way the encounter camera does: 1152x648 with the ground line
##   at half the viewport height, centred first on where a dead-centre landing
##   puts the miner and then on where the pan ends.
## - Draws the cinematic letterbox over both, because the top bar covers the
##   first 91px and the organ is deliberately authored to run behind it. A
##   capture without the bars would answer the wrong question.
##
## Run it with a real renderer, not headless:
##   godot --rendering-driver opengl3 --path . --script res://local_tests/capture_thief_finale_stage.gd

const STAGE_SCENE: PackedScene = preload(
	"res://Scenes/cinematics/thief_finale_encounter_stage.tscn"
)
const OUTPUT_DIRECTORY: String = "user://finale_capture"
const VIEWPORT_SIZE := Vector2i(1152, 648)
## Where a dead-centre landing puts the miner, in the stage's own coordinates.
const MINER_STAGE_X: float = -176.0
## Where the organ stands, and therefore where the pan ends.
const ORGAN_STAGE_X: float = 784.0
## The cinematic frame's bar_height_ratio against the viewport height.
const BAR_HEIGHT: float = 648.0 * 0.14
## Frames to let the terrain stream and the room bake before reading pixels.
const SETTLE_FRAMES: int = 30


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
	# Before it enters the tree: the previews delete themselves in _enter_tree,
	# and Godot readies children first, so there is no later moment to say this.
	# The cast stand-ins matter as much as the terrain here - the whole reason to
	# render the shot is to see the figure against the instrument.
	var preview := stage.get_node_or_null(^"EditorTerrainPreview")
	if preview != null:
		preview.remove_in_running_game = false
	for child in stage.get_children():
		if child.get_script() == null:
			continue
		if "remove_in_running_game" in child and child != preview:
			child.remove_in_running_game = false
	viewport.add_child(stage)

	var camera := Camera2D.new()
	viewport.add_child(camera)
	camera.make_current()

	if preview != null and preview.has_method(&"build_preview"):
		preview.build_preview()

	_add_letterbox(viewport)

	for _settle_frame in range(SETTLE_FRAMES):
		await process_frame

	var captured := 0
	captured += 1 if await _capture(
		viewport, camera, MINER_STAGE_X, "01_landing.png"
	) else 0
	captured += 1 if await _capture(
		viewport, camera, ORGAN_STAGE_X, "02_organ.png"
	) else 0
	# Halfway through the pan, which is the framing neither end of the move
	# shows and the one most likely to be crossing bare wall.
	captured += 1 if await _capture(
		viewport,
		camera,
		(MINER_STAGE_X + ORGAN_STAGE_X) * 0.5,
		"03_mid_pan.png"
	) else 0

	if preview != null and preview.has_method(&"get_preview_error"):
		var preview_error: String = preview.get_preview_error()
		if not preview_error.is_empty():
			push_error("Preview reported: %s" % preview_error)

	print(
		"THIEF_FINALE_CAPTURE: %d frames in %s"
		% [captured, ProjectSettings.globalize_path(OUTPUT_DIRECTORY)]
	)
	quit(0 if captured == 3 else 1)


## Points the camera at one stage column and writes that frame to disk.
##
## The camera's y stays on the dig line because that is what the encounter
## framing does: it centres the ground the cast stand on, not the room.
func _capture(
	viewport: SubViewport,
	camera: Camera2D,
	stage_x: float,
	file_name: String
) -> bool:
	camera.position = Vector2(stage_x, 0.0)
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


## Lays the cinematic frame's bars over the capture.
func _add_letterbox(viewport: SubViewport) -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	viewport.add_child(overlay)
	for is_top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.0, 0.0, 0.0, 1.0)
		bar.size = Vector2(float(VIEWPORT_SIZE.x), BAR_HEIGHT)
		bar.position = Vector2(
			0.0,
			0.0 if is_top else float(VIEWPORT_SIZE.y) - BAR_HEIGHT
		)
		overlay.add_child(bar)
