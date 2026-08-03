extends Label


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	text = ProjectSettings.get_setting("application/config/version") if ProjectSettings.get_setting("application/config/version") != "" else "You found an easter egg! This text isn't working for some reason :)"
	pass # Replace with function body.
