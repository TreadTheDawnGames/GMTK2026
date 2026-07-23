class_name MiningImpactSmoke
extends Node2D

## How it works:
## Mining impacts add bounded terrain-space lobes to one short-lived cloud.
## The node simulates bonding, buoyancy, and terrain collision, then writes
## every lobe to one MultiMesh draw call; it emits no gameplay state.
## The invariant is that the lobe count never exceeds the active platform cap.
## Jam justification: simulation and rendering share one small lobe dataset and
## one consumer; keep this local unless a second smoke presenter is introduced.

class SmokeLobe:
	var terrain_position: Vector2
	var velocity: Vector2
	var current_radius: float
	var target_radius: float
	var display_radius: float
	var display_left_radius: float
	var display_right_radius: float
	var shape_seed: float
	var shape_phase: float


class SmokeCloud:
	## The owner caps this array, feeds the nearest lobe when full, and clears
	## the entire collection when its refreshed lifetime expires.
	var lobes: Array[SmokeLobe] = []
	var total_lifetime: float
	var remaining_lifetime: float
	var pressure: float


@export_category("References")
@export var terrain_manager: TerrainManager
@export var terrain_renderer: TerrainLayerRenderer
@export var view_controller: ViewController
@export var smoke_mesh: MultiMeshInstance2D

@export_category("Cloud")
@export_range(0.1, 12.0, 0.1) var cloud_lifetime_seconds: float = 6.0
@export_range(1.0, 100.0, 1.0) var starting_radius: float = 24.0
@export_range(16.0, 300.0, 1.0) var maximum_radius: float = 96.0
@export_range(1.0, 20.0, 0.5) var radius_per_sqrt_cell: float = 3.0
@export_range(1.0, 300.0, 5.0) var growth_speed: float = 70.0
@export_range(0.0, 1.0, 0.05) var pressure_per_hit: float = 0.3
@export_range(0.0, 1.0, 0.05) var pressure_decay_per_second: float = 0.1
## Native cap; hits at capacity enlarge the nearest existing lobe.
@export_range(1, 32, 1) var maximum_lobes: int = 20
## Lower browser cap bounds per-frame collision samples and MultiMesh writes.
@export_range(1, 24, 1) var web_maximum_lobes: int = 12
@export var smoke_color: Color = Color("a65f3f")

@export_category("Bonding")
@export_range(1.0, 300.0, 1.0) var minimum_bond_spacing: float = 96.0
@export_range(0.0, 20.0, 0.5) var bond_acceleration: float = 2.0
@export_range(0.5, 1.0, 0.05) var bond_overlap_ratio: float = 0.85

@export_category("Motion")
@export_range(0.0, 1_000.0, 5.0) var minimum_launch_speed: float = 100.0
@export_range(0.0, 1_000.0, 5.0) var maximum_launch_speed: float = 140.0
@export_range(0.0, 500.0, 5.0) var upward_buoyancy: float = 110.0
@export_range(0.0, 500.0, 5.0) var maximum_rise_speed: float = 180.0
@export_range(0.0, 10.0, 0.05) var air_drag: float = 0.45
@export_range(0.0, 1.0, 0.05) var wall_slide_factor: float = 0.85
@export_range(1.0, 1_000.0, 5.0) var impact_push_radius: float = 220.0
@export_range(0.0, 1_000.0, 5.0) var impact_push_speed: float = 120.0
@export_range(1.0, 100.0, 1.0) var maximum_collision_radius: float = 20.0
@export_range(1.0, 4.0, 0.1) var horizontal_fill_scale: float = 2.0
@export_range(16.0, 300.0, 1.0) var maximum_horizontal_radius: float = 180.0
@export_range(0.0, 16.0, 0.5) var wall_clearance: float = 1.0
@export_range(0.0, 500.0, 5.0) var entrance_pull_acceleration: float = 45.0
@export_range(0.0, 200.0, 1.0) var top_consumption_margin: float = 16.0

var _cloud: SmokeCloud
var _random := RandomNumberGenerator.new()


## Prepares random values and sleeps processing until smoke exists.
func _ready() -> void:
	_random.randomize()
	if smoke_mesh != null and smoke_mesh.multimesh != null:
		smoke_mesh.multimesh.visible_instance_count = 0
	set_process(false)


