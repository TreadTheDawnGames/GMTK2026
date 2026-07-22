extends RepairTask
class_name WinButtonTask

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super._ready()
	%Button.pressed.connect(_succeed)
	pass # Replace with function body.
