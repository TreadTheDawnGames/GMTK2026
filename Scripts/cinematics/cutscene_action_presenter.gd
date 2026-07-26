class_name CutsceneActionPresenter
extends Node

## How it works:
## - MiningSceneWiring forwards typed cutscene camera, audio, and VFX requests.
## - Camera framing uses the existing encounter view and shared Camera2D.
## - Audio owns one music player; one-shots free themselves when finished.
## - VFX instances live under the supplied world root and are keyed for STOP.
## - reset_presentation() removes every persistent effect at encounter teardown.
## - The invariant is that no cutscene presentation survives a reset.

var _view_controller: ViewController
var _camera: Camera2D
var _impact_shake: ImpactShake
var _world_root: Node
var _cell_world_size: float = 1.0
var _base_zoom := Vector2.ONE
var _current_offset_cells := Vector2.ZERO
var _camera_tween: Tween
var _music_tween: Tween
var _music_player: AudioStreamPlayer
var _shake_generation: int = 0
## One entry per unfinished PLAY_SFX beat. The active encounter's finite timeline
## bounds growth; completion or reset removes every entry and player.
var _active_sfx: Array[AudioStreamPlayer] = []
## One entry per authored effect id. SPAWN replaces an existing id and STOP,
## timed cleanup, or reset erases it, so growth is bounded by live VFX beats.
var _active_vfx: Dictionary = {}
var _reduce_motion_enabled: bool = false


func configure(
	view_controller: ViewController,
	camera: Camera2D,
	impact_shake: ImpactShake,
	world_root: Node,
	cell_world_size: float
) -> void:
	_view_controller = view_controller
	_camera = camera
	_impact_shake = impact_shake
	_world_root = world_root
	_cell_world_size = maxf(cell_world_size, 1.0)
	if _camera != null:
		_base_zoom = _camera.zoom
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "CutsceneMusic"
	add_child(_music_player)


## Snaps camera framing and suppresses shake and decorative authored VFX.
func set_reduce_motion_enabled(enabled: bool) -> void:
	_reduce_motion_enabled = enabled
	if not enabled:
		return
	_shake_generation += 1
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = null
	if _impact_shake != null:
		_impact_shake.end_sustained()
	for effect_variant in _active_vfx.values():
		var effect := effect_variant as Node
		if is_instance_valid(effect):
			effect.queue_free()
	_active_vfx.clear()


func present_camera_action(
	action: int,
	offset: Vector2,
	zoom: Vector2,
	shake_strength: float,
	duration_seconds: float
) -> void:
	match action:
		CutsceneBeat.CameraAction.FRAME:
			_present_frame(offset, zoom, duration_seconds)
		CutsceneBeat.CameraAction.SHAKE:
			_present_shake(shake_strength, duration_seconds)
		CutsceneBeat.CameraAction.RESET:
			_reset_camera(duration_seconds)


func present_audio_action(
	action: int,
	stream: AudioStream,
	bus: StringName,
	volume_db: float,
	pitch_scale: float,
	fade_seconds: float
) -> void:
	match action:
		CutsceneBeat.AudioAction.PLAY_SFX:
			if stream != null:
				_play_sfx(stream, bus, volume_db, pitch_scale)
		CutsceneBeat.AudioAction.PLAY_MUSIC:
			if stream != null:
				_play_music(
					stream,
					bus,
					volume_db,
					pitch_scale,
					fade_seconds
				)
		CutsceneBeat.AudioAction.STOP_MUSIC:
			_stop_music(fade_seconds)


func present_vfx_action(
	action: int,
	effect_id: StringName,
	scene: PackedScene,
	world_position: Vector2,
	duration_seconds: float
) -> void:
	if action == CutsceneBeat.VfxAction.STOP:
		_remove_vfx(effect_id)
		return
	if _reduce_motion_enabled or scene == null:
		return
	_remove_vfx(effect_id)
	var instance := scene.instantiate()
	if instance == null:
		return
	var parent := _world_root if is_instance_valid(_world_root) else self
	parent.add_child(instance)
	var node_2d := instance as Node2D
	if node_2d != null:
		node_2d.global_position = world_position
	_active_vfx[effect_id] = instance
	if duration_seconds > 0.0:
		_expire_vfx_after(
			effect_id,
			instance,
			duration_seconds
		)