## Adds a bonded smoke volume and drives it with the visible swing.
func play_at_impact(
	impact_screen_position: Vector2,
	cells_removed: int,
	combo_strength: float,
	_debris_multiplier: float = 1.0,
	swing_side: int = 1
) -> void:
	if cells_removed <= 0 or terrain_manager == null:
		return
	var wind_direction := Vector2(
		-float(signi(swing_side)),
		0.0
	)
	push_air(
		impact_screen_position,
		impact_push_speed * lerpf(
			1.0,
			1.5,
			clampf(combo_strength, 0.0, 1.0)
		),
		impact_push_radius,
		wind_direction
	)

	if _cloud == null:
		_cloud = SmokeCloud.new()
	var spawn_position := _get_foreground_spawn_position(
		impact_screen_position
	)
	var added_radius := minf(
		starting_radius
			+ sqrt(float(cells_removed)) * radius_per_sqrt_cell,
		maximum_radius
	)
	var launch_velocity := Vector2(
		wind_direction.x * _random.randf_range(
			minimum_launch_speed,
			maximum_launch_speed
		),
		0.0
	)

	var lobe_budget := maximum_lobes
	if OS.has_feature("web"):
		lobe_budget = mini(lobe_budget, web_maximum_lobes)
	if _cloud.lobes.size() < lobe_budget:
		var lobe := SmokeLobe.new()
		lobe.terrain_position = spawn_position
		lobe.velocity = launch_velocity
		lobe.current_radius = starting_radius
		lobe.target_radius = added_radius
		lobe.display_radius = starting_radius
		lobe.display_left_radius = starting_radius
		lobe.display_right_radius = starting_radius
		lobe.shape_seed = _random.randf_range(0.0, TAU)
		_cloud.lobes.append(lobe)
	else:
		# At the web-safe cap, feed the nearest existing volume instead of
		# creating another simulation element or collapsing the whole field.
		var nearest_lobe := _find_nearest_lobe(spawn_position)
		nearest_lobe.target_radius = minf(
			sqrt(
				nearest_lobe.target_radius * nearest_lobe.target_radius
				+ added_radius * added_radius
			),
			maximum_radius
		)
		nearest_lobe.velocity += launch_velocity * 0.45

	_cloud.total_lifetime = cloud_lifetime_seconds
	_cloud.remaining_lifetime = cloud_lifetime_seconds
	_cloud.pressure = clampf(
		_cloud.pressure
			+ pressure_per_hit
			+ combo_strength * pressure_per_hit,
		0.0,
		1.0
	)
	set_process(true)
	_sync_render_instances()


## Pushes nearby smoke sideways when a mining impact moves the air.
func push_air(
	source_screen_position: Vector2,
	push_speed: float,
	push_radius: float,
	primary_direction: Vector2 = Vector2.UP
) -> void:
	if (
		_cloud == null
		or terrain_manager == null
		or push_radius <= 0.0
	):
		return
	var source_position := terrain_manager.screen_to_terrain_position(
		source_screen_position
	)
	for lobe in _cloud.lobes:
		var offset := lobe.terrain_position - source_position
		var distance := offset.length()
		if distance >= push_radius:
			continue
		var falloff := 1.0 - distance / push_radius
		var sideways_direction := signf(primary_direction.x)
		if is_zero_approx(sideways_direction) and distance > 0.001:
			sideways_direction = signf(offset.x)
		lobe.velocity.x += (
			sideways_direction * push_speed * falloff
		)


## Expands, bonds, lifts, and expires the active smoke field.
func _process(delta: float) -> void:
	if _cloud == null:
		set_process(false)
		return
	_cloud.remaining_lifetime -= delta
	if _cloud.remaining_lifetime <= 0.0:
		_clear_cloud()
		return

	_cloud.pressure = move_toward(
		_cloud.pressure,
		0.0,
		pressure_decay_per_second * delta
	)
	_apply_bonding(delta)
	var drag_multiplier := exp(-air_drag * delta)
	for lobe in _cloud.lobes:
		lobe.current_radius = move_toward(
			lobe.current_radius,
			lobe.target_radius,
			growth_speed * delta
		)
		var open_horizontal_radii := _get_open_horizontal_radii(
			lobe.terrain_position,
			minf(
				lobe.current_radius * horizontal_fill_scale,
				maximum_horizontal_radius
			)
		)
		lobe.display_left_radius = open_horizontal_radii.x
		lobe.display_right_radius = open_horizontal_radii.y
		lobe.display_radius = minf(
			lobe.display_left_radius,
			lobe.display_right_radius
		)
		lobe.shape_phase += delta * (0.45 + _cloud.pressure * 0.8)
		lobe.velocity *= drag_multiplier
		lobe.velocity.y = minf(lobe.velocity.y, 0.0)
		lobe.velocity.y -= upward_buoyancy * delta
		lobe.velocity.y = maxf(
			lobe.velocity.y,
			-maximum_rise_speed
		)
		if lobe.velocity.y < 0.0:
			var entrance_center_x := (
				float(terrain_manager.config.terrain_width_cells)
				* float(terrain_manager.config.terrain_cell_world_size)
				* 0.5
			)
			lobe.velocity.x += signf(
				entrance_center_x - lobe.terrain_position.x
			) * entrance_pull_acceleration * delta
		_move_lobe(
			lobe,
			minf(
				lobe.display_radius * 0.55,
				maximum_collision_radius
			),
			delta
		)

	if not (
		view_controller != null
		and view_controller.is_reviewing()
	):
		for lobe_index in range(_cloud.lobes.size() - 1, -1, -1):
			if _has_lobe_cleared_normal_view_top(
				_cloud.lobes[lobe_index]
			):
				_cloud.lobes.remove_at(lobe_index)
	if _cloud.lobes.is_empty():
		_clear_cloud()
		return
	_sync_render_instances()


