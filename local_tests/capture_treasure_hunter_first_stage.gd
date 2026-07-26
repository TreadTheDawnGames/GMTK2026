extends SceneTree

## Renders the Treasure Hunter's first room the way the encounter frames it, so
## the cavern and its depth planes can be judged by eye instead of by cell count.
##
## How it works:
## - Instantiates the real stage and keeps its EditorTerrainPreview alive, which
##   normally deletes itself in a running game. That branch holds a production
##   TerrainManager and TerrainLayerRenderer, so what this draws is the same
##   rock, shader, profile and room mask the game draws.
## - Switches the shared trodden-floor ground treatment on at this encounter's
##   own floor line, because the encounter resource now opts into it and a
##   capture without it answers a question about a shot that no longer exists.
## - Frames it at 1152x648 with the ground line at half the viewport, at the
##   dead-centre landing and at both ends of the 49-column landing band. The
##   band is the whole reason the third and fourth frames exist: the wall he
##   breaks is fixed rock and cannot follow him, so the leftmost landing is the
##   run that sees least of it.
## - Draws the cinematic letterbox over every frame, because the bars cover the
##   top and bottom of the real shot and a capture without them flatters the
##   framing.
##
## Run it with a real renderer, not headless - a headless run returns null
## images:
##   godot --rendering-driver opengl3 --path . --script res://local_tests/capture_treasure_hunter_first_stage.gd

const STAGE_SCENE: PackedScene = preload(
	"res://Scenes/cinematics/treasure_hunter_first_encounter_stage.tscn"
)
const ENCOUNTER: Resource = preload(
	"res://resources/encounters/treasure_hunter_first_encounter.tres"
)
const MINING_CONFIG: Resource = preload(
	"res://resources/mining/mining_config.tres"
)
const OUTPUT_DIRECTORY: String = "user://treasure_hunter_first_capture"
const VIEWPORT_SIZE := Vector2i(1152, 648)

## The other shapes this room has to survive.
##
## The project stretches with aspect "expand", so a different window does not
## letterbox the shot - it shows MORE world. A taller viewport reveals rock above
## the carved roof and ground below the floor, and a wider one reaches past both
## ends of the room. That is where a raw layer seam or a bright void shows up,
## and it is the one thing the authored 16:9 frame can never tell you.
const ASPECT_VARIANTS: Array[Vector2i] = [
	Vector2i(1152, 720),
	Vector2i(1152, 864),
	Vector2i(1512, 648),
]

## Where a dead-centre landing puts the miner in the stage's own coordinates:
## the stage sits 22 cells right of the terrain centre, so he is 176px left of
## its origin.
const MINER_STAGE_X: float = -176.0
## The two ends of the 49-column landing band, 24 cells either side at 8 world
## units a cell.
const LANDING_HALF_SPAN_PIXELS: float = 192.0
## The middle of the plug he mines through, in the same space: terrain column
## 262 against the stage's own origin at column 214.
const WALL_STRIKE_STAGE_X: float = 384.0
## The cinematic frame's own bar_height_ratio. Applied against whatever height
## the viewport currently has, so an aspect variant gets its real bars.
const BAR_HEIGHT_RATIO: float = 0.14
## Frames to let the terrain stream and the room bake before reading pixels.
const SETTLE_FRAMES: int = 30

var _captured: int = 0
var _expected: int = 0


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
	_dress_trodden_floor(preview)
	_add_letterbox(viewport)

	for _settle_frame in range(SETTLE_FRAMES):
		await process_frame

	await _capture(viewport, camera, MINER_STAGE_X, "01_centre_landing.png")
	await _capture(
		viewport,
		camera,
		MINER_STAGE_X - LANDING_HALF_SPAN_PIXELS,
		"02_leftmost_landing.png"
	)
	await _capture(
		viewport,
		camera,
		MINER_STAGE_X + LANDING_HALF_SPAN_PIXELS,
		"03_rightmost_landing.png"
	)
	await _capture(viewport, camera, WALL_STRIKE_STAGE_X, "04_sealed_wall.png")
	await _capture_aspect_variants(viewport, camera)

	if preview != null and preview.has_method(&"get_preview_error"):
		var preview_error: String = preview.get_preview_error()
		if not preview_error.is_empty():
			push_error("Preview reported: %s" % preview_error)

	print(
		"TREASURE_HUNTER_FIRST_CAPTURE: %d/%d frames in %s"
		% [
			_captured,
			_expected,
			ProjectSettings.globalize_path(OUTPUT_DIRECTORY),
		]
	)
	quit(0 if _captured == _expected else 1)


