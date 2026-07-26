class_name PickaxeRewardCelebration
extends Node2D

## How it works:
## - A granted pickaxe throws one bounded burst around the miner.
## - Flat confetti pieces move in screen space and fall under simple gravity.
## - The shared upgrade signal makes both Treasure Hunter gifts use this effect.
## - A new burst replaces the old one; no particle survives its lifetime.
## - The invariant is that active confetti never exceeds the platform cap.

class ConfettiParticle:
	var position: Vector2
	var velocity: Vector2
	var rotation: float
	var angular_velocity: float
	var size: Vector2
	var color: Color
	var remaining_seconds: float


@export_category("Reference")
@export var miner_rig: MinerRig

@export_category("Burst")
@export_range(1, 64, 1) var particle_count: int = 32
@export_range(1, 48, 1) var web_particle_count: int = 22
@export_range(0.1, 3.0, 0.05) var lifetime_seconds: float = 1.25
@export_range(0.0, 800.0, 10.0) var minimum_speed: float = 180.0
@export_range(0.0, 800.0, 10.0) var maximum_speed: float = 340.0
@export_range(0.0, 1_000.0, 10.0) var gravity: float = 520.0
@export var palette: Array[Color] = [
	Color("fff1c4"),
	Color("f2b134"),
	Color("df7126"),
	Color("8f3f71"),
	Color("3b7d4f"),
]

# Growth is hard-capped to the native/web particle count and cleared per burst.
var _particles: Array[ConfettiParticle] = []
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	_random.randomize()
	set_process(false)


## Celebrates the one authoritative upgrade event, regardless of which of the
## two Treasure Hunter encounters granted it.
func play_for_upgrade(_definition: PickaxeDefinition) -> void:
	if miner_rig == null or palette.is_empty():
		return
	_particles.clear()
	var burst_count := particle_count
	if OS.has_feature("web"):
		burst_count = mini(burst_count, web_particle_count)
	var origin := (
		miner_rig.get_cinematic_foot_screen_position()
		- Vector2(0.0, 72.0)
	)
	for particle_index in range(burst_count):
		var particle := ConfettiParticle.new()
		var angle := _random.randf_range(-PI + 0.35, -0.35)
		var speed := _random.randf_range(minimum_speed, maximum_speed)
		particle.position = origin + Vector2(
			_random.randf_range(-24.0, 24.0),
			_random.randf_range(-8.0, 8.0)
		)
		particle.velocity = Vector2.RIGHT.rotated(angle) * speed
		particle.rotation = _random.randf_range(0.0, TAU)
		particle.angular_velocity = _random.randf_range(-10.0, 10.0)
		particle.size = Vector2(
			_random.randf_range(5.0, 10.0),
			_random.randf_range(2.0, 5.0)
		)
		particle.color = palette[particle_index % palette.size()]
		particle.remaining_seconds = lifetime_seconds * _random.randf_range(
			0.75,
			1.0
		)
		_particles.append(particle)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	for particle_index in range(_particles.size() - 1, -1, -1):
		var particle := _particles[particle_index]
		particle.remaining_seconds -= delta
		if particle.remaining_seconds <= 0.0:
			_particles.remove_at(particle_index)
			continue
		particle.velocity.y += gravity * delta
		particle.position += particle.velocity * delta
		particle.rotation += particle.angular_velocity * delta
	queue_redraw()
	if _particles.is_empty():
		set_process(false)


func _draw() -> void:
	for particle in _particles:
		draw_set_transform(
			particle.position,
			particle.rotation,
			Vector2.ONE
		)
		draw_rect(
			Rect2(-particle.size * 0.5, particle.size),
			particle.color
		)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