## Sends the bounded smoke supports to one shared GPU draw call.
func _sync_render_instances() -> void:
	if smoke_mesh == null or smoke_mesh.multimesh == null:
		return
	var smoke_multimesh := smoke_mesh.multimesh
	if _cloud == null:
		smoke_multimesh.visible_instance_count = 0
		return
	var visible_count := mini(
		_cloud.lobes.size(),
		smoke_multimesh.instance_count
	)
	smoke_multimesh.visible_instance_count = visible_count
	var life_ratio := clampf(
		_cloud.remaining_lifetime / _cloud.total_lifetime,
		0.0,
		1.0
	)
	for lobe_index in range(visible_count):
		var lobe := _cloud.lobes[lobe_index]
		var screen_position := (
			terrain_manager.terrain_to_screen_position(
				lobe.terrain_position
			)
		)
		var horizontal_half_size := (
			lobe.display_left_radius
			+ lobe.display_right_radius
		) * 0.5
		var horizontal_center_shift := (
			lobe.display_right_radius
			- lobe.display_left_radius
		) * 0.5
		smoke_multimesh.set_instance_transform_2d(
			lobe_index,
			Transform2D(
				0.0,
				Vector2(
					horizontal_half_size,
					lobe.current_radius * 1.2
				),
				0.0,
				screen_position
					+ Vector2.RIGHT * horizontal_center_shift
			)
		)
		var rock_color := smoke_color
		rock_color.a = 0.68 * life_ratio
		smoke_multimesh.set_instance_color(
			lobe_index,
			rock_color
		)
		smoke_multimesh.set_instance_custom_data(
			lobe_index,
			Color(
				fposmod(lobe.shape_seed / TAU, 1.0),
				lobe.shape_phase,
				_cloud.pressure,
				0.0
			)
		)


## Measures the open space on each side so smoke fills but never crosses walls.
func _get_open_horizontal_radii(
	terrain_position: Vector2,
	desired_radius: float
) -> Vector2:
	var cell_size := float(
		terrain_manager.config.terrain_cell_world_size
	)
	var minimum_radius := cell_size * 0.5
	var left_radius := desired_radius
	var right_radius := desired_radius
	var sample_distance := cell_size
	while sample_distance <= desired_radius:
		if terrain_manager.is_solid_at_terrain_position(
			terrain_position + Vector2.LEFT * sample_distance
		):
			left_radius = maxf(
				sample_distance - wall_clearance,
				minimum_radius
			)
			break
		sample_distance += cell_size
	sample_distance = cell_size
	while sample_distance <= desired_radius:
		if terrain_manager.is_solid_at_terrain_position(
			terrain_position + Vector2.RIGHT * sample_distance
		):
			right_radius = maxf(
				sample_distance - wall_clearance,
				minimum_radius
			)
			break
		sample_distance += cell_size
	return Vector2(
		maxf(left_radius, minimum_radius),
		maxf(right_radius, minimum_radius)
	)


## Pulls stretched neighboring supports together without collapsing spacing.
func _apply_bonding(delta: float) -> void:
	for lobe_index in range(1, _cloud.lobes.size()):
		var first_lobe := _cloud.lobes[lobe_index - 1]
		var second_lobe := _cloud.lobes[lobe_index]
		var offset := second_lobe.terrain_position - first_lobe.terrain_position
		var distance := offset.length()
		var supported_spacing := minf(
			minimum_bond_spacing,
			(
				first_lobe.current_radius
				+ second_lobe.current_radius
			) * bond_overlap_ratio
		)
		if distance <= supported_spacing or distance <= 0.001:
			continue
		var correction := offset.normalized() * (
			distance - supported_spacing
		) * bond_acceleration * delta
		first_lobe.velocity += correction
		second_lobe.velocity -= correction
		# Bonding keeps the field together without pulling an upper volume
		# downward toward a newer strike.
		first_lobe.velocity.y = minf(first_lobe.velocity.y, 0.0)
		second_lobe.velocity.y = minf(second_lobe.velocity.y, 0.0)


