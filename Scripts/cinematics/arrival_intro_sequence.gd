class_name ArrivalIntroSequence
extends Node2D

## How it works:
## - Authored Marker2D anchors say where the bus enters, stops, and leaves.
## - begin() reserves the miner's shared cinematic visual override and parks
##   every prop; play_arrival() then drives the bus in and reveals the miner.
## - The miner moves through MinerRig's existing override API only, so his
##   gameplay root, RunState, and mining depth are never touched.
## - The station stays after the intro. The camera is fixed and terrain scrolls
##   beneath it, so this node re-anchors itself to the live ground line every
##   frame and the stop leaves the shot only as the miner actually descends.
## - finish() releases the miner but leaves the staged surface standing, then
##   schedules the ambient pickup: a while later a bus returns, collects the
##   attendant, and leaves, so scrolling back up finds a changed surface.
## The invariant is that this sequence is presentation-only from end to end.
##
## The pickup is deliberately outside every gate. It never claims
## MiningCinematicFlow, never touches MinerRig, never opens dialogue, and never
## pauses the tree, so a player who never scrolls up is unaffected by it.

signal arrival_finished
signal attendant_picked_up

var _audio_handler: PlayerAudioHandler


## Receives the shared audio service from the mining composition root.
func set_audio_handler(audio_handler: PlayerAudioHandler) -> void:
	_audio_handler = audio_handler


@export_category("References")
@export var miner_rig: MinerRig
@export var bus: Node2D
@export var bus_sprite: Sprite2D
## Two travel states, drawn per direction. Left to right the door side faces the
## camera; right to left you see the far side with the door away. Swapping
## between them is a texture change, not a flip — the front must always lead.
@export var bus_side_right_texture: Texture2D
@export var bus_side_left_texture: Texture2D

@export_category("Bus Art Placement")
## The door art and the right-facing side share one geometry: same opaque bbox,
## same wheel centres. Only the left-facing art differs, so it carries its own
## sprite offset and wheel-shine UVs.
@export var stopped_sprite_offset: Vector2 = Vector2(-14.0, -74.0)
@export var side_left_sprite_offset: Vector2 = Vector2(14.0, -74.0)
@export var stopped_wheel_uvs: PackedVector2Array = PackedVector2Array([
	Vector2(0.390962, 0.568345),
	Vector2(0.684128, 0.568345),
])
@export var side_left_wheel_uvs: PackedVector2Array = PackedVector2Array([
	Vector2(0.315423, 0.568345),
	Vector2(0.608588, 0.568345),
])
@export var station: Node2D
@export var attendant: CharacterPresenter
## Supplies the live ground line so the stop stays planted on the surface as
## terrain scrolls past the fixed camera.
@export var surface_presentation: SurfacePresentation
@export var terrain_renderer: TerrainLayerRenderer
@export var bus_arrival_anchor: Marker2D
@export var bus_stop_anchor: Marker2D
@export var bus_exit_anchor: Marker2D
@export var door_step_anchor: Marker2D
## Measured trailing edge of the bus body, mirroring FrontEdgeAnchor. The
## opening shot frames against it, so re-measuring the art moves the framing
## with it instead of leaving a hardcoded half-width somewhere else. It is
## optional on purpose: without it the opening falls back to a plain timed
## zoom rather than refusing to stage.
@export var bus_rear_edge_anchor: Marker2D
## Where the miner stands once he is off the bus. Only its x is used; his y is
## the ground line, the same one he mines from.
@export var miner_drop_off_anchor: Marker2D
## Where the returning bus parks to collect the attendant. It stays behind the
## stop in draw order, so it reads as pulling up on the road behind the bench.
@export var attendant_pickup_stop_anchor: Marker2D

