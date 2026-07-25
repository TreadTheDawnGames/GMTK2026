class_name SurfacePresentation
extends Node

## How it works:
## - Two authored fullscreen rects share one horizon: the sky behind everything
##   and the warm sunlight wash over the whole shot.
## - Both need the same two values: where the original ground line sits on
##   screen and where the sun sits on screen. This node is their single source.
## - The ground line comes from the terrain view, so digging scrolls daylight up
##   out of frame with no extra bookkeeping.
## - Grass and crust are NOT here. They belong to the foreground stratum in
##   terrain_layer.gdshader, so that mining removes them with the ground.
## - Both rects are resized in world units to whatever the camera can see, so
##   daylight never stops short of the frame edge. At gameplay zoom that is the
##   authored full-viewport rect; while the opening shot is still zoomed out it
##   is a much larger area.
## - Both shaders nonetheless paint in viewport pixels, so everything published
##   here is converted into the frame first, and each rect is told how large it
##   currently draws. That is what holds the sun, the clouds, and the distant
##   ridges still while the opening shot zooms in: without it the backdrop is
##   pinned to a rect that is moving and shrinking under it, and it swims.
## The invariant is that both rects agree on the horizon and the sun.

# Pixels of backdrop carried past every frame edge, so a fractional zoom can
# never round a seam of clear colour into the shot.
const _BACKDROP_OVERSCAN_PX: float = 2.0

@export_category("References")
@export var terrain_manager: TerrainManager
@export var config: MiningConfig
@export var sky_rect: ColorRect
@export var sunlight_wash_rect: ColorRect
## The shot's camera. Both rects follow what it can see. Leaving it empty keeps
## the authored full-viewport rects exactly as they are.
@export var camera: Camera2D

@export_category("Sun")
## Viewport pixels. Every rect reads this, so the halo in the sky and the warm
## pool on the ground always sit under the same sun. Only x is taken from it:
## the sun is set against the horizon, not against the frame.
@export var sun_screen_position: Vector2 = Vector2(676.0, 284.0)
## How far below the ground line the sun's centre sits, which is the whole of
## the setting. Only its top sliver and its halo clear the horizon, so the light
## rises from below instead of falling from above.
##
## It is measured from the ground line rather than pinned to a screen row
## because the ground line is the only thing here that moves: the opening shot
## zooms, and digging scrolls the surface up out of frame. Pinned to a row, the
## sun climbed off the horizon and read as a flat disc pasted in the sky the
## moment either happened. Raising this to zero puts the whole disc above the
## land and turns the shot back into midday.
@export_range(-200.0, 200.0, 1.0) var sun_below_horizon_px: float = 24.0

var _sky_material: ShaderMaterial
var _wash_material: ShaderMaterial
var _last_surface_screen_y: float = NAN
var _last_viewport_size: Vector2 = Vector2.ZERO
var _last_backdrop_screen_size: Vector2 = Vector2.ZERO
var _last_sun_screen_position: Vector2 = Vector2(NAN, NAN)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if (
		terrain_manager == null
		or config == null
		or sky_rect == null
		or sunlight_wash_rect == null
	):
		push_error("SurfacePresentation references are incomplete.")
		set_process(false)
		return
	_sky_material = sky_rect.material as ShaderMaterial
	_wash_material = sunlight_wash_rect.material as ShaderMaterial
	if (
		_sky_material == null
		or _wash_material == null
	):
		push_error("SurfacePresentation requires every authored ShaderMaterial.")
		set_process(false)
		return
	_publish_all()


func _process(_delta: float) -> void:
	_publish_all()


## Returns the viewport point currently showing the original surface centre.
## World props use both axes; shaders use only its y component.
func get_surface_screen_position() -> Vector2:
	# Reuse the one terrain conversion path so daylight, apron, and dirt never
	# disagree about where the surface is.
	return terrain_manager.terrain_to_screen_position(
		Vector2(
			float(config.terrain_width_cells)
				* 0.5
				* float(config.terrain_cell_world_size),
			_get_surface_terrain_y()
		)
	)


