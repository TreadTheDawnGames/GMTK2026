extends SceneTree

var _failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node2D.new()
	root.add_child(host)
	var camera := Camera2D.new()
	host.add_child(camera)
	var shake := ImpactShake.new()
	shake.camera = camera
	host.add_child(shake)
	var view := ViewController.new()
	var presenter := CutsceneActionPresenter.new()
	host.add_child(presenter)
	presenter.configure(view, camera, shake, host, 8.0)

	presenter.present_camera_action(
		CutsceneBeat.CameraAction.FRAME,
		Vector2(16.0, -8.0),
		Vector2(1.25, 1.25),
		0.0,
		0.0
	)
	_expect(
		camera.zoom.is_equal_approx(Vector2(1.25, 1.25)),
		"FRAME applies authored zoom"
	)
	presenter.present_camera_action(
		CutsceneBeat.CameraAction.FRAME,
		Vector2.ZERO,
		Vector2(2.0, 2.0),
		0.0,
		0.2
	)
	await create_timer(0.02).timeout
	presenter.present_camera_action(
		CutsceneBeat.CameraAction.FRAME,
		Vector2.ZERO,
		Vector2(3.0, 3.0),
		0.0,
		0.0
	)
	await create_timer(0.03).timeout
	_expect(
		camera.zoom.is_equal_approx(Vector2(3.0, 3.0)),
		"An immediate frame must kill the previous camera tween."
	)

	var music := AudioStreamWAV.new()
	presenter.present_audio_action(
		CutsceneBeat.AudioAction.PLAY_MUSIC,
		music,
		&"Master",
		-6.0,
		1.0,
		0.0
	)
	var music_player := presenter.get_node_or_null("CutsceneMusic") as AudioStreamPlayer
	_expect(
		music_player != null and music_player.stream == music,
		"PLAY_MUSIC owns the authored stream"
	)
	presenter.present_audio_action(
		CutsceneBeat.AudioAction.PLAY_SFX,
		AudioStreamGenerator.new(),
		&"Master",
		0.0,
		1.0,
		0.0
	)
	await process_frame
	var sfx_player: AudioStreamPlayer
	for child in presenter.get_children():
		if child is AudioStreamPlayer and child != music_player:
			sfx_player = child as AudioStreamPlayer
			break
	_expect(
		sfx_player != null and sfx_player.playing,
		"PLAY_SFX must own its live one-shot until completion."
	)

	var effect_source := Node2D.new()
	var effect_scene := PackedScene.new()
	_expect(
		effect_scene.pack(effect_source) == OK,
		"VFX fixture packs"
	)
	effect_source.free()
	presenter.present_vfx_action(
		CutsceneBeat.VfxAction.SPAWN,
		&"dust",
		effect_scene,
		Vector2(21.0, 34.0),
		0.0
	)
	var spawned := host.get_child(host.get_child_count() - 1) as Node2D
	_expect(
		spawned != null and spawned.global_position == Vector2(21.0, 34.0),
		"SPAWN places a VFX instance in world space"
	)
	presenter.present_vfx_action(
		CutsceneBeat.VfxAction.STOP,
		&"dust",
		null,
		Vector2.ZERO,
		0.0
	)
	await process_frame
	_expect(not is_instance_valid(spawned), "STOP removes the matching VFX")

	presenter.reset_presentation()
	await process_frame
	_expect(
		camera.zoom.is_equal_approx(Vector2.ONE),
		"reset restores the shared camera zoom"
	)
	_expect(
		music_player != null and not music_player.playing,
		"reset stops cutscene music"
	)
	_expect(
		not is_instance_valid(sfx_player),
		"reset must stop and free unfinished cutscene SFX."
	)

	host.queue_free()
	await process_frame
	if _failures.is_empty():
		print("CUTSCENE_ACTION_PRESENTER_VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
