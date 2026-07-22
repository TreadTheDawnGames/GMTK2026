extends TextureProgressBar
class_name SystemDamage
## Tracks objective durability with a runtime-adjustable decay rate.

signal system_destroyed()

@export var max_health: float = 90.0:
	set(value):
		max_health = maxf(value, 0.0)
		max_value = max_health
		if is_node_ready():
			durability = minf(durability, max_health)

var durability := 0.0
var decay_rate_scale := 1.0
var _is_destroyed := false


func _ready() -> void:
	max_value = max_health
	reset_durability()

func _process(delta: float) -> void:
	if _is_destroyed:
		return
	durability = maxf(durability - delta * decay_rate_scale, 0.0)
	value = durability
	if is_zero_approx(durability):
		_is_destroyed = true
		system_destroyed.emit()


func repair_damage(amount: float) -> void:
	durability = clampf(durability + amount, 0.0, max_health)
	value = durability
	_is_destroyed = false


func reset_durability() -> void:
	durability = max_health
	value = durability
	_is_destroyed = false


func set_decay_rate_scale(rate_scale: float) -> void:
	decay_rate_scale = maxf(rate_scale, 0.0)
