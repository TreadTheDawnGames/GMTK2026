extends RepairTask

var times_pressed : int = 0
@export var required_pressed : int = 50

@onready var times_pressed_label: Label = %TimesPressed

func _input(event: InputEvent) -> void:
	super._input(event)
	if event is InputEventKey:
		var keyvent : InputEventKey = event as InputEventKey
		if not keyvent.pressed:
			return
		if keyvent.keycode == Key.KEY_SPACE:
			times_pressed_label.text = str(times_pressed, "/", required_pressed)
			if times_pressed == required_pressed:
				_succeed()
		pass
	pass