## Turns on the same shared ground treatment the encounter now opts into.
##
## The floor line is derived from the encounter's own depth and the config's
## cell size, exactly as DepthEncounterController derives it, so this capture
## cannot dress a line the running game would put somewhere else.
func _dress_trodden_floor(preview: Node) -> void:
	if preview == null:
		return
	if not ENCOUNTER.dresses_trodden_floor:
		return
	var renderer := preview.get_node_or_null(^"TerrainLayerRenderer")
	if renderer == null or not renderer.has_method(&"set_trodden_floor"):
		push_error("The preview has no renderer to dress the floor on.")
		return
	var floor_world_y := float(
		MINING_CONFIG.initial_surface_row + ENCOUNTER.depth_from_surface
	) * float(MINING_CONFIG.terrain_cell_world_size)
	renderer.set_trodden_floor(true, floor_world_y)


## Re-renders the centre landing at every other shape the game can open in.
##
## The letterbox is rebuilt per shape rather than scaled, because the bars are a
## ratio of viewport height and a capture that kept the 16:9 bars would hide
## exactly the extra world these frames exist to show.
func _capture_aspect_variants(
	viewport: SubViewport,
	camera: Camera2D
) -> void:
	for variant: Vector2i in ASPECT_VARIANTS:
		viewport.size = variant
		_rebuild_letterbox(viewport)
		await process_frame
		await process_frame
		await _capture(
			viewport,
			camera,
			MINER_STAGE_X,
			"05_aspect_%dx%d.png" % [variant.x, variant.y]
		)
	viewport.size = VIEWPORT_SIZE
	_rebuild_letterbox(viewport)
	await process_frame


## THE F3 PARITY OVERLAY CANNOT BE CAPTURED HERE, AND THIS NOTE IS WHY.
##
## Three things were tried and all three produce a frame that looks like a pass:
## SubViewport.push_input never reaches _unhandled_key_input without a
## SubViewportContainer above it; Input.parse_input_event does not reach it
## either in a --script harness; and calling the renderer's handler directly does
## flip the flag but still draws nothing, because TerrainLayerRenderer._draw()
## paints at the renderer node's own transform and EditorTerrainPreview holds it
## at z_index -100 - so the green wash lands behind every chunk sprite it is
## meant to be over. F3 works in a real run; it cannot work through this preview.
##
## The parity question this pass actually raises is answered instead where it can
## be proven: carve_treasure_hunter_first_room.gd asserts that stratum zero is
## identical to the logical mask, cell for cell. That is the invariant - the front
## silhouette the player reads is the silhouette collision agrees with - and a
## numeric check over 46,080 cells is better evidence for it than a screenshot.


## Replaces the letterbox with one sized for the viewport's current shape.
func _rebuild_letterbox(viewport: SubViewport) -> void:
	for child in viewport.get_children():
		if child is CanvasLayer:
			viewport.remove_child(child)
			child.queue_free()
	_add_letterbox(viewport)


## Points the camera at one stage column and writes that frame to disk.
##
## The camera's y stays on the dig line because that is what the encounter
## framing does: it centres the ground the cast stand on, not the room.
func _capture(
	viewport: SubViewport,
	camera: Camera2D,
	stage_x: float,
	file_name: String
) -> void:
	_expected += 1
	camera.position = Vector2(stage_x, 0.0)
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	if image == null:
		push_error("Nothing rendered for %s." % file_name)
		return
	var output_path := "%s/%s" % [OUTPUT_DIRECTORY, file_name]
	if image.save_png(output_path) != OK:
		push_error("Could not write %s." % output_path)
		return
	_captured += 1


## Lays the cinematic frame's bars over the capture.
func _add_letterbox(viewport: SubViewport) -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	viewport.add_child(overlay)
	for is_top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.0, 0.0, 0.0, 1.0)
		var bar_height := float(viewport.size.y) * BAR_HEIGHT_RATIO
		bar.size = Vector2(float(viewport.size.x), bar_height)
		bar.position = Vector2(
			0.0,
			0.0 if is_top else float(viewport.size.y) - bar_height
		)
		overlay.add_child(bar)
