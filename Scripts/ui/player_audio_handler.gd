extends Node2D
class_name PlayerAudioHandler

## Returns the project autoload without coupling consumers to a bare global.
static func get_global(context: Node) -> PlayerAudioHandler:
	var audio_handler: PlayerAudioHandler = (
		context.get_node_or_null("/root/AudioHandler") as PlayerAudioHandler
	)
	if audio_handler == null:
		push_error("AudioHandler autoload is unavailable.")
	return audio_handler

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func PlaySoundAtGlobalPosition(sound : AudioStream, globPos : Vector2, doPitchScale = true, busName : String = "SFX"):
	if(not sound):
		DisplayServer.beep()
	
	var audioPlayer : AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	audioPlayer.stream = sound
	audioPlayer.global_position = globPos
	audioPlayer.autoplay = true
	audioPlayer.pitch_scale = (randf_range(1.0, 1.5) if doPitchScale else 1.0)
	audioPlayer.bus = busName
	audioPlayer.finished.connect(func(): audioPlayer.queue_free())
	get_tree().root.add_child(audioPlayer)
	
## pitchScale is applied when doPitchScale is false, so callers that already
## know the pitch they want (the combo ladder) can set it exactly instead of
## taking the random spread.
func play_sound(sound : AudioStream, busName : String = "SFX", doPitchScale = false, pitchScale : float = 1.0):
	if(not sound):
		DisplayServer.beep()

	var audioPlayer : AudioStreamPlayer = AudioStreamPlayer.new()
	audioPlayer.stream = sound
	#audioPlayer.global_position = get_viewport_rect().get_center()
	audioPlayer.autoplay = true
	audioPlayer.pitch_scale = (randf_range(1.0, 1.5) if doPitchScale else pitchScale)
	audioPlayer.bus = busName
	audioPlayer.finished.connect(func(): audioPlayer.queue_free())
	get_tree().root.add_child(audioPlayer)