## Returns the viewport row currently showing the original ground line.
func get_surface_screen_y() -> float:
	return get_surface_screen_position().y


func _publish_all() -> void:
	_frame_backdrop_rects()
	_publish_sun_position()
	_publish_frame_size()
	_publish_surface_screen_y()


## Grows both rects to cover everything the camera can see. Camera offset is
## deliberately ignored: the rects stay planted in the world, so the impact
## shake still carries the sky with it exactly as it did at a fixed size.
func _frame_backdrop_rects() -> void:
	if camera == null:
		return
	var camera_zoom := camera.zoom
	if is_zero_approx(camera_zoom.x) or is_zero_approx(camera_zoom.y):
		return
	var covered_size := (
		get_viewport().get_visible_rect().size / camera_zoom
		+ Vector2.ONE * (_BACKDROP_OVERSCAN_PX * 2.0)
	)
	var covered_origin := camera.global_position - covered_size * 0.5
	for rect: ColorRect in [sky_rect, sunlight_wash_rect]:
		rect.position = covered_origin
		rect.size = covered_size


## The frame the shaders measure in. With no camera the authored rect is the
## frame, exactly as it was before the rects started following one.
func _get_screen_size() -> Vector2:
	if camera == null:
		return sky_rect.size
	return get_viewport().get_visible_rect().size


## Converts a world point into the viewport pixel it is drawn at. Camera offset
## is left out for the same reason _frame_backdrop_rects leaves it out: the
## impact shake moves the whole frame and the backdrop rides along with it.
func _world_to_screen_position(world_position: Vector2) -> Vector2:
	if camera == null:
		return world_position - sky_rect.position
	return (
		(world_position - camera.global_position) * camera.zoom
		+ _get_screen_size() * 0.5
	)


func _publish_surface_screen_y() -> void:
	var surface_screen_y := _world_to_screen_position(
		get_surface_screen_position()
	).y
	if (
		not is_nan(_last_surface_screen_y)
		and is_equal_approx(surface_screen_y, _last_surface_screen_y)
	):
		return
	_last_surface_screen_y = surface_screen_y
	_set_shared_parameter(&"surface_screen_y", surface_screen_y)


## Sets the sun against the ground line, so it stays the same distance behind
## the horizon at every zoom and at every depth the surface has scrolled to.
func _publish_sun_position() -> void:
	var sun_position := Vector2(
		sun_screen_position.x,
		_world_to_screen_position(get_surface_screen_position()).y
			+ sun_below_horizon_px
	)
	if sun_position.is_equal_approx(_last_sun_screen_position):
		return
	_last_sun_screen_position = sun_position
	# Only the sky and the wash place the sun; the apron is lit by the wash.
	_sky_material.set_shader_parameter(
		&"sun_screen_position",
		sun_position
	)
	_wash_material.set_shader_parameter(
		&"sun_screen_position",
		sun_position
	)


## The frame both shaders measure in, and how much of it each rect covers. The
## second is the zoom: the rect is sized in world units, so its on-screen size
## is what the shaders divide back out to recover viewport pixels.
func _publish_frame_size() -> void:
	var screen_size := _get_screen_size()
	var backdrop_screen_size := sky_rect.size
	if camera != null:
		backdrop_screen_size *= camera.zoom
	if (
		screen_size.is_equal_approx(_last_viewport_size)
		and backdrop_screen_size.is_equal_approx(_last_backdrop_screen_size)
	):
		return
	_last_viewport_size = screen_size
	_last_backdrop_screen_size = backdrop_screen_size
	_set_shared_parameter(&"viewport_size", screen_size)
	_set_shared_parameter(&"backdrop_screen_size", backdrop_screen_size)


## Pushes one shared uniform to every rect that declares it.
func _set_shared_parameter(name: StringName, value: Variant) -> void:
	_sky_material.set_shader_parameter(name, value)
	_wash_material.set_shader_parameter(name, value)


func _get_surface_terrain_y() -> float:
	return (
		float(config.initial_surface_row)
		* float(config.terrain_cell_world_size)
	)