## Returns the existing support nearest a capped new smoke source.
func _find_nearest_lobe(terrain_position: Vector2) -> SmokeLobe:
	var nearest_lobe := _cloud.lobes[0]
	var nearest_distance := nearest_lobe.terrain_position.distance_squared_to(
		terrain_position
	)
	for lobe_index in range(1, _cloud.lobes.size()):
		var candidate := _cloud.lobes[lobe_index]
		var candidate_distance := (
			candidate.terrain_position.distance_squared_to(terrain_position)
		)
		if candidate_distance < nearest_distance:
			nearest_lobe = candidate
			nearest_distance = candidate_distance
	return nearest_lobe


## Finds the upper foreground rim nearest the current hammer impact.
func _get_foreground_spawn_position(
	impact_screen_position: Vector2
) -> Vector2:
	var impact_terrain_position := (
		terrain_manager.screen_to_terrain_position(
			impact_screen_position
		)
	)
	if terrain_renderer == null:
		return impact_terrain_position
	var foreground_opening := (
		terrain_renderer.get_latest_foreground_opening_rect()
	)
	if (
		not foreground_opening.has_area()
		or not foreground_opening.grow(
			float(terrain_manager.config.terrain_cell_world_size)
		).has_point(impact_terrain_position)
	):
		return impact_terrain_position

	var edge_angle := _random.randf_range(
		-PI * 0.5 - 0.35,
		-PI * 0.5 + 0.35
	)
	var edge_direction := Vector2.RIGHT.rotated(edge_angle)
	var spawn_position := (
		foreground_opening.get_center()
		+ edge_direction * foreground_opening.size * 0.5
	)
	for _inward_step in range(8):
		if not terrain_manager.is_solid_at_terrain_position(
			spawn_position
		):
			break
		spawn_position = spawn_position.move_toward(
			foreground_opening.get_center(),
			float(terrain_manager.config.terrain_cell_world_size)
		)
	return spawn_position


## Moves open axes while blocked axes slide along the tunnel wall.
func _move_lobe(
	lobe: SmokeLobe,
	collision_radius: float,
	delta: float
) -> void:
	var current_position := lobe.terrain_position
	var next_position := current_position + lobe.velocity * delta
	if not _position_collides(
		next_position,
		collision_radius,
		lobe.velocity
	):
		lobe.terrain_position = next_position
		return

	var vertical_position := Vector2(
		current_position.x,
		next_position.y
	)
	if not _position_collides(
		vertical_position,
		collision_radius,
		Vector2(0.0, lobe.velocity.y)
	):
		current_position.y = vertical_position.y
	else:
		lobe.velocity.y = 0.0
		lobe.velocity.x *= wall_slide_factor

	var horizontal_position := Vector2(
		next_position.x,
		current_position.y
	)
	if not _position_collides(
		horizontal_position,
		collision_radius,
		Vector2(lobe.velocity.x, 0.0)
	):
		current_position.x = horizontal_position.x
	else:
		lobe.velocity.x = 0.0
		lobe.velocity.y *= wall_slide_factor
	lobe.terrain_position = current_position


## Reports whether a support volume's leading edges touch remaining terrain.
func _position_collides(
	terrain_position: Vector2,
	radius: float,
	velocity: Vector2
) -> bool:
	var horizontal_edge := terrain_position + Vector2(
		signf(velocity.x) * radius,
		0.0
	)
	var vertical_edge := terrain_position + Vector2(
		0.0,
		signf(velocity.y) * radius
	)
	return (
		terrain_manager.is_solid_at_terrain_position(horizontal_edge)
		or terrain_manager.is_solid_at_terrain_position(vertical_edge)
	)


## Reports whether one support volume fully cleared the normal view top.
func _has_lobe_cleared_normal_view_top(lobe: SmokeLobe) -> bool:
	var screen_position := terrain_manager.terrain_to_screen_position(
		lobe.terrain_position
	)
	var lobe_bottom := (
		screen_position.y
		+ lobe.display_radius * 1.24
	)
	return lobe_bottom < -top_consumption_margin


## Removes escaped or expired smoke and sleeps its simulation.
func _clear_cloud() -> void:
	_cloud = null
	_sync_render_instances()
	set_process(false)