func reset_presentation(_unused: Variant = null) -> void:
	_shake_generation += 1
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = null
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null
	if _view_controller != null:
		_apply_view_offset(Vector2.ZERO)
	if _camera != null:
		_camera.zoom = _base_zoom
	if _impact_shake != null:
		_impact_shake.end_sustained()
	if _music_player != null:
		_music_player.stop()
	for sfx_player in _active_sfx:
		if is_instance_valid(sfx_player):
			sfx_player.stop()
			sfx_player.queue_free()
	_active_sfx.clear()
	for effect_variant in _active_vfx.values():
		var effect := effect_variant as Node
		if is_instance_valid(effect):
			effect.queue_free()
	_active_vfx.clear()


func _present_frame(
	offset: Vector2,
	zoom: Vector2,
	duration_seconds: float
) -> void:
	var target_offset_cells := offset / _cell_world_size
	var target_zoom := Vector2(
		maxf(zoom.x, 0.01),
		maxf(zoom.y, 0.01)
	)
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = null
	if _reduce_motion_enabled or duration_seconds <= 0.0:
		if _view_controller != null:
			_apply_view_offset(target_offset_cells)
		if _camera != null:
			_camera.zoom = target_zoom
		return
	_camera_tween = create_tween()
	_camera_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if _view_controller != null:
		_camera_tween.parallel().tween_method(
			_apply_view_offset,
			_current_offset_cells,
			target_offset_cells,
			duration_seconds
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _camera != null:
		_camera_tween.parallel().tween_property(
			_camera,
			"zoom",
			target_zoom,
			duration_seconds
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _apply_view_offset(offset_cells: Vector2) -> void:
	_current_offset_cells = offset_cells
	if _view_controller != null:
		_view_controller.set_encounter_view_offset_cells(offset_cells)


func _present_shake(strength: float, duration_seconds: float) -> void:
	if _reduce_motion_enabled or _impact_shake == null:
		return
	_shake_generation += 1
	var generation := _shake_generation
	_impact_shake.begin_sustained(maxf(strength, 0.0))
	_finish_shake_after(
		generation,
		maxf(duration_seconds, _impact_shake.duration_seconds)
	)


func _reset_camera(duration_seconds: float) -> void:
	_present_frame(Vector2.ZERO, _base_zoom, duration_seconds)
	_shake_generation += 1
	if _impact_shake != null:
		_impact_shake.end_sustained()


func _play_sfx(
	stream: AudioStream,
	bus: StringName,
	volume_db: float,
	pitch_scale: float
) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	player.pitch_scale = maxf(pitch_scale, 0.01)
	_active_sfx.append(player)
	player.finished.connect(
		_on_sfx_finished.bind(player),
		CONNECT_ONE_SHOT
	)
	add_child(player)
	player.play()


func _on_sfx_finished(player: AudioStreamPlayer) -> void:
	_active_sfx.erase(player)
	if is_instance_valid(player):
		player.queue_free()


func _play_music(
	stream: AudioStream,
	bus: StringName,
	volume_db: float,
	pitch_scale: float,
	fade_seconds: float
) -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_player.stop()
	_music_player.stream = stream
	_music_player.bus = bus
	_music_player.pitch_scale = maxf(pitch_scale, 0.01)
	_music_player.volume_db = -80.0 if fade_seconds > 0.0 else volume_db
	_music_player.play()
	if fade_seconds <= 0.0:
		return
	_music_tween = create_tween()
	_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.tween_property(
		_music_player,
		"volume_db",
		volume_db,
		fade_seconds
	)


func _stop_music(fade_seconds: float) -> void:
	if _music_player == null or not _music_player.playing:
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	if fade_seconds <= 0.0:
		_music_player.stop()
		return
	_music_tween = create_tween()
	_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.tween_property(
		_music_player,
		"volume_db",
		-80.0,
		fade_seconds
	)
	_music_tween.tween_callback(_music_player.stop)


func _remove_vfx(effect_id: StringName) -> void:
	if not _active_vfx.has(effect_id):
		return
	var instance := _active_vfx[effect_id] as Node
	_active_vfx.erase(effect_id)
	if is_instance_valid(instance):
		instance.queue_free()


func _finish_shake_after(generation: int, seconds: float) -> void:
	await get_tree().create_timer(
		seconds,
		true,
		false,
		true
	).timeout
	if generation == _shake_generation and _impact_shake != null:
		_impact_shake.end_sustained()


func _expire_vfx_after(
	effect_id: StringName,
	instance: Node,
	seconds: float
) -> void:
	await get_tree().create_timer(
		seconds,
		true,
		false,
		true
	).timeout
	if _active_vfx.get(effect_id) == instance:
		_remove_vfx(effect_id)
