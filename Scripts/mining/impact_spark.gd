class_name ImpactSpark
extends Node2D

## How it works:
## - One landed hit creates a single hard-edged flash plus a few flat-filled
##   shards at the pickaxe contact point, sized by the hit's combo strength.
## - Marks are stored in terrain space and drawn through the terrain manager,
##   so they stay on the cut for their short life while the view scrolls.
## - Nothing fades: shapes shrink to nothing, which is how the rest of the
##   game's flat drawn art reads, and it keeps every fragment fully opaque.
## The invariant is that neither collection exceeds its active platform budget.

class SparkShard:
	var terrain_position: Vector2
	var direction: Vector2
	var speed: float
	var total_lifetime: float
	var remaining_lifetime: float
	var length_px: float
	var width_px: float
	var color: Color
	var vertices: PackedVector2Array = PackedVector2Array()


class SparkFlash:
	var terrain_position: Vector2
	var total_lifetime: float
	var remaining_lifetime: float
	var radius_px: float
	var rotation: float
	var color: Color
	var vertices: PackedVector2Array = PackedVector2Array()


@export_category("References")
@export var terrain_manager: TerrainManager

@export_category("Burst")
## Shards thrown by a zero-combo hit and by a fully-maxed one.
@export_range(0, 24, 1) var minimum_shard_amount: int = 7
@export_range(0, 24, 1) var maximum_shard_amount: int = 22
@export_range(0.02, 1.0, 0.01) var shard_lifetime: float = 0.3
@export_range(0.02, 1.0, 0.01) var flash_lifetime: float = 0.13
## Half-height of the flash star at zero and at full combo strength.
@export_range(2.0, 96.0, 1.0) var minimum_flash_radius_px: float = 16.0
@export_range(2.0, 96.0, 1.0) var maximum_flash_radius_px: float = 40.0
## Points on the flash star. Six keeps it reading as a struck-rock spark.
@export_range(3, 10, 1) var flash_point_count: int = 6

@export_category("Motion")
@export_range(0.0, 2_000.0, 10.0) var minimum_shard_speed: float = 300.0
@export_range(0.0, 2_000.0, 10.0) var maximum_shard_speed: float = 680.0
## Shards leave along the rebound of the swing, spread over this cone.
@export_range(10.0, 180.0, 1.0) var shard_spread_degrees: float = 108.0
## How far the cone tilts away from the side the pickaxe came down on.
@export_range(0.0, 90.0, 1.0) var shard_rebound_degrees: float = 34.0
@export_range(2.0, 60.0, 0.5) var minimum_shard_length_px: float = 10.0
@export_range(2.0, 60.0, 0.5) var maximum_shard_length_px: float = 30.0
@export_range(0.5, 12.0, 0.5) var shard_width_px: float = 3.0

@export_category("Palette")
## Struck-rock heat, warm enough to sit inside the terrain debris palette.
@export var spark_core_color: Color = Color("fff1c4")
@export var spark_hot_color: Color = Color("f2b134")
@export var spark_tail_color: Color = Color("df7126")

@export_category("Performance")
## Bounded per-hit accumulation: a burst that would exceed either budget drops
## the oldest marks first, so repeated hits never grow these arrays.
@export_range(1, 128, 1) var maximum_active_shards: int = 72
## Browser bursts keep the full size and palette with fewer simultaneous draw
## commands; twenty-eight still exceeds the authored maximum of one hit.
@export_range(1, 64, 1) var web_maximum_active_shards: int = 28
@export_range(1, 8, 1) var maximum_active_flashes: int = 3

var _shards: Array[SparkShard] = []
var _flashes: Array[SparkFlash] = []
# Pools are bounded by the matching active budgets and retain tiny polygon
# buffers so repeated hits do not allocate presentation records or vertices.
var _shard_pool: Array[SparkShard] = []
var _flash_pool: Array[SparkFlash] = []
var _random := RandomNumberGenerator.new()


## Prepares random values and sleeps processing until the first hit.
func _ready() -> void:
	_random.randomize()
	set_process(false)


