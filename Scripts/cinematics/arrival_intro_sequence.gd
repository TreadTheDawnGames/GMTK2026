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

@export_category("References")
@export var miner_rig: MinerRig
@export var bus: Node2D
@export var bus_sprite: Sprite2D
## Draws only the leading section above the miner during the exit reveal.
@export var bus_front_sprite: Sprite2D
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
## Texture pixels retained for the leading section. Slightly over half keeps
## the miner fully hidden until the bus's front passes his centre-screen spot.
@export_range(1.0, 1024.0, 1.0) var bus_front_region_width_px: float = 560.0
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
## Where the miner waits while the parked bus hides him.
@export var miner_drop_off_anchor: Marker2D
## Where the returning bus parks to collect the attendant. It stays behind the
## stop in draw order, so it reads as pulling up on the road behind the bench.
@export var attendant_pickup_stop_anchor: Marker2D

@export_category("Timing")
@export_range(0.2, 6.0, 0.05) var bus_arrival_seconds: float = 0.9
@export_range(0.0, 1.5, 0.05) var bus_settle_seconds: float = 0.12
## Beat between the bus stopping and the miner being off it. He alights on the
## far side, so this is the pause the doors happen in.
@export_range(0.0, 3.0, 0.05) var miner_exit_delay_seconds: float = 0.2
@export_range(0.0, 2.0, 0.05) var hold_before_dialogue_seconds: float = 0.0
@export_range(0.2, 6.0, 0.05) var bus_departure_seconds: float = 1.5

@export_category("Drive Past")
## Ambient. A while after control returns the bus runs back the other way,
## left to right, without stopping. Pure flavour for a player who scrolls up.
@export var drive_past_enabled: bool = true
@export_range(2.0, 600.0, 1.0) var drive_past_delay_seconds: float = 28.0
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
## Keep this below bus_front_draw_order so the parked bus hides him until the wipe.
@export_range(0, 16, 1) var miner_cinematic_draw_order: int = 4
## Full bus body behind the miner while he steps out.
@export_range(0, 16, 1) var bus_body_draw_order: int = 3
## Cropped leading section above the miner, so the front passes in front of him.
@export_range(0, 16, 1) var bus_front_draw_order: int = 5
## Used for the ambient passes. They happen while the player is mining, so the
## bus runs behind the cast and can never sweep across the miner.
@export_range(-16, 16, 1) var bus_behind_draw_order: int = 0
## The miner's gameplay draw order. Terrain layer one sits at z_index 2, so at
## this value the foreground stratum covers his legs exactly as it does during
## play. Handing it back on the settle step makes that read as him planting his
## feet, instead of his legs clipping away in one frame once the shot is over.
@export_range(0, 16, 1) var miner_settle_draw_order: int = 1

var _is_playing: bool = false
var _is_pickup_active: bool = false
var _attendant_was_collected: bool = false
var _has_driven_past: bool = false
var _ground_foot_y: float = 0.0
var _dig_foot_x: float = 0.0
var _bus_rest_position: Vector2
var _prop_tween: Tween
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
	bus_front_sprite.z_index = bus_front_draw_order
	bus_front_sprite.show()
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
	# The parked bus draws over him, so placing him now costs nothing and lets
	# the departure itself wipe him into view instead of popping him in once
	# the road is clear. The bus only pulls away once he is off it.
	_place_miner_at_drop_off()
	_begin_bus_departure()
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
	# Hand back gameplay draw order in place. The miner is already at the exact
	# dig spot, so the foreground can close over his legs without inventing a
	# walk or another translation before input unlocks.
	miner_rig.place_cinematic_foot_at(
		Vector2(_dig_foot_x, _ground_foot_y),
		miner_settle_draw_order
	)
	var restore_tween := miner_rig.restore_cinematic_visual(restore_seconds)
	if restore_tween != null:
		await restore_tween.finished
	# The ambient passes run behind the cast from here on, so neither can sweep
	# across the miner while he is mining.
	bus_front_sprite.hide()
	bus.z_index = bus_behind_draw_order
	_run_ambient_passes()


## Releases the miner immediately for interrupted intros.
func abort_and_restore() -> void:
	if not _is_playing:
		return
	_is_playing = false
	_is_pickup_active = false
	_kill_prop_tween()
	bus_front_sprite.hide()
	miner_rig.show()
	miner_rig.cancel_cinematic_visual_override()


## Reports whether an arrival or departure currently owns the staging.
func is_playing() -> bool:
	return _is_playing


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


## Sends the bus back left to right without stopping, purely as life on the
## surface for a player who scrolls up. It never stops, so it keeps the
## door-facing frame the whole way, per the authored direction rule.
func _run_drive_past() -> void:
	if not drive_past_enabled or attendant_pickup_stop_anchor == null:
		return
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
	_previous_bus_x = bus.position.x
	await _drive_bus_to(
		bus_arrival_anchor.position.x,
		drive_past_seconds,
		false
	)
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
	await _drive_bus_to(
		attendant_pickup_stop_anchor.position.x,
		bus_arrival_seconds,
		true
	)
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
	_sync_bus_front_sprite(frame, sprite_offset)
	if _wheel_material == null or wheel_uvs.size() < 2:
		return
	_wheel_material.set_shader_parameter(&"wheel_one_uv", wheel_uvs[0])
	_wheel_material.set_shader_parameter(&"wheel_two_uv", wheel_uvs[1])


## Crops and aligns the direction's leading section over the full bus body.
func _sync_bus_front_sprite(
	frame: Texture2D,
	sprite_offset: Vector2
) -> void:
	if bus_front_sprite == null:
		return
	var texture_size := frame.get_size()
	var region_width := minf(bus_front_region_width_px, texture_size.x)
	var region_x := (
		0.0
		if frame == bus_side_left_texture
		else texture_size.x - region_width
	)
	var region_center_x := region_x + region_width * 0.5
	bus_front_sprite.texture = frame
	bus_front_sprite.region_rect = Rect2(
		region_x,
		0.0,
		region_width,
		texture_size.y
	)
	bus_front_sprite.position = sprite_offset + Vector2(
		(region_center_x - texture_size.x * 0.5) * bus_sprite.scale.x,
		0.0
	)
	bus_front_sprite.scale = bus_sprite.scale


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
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


## Suspends until the current prop motion is done, if one is running.
func _await_prop_tween() -> void:
	if _prop_tween != null and _prop_tween.is_valid():
		await _prop_tween.finished


## Stands the miner at the stop while the parked bus still covers him. He is
## shown here rather than after the wipe, so the bus's trailing edge uncovers a
## miner who was already standing there instead of one who pops into being.
func _place_miner_at_drop_off() -> void:
	miner_rig.place_cinematic_foot_at(
		Vector2(
			miner_drop_off_anchor.global_position.x,
			_ground_foot_y
		),
		miner_cinematic_draw_order
	)
	miner_rig.show()


func _kill_prop_tween() -> void:
	if _prop_tween != null and _prop_tween.is_valid():
		_prop_tween.kill()
	_prop_tween = null


func _has_complete_references() -> bool:
	return (
		miner_rig != null
		and bus != null
		and bus_sprite != null
		and bus_front_sprite != null
		and station != null
		and attendant != null
		and terrain_renderer != null
		and bus_arrival_anchor != null
		and bus_stop_anchor != null
		and bus_exit_anchor != null
		and door_step_anchor != null
		and miner_drop_off_anchor != null
	)
