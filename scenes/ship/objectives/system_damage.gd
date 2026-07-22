extends TextureProgressBar
class_name SystemDamage

signal system_destroyed()

@onready var timer: Timer = %TimeBeforeDestruction

@export var max_health : float = 10:
	set(value):
		max_health = value
		max_value = max_health

func _ready():
	max_value = max_health
	timer.timeout.connect(system_destroyed.emit)
	start_timer()

func repair_damage(amount : float):
	print("wait time before: ", timer.wait_time)
	timer.start(clamp(timer.wait_time + amount, 0.0, max_health))
	print("wait time after: ", timer.wait_time)
	print("repairing")

func start_timer():
	timer.start(max_health)
	pass

func on_timeout():
	system_destroyed.emit()
	pass

func _process(_delta: float) -> void:
	value = timer.time_left