@export_category("Timing")
## The drive-in starts outside the wide title framing, so it covers about two
## and a half times the distance the gameplay frame would have needed. This is
## paced for that longer run at roughly the original speed; shortening it back
## toward 0.9 makes the bus arrive two and a half times as fast.
@export_range(0.2, 6.0, 0.05) var bus_arrival_seconds: float = 2.0
@export_range(0.0, 1.5, 0.05) var bus_settle_seconds: float = 0.12
## Beat between the bus stopping and the miner being off it. He alights on the
## far side, so this is the pause the doors happen in.
@export_range(0.0, 3.0, 0.05) var miner_exit_delay_seconds: float = 0.2
@export_range(0.0, 2.0, 0.05) var hold_before_dialogue_seconds: float = 0.0
## The pull-away is eased in, so this is the length of an accelerating run over
## the whole 1559 px to the exit anchor, not a constant speed. A cubic ease over
## 1.5 s left the shot at roughly three times its own average by the end, which
## is what read as the bus being yanked off screen; a gentler curve over a
## longer run keeps the trailing edge slow enough to uncover the miner as a
## wipe rather than a cut.
@export_range(0.2, 6.0, 0.05) var bus_departure_seconds: float = 2.6

@export_category("Drive Past")
## Ambient. A while after control returns the bus runs back the other way,
## left to right, without stopping. Pure flavour for a player who scrolls up.
@export var drive_past_enabled: bool = true
## Measured from the moment he is off the road and into his own shaft, not from
## the moment control is handed over. On a clock alone the pass fired long after
## he had dug down, by which point the road it runs along has scrolled off the
## top of the frame and the whole thing happens where nobody can see it.
@export_range(0.5, 600.0, 0.5) var drive_past_delay_seconds: float = 3.0
@export_range(0.5, 12.0, 0.1) var drive_past_seconds: float = 3.2

@export_category("Attendant Pickup")
## Ambient epilogue. A bus returns this long after control is handed back and
## takes the attendant away, so a player who scrolls back up finds him gone.
@export var attendant_pickup_enabled: bool = true
@export_range(5.0, 600.0, 1.0) var attendant_pickup_delay_seconds: float = 75.0
## How long the attendant takes to step across and board.
@export_range(0.1, 4.0, 0.05) var attendant_boarding_seconds: float = 0.7
## How far he moves toward the door as he boards.
@export_range(0.0, 400.0, 1.0) var attendant_boarding_distance_px: float = 58.0
## Pause at the stop before the doors close again.
@export_range(0.0, 4.0, 0.05) var attendant_pickup_hold_seconds: float = 0.4

@export_category("Placement")
## The original surface-centre point every prop is authored against in viewport
## pixels. Following its terrain conversion on both axes prevents horizontal
## camera tracking from sliding the ground out from under the station.
@export var authored_surface_anchor_screen_position: Vector2 = Vector2(
	576.0,
	262.0
)
@export_category("Motion")
## Vertical dip as the bus stops, so the arrival lands instead of gliding.
@export_range(0.0, 32.0, 0.5) var bus_settle_dip_pixels: float = 5.0
## How far the body drops when a wheel crosses the miner's shaft on an ambient
## pass. The hole is a real thing in the road by then, so a bus that rides over
## it without noticing reads as driving on a painted backdrop.
@export_range(0.0, 24.0, 0.5) var bus_hole_bounce_pixels: float = 4.0
@export_range(0.05, 1.5, 0.05) var bus_hole_bounce_seconds: float = 0.32
## Keep this below bus_body_draw_order. He waits behind the whole bus and its
## trailing edge is what uncovers him, so nothing may ever draw him over it.
@export_range(0, 16, 1) var miner_cinematic_draw_order: int = 4
## The whole bus, in front of the cinematic miner. It used to sit behind him
## with a cropped copy of its own leading section redrawn above him, which put
## the crop's boundary across his body: the bus covered him until that boundary
## passed, and from there he was drawn standing on top of the bodywork.
@export_range(0, 16, 1) var bus_body_draw_order: int = 5
## Used for the ambient passes. The bus runs in the far lane, so it passes in
## front of the stop and the man waiting at it, and behind the miner standing
## further down the road. It used to run behind the stop as well, which put the
## whole bus on the wrong side of the one building it belongs to.
@export_range(-16, 16, 1) var bus_behind_draw_order: int = 2

