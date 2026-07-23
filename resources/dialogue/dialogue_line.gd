class_name DialogueLine
extends Resource

## One ordered line in a conversation. A zero auto-advance delay waits for the
## player; a positive value advances after that many seconds.

@export var speaker_slot: StringName
@export_multiline var text: String
@export_range(0.0, 30.0, 0.1) var auto_advance_delay_seconds: float = 0.0
