extends SceneTree

## How it works:
## - Builds transient beats instead of depending on shipped story resources.
## - Verifies waypoint scrubbing, typed action state, validation, and requests.
## - A plain Node2D actor keeps the test independent of character art.
## - Runtime action beats have zero duration so the test never waits on wall time.
## - The invariant is that preview state and emitted request data stay typed.

var _failures: PackedStringArray = []
var _actor := Node2D.new()
var _camera_requests: Array[Array] = []
var _audio_requests: Array[Array] = []
var _vfx_requests: Array[Array] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var stage := CharacterEncounterStage.new()
	stage.position = Vector2(100.0, 50.0)
	root.add_child(stage)
	stage.add_child(_actor)

	var player := CutsceneSequencePlayer.new()
	stage.add_child(player)
	player.bind(_resolve_actor, Callable(), Callable(), stage)

	_verify_waypoint_scrub(player)
	_verify_action_scrub(player)
	_verify_validation()
	_verify_stage_forwarding(stage)
	_verify_runtime_requests(player)

	stage.free()
	if _failures.is_empty():
		print("CUTSCENE_ADVANCED_ACTIONS_PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _verify_waypoint_scrub(player: CutsceneSequencePlayer) -> void:
	var move := CutsceneBeat.new()
	move.kind = CutsceneBeat.Kind.MOVE
	move.actor = &"hero"
	move.duration_seconds = 4.0
	move.starts_from_authored_point = true
	move.movement_waypoints = [
		Vector2(10.0, 0.0),
		Vector2(10.0, 10.0),
	]
	move.target_offset = Vector2(20.0, 10.0)
	move.step_height = 0.0
	var sequence := _sequence_with([move])
	var state: Dictionary = player.evaluate_at(sequence, 2.0)[&"hero"]
	_expect_vector(
		state[&"position"],
		Vector2(110.0, 55.0),
		"Waypoint scrub must distribute time by route distance."
	)


func _verify_action_scrub(player: CutsceneSequencePlayer) -> void:
	var camera := CutsceneBeat.new()
	camera.kind = CutsceneBeat.Kind.CAMERA
	camera.duration_seconds = 2.0
	camera.camera_action = CutsceneBeat.CameraAction.FRAME
	camera.camera_offset = Vector2(20.0, -10.0)
	camera.camera_zoom = Vector2(2.0, 2.0)

	var music := CutsceneBeat.new()
	music.kind = CutsceneBeat.Kind.AUDIO
	music.start_seconds = 0.25
	music.audio_action = CutsceneBeat.AudioAction.PLAY_MUSIC
	music.audio_stream = AudioStreamGenerator.new()

	var vfx := CutsceneBeat.new()
	vfx.kind = CutsceneBeat.Kind.VFX
	vfx.start_seconds = 0.5
	vfx.duration_seconds = 2.0
	vfx.vfx_action = CutsceneBeat.VfxAction.SPAWN
	vfx.vfx_id = &"dust"
	vfx.vfx_scene = _packed_node_scene()
	vfx.target_offset = Vector2(8.0, 6.0)

	var state := player.evaluate_at(
		_sequence_with([camera, music, vfx]),
		0.5
	)
	var frame_response := float(Tween.interpolate_value(
		0.0,
		1.0,
		0.25,
		1.0,
		Tween.TRANS_SINE,
		Tween.EASE_IN_OUT
	))
	_expect_vector(
		state[&"camera"][&"offset"],
		Vector2.ZERO.lerp(Vector2(20.0, -10.0), frame_response),
		"Camera scrub must use the runtime frame easing."
	)
	_expect_vector(
		state[&"camera"][&"zoom"],
		Vector2.ONE.lerp(Vector2(2.0, 2.0), frame_response),
		"Camera scrub zoom must use the runtime frame easing."
	)
	_expect(
		state[&"audio"][&"music"] != null,
		"Music state must persist after its play beat."
	)
	_expect(
		(state[&"vfx"] as Dictionary).has(&"dust"),
		"Spawned VFX must exist inside its authored window."
	)
	_expect_vector(
		state[&"vfx"][&"dust"][&"position"],
		Vector2(108.0, 56.0),
		"VFX scrub position must resolve in stage space."
	)


func _verify_validation() -> void:
	var camera := CutsceneBeat.new()
	camera.kind = CutsceneBeat.Kind.CAMERA
	camera.camera_zoom = Vector2.ZERO
	var camera_errors := camera.validate(PackedStringArray())
	_expect(
		_contains_text(camera_errors, "camera_zoom must be positive"),
		"Camera validation must reject a zero zoom."
	)

	var audio := CutsceneBeat.new()
	audio.kind = CutsceneBeat.Kind.AUDIO
	var audio_errors := audio.validate(PackedStringArray())
	_expect(
		_contains_text(audio_errors, "needs an audio stream"),
		"Audio validation must reject a missing play stream."
	)

	var vfx := CutsceneBeat.new()
	vfx.kind = CutsceneBeat.Kind.VFX
	var vfx_errors := vfx.validate(PackedStringArray())
	_expect(
		_contains_text(vfx_errors, "stable effect id")
		and _contains_text(vfx_errors, "effect scene"),
		"VFX validation must require an id and spawn scene."
	)


func _verify_runtime_requests(player: CutsceneSequencePlayer) -> void:
	player.camera_action_requested.connect(_on_camera_requested)
	player.audio_action_requested.connect(_on_audio_requested)
	player.vfx_action_requested.connect(_on_vfx_requested)

	var camera := CutsceneBeat.new()
	camera.kind = CutsceneBeat.Kind.CAMERA
	camera.blocks = false
	camera.camera_offset = Vector2(4.0, 5.0)

	var audio := CutsceneBeat.new()
	audio.kind = CutsceneBeat.Kind.AUDIO
	audio.blocks = false
	audio.audio_stream = AudioStreamGenerator.new()

	var vfx := CutsceneBeat.new()
	vfx.kind = CutsceneBeat.Kind.VFX
	vfx.blocks = false
	vfx.vfx_id = &"spark"
	vfx.vfx_scene = _packed_node_scene()

	player.play(_sequence_with([camera, audio, vfx]))
	_expect(_camera_requests.size() == 1, "Runtime must emit one camera request.")
	_expect(_audio_requests.size() == 1, "Runtime must emit one audio request.")
	_expect(_vfx_requests.size() == 1, "Runtime must emit one VFX request.")
	player.stop()


func _verify_stage_forwarding(stage: CharacterEncounterStage) -> void:
	stage.sequence_camera_action_requested.connect(_on_camera_requested)
	stage.sequence_audio_action_requested.connect(_on_audio_requested)
	stage.sequence_vfx_action_requested.connect(_on_vfx_requested)
	stage.call(&"_ensure_sequence_player")
	var stage_player := (
		stage.get_node("CutsceneSequencePlayer") as CutsceneSequencePlayer
	)
	var camera := CutsceneBeat.new()
	camera.kind = CutsceneBeat.Kind.CAMERA
	camera.blocks = false
	var audio := CutsceneBeat.new()
	audio.kind = CutsceneBeat.Kind.AUDIO
	audio.blocks = false
	audio.audio_stream = AudioStreamGenerator.new()
	var vfx := CutsceneBeat.new()
	vfx.kind = CutsceneBeat.Kind.VFX
	vfx.blocks = false
	vfx.vfx_id = &"forwarded"
	vfx.vfx_scene = _packed_node_scene()
	stage_player.play(_sequence_with([camera, audio, vfx]))
	_expect(
		_camera_requests.size() == 1,
		"Stage must forward camera requests."
	)
	_expect(
		_audio_requests.size() == 1,
		"Stage must forward audio requests."
	)
	_expect(
		_vfx_requests.size() == 1,
		"Stage must forward VFX requests."
	)
	stage_player.stop()
	_camera_requests.clear()
	_audio_requests.clear()
	_vfx_requests.clear()


func _sequence_with(beats: Array[CutsceneBeat]) -> CutsceneSequence:
	var sequence := CutsceneSequence.new()
	sequence.sequence_id = &"advanced_action_test"
	sequence.beats = beats
	return sequence


func _packed_node_scene() -> PackedScene:
	var scene := PackedScene.new()
	var effect := Node2D.new()
	scene.pack(effect)
	effect.free()
	return scene


func _resolve_actor(actor_id: StringName) -> Node2D:
	return _actor if actor_id == &"hero" else null


func _on_camera_requested(
	action: int,
	offset: Vector2,
	zoom: Vector2,
	shake_strength: float,
	duration_seconds: float
) -> void:
	_camera_requests.append([
		action, offset, zoom, shake_strength, duration_seconds,
	])


func _on_audio_requested(
	action: int,
	stream: AudioStream,
	bus: StringName,
	volume_db: float,
	pitch_scale: float,
	fade_seconds: float
) -> void:
	_audio_requests.append([
		action, stream, bus, volume_db, pitch_scale, fade_seconds,
	])


func _on_vfx_requested(
	action: int,
	effect_id: StringName,
	scene: PackedScene,
	screen_position: Vector2,
	duration_seconds: float
) -> void:
	_vfx_requests.append([
		action, effect_id, scene, screen_position, duration_seconds,
	])


func _contains_text(values: PackedStringArray, needle: String) -> bool:
	for value in values:
		if value.contains(needle):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_vector(actual: Vector2, expected: Vector2, message: String) -> void:
	_expect(actual.is_equal_approx(expected), "%s Got %s." % [message, actual])
