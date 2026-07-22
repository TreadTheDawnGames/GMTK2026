extends RepairTask
class_name WinButtonTask
## Completes when the player presses its authored confirmation button.


func _ready() -> void:
	super._ready()
	%Button.pressed.connect(_succeed)