var _is_playing: bool = false
var _is_pickup_active: bool = false
var _attendant_was_collected: bool = false
var _has_driven_past: bool = false
## The line he stands on: where he gets off the bus, and where play begins.
var _ground_foot_y: float = 0.0
var _dig_foot_x: float = 0.0
var _bus_rest_position: Vector2
var _prop_tween: Tween
## Set while an ambient pass is crossing the shot, with one crossing flag per
## drawn wheel so each finds the miner's shaft on its own.
var _is_ambient_pass_driving: bool = false
var _wheel_was_left_of_hole: Array[bool] = [false, false]
var _bounce_tween: Tween
var _wheel_material: ShaderMaterial
var _wheel_radius_pixels: float = 1.0
var _wheel_spin_phase: float = 0.0
var _previous_bus_x: float = 0.0


func _ready() -> void:
	_follow_ground_line()
	_prepare_wheel_shine()


## Keeps the stop planted on the surface and rolls the wheels as the bus moves.
func _process(_delta: float) -> void:
	_follow_ground_line()
	_advance_wheel_spin()
	_bounce_bus_over_the_hole()


## Caches the wheel material and converts its authored radius into pixels, so
## travel distance can be turned into rotation without a second authored number.
func _prepare_wheel_shine() -> void:
	if bus_sprite == null:
		return
	_wheel_material = bus_sprite.material as ShaderMaterial
	_previous_bus_x = bus.position.x if bus != null else 0.0
	if _wheel_material == null or bus_sprite.texture == null:
		return
	var authored_radius: Variant = _wheel_material.get_shader_parameter(
		&"wheel_radius_uv"
	)
	if authored_radius == null:
		return
	_wheel_radius_pixels = maxf(
		float(authored_radius)
			* float(bus_sprite.texture.get_height())
			* absf(bus_sprite.scale.y),
		1.0
	)


## Rolls the wheels by the arc length the bus actually travelled, so a parked
## bus is perfectly still and no rotation is invented while it waits.
func _advance_wheel_spin() -> void:
	if _wheel_material == null or bus == null:
		return
	var travelled := bus.position.x - _previous_bus_x
	_previous_bus_x = bus.position.x
	if is_zero_approx(travelled):
		return
	# Rolling without slipping: turned angle is distance over wheel radius. The
	# sprite may be mirrored to face the other way, which mirrors the apparent
	# rotation too, so the sign follows scale.x.
	_wheel_spin_phase = fposmod(
		_wheel_spin_phase
			+ travelled / _wheel_radius_pixels
				* signf(bus_sprite.scale.x),
		TAU
	)
	_wheel_material.set_shader_parameter(
		&"wheel_spin_phase",
		_wheel_spin_phase
	)


func _follow_ground_line() -> void:
	if surface_presentation == null:
		return
	position = (
		surface_presentation.get_surface_screen_position()
		- authored_surface_anchor_screen_position
	)


## Parks every prop, reserves the miner's visual, and shows the staged surface.
func begin() -> bool:
	if _is_playing or not _has_complete_references():
		push_error("ArrivalIntroSequence references are incomplete.")
		return false
	if not miner_rig.begin_cinematic_visual_override():
		push_error("ArrivalIntroSequence could not reserve the miner visual.")
		return false
	_is_playing = true
	# Capture the miner's authored resting sole before anything moves it. The
	# surface is flat, so this one point supplies both the ground line the bus
	# stops on and the exact spot where the miner is revealed.
	var rest_foot := miner_rig.get_cinematic_foot_screen_position()
	_ground_foot_y = rest_foot.y
	_dig_foot_x = rest_foot.x
	_bus_rest_position = bus_stop_anchor.position
	bus.position = Vector2(
		bus_arrival_anchor.position.x,
		_bus_rest_position.y
	)
	_previous_bus_x = bus.position.x
	bus.z_index = bus_body_draw_order
	_set_bus_travel_art(-1)
	station.modulate.a = 1.0
	attendant.modulate.a = 1.0
	attendant.show()
	miner_rig.hide()
	show()
	return true


