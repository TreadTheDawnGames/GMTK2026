class_name MiningHitParticles
extends Node2D

## Plays dirt pieces that collide with the remaining terrain.

class DirtPiece:
	var terrain_position: Vector2
	var velocity: Vector2
	var remaining_lifetime: float
	var radius: float
	var color: Color
	var settled: bool = false


@export_category("References")
@export var terrain_manager: TerrainManager

@export_category("Burst")
@export_range(1, 128, 1) var base_particle_amount: int = 14
@export_range(0.0, 4.0, 0.1) var combo_amount_multiplier: float = 1.0
@export_range(0.1, 3.0, 0.05) var particle_lifetime: float = 1.1
@export_range(1.0, 16.0, 0.5) var minimum_radius: float = 3.0
@export_range(1.0, 16.0, 0.5) var maximum_radius: float = 6.0

@export_category("Motion")
@export_range(0.0, 1_000.0, 5.0) var minimum_launch_speed: float = 105.0
@export_range(0.0, 1_000.0, 5.0) var maximum_launch_speed: float = 205.0
@export_range(0.0, 180.0, 1.0) var launch_spread_degrees: float = 68.0
@export_range(0.0, 2_000.0, 10.0) var gravity: float = 310.0
@export_range(0.0, 1.0, 0.05) var bounce_factor: float = 0.35
@export_range(0.0, 1.0, 0.05) var surface_friction: float = 0.65
@export_range(0.0, 200.0, 1.0) var settle_speed: float = 35.0

@export_category("Color")
@export var primary_color: Color = Color("8c5740")
@export var accent_color: Color = Color("75483a")

var _pieces: Array[DirtPiece] = []
var _random := RandomNumberGenerator.new()


## Prepares random values for particle bursts.
func _ready() -> void:
	_random.randomize()


## Creates a dirt burst at the hammer's animated impact point.
func play_at_impact(
	impact_screen_position: Vector2,
	effect_strength: float
) -> void:
	var particle_amount := base_particle_amount + roundi(
		base_particle_amount * combo_amount_multiplier * effect_strength
	)
	var spawn_position := terrain_manager.screen_to_terrain_position(
		impact_screen_position + Vector2.UP * 2.0
	)
	var half_spread := deg_to_rad(launch_spread_degrees) * 0.5

	for particle_index in range(particle_amount):
		var piece := DirtPiece.new()
		piece.terrain_position = spawn_position
		piece.velocity = Vector2.UP.rotated(
			_random.randf_range(-half_spread, half_spread)
		) * _random.randf_range(
			minimum_launch_speed,
			maximum_launch_speed
		)
		piece.remaining_lifetime = particle_lifetime
		piece.radius = _random.randf_range(
			minimum_radius,
			maximum_radius
		)
		piece.color = (
			accent_color
			if _random.randf() < 0.3
			else primary_color
		)
		_pieces.append(piece)
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


## Draws each dirt piece at its current terrain position.
func _draw() -> void:
	for piece in _pieces:
		draw_circle(
			terrain_manager.terrain_to_screen_position(
				piece.terrain_position
			),
			piece.radius,
			piece.color
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
		signf(piece.velocity.x) * piece.radius,
		0.0
	)
	var vertical_edge := terrain_position + Vector2(
		0.0,
		signf(piece.velocity.y) * piece.radius
	)
	return (
		terrain_manager.is_solid_at_terrain_position(horizontal_edge)
		or terrain_manager.is_solid_at_terrain_position(vertical_edge)
	)
