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
## - Both rects are resized to whatever the camera can see, and their shader
##   coordinates are shifted by the rect's own origin. At gameplay zoom that is
##   the authored full-viewport rect at (0, 0); while the opening shot is still
##   zoomed out it is the larger area, so daylight never stops short of the
##   frame edge.
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
## pool on the ground always sit under the same sun. Keep it clear of the
## letterbox top bar (the first 91 px) or the intro hides the sun behind it.
## Authored setting, just past the ground line at y = 262: the disc is mostly
## behind the horizon, so the light rises from below instead of falling from
## above. Raising this back above the band turns the shot into midday again.
@export var sun_screen_position: Vector2 = Vector2(676.0, 284.0)

var _sky_material: ShaderMaterial
var _wash_material: ShaderMaterial
var _last_surface_screen_y: float = NAN
var _last_viewport_size: Vector2 = Vector2.ZERO
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
	_publish_viewport_size()
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


## Both shaders read UV against their own rect, so every viewport-space value
## they are given has to be moved into that rect's frame first.
func _get_backdrop_origin() -> Vector2:
	return sky_rect.position


func _publish_surface_screen_y() -> void:
	var surface_screen_y := (
		get_surface_screen_y()
		- _get_backdrop_origin().y
	)
	if (
		not is_nan(_last_surface_screen_y)
		and is_equal_approx(surface_screen_y, _last_surface_screen_y)
	):
		return
	_last_surface_screen_y = surface_screen_y
	_set_shared_parameter(&"surface_screen_y", surface_screen_y)


func _publish_sun_position() -> void:
	var rect_sun_position := sun_screen_position - _get_backdrop_origin()
	if rect_sun_position.is_equal_approx(_last_sun_screen_position):
		return
	_last_sun_screen_position = rect_sun_position
	# Only the sky and the wash place the sun; the apron is lit by the wash.
	_sky_material.set_shader_parameter(
		&"sun_screen_position",
		rect_sun_position
	)
	_wash_material.set_shader_parameter(
		&"sun_screen_position",
		rect_sun_position
	)


func _publish_viewport_size() -> void:
	var viewport_size := sky_rect.size
	if viewport_size.is_equal_approx(_last_viewport_size):
		return
	_last_viewport_size = viewport_size
	_set_shared_parameter(&"viewport_size", viewport_size)


## Pushes one shared uniform to every rect that declares it.
func _set_shared_parameter(name: StringName, value: Variant) -> void:
	_sky_material.set_shader_parameter(name, value)
	_wash_material.set_shader_parameter(name, value)


func _get_surface_terrain_y() -> float:
	return (
		float(config.initial_surface_row)
		* float(config.terrain_cell_world_size)
	)