## Drives the bus in, drops the miner at the dig spot, and pulls away.
func play_arrival() -> void:
	if not _is_playing:
		return

	var bus_audio: AudioStreamPlayer
	if _audio_handler != null:
		bus_audio = _audio_handler.play_sound(AudioLibrary.BUS_FULL)
		create_tween().tween_property(bus_audio, "volume_linear", 0.0, 0.0)
		create_tween().tween_property(bus_audio, "volume_linear", 1, 1)
	
	
	await _drive_bus_to(_bus_rest_position.x, bus_arrival_seconds, true)
	if not _is_playing:
		return
	# He gets off on the far side, out of sight, a beat after the bus settles.
	if miner_exit_delay_seconds > 0.0:
		await get_tree().create_timer(
			miner_exit_delay_seconds,
			true
		).timeout
	if not _is_playing:
		return
	# He is off the bus and waiting at the stop before it moves, so the shot has
	# someone standing there for the departure to pull away from.
	_place_miner_at_drop_off()
	_begin_bus_departure()
	
	if is_instance_valid(bus_audio):
		create_tween().tween_property(bus_audio, "volume_linear", 0, 3)
	await _await_prop_tween()

	if not _is_playing:
		return
	if hold_before_dialogue_seconds > 0.0:
		await get_tree().create_timer(
			hold_before_dialogue_seconds,
			true
		).timeout
	if not _is_playing:
		return
	arrival_finished.emit()


## Settles the miner back onto his gameplay rest pose. The stop stays standing:
## only the HUD changes when mining begins, and the surface leaves the shot by
## scrolling as the miner descends.
func finish(restore_seconds: float = 0.2) -> void:
	if not _is_playing:
		return
	_is_playing = false
	_kill_prop_tween()
	miner_rig.show()
	# The bus drop-off is the gameplay dig spot. Restore scale and draw order
	# without inventing a second translation after the bus has left him there.
	var restore_tween := miner_rig.restore_cinematic_visual(restore_seconds)
	if restore_tween != null:
		await restore_tween.finished
	# The ambient passes run behind the cast from here on, so neither can sweep
	# across the miner while he is mining.
	bus.z_index = bus_behind_draw_order
	_run_ambient_passes()


## Releases the miner immediately for interrupted intros.
func abort_and_restore() -> void:
	if not _is_playing:
		return
	_is_playing = false
	_is_pickup_active = false
	_kill_prop_tween()
	miner_rig.show()
	miner_rig.cancel_cinematic_visual_override()


## Reports whether an arrival or departure currently owns the staging.
func is_playing() -> bool:
	return _is_playing


## Returns the viewport x of the bus's trailing edge, or INF when the anchor is
## not authored. The opening shot reads it every frame to keep the whole bus
## inside a frame that is still shrinking around it.
func get_bus_rear_edge_x() -> float:
	if bus == null or bus_rear_edge_anchor == null:
		return INF
	return bus_rear_edge_anchor.global_position.x


## Reports whether the ambient bus has already taken the attendant away.
func has_collected_attendant() -> bool:
	return _attendant_was_collected


## Reports whether the ambient left-to-right drive-past has already run.
func has_driven_past() -> bool:
	return _has_driven_past


## Runs the two ambient bus passes in order: a drive-past the other way, then
## later the return that collects the attendant. Neither gates the player.
func _run_ambient_passes() -> void:
	await _run_drive_past()
	await _run_attendant_pickup()


