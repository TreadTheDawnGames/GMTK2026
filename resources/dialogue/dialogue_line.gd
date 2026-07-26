@tool
class_name DialogueLine
extends Resource

## @tool because the cutscene editor reads and writes these from editor context.
## A non-tool resource script loads as a placeholder there: its stored values are
## readable but its methods are not callable, so get_typing_seconds silently took
## the whole beat panel down with it.

## One ordered line in a conversation. A zero auto-advance delay waits for the
## player; a positive value advances after that many seconds.

@export var speaker_slot: StringName
@export var speaker_pose: StringName
## Optional same-named AnimationPlayer cue on the active encounter stage.
@export var stage_cue: StringName
@export_multiline var text: String
@export_range(0.0, 30.0, 0.1) var auto_advance_delay_seconds: float = 0.0
## Seconds per revealed character for this line only. Zero inherits the
## DialogueDirector's speed, which is what almost every line should do.
##
## Override it for a line whose pace is the point: a slow, weighted warning, or
## a burst of panic. Punctuation still stretches from whatever speed applies, so
## an override changes the tempo without flattening the phrasing.
@export_range(0.0, 0.2, 0.001) var character_display_speed_override: float = 0.0
## One-based word counts after which the typewriter holds before continuing.
## The visible text stays canonical; this authors delivery without adding
## punctuation or splitting one spoken line into extra player advances.
@export var typing_pause_after_word_counts: PackedInt32Array
@export_range(0.0, 2.0, 0.05) var typing_pause_seconds: float = 0.0


## Returns the seconds this line takes to type out at a given base speed, with
## the same punctuation stretching the director applies while revealing it.
##
## The editor needs this to say how long a line runs before anyone plays it, and
## to size a DIALOGUE beat to the words it actually holds. It deliberately takes
## the punctuation sets as arguments rather than reaching for the director: the
## resource has no scene to look in, and a cutscene panel evaluating a line has
## no director running.
func get_typing_seconds(
	base_speed: float,
	slowest_characters: Array[String],
	slower_characters: Array[String]
) -> float:
	var speed := (
		character_display_speed_override
		if character_display_speed_override > 0.0
		else base_speed
	)
	if speed <= 0.0 or text.is_empty():
		return 0.0
	var total := 0.0
	for index in range(text.length()):
		var letter := text[index]
		if slowest_characters.has(letter):
			total += speed * 5.0
		elif slower_characters.has(letter):
			total += speed * 3.0
		else:
			total += speed
	total += (
		float(typing_pause_after_word_counts.size())
		* typing_pause_seconds
	)
	return total