## Strikes one spark at the hammer's animated contact point. Shares the impact
## presentation signature so the scene wiring routes it like the dust and shake.
func play_at_impact(
	impact_screen_position: Vector2,
	cells_removed: int,
	combo_strength: float,
	_debris_multiplier: float = 1.0,
	swing_side: int = 1
) -> void:
	if cells_removed <= 0 or terrain_manager == null:
		return
	var strength := clampf(combo_strength, 0.0, 1.0)
	var spawn_position := terrain_manager.screen_to_terrain_position(
		impact_screen_position
	)

	_add_flash(spawn_position, strength)

	# Sparks fly back up and away from the side the pickaxe swung in from, the
	# same way the dust plume is pushed by swing_side.
	var rebound_sign := -float(signi(swing_side))
	if is_zero_approx(rebound_sign):
		rebound_sign = 1.0
	var cone_center := Vector2.UP.rotated(
		deg_to_rad(shard_rebound_degrees) * rebound_sign
	)
	var half_spread := deg_to_rad(shard_spread_degrees) * 0.5
	var shard_amount := roundi(
		lerpf(
			float(minimum_shard_amount),
			float(maximum_shard_amount),
			strength
		)
	)
	var shard_budget := maximum_active_shards
	if OS.has_feature("web"):
		shard_budget = mini(shard_budget, web_maximum_active_shards)
	shard_amount = mini(shard_amount, shard_budget)
	# Keep the newest strike readable by discarding the oldest shards first.
	var shards_to_drop := maxi(
		0,
		_shards.size() + shard_amount - shard_budget
	)
	for _drop_index in range(shards_to_drop):
		var retired_shard: SparkShard = _shards.pop_front()
		if _shard_pool.size() < shard_budget:
			_shard_pool.append(retired_shard)

	for _shard_index in range(shard_amount):
		var shard: SparkShard = (
			_shard_pool.pop_back()
			if not _shard_pool.is_empty()
			else SparkShard.new()
		)
		shard.terrain_position = spawn_position
		shard.direction = cone_center.rotated(
			_random.randf_range(-half_spread, half_spread)
		)
		shard.speed = _random.randf_range(
			minimum_shard_speed,
			maximum_shard_speed
		) * lerpf(1.0, 1.3, strength)
		shard.total_lifetime = shard_lifetime * _random.randf_range(0.7, 1.0)
		shard.remaining_lifetime = shard.total_lifetime
		shard.length_px = _random.randf_range(
			minimum_shard_length_px,
			maximum_shard_length_px
		) * lerpf(1.0, 1.25, strength)
		shard.width_px = shard_width_px
		shard.color = _pick_spark_color()
		shard.vertices.clear()
		shard.vertices.append(Vector2(shard.length_px, 0.0))
		shard.vertices.append(Vector2(0.0, shard.width_px * 0.5))
		shard.vertices.append(Vector2(0.0, -shard.width_px * 0.5))
		_shards.append(shard)
	set_process(true)
	queue_redraw()


## Adds the single struck-rock flash, retiring the oldest if it has to.
func _add_flash(spawn_position: Vector2, strength: float) -> void:
	while _flashes.size() >= maxi(maximum_active_flashes, 1):
		var retired_flash: SparkFlash = _flashes.pop_front()
		if _flash_pool.size() < maxi(maximum_active_flashes, 1):
			_flash_pool.append(retired_flash)
	var flash: SparkFlash = (
		_flash_pool.pop_back()
		if not _flash_pool.is_empty()
		else SparkFlash.new()
	)
	flash.terrain_position = spawn_position
	flash.total_lifetime = flash_lifetime
	flash.remaining_lifetime = flash.total_lifetime
	flash.radius_px = lerpf(
		minimum_flash_radius_px,
		maximum_flash_radius_px,
		strength
	)
	flash.rotation = _random.randf_range(0.0, TAU)
	flash.color = spark_core_color
	flash.vertices.clear()
	var point_count := maxi(flash_point_count, 3)
	for vertex_index in range(point_count * 2):
		var angle := TAU * float(vertex_index) / float(point_count * 2)
		var vertex_radius := 1.0 if vertex_index % 2 == 0 else 0.38
		flash.vertices.append(
			Vector2.RIGHT.rotated(angle) * vertex_radius
		)
	_flashes.append(flash)


## Chooses one of the three authored heat tones for a single shard.
func _pick_spark_color() -> Color:
	var roll := _random.randf()
	if roll < 0.3:
		return spark_core_color
	if roll < 0.72:
		return spark_hot_color
	return spark_tail_color


## Flies the shards outward and retires every expired mark.
func _process(delta: float) -> void:
	for shard_index in range(_shards.size() - 1, -1, -1):
		var shard := _shards[shard_index]
		shard.remaining_lifetime -= delta
		if shard.remaining_lifetime <= 0.0:
			var retired_shard := _shards[shard_index]
			_shards.remove_at(shard_index)
			if _shard_pool.size() < maximum_active_shards:
				_shard_pool.append(retired_shard)
			continue
		shard.terrain_position += shard.direction * shard.speed * delta
		# Sparks bleed speed fast, which is what stops them reading as debris.
		shard.speed *= 0.86
	for flash_index in range(_flashes.size() - 1, -1, -1):
		var flash := _flashes[flash_index]
		flash.remaining_lifetime -= delta
		if flash.remaining_lifetime <= 0.0:
			var retired_flash := _flashes[flash_index]
			_flashes.remove_at(flash_index)
			if _flash_pool.size() < maximum_active_flashes:
				_flash_pool.append(retired_flash)
	queue_redraw()
	if _shards.is_empty() and _flashes.is_empty():
		set_process(false)


## Draws every live mark as a flat fill with no gradient and no soft edge.
func _draw() -> void:
	for flash in _flashes:
		var flash_center := terrain_manager.terrain_to_screen_position(
			flash.terrain_position
		)
		var life_ratio := clampf(
			flash.remaining_lifetime / flash.total_lifetime,
			0.0,
			1.0
		)
		var flash_scale := flash.radius_px * life_ratio
		draw_set_transform(
			flash_center,
			flash.rotation,
			Vector2.ONE * flash_scale
		)
		draw_colored_polygon(flash.vertices, flash.color)

	for shard in _shards:
		var shard_tail := terrain_manager.terrain_to_screen_position(
			shard.terrain_position
		)
		var life_ratio := clampf(
			shard.remaining_lifetime / shard.total_lifetime,
			0.0,
			1.0
		)
		var shard_length := shard.length_px * life_ratio
		if shard_length <= 0.5:
			continue
		draw_set_transform(
			shard_tail,
			shard.direction.angle(),
			Vector2.ONE * life_ratio
		)
		draw_colored_polygon(shard.vertices, shard.color)
	draw_set_transform(Vector2.ZERO, 0.0)