## Suspends until the miner has dug in and left the road clear. He is on the
## surface for as long as he is standing on the ground he started from, so this
## is the same test the rig already answers for its own draw order.
func _await_miner_below_ground() -> void:
	while (
		is_instance_valid(miner_rig)
		and miner_rig.is_on_surface()
	):
		await get_tree().process_frame


## Opens a pass over the dug road. Each wheel's side of the shaft is recorded
## first, so a pass that starts with the hole already behind it never opens on
## a crossing it did not make.
func _begin_ambient_pass() -> void:
	_bus_rest_position.y = bus.position.y
	for wheel_index: int in range(_wheel_was_left_of_hole.size()):
		_wheel_was_left_of_hole[wheel_index] = (
			_get_wheel_local_x(wheel_index) < _get_hole_local_x()
		)
	_is_ambient_pass_driving = true


## The column he digs down, in this node's own space, which is the one the bus
## positions are measured in. It is his dig spot rather than where he got off
## the bus: the shaft is where he stood to mine, not where he stepped down.
func _get_hole_local_x() -> float:
	return to_local(Vector2(_dig_foot_x, 0.0)).x


func _end_ambient_pass() -> void:
	_is_ambient_pass_driving = false
	_kill_bounce_tween()


## Jolts the bus as a wheel crosses the shaft the miner opened in the road.
## Each wheel is tracked separately, so a pass over the hole reads as the front
## dropping into it and the back following it rather than as one shudder.
func _bounce_bus_over_the_hole() -> void:
	if not _is_ambient_pass_driving or bus == null or bus_sprite == null:
		return
	var hole_x := _get_hole_local_x()
	for wheel_index: int in range(_wheel_was_left_of_hole.size()):
		var is_left_of_hole := _get_wheel_local_x(wheel_index) < hole_x
		if is_left_of_hole == _wheel_was_left_of_hole[wheel_index]:
			continue
		_wheel_was_left_of_hole[wheel_index] = is_left_of_hole
		_kick_bus_bounce()


