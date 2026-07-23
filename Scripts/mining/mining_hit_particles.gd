class_name MiningHitParticles
extends Node2D

## Plays dirt pieces that collide with the remaining terrain.

class DirtPiece:
	var terrain_position: Vector2
	var velocity: Vector2
	var total_lifetime: float
	var remaining_lifetime: float
	var half_size: float
	var color: Color
	var settled: bool = false


@export_category("References")
@export var terrain_manager: TerrainManager

@export_category("Burst")
@export_range(0.1, 2.0, 0.05) var pieces_per_removed_cell: float = 0.6
@export_range(1, 128, 1) var minimum_piece_amount: int = 18
@export_range(1, 256, 1) var maximum_piece_amount: int = 128
@export_range(0.1, 3.0, 0.05) var piece_lifetime: float = 1.0
@export_range(0.1, 1.0, 0.05) var fade_portion: float = 0.55
@export_range(0.25, 1.0, 0.05) var minimum_cell_scale: float = 0.5
@export_range(0.25, 1.5, 0.05) var maximum_cell_scale: float = 1.0

@export_category("Motion")
@export_range(0.0, 1_000.0, 5.0) var minimum_launch_speed: float = 180.0
@export_range(0.0, 1_000.0, 5.0) var maximum_launch_speed: float = 330.0
@export_range(0.0, 180.0, 1.0) var launch_spread_degrees: float = 140.0
@export_range(0.0, 2_000.0, 10.0) var gravity: float = 420.0
@export_range(0.0, 1.0, 0.05) var bounce_factor: float = 0.3
@export_range(0.0, 1.0, 0.05) var surface_friction: float = 0.65
@export_range(0.0, 200.0, 1.0) var settle_speed: float = 35.0

@export_category("Performance")
## Limits simultaneous dirt pixels so repeated hits stay inexpensive.
@export_range(1, 512, 1) var maximum_active_pieces: int = 192
## Applies a lower simultaneous-pixel limit in browser exports.
@export_range(1, 256, 1) var web_maximum_active_pieces: int = 64

var _pieces: Array[DirtPiece] = []
var _random := RandomNumberGenerator.new()


## Prepares random values and sleeps processing until the first burst.
func _ready() -> void:
	_random.randomize()
	set_process(false)


## Creates a dirt burst at the hammer's animated impact point.
func play_at_impact(
	impact_screen_position: Vector2,
	cells_removed: int,
	effect_strength: float,
	debris_multiplier: float = 1.0
) -> void:
	if cells_removed <= 0:
		return
	var requested_piece_amount := clampi(
		roundi(
			float(cells_removed)
			* pieces_per_removed_cell
			* maxf(debris_multiplier, 0.0)
		),
		minimum_piece_amount,
		maximum_piece_amount
	)
	var active_piece_budget := maximum_active_pieces
	if OS.has_feature("web"):
		active_piece_budget = mini(
			active_piece_budget,
			web_maximum_active_pieces
		)
	var piece_amount := mini(requested_piece_amount, active_piece_budget)
	var oldest_pieces_to_remove := maxi(
		0,
		_pieces.size() + piece_amount - active_piece_budget
	)
	# Keep the newest impact readable by discarding oldest pieces first.
	for _piece_index in range(oldest_pieces_to_remove):
		_pieces.remove_at(0)

	var spawn_position := terrain_manager.screen_to_terrain_position(
		impact_screen_position + Vector2.UP * 2.0
	)
	var half_spread := deg_to_rad(launch_spread_degrees) * 0.5
	var speed_bonus := lerpf(
		1.0,
		1.35,
		clampf(effect_strength, 0.0, 1.0)
	)
	var logical_cell_size := float(
		terrain_manager.config.logical_pixel_scale
	)

	for _piece_index in range(piece_amount):
		var piece := DirtPiece.new()
		piece.terrain_position = spawn_position
		piece.velocity = Vector2.UP.rotated(
			_random.randf_range(-half_spread, half_spread)
		) * _random.randf_range(
			minimum_launch_speed,
			maximum_launch_speed
		) * speed_bonus
		piece.total_lifetime = piece_lifetime
		piece.remaining_lifetime = piece.total_lifetime
		piece.half_size = logical_cell_size * 0.5 * _random.randf_range(
			minimum_cell_scale,
			maximum_cell_scale
		)
		piece.color = (
			terrain_manager.config.terrain_accent_color
			if _random.randf() < 0.25
			else terrain_manager.config.terrain_color
		)
		_pieces.append(piece)
	set_process(true)
	queue_redraw()


## Moves active dirt pieces and removes expired pieces.
func _process(delta: float) -> void:
	for piece_index in range(_pieces.size() - 1, -1, -1):
		var piece := _pieces[piece_index]
		piece.remaining_lifetime -= delta
		if piece.remaining_lifetime <= 0.0:
			_pieces.remove_at(piece_index)
			continue
		if not piece.settled:
			piece.velocity.y += gravity * delta
			_move_piece(piece, delta)
	queue_redraw()
	if _pieces.is_empty():
		set_process(false)


## Draws each fading dirt pixel at its current terrain position.
func _draw() -> void:
	for piece in _pieces:
		var screen_position := terrain_manager.terrain_to_screen_position(
			piece.terrain_position
		)
		var fade_duration := piece.total_lifetime * fade_portion
		var fade_alpha := clampf(
			piece.remaining_lifetime / fade_duration,
			0.0,
			1.0
		)
		var draw_color := piece.color
		draw_color.a *= fade_alpha
		draw_rect(
			Rect2(
				screen_position - Vector2.ONE * piece.half_size,
				Vector2.ONE * piece.half_size * 2.0
			),
			draw_color
		)


## Moves one dirt piece and bounces it away from solid terrain.
func _move_piece(piece: DirtPiece, delta: float) -> void:
	var next_position := (
		piece.terrain_position
		+ piece.velocity * delta
	)
	if not _position_collides(next_position, piece):
		piece.terrain_position = next_position
		return

	var vertical_position := Vector2(
		piece.terrain_position.x,
		next_position.y
	)
	var hit_vertical := _position_collides(vertical_position, piece)
	if hit_vertical:
		piece.velocity.y *= -bounce_factor
		piece.velocity.x *= surface_friction

	var horizontal_position := Vector2(
		next_position.x,
		piece.terrain_position.y
	)
	if _position_collides(horizontal_position, piece):
		piece.velocity.x *= -bounce_factor

	if hit_vertical and absf(piece.velocity.y) <= settle_speed:
		piece.velocity = Vector2.ZERO
		piece.settled = true
		return

	var bounced_position := (
		piece.terrain_position
		+ piece.velocity * delta
	)
	if _position_collides(bounced_position, piece):
		piece.velocity = Vector2.ZERO
		piece.settled = true
		return
	piece.terrain_position = bounced_position


## Returns whether a dirt piece touches solid terrain at a position.
func _position_collides(
	terrain_position: Vector2,
	piece: DirtPiece
) -> bool:
	var horizontal_edge := terrain_position + Vector2(
		signf(piece.velocity.x) * piece.half_size,
		0.0
	)
	var vertical_edge := terrain_position + Vector2(
		0.0,
		signf(piece.velocity.y) * piece.half_size
	)
	return (
		terrain_manager.is_solid_at_terrain_position(horizontal_edge)
		or terrain_manager.is_solid_at_terrain_position(vertical_edge)
	)