## Drops the body and lets it come back, once per wheel. It is deliberately
## shorter than the settle dip the arrival uses: that one is weight coming off
## the suspension, this one is a wheel finding a hole and leaving it again.
func _kick_bus_bounce() -> void:
	if _bounce_tween != null and _bounce_tween.is_valid():
		_bounce_tween.kill()
	var rest_y := _bus_rest_position.y
	_bounce_tween = create_tween()
	_bounce_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_bounce_tween.tween_property(
		bus,
		"position:y",
		rest_y + bus_hole_bounce_pixels,
		maxf(bus_hole_bounce_seconds, 0.01) * 0.35
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_bounce_tween.tween_property(
		bus,
		"position:y",
		rest_y,
		maxf(bus_hole_bounce_seconds, 0.01) * 0.65
	).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Where one drawn wheel sits along the shot right now, taken from the same
## authored UVs the wheel shine is placed with, so re-measuring the art moves
## the bounce with it.
func _get_wheel_local_x(wheel_index: int) -> float:
	var wheel_uvs := (
		side_left_wheel_uvs
		if bus_sprite.texture == bus_side_left_texture
		else stopped_wheel_uvs
	)
	if wheel_index >= wheel_uvs.size() or bus_sprite.texture == null:
		return bus.position.x
	return (
		bus.position.x
		+ bus_sprite.position.x
		+ (wheel_uvs[wheel_index].x - 0.5)
			* float(bus_sprite.texture.get_width())
			* bus_sprite.scale.x
	)


## Sends the bus back left to right without stopping, purely as life on the
## surface for a player who scrolls up. It never stops, so it keeps the
## door-facing frame the whole way, per the authored direction rule.
func _run_drive_past() -> void:
	if not drive_past_enabled or attendant_pickup_stop_anchor == null:
		return
	# The road is his until he is off it: driving a bus through the spot he is
	# standing on reads as it going straight over him. Waiting for the shaft
	# first is also what keeps the pass in shot, since the road scrolls away
	# behind him as he descends.
	await _await_miner_below_ground()

	await get_tree().create_timer(
		maxf(drive_past_delay_seconds, 0.01),
		true
	).timeout
	if not is_instance_valid(bus):
		return
	bus.position = Vector2(
		bus_exit_anchor.position.x,
		bus_stop_anchor.position.y
	)
	var bus_audio: AudioStreamPlayer2D
	if _audio_handler != null:
		bus_audio = _audio_handler.PlaySoundAtGlobalPosition(
			AudioLibrary.BUS,
			bus.global_position,
			bus
		)
	if bus_audio != null:
		bus_audio.volume_db = 0
		var audio_tween: Tween = create_tween()
		audio_tween.tween_property(bus_audio, "volume_linear", 0.0, 0.0)
		audio_tween.tween_property(
			bus_audio,
			"volume_linear",
			1.0,
			drive_past_seconds / 2
		)
		audio_tween.tween_property(
			bus_audio,
			"volume_linear",
			0,
			drive_past_seconds / 2
		)

	_previous_bus_x = bus.position.x
	_begin_ambient_pass()
	await _drive_bus_to(
		bus_arrival_anchor.position.x,
		drive_past_seconds,
		false
	)
	_end_ambient_pass()
	_has_driven_past = true


## Waits out the authored delay, then brings a bus back for the attendant.
## Nothing here gates the player: no flow claim, no miner, no dialogue, no pause.
func _run_attendant_pickup() -> void:
	if (
		not attendant_pickup_enabled
		or _is_pickup_active
		or _attendant_was_collected
		or attendant_pickup_stop_anchor == null
	):
		return
	_is_pickup_active = true
	await get_tree().create_timer(
		maxf(attendant_pickup_delay_seconds, 0.01),
		true
	).timeout
	await _await_miner_below_ground()
	if not _is_pickup_active or not is_instance_valid(attendant):
		_is_pickup_active = false
		return

	# The bus left to the left, and the drive-past carried it off to the right,
	# so bring it back to its offscreen right entry before it drives in again.
	bus.position = Vector2(
		bus_arrival_anchor.position.x,
		bus_stop_anchor.position.y
	)
	_previous_bus_x = bus.position.x
	_begin_ambient_pass()
	await _drive_bus_to(
		attendant_pickup_stop_anchor.position.x,
		bus_arrival_seconds,
		true
	)
	_end_ambient_pass()
	if not _is_pickup_active:
		return
	await _board_attendant()
	if not _is_pickup_active:
		return
	if attendant_pickup_hold_seconds > 0.0:
		await get_tree().create_timer(
			attendant_pickup_hold_seconds,
			true
		).timeout
	if not _is_pickup_active:
		return
	_begin_bus_departure()
	await _await_prop_tween()
	_is_pickup_active = false
	_attendant_was_collected = true
	attendant_picked_up.emit()


## Steps the attendant across to the open door and out of the shot.
func _board_attendant() -> void:
	_kill_prop_tween()
	_prop_tween = create_tween()
	_prop_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_prop_tween.set_parallel(true)
	_prop_tween.tween_property(
		attendant,
		"position:x",
		attendant.position.x + attendant_boarding_distance_px,
		maxf(attendant_boarding_seconds, 0.01)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_prop_tween.tween_property(
		attendant,
		"modulate:a",
		0.0,
		maxf(attendant_boarding_seconds, 0.01)
	).set_delay(maxf(attendant_boarding_seconds, 0.01) * 0.45)
	await _prop_tween.finished
	attendant.hide()


func _drive_bus_to(
	target_x: float,
	duration: float,
	settle_on_arrival: bool
) -> void:
	# The frame follows the direction of travel, so callers cannot forget it.
	_set_bus_travel_art(signi(roundi(target_x - bus.position.x)))
	_kill_prop_tween()
	_prop_tween = create_tween()
	_prop_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_prop_tween.tween_property(
		bus,
		"position:x",
		target_x,
		maxf(duration, 0.01)
	).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT if settle_on_arrival else Tween.EASE_IN
	)
	if settle_on_arrival and bus_settle_seconds > 0.0:
		# A short dip and recovery reads as weight coming off the suspension.
		_prop_tween.tween_property(
			bus,
			"position:y",
			_bus_rest_position.y + bus_settle_dip_pixels,
			bus_settle_seconds * 0.4
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_prop_tween.tween_property(
			bus,
			"position:y",
			_bus_rest_position.y,
			bus_settle_seconds * 0.6
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _prop_tween.finished


## Selects the frame for the direction of travel, so the bus's front always
## leads. Getting this wrong is what makes it look like it is reversing.
func _set_bus_travel_art(travel_direction: int) -> void:
	if travel_direction < 0:
		_apply_bus_art(
			bus_side_left_texture,
			side_left_sprite_offset,
			side_left_wheel_uvs
		)
	else:
		_apply_bus_art(
			bus_side_right_texture,
			stopped_sprite_offset,
			stopped_wheel_uvs
		)


## Swaps the frame together with the placement and wheel positions it was
## measured for. Keeping the three together is what stops a swap from sliding
## the body or leaving the wheel shine glinting off the bodywork.
func _apply_bus_art(
	frame: Texture2D,
	sprite_offset: Vector2,
	wheel_uvs: PackedVector2Array
) -> void:
	if bus_sprite == null or frame == null:
		return
	bus_sprite.texture = frame
	bus_sprite.position = sprite_offset
	if _wheel_material == null or wheel_uvs.size() < 2:
		return
	_wheel_material.set_shader_parameter(&"wheel_one_uv", wheel_uvs[0])
	_wheel_material.set_shader_parameter(&"wheel_two_uv", wheel_uvs[1])


## Shuts the door and pulls away in one motion, without waiting for it.
func _begin_bus_departure() -> void:
	_set_bus_travel_art(
		signi(roundi(bus_exit_anchor.position.x - bus.position.x))
	)
	_kill_prop_tween()
	_prop_tween = create_tween()
	_prop_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_prop_tween.set_parallel(true)
	_prop_tween.tween_property(
		bus,
		"position:x",
		bus_exit_anchor.position.x,
		maxf(bus_departure_seconds, 0.01)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Suspends until the current prop motion is done, if one is running.
func _await_prop_tween() -> void:
	if _prop_tween != null and _prop_tween.is_valid():
		await _prop_tween.finished


## Stands the miner at the stop the moment the bus has settled: off the bus,
## just ahead of its front wheel, and behind it. The parked bus covers him
## there, so showing him now costs nothing and the departure's trailing edge is
## what uncovers him rather than anything switching on.
func _place_miner_at_drop_off() -> void:
	miner_rig.place_cinematic_foot_at(
		Vector2(
			miner_drop_off_anchor.global_position.x,
			_ground_foot_y
		),
		miner_cinematic_draw_order
	)
	miner_rig.show()


## Ends the pass's own vertical jolt as well, so an interrupted pass cannot
## leave the body parked halfway into a bounce.
func _kill_bounce_tween() -> void:
	if _bounce_tween != null and _bounce_tween.is_valid():
		_bounce_tween.kill()
	_bounce_tween = null


func _kill_prop_tween() -> void:
	if _prop_tween != null and _prop_tween.is_valid():
		_prop_tween.kill()
	_prop_tween = null


func _has_complete_references() -> bool:
	return (
		miner_rig != null
		and bus != null
		and bus_sprite != null
		and station != null
		and attendant != null
		and terrain_renderer != null
		and bus_arrival_anchor != null
		and bus_stop_anchor != null
		and bus_exit_anchor != null
		and door_step_anchor != null
		and miner_drop_off_anchor != null
	)
