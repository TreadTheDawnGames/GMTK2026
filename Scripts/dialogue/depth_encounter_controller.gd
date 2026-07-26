class_name DepthEncounterController
extends Node

## How it works:
## - Each encounter resource places one mineable chamber at an authored depth.
## - Crossing its ceiling captures the interaction even when one hit skips rows.
## - Dialogue begins only after the presentation miner lands on that floor.
## - A blocked reservation retries when the previous cinematic releases.
## - Stable actor IDs reuse presenters across visits and the cafe gathering.
## - The gathering stands on stage marks named for each actor when they exist,
##   and on the even terrain spread when they do not.
## - Optional encounter stages own reversible movement and named line cues.
## - MiningCinematicFlow gates input while this controller owns an interaction.
## - Adding a cutscene means adding its resource to the ordered config array.
## - The final thief remains pinned to the configured bottom depth.
## - The invariant is that no hit can skip an authored tunnel threshold.

signal final_encounter_reached(encounter_id: StringName)
signal encounter_completed(encounter_index: int)
signal coffee_speed_boost_requested
signal rat_colony_support_requested
signal character_stage_strike_requested(screen_position: Vector2)
signal stampede_rumble_started(strength_px: float)
signal stampede_rumble_finished
## Relays a stage's request to open real rock where a strike landed.
signal character_stage_rock_break_requested(
	screen_position: Vector2,
	radius_cells: int
)
## Relays a stage's requested two-axis displacement from encounter focus.
signal character_stage_camera_pan_requested(offset_cells: Vector2)
signal character_stage_camera_action_requested(
	action: int,
	offset: Vector2,
	zoom: Vector2,
	shake_strength: float,
	duration_seconds: float
)
signal character_stage_audio_action_requested(
	action: int,
	stream: AudioStream,
	bus: StringName,
	volume_db: float,
	pitch_scale: float,
	fade_seconds: float
)
signal character_stage_vfx_action_requested(
	action: int,
	effect_id: StringName,
	scene: PackedScene,
	world_position: Vector2,
	duration_seconds: float
)

const FLOW_OWNER: StringName = &"depth_encounter"
const MINER_SPEAKER_SLOT: StringName = &"miner"
const FINAL_BREAKTHROUGH_CUE: StringName = &"resume_mining"
## The cast draws between terrain strata zero and one, so its feet stand above
## the second stratum's visible support. Rooms that cut fully through that
## stratum fall back to the front layer instead of inventing a floor.
const CAST_FLOOR_LAYER_INDEX: int = 1
const CAST_FLOOR_FALLBACK_LAYER_INDEX: int = 0
## How far above its floor row a landing still counts as having arrived.
##
## A cutscene room's ground is not its floor row. The level tunnel lays up to
## three cells of loose rock along the floor, and that rock is what the miner
## comes to rest on, so a fall into a sculpted room legitimately stops short of
## the row the schedule calls the floor. Requiring the bare row waits for a
## landing that cannot happen: the encounter stays pending forever with the
## cinematic flow already claimed, which reads in game as mining that simply
## stops working.
##
## Four rows clears the tallest authored bump with one to spare. The story
## contract asks this comparison to tolerate overshoot rather than demand an
## exact impact row, and this is the same allowance in the other direction.
const LANDING_FLOOR_TOLERANCE_ROWS: int = 4
## Pixels every cutscene actor is raised off the sampled floor support.
##
## The sampler answers with the first solid cell of the rock. What the player
## sees is that rock's drawn outline, which is stroked outward from the boundary
## and so sits above it, and a character seated on the raw support stands with
## their soles inside that band looking half sunk into the ground.
##
## One value here rather than a nudge per character, because it is not a property
## of anyone's art: Cheese Girl's sprite offset already stands her exactly on her
## own origin, and she reads as low anyway. Both the miner's seating and the
## stage's walking sampler go through this, so the cast cannot drift apart from
## the man they are talking to.
##
## Three pixels clears the inked edge and the idle pose's two-pixel dip now that
## CharacterPresenter measures the actual drawn sole rather than an authored
## canvas offset.
const CUTSCENE_FLOOR_LIFT_PIXELS: float = 3.0
## How still the sampled floor has to be, and for how many readings, before the
## room counts as having arrived. Half a pixel is under the sub-cell resolution
## the mask is written at, so it cannot be met by a room still travelling.
const SETTLE_TOLERANCE_PIXELS: float = 0.5
const SETTLE_STABLE_READINGS: int = 3
## Roughly two seconds at sixty frames. Long enough for any authored focus move,
## short enough that a room which never resolves does not hang the run.
const SETTLE_TIMEOUT_FRAMES: int = 120

@export_category("Schedule")
@export var encounter_config: DepthEncounterConfig
@export var mining_config: MiningConfig

@export_category("References")
@export var dialogue_director: DialogueDirector
@export var character_scene: PackedScene
@export var character_parent: Node2D
@export var pickaxe_progression: PickaxeProgression
@export var miner_rig: MinerRig
@export var cinematic_flow: MiningCinematicFlow
@export var terrain_renderer: TerrainLayerRenderer

var _presenters: Array[CharacterPresenter] = []
var _presenters_by_actor_id: Dictionary[StringName, CharacterPresenter] = {}
var _speaker_slots_by_actor_id: Dictionary[StringName, StringName] = {}
var _encounter_positions: Array[Vector2] = []
var _stages: Array[CharacterEncounterStage] = []
## Sentinel for "the cast is not currently lifted". A real draw order could be
## any integer including zero, so absence needs a value none of them will be.
const _UNSET_DRAW_ORDER: int = -9999

var _active_stage: CharacterEncounterStage
## The cast layer's authored draw order, held while a cutscene borrows it.
var _cast_rest_draw_order: int = _UNSET_DRAW_ORDER
var _next_encounter_index: int = 0
var _pending_encounter_index: int = -1
var _active_encounter_index: int = -1
var _is_initialized: bool = false
var _credits_have_completed: bool = false
var _latest_landing_world_y: int = -1
var _active_conversation: DialogueConversation
var _is_final_breakthrough_armed: bool = false
var _is_final_breakthrough_resolving: bool = false
## True while a timeline's DIALOGUE beat is holding on a conversation this
## controller started for it, so the conversation ending releases that beat
## instead of ending the whole encounter.
var _sequence_is_awaiting_dialogue: bool = false
## True once a timeline's DIALOGUE beat has run the encounter's conversation, so
## the schedule knows not to start it again when the timeline finishes.
var _timeline_presented_conversation: bool = false
var _prestaged_encounter_index: int = -1
var _game_state: RunState


## Creates every authored character before the player reaches their room.
func _ready() -> void:
	if not _prepare_authored_characters():
		return
	_is_initialized = true


## Supplies the authoritative run model at the composition boundary.
func set_run_state(run_state: RunState) -> void:
	_game_state = run_state


## Captures the next cutscene when mining crosses its authored tunnel ceiling.
func _on_depth_changed(depth: int) -> void:
	if not _can_schedule_next_encounter():
		return
	var encounter := encounter_config.encounters[_next_encounter_index]
	var ceiling_depth := encounter_config.get_encounter_ceiling_depth(
		encounter,
		mining_config.total_run_depth
	)
	if depth < ceiling_depth:
		return
	_schedule_next_encounter()


## Promotes a reserved encounter only after the visible fall reaches its floor.
## Mining may report the crossed depth before ViewController receives its new
## target, so activating from depth_changed can freeze focus at the old height.
func _on_landing_reached(mining_y: int) -> void:
	_latest_landing_world_y = maxi(_latest_landing_world_y, mining_y)
	if _pending_encounter_index < 0 and _game_state != null:
		_on_depth_changed(_game_state.depth)
	_try_activate_pending_encounter()


## Retries a crossed floor after another cinematic releases the shared gate.
func _on_cinematic_flow_finished(finished_owner: StringName) -> void:
	if finished_owner == FLOW_OWNER or _game_state == null:
		return
	_on_depth_changed(_game_state.depth)


func _try_activate_pending_encounter() -> void:
	if (
		_pending_encounter_index < 0
		or _active_encounter_index >= 0
		or not cinematic_flow.is_owned_by(FLOW_OWNER)
	):
		return
	var pending_encounter := encounter_config.encounters[
		_pending_encounter_index
	]
	var encounter_floor_y := (
		mining_config.initial_surface_row
		+ pending_encounter.resolve_depth(mining_config.total_run_depth)
	)
	if (
		_latest_landing_world_y
		< encounter_floor_y - LANDING_FLOOR_TOLERANCE_ROWS
	):
		return
	_activate_pending_encounter()


func _can_schedule_next_encounter() -> bool:
	return (
		_is_initialized
		and _active_encounter_index < 0
		and _pending_encounter_index < 0
		and _next_encounter_index < encounter_config.encounters.size()
		and (
			not encounter_config.encounters[
				_next_encounter_index
			].requires_credits_complete
			or _credits_have_completed
		)
	)


## Releases the post-credit story floor and retries a depth already reached.
func _on_credits_completed() -> void:
	_credits_have_completed = true
	if _game_state != null:
		_on_depth_changed(_game_state.depth)


## Restores only the run-scoped credits prerequisite.
func _on_run_reset() -> void:
	if (
		_prestaged_encounter_index >= 0
		and _prestaged_encounter_index < _presenters.size()
	):
		_presenters[_prestaged_encounter_index].hide()
	_prestaged_encounter_index = -1
	_exit_cast_cutscene_draw_order()
	_credits_have_completed = false
	_is_final_breakthrough_armed = false
	_is_final_breakthrough_resolving = false
	_latest_landing_world_y = (
		mining_config.initial_surface_row
		if mining_config != null
		else -1
	)


func _schedule_next_encounter() -> bool:
	if not _can_schedule_next_encounter():
		return false
	if not cinematic_flow.try_begin(FLOW_OWNER):
		return false
	_pending_encounter_index = _next_encounter_index
	var encounter := encounter_config.encounters[_pending_encounter_index]
	if encounter.prestage_before_landing:
		var stage := _stages[_pending_encounter_index]
		var presenter := _presenters[_pending_encounter_index]
		if stage != null:
			var encounter_anchor := _encounter_positions[
				_pending_encounter_index
			]
			stage.position = encounter_anchor
			presenter.apply_appearance(encounter.appearance)
			if stage.conversation_tracks_miner:
				_align_actor_markers_to_miner(stage)
			if (
				stage.props_track_tracked_cast
				and stage.prop_markers_root != null
			):
				stage.prop_markers_root.position.x = (
					stage.actor_markers_root.position.x
				)
			var entrance_position := stage.entrance_marker.global_position
			var encounter_floor_row := (
				mining_config.initial_surface_row
				+ encounter.resolve_depth(mining_config.total_run_depth)
			)
			var entrance_floor_y := _sample_cutscene_floor(
				entrance_position.x,
				encounter_floor_row
			)
			if not is_nan(entrance_floor_y) and not is_inf(entrance_floor_y):
				entrance_position.y = entrance_floor_y
			presenter.global_position = entrance_position
			if presenter.has_pose(stage.conversation_pose):
				presenter.play_pose(stage.conversation_pose)
			if stage.conversation_facing != 0:
				presenter.set_facing_direction(stage.conversation_facing)
			presenter.show()
			_prestaged_encounter_index = _pending_encounter_index
			_enter_cast_cutscene_draw_order()
	# He is on his way down into the room from this moment. The pose holds until
	# the landing promotes the encounter, which is the only thing that knows he
	# has arrived.
	miner_rig.show_cutscene_fall()
	_try_activate_pending_encounter()
	return true


## Promotes one crossed ceiling into the active in-world tunnel sequence.
func _activate_pending_encounter() -> void:
	if (
		_pending_encounter_index < 0
		or not cinematic_flow.is_owned_by(FLOW_OWNER)
	):
		return
	_active_encounter_index = _pending_encounter_index
	_pending_encounter_index = -1
	var presenter := _presenters[_active_encounter_index]
	var encounter := encounter_config.encounters[_active_encounter_index]
	presenter.apply_appearance(encounter.appearance)
	var encounter_anchor := _encounter_positions[_active_encounter_index]
	# A prestaged actor already stands at the entrance during the fall; moving
	# him back to the room anchor here would create a landing-frame pop.
	if not encounter.prestage_before_landing:
		presenter.position = encounter_anchor
	var stage := _stages[_active_encounter_index]
	if stage != null:
		stage.position = encounter_anchor
		if stage.conversation_tracks_miner:
			_align_actor_markers_to_miner(stage)
	# He has hit the room's floor. Sprawl, then get up, while the frame opens
	# around him.
	miner_rig.show_cutscene_landing()
	_apply_trodden_floor(encounter)
	cinematic_flow.focus(FLOW_OWNER)
	_begin_active_encounter.call_deferred()


## Holds until the encounter camera has stopped travelling, so the cast are
## placed against a room that has arrived rather than one still on its way.
##
## The floor sampler is itself the settle signal. It is the exact value every
## placement depends on, so waiting on it cannot disagree with what is about to
## be measured - and it needs no reference to the camera, which this controller
## does not hold. Two readings the same to within half a pixel, three times over,
## is the room having stopped.
##
## The cap matters as much as the test. A room whose floor never resolves - an
## encounter whose chunks have not streamed, or one authored with no ground under
## the landing column - would otherwise hold the whole cutscene here forever with
## the cinematic gate already claimed, which in game looks like mining that simply
## stopped working. Timing out and placing the cast anyway degrades to exactly the
## behaviour this replaced.
func _await_room_settled(floor_sampler: Callable) -> void:
	var previous_floor_y := NAN
	var stable_readings := 0
	for _frame in range(SETTLE_TIMEOUT_FRAMES):
		await get_tree().process_frame
		if _active_encounter_index < 0:
			return
		var sampled_y: float = floor_sampler.call(
			miner_rig.get_landing_foot_screen_x()
		)
		if (
			not is_nan(sampled_y)
			and not is_nan(previous_floor_y)
			and absf(sampled_y - previous_floor_y) < SETTLE_TOLERANCE_PIXELS
		):
			stable_readings += 1
			if stable_readings >= SETTLE_STABLE_READINGS:
				return
		else:
			stable_readings = 0
		previous_floor_y = sampled_y


## Returns the screen height a cutscene actor's soles rest at for one column.
##
## Everyone standing in a cutscene room resolves their footing through here - the
## miner when he is seated on arrival, and every visitor as they walk - so the
## cast can never end up on a different reading of the same floor.
func _sample_cutscene_floor(screen_x: float, landing_world_row: int) -> float:
	var support: float = (
		terrain_renderer.get_layer_opening_floor_support_screen_y(
			screen_x,
			landing_world_row,
			CAST_FLOOR_LAYER_INDEX
		)
	)
	if is_nan(support):
		support = terrain_renderer.get_layer_opening_floor_support_screen_y(
			screen_x,
			landing_world_row,
			CAST_FLOOR_FALLBACK_LAYER_INDEX
		)
	if is_nan(support):
		return support
	return support - CUTSCENE_FLOOR_LIFT_PIXELS


## Slides the whole actor marker set so the conversation stop lands the authored
## distance from wherever the miner's descent actually left him.
##
## The snaking fall can arrive down any column in a wide band, and the encounter
## camera centres on that column, so a marker pinned to the room is at a
## different place in the frame every run. Moving only the conversation and rest
## markers fixed the wrong half of that: a visitor staged a few body-widths away
## could be sent to a stop beyond her own entrance, and an exit authored past the
## frame edge stayed on screen whenever the miner landed toward that side.
##
## Shifting the whole set keeps every authored relationship — how long the
## approach is, how far past the frame the exit sits — true at every landing
## column. The shift is measured from where the conversation marker currently is,
## so running this twice moves nothing the second time.
func _align_actor_markers_to_miner(stage: CharacterEncounterStage) -> void:
	if (
		not is_instance_valid(stage.actor_markers_root)
		or not is_instance_valid(stage.conversation_marker)
	):
		return
	var target_x := (
		miner_rig.get_cinematic_foot_screen_position().x
		+ stage.conversation_root_offset_from_miner_x
	)
	stage.actor_markers_root.global_position.x += (
		target_x - stage.conversation_marker.global_position.x
	)


## Keeps all authored characters attached to their terrain positions.
func _on_view_position_changed(view_cell_position: Vector2) -> void:
	var cell_size := float(mining_config.terrain_cell_world_size)
	var terrain_left := (
		mining_config.terrain_screen_center_x
		- view_cell_position.x * cell_size
	)
	character_parent.position = Vector2(
		terrain_left,
		mining_config.mining_face_screen_y
			- view_cell_position.y * cell_size
	)


## Bounces whichever visible chamber speaker owns the presented line.
func _on_dialogue_line_presented(
	conversation_id: StringName,
	line_index: int,
	speaker_slot: StringName,
	speaker_pose: StringName
) -> void:
	if _active_encounter_index < 0:
		return
	var encounter := encounter_config.encounters[_active_encounter_index]
	if (
		_active_conversation == null
		or conversation_id != _active_conversation.conversation_id
	):
		return
	var active_line := (
		_active_conversation.lines[line_index]
		if line_index >= 0 and line_index < _active_conversation.lines.size()
		else null
	)
	if (
		encounter.occurs_at_run_bottom
		and active_line != null
		and active_line.stage_cue == FINAL_BREAKTHROUGH_CUE
	):
		_arm_final_breakthrough()
	if (
		_active_stage != null
		and active_line != null
	):
		# Every line, not only the cued ones. A stage that runs an idle routine
		# of its own has no other way to know somebody is mid-sentence, and a
		# routine that keeps playing over a line fights the line.
		_active_stage.on_dialogue_line_presented(speaker_slot, line_index)
		if not active_line.stage_cue.is_empty():
			_active_stage.play_cue(active_line.stage_cue, line_index)
	_reset_speech_reactions()
	if speaker_slot == MINER_SPEAKER_SLOT:
		miner_rig.react_to_presented_line()
		return
	if _is_gathering_encounter(_active_encounter_index):
		for actor_id in encounter_config.gathering_actor_ids:
			if (
				_speaker_slots_by_actor_id.get(actor_id, &"")
					== speaker_slot
				and _presenters_by_actor_id.has(actor_id)
			):
				var presenter := _presenters_by_actor_id[actor_id]
				if (
					not speaker_pose.is_empty()
					and presenter.has_pose(speaker_pose)
				):
					presenter.play_pose(speaker_pose)
				presenter.react_to_presented_line()
				return
	elif speaker_slot == encounter.speaker_slot:
		var presenter := _presenters[_active_encounter_index]
		if (
			not speaker_pose.is_empty()
			and presenter.has_pose(speaker_pose)
		):
			presenter.play_pose(speaker_pose)
		presenter.react_to_presented_line()


## Opens the authored dialogue or releases a malformed encounter safely.
func _begin_active_encounter() -> void:
	var encounter := encounter_config.encounters[_active_encounter_index]
	var presenter := _presenters[_active_encounter_index]
	_reset_speech_reactions()
	_active_stage = _stages[_active_encounter_index]
	if _active_stage == null:
		# No stage means no authored marks and no floor sampler, so the roster
		# falls back to the even spread on the bare dig line. Same as before.
		if _is_gathering_encounter(_active_encounter_index):
			_gather_cafe_characters(Callable())
		# Revealing a presenter is the stage's job, through prepare(). An
		# encounter authored without one still has to be seen to speak.
		presenter.show()
	if _active_stage != null:
		# Before the frame opens, so the first drawn cutscene frame already has
		# them in front of the foreground layer instead of popping forward.
		miner_rig.enter_cutscene_draw_order()
		_enter_cast_cutscene_draw_order()
		dialogue_director.open_cinematic_frame()
		await dialogue_director.wait_until_frame_open()
		if _active_encounter_index < 0:
			return
		# Layer one, the stratum the cast actually stands on.
		#
		# This asked for layer two back when the profile lowered layer one over a
		# chamber floor so the layer beneath it formed the visible ground. That
		# reveal is off now, so the surface underfoot is the foreground stratum
		# and sampling the one behind it found a support hundreds of pixels lower
		# - which is where the cast were being walked to, well below the room and
		# off the bottom of the frame.
		var floor_sampler := _sample_cutscene_floor.bind(
			_game_state.mining_y
		)
		# Nobody is placed until the room has stopped moving under them.
		#
		# focus() re-aims the camera at the encounter as it activates, so for a
		# short while after the frame opens the whole room is still sliding. Every
		# placement below resolves a SCREEN position from the floor, and a screen
		# position sampled mid-slide is correct for a frame that no longer exists
		# by the time the tween lands: the room settles hundreds of pixels away and
		# the actor stays behind, standing below the room and off the bottom of the
		# screen.
		#
		# This was only ever obvious on encounters whose opening walk starts
		# immediately. One driven by a timeline whose first MOVE is a second in had
		# the camera settle during its own wall strikes and looked fine, which is
		# what made this read as a rat-colony problem rather than a shared one.
		await _await_room_settled(floor_sampler)
		if _active_encounter_index < 0:
			return
		# Stand the miner on the rock rather than on the row underneath it.
		#
		# The cast sampler lifts CharacterPresenter soles clear of the inked
		# contour. MinerRig owns its own measured overlap contract, so undo only
		# that cast lift and hand it the raw terrain support. This keeps every
		# cutscene on the same footing as surface play and ordinary mining.
		miner_rig.seat_landing_foot_at_screen_y(
			floor_sampler.call(miner_rig.get_landing_foot_screen_x())
			+ CUTSCENE_FLOOR_LIFT_PIXELS
		)
		if encounter.prestage_before_landing:
			# prepare() must snapshot the actor's original hidden state so a
			# cancellation can restore it after taking over the visible prestage.
			presenter.hide()
		if not _active_stage.prepare(presenter, floor_sampler):
			push_error(
				"Encounter '%s' could not prepare its stage."
				% encounter.encounter_id
			)
			_fail_active_encounter()
			return
		if encounter.prestage_before_landing:
			_prestaged_encounter_index = -1
		# After prepare, not before it. prepare() stands the stage's own visitor
		# on the entrance mark at that marker's authored y, which is the dig line
		# - and a visitor who is already in place and never walks is never
		# grounded by anything else. Running the gathering last puts the whole
		# roster, that visitor included, on the surface the sampler reports.
		if _is_gathering_encounter(_active_encounter_index):
			_gather_cafe_characters(floor_sampler)
		await _active_stage.play_opening()
		if _active_encounter_index < 0:
			return
		# A timeline that ran the conversation itself has already played the whole
		# shot, so the schedule must not start it a second time. Its beats are
		# done by the time play_opening returns, which is where an encounter
		# driven this way ends.
		if _timeline_presented_conversation:
			_timeline_presented_conversation = false
			_complete_encounter_after_dialogue(encounter)
			return
	_active_conversation = encounter.conversation
	if (
		encounter.encrypted_conversation != null
		and encounter.encrypted_conversation.has_payload()
	):
		_active_conversation = (
			encounter.encrypted_conversation.decrypt_conversation()
		)
	if encounter.occurs_at_run_bottom and _active_conversation == null:
		push_error(
			"Final encounter '%s' has no authored dialogue."
			% encounter.encounter_id
		)
		_fail_active_encounter()
		return
	if (
		_active_conversation != null
		and dialogue_director.start_conversation(
			_active_conversation,
			_is_gathering_encounter(_active_encounter_index)
				or _active_stage != null
				or encounter.occurs_at_run_bottom
		)
	):
		return
	push_error(
		"Encounter '%s' could not start dialogue." % encounter.encounter_id
	)
	if encounter.occurs_at_run_bottom:
		_fail_active_encounter()
		return
	_fail_active_encounter()


## Dresses this room's floor as walked-on ground, if the encounter asked for it.
##
## The floor line is derived from the encounter's own depth rather than passed in,
## so a room can never dress a line it does not stand on. It is cleared in
## _finish_cinematic_flow, which is the one place every ending goes through - a
## completed shot, a cancelled one and a failed one all release there, and a
## dressing left behind would follow the player down the rest of the run.
func _apply_trodden_floor(encounter: DepthCharacterEncounter) -> void:
	if not encounter.dresses_trodden_floor:
		terrain_renderer.set_trodden_floor(false)
		return
	var floor_world_y := float(
		mining_config.initial_surface_row
		+ encounter.resolve_depth(mining_config.total_run_depth)
	) * float(mining_config.terrain_cell_world_size)
	terrain_renderer.set_trodden_floor(true, floor_world_y)


## Reports whether this conversation is the cast's shared cafe stop.
func _is_gathering_encounter(encounter_index: int) -> bool:
	return (
		encounter_index >= 0
		and encounter_index < encounter_config.encounters.size()
		and encounter_config.encounters[encounter_index].gathers_cast
	)


## Places the authored stable identities together for the cafe celebration.
##
## Two ways, and the stage decides which. If it authors a marker under
## `ActorMarkers` named for a gathered actor, that mark is where they stand and
## the injected sampler decides how high; otherwise the whole roster falls back to
## the even spread across the terrain this has always used.
##
## The marks exist because the spread cannot compose a shot. It puts five
## characters at a fixed 128px pitch centred on the room while the camera centres
## on whatever column the miner's snaking fall arrived down - up to 192px away -
## so he regularly lands standing inside one of them, and the storefront, the
## furniture and the cast can never hold a relationship to each other. A marker
## set slides with him, so the gathering keeps its shape at every landing column.
##
## An actor the stage already draws into its own artwork is placed but left
## hidden. Cheese Girl is painted into the cafe's serving window, so showing her
## presenter as well would put two of her in the same frame; `actors_drawn_into_set`
## is the stage saying so, and this is the runtime honouring it. She is still
## placed, because the schedule still needs somewhere to say she is.
func _gather_cafe_characters(floor_sampler: Callable) -> void:
	var gathering_y := _presenters[_active_encounter_index].position.y
	var actor_count := encounter_config.gathering_actor_ids.size()
	var edge_margin_cells := clampi(
		absi(encounter_config.encounter_horizontal_offset_cells) / 2,
		4,
		maxi(mining_config.terrain_width_cells / 4, 4)
	)
	var minimum_cell_x := float(edge_margin_cells)
	var maximum_cell_x := float(
		maxi(
			mining_config.terrain_width_cells - 1 - edge_margin_cells,
			edge_margin_cells
		)
	)
	var spacing_cells := (
		0.0
		if actor_count <= 1
		else minf(
			16.0,
			(maximum_cell_x - minimum_cell_x)
				/ float(actor_count - 1)
		)
	)
	var group_span_cells := spacing_cells * float(maxi(actor_count - 1, 0))
	var group_start_cell_x := clampf(
		float(mining_config.terrain_width_cells) * 0.5
			- group_span_cells * 0.5,
		minimum_cell_x,
		maxf(maximum_cell_x - group_span_cells, minimum_cell_x)
	)
	for actor_index in range(actor_count):
		var actor_id := encounter_config.gathering_actor_ids[actor_index]
		if not _presenters_by_actor_id.has(actor_id):
			continue
		var presenter := _presenters_by_actor_id[actor_id]
		var authored_mark := _get_gathering_marker(actor_id)
		if authored_mark == null:
			presenter.position = Vector2(
				(group_start_cell_x + float(actor_index) * spacing_cells)
					* float(mining_config.terrain_cell_world_size),
				gathering_y
			)
		else:
			presenter.global_position = Vector2(
				authored_mark.global_position.x,
				_resolve_gathering_floor_y(floor_sampler, authored_mark)
			)
		if _stage_draws_actor_into_its_set(actor_id):
			presenter.hide()
			continue
		presenter.show()


## Returns the active stage's authored mark for one gathered actor, or null when
## it has not authored one.
##
## Looked up by the actor's own id, so the scene says who stands where in the same
## words the schedule and the timeline use, and an ordinary text search for an
## actor id finds their mark along with everything else about them.
func _get_gathering_marker(actor_id: StringName) -> Marker2D:
	if (
		_active_stage == null
		or not is_instance_valid(_active_stage.actor_markers_root)
	):
		return null
	return _active_stage.actor_markers_root.get_node_or_null(
		NodePath(String(actor_id))
	) as Marker2D


## Returns the height a gathered actor's soles rest at: the sampled floor under
## their mark, raised by however far off the ground that mark was authored.
##
## A mark's y is a HEIGHT ABOVE THE GROUND, not a position. Every actor marker in
## every stage is authored at y = 0 and that still means "standing on whatever the
## terrain turns out to be there", because the sampler decides the rest. A negative
## y is how a character is put on top of something: Quibble sits on the cafe's
## bench, thirty pixels up, and the bench itself moves with the loose rock under it
## because the whole cluster tracks the same landing column.
##
## Reading it as an offset rather than as an absolute is what keeps that true. An
## authored absolute would be correct at one landing column and wrong at every
## other, since the rock the bench stands on is different rock each run.
##
## The fallback is not decoration. The sampler answers NAN for a column whose rock
## has not resolved, and a NAN position puts an actor nowhere at all - so a room
## that has not fully settled costs a few pixels of sink rather than losing a
## character out of the shot.
func _resolve_gathering_floor_y(
	floor_sampler: Callable,
	authored_mark: Marker2D
) -> float:
	var height_above_ground := (
		authored_mark.global_position.y - _active_stage.global_position.y
		if _active_stage != null
		else 0.0
	)
	if not floor_sampler.is_valid():
		return authored_mark.global_position.y
	var sampled_y := float(floor_sampler.call(authored_mark.global_position.x))
	if is_nan(sampled_y):
		return authored_mark.global_position.y
	return sampled_y + height_above_ground


## Reports whether the active stage's own artwork already draws this character.
func _stage_draws_actor_into_its_set(actor_id: StringName) -> bool:
	return (
		_active_stage != null
		and _active_stage.actors_drawn_into_set.has(actor_id)
	)


## Grants the authored reward and advances to the next listed encounter.
func _on_conversation_finished(conversation_id: StringName) -> void:
	if _active_encounter_index < 0:
		return
	var encounter := encounter_config.encounters[_active_encounter_index]
	if (
		_active_conversation == null
		or conversation_id != _active_conversation.conversation_id
	):
		return

	# A timeline that asked for this conversation is still holding its clock on
	# it. Release the beat and let the sequence finish the shot; the rewards and
	# teardown below belong to the encounter ending, not to one beat of it.
	if _sequence_is_awaiting_dialogue:
		_sequence_is_awaiting_dialogue = false
		_timeline_presented_conversation = true
		_active_conversation = null
		if _active_stage != null:
			_active_stage.notify_dialogue_finished()
		return

	await _complete_encounter_after_dialogue(encounter)


## Grants the encounter's rewards, closes the shot, and hands mining back.
##
## Factored out because an encounter can now end in one of two places. Normally
## the conversation finishing is the end of the shot. When an authored timeline
## owns the encounter, the conversation is one beat inside it and the shot ends
## when the timeline does, so both paths arrive here rather than one of them
## quietly skipping the rewards.
func _complete_encounter_after_dialogue(
	encounter: DepthCharacterEncounter
) -> void:
	if (
		encounter.pickaxe_reward != null
		and not pickaxe_progression.grant_upgrade(
			encounter.pickaxe_reward
		)
	):
		push_error(
			"Encounter '%s' could not grant pickaxe '%s'."
			% [encounter.encounter_id, encounter.pickaxe_reward.id]
		)
	if encounter.grants_coffee_speed_boost:
		coffee_speed_boost_requested.emit()
	encounter_completed.emit(_active_encounter_index)
	_reset_speech_reactions()
	_active_conversation = null
	if encounter.occurs_at_run_bottom and _is_final_breakthrough_resolving:
		_complete_final_breakthrough()
		return
	if encounter.occurs_at_run_bottom:
		final_encounter_reached.emit(encounter.encounter_id)
		_is_final_breakthrough_armed = false
	var had_active_stage := _active_stage != null
	if had_active_stage:
		await _active_stage.play_closing()
		_active_stage = null
	if encounter.occurs_at_run_bottom or had_active_stage:
		dialogue_director.close_cinematic_frame()
		await dialogue_director.wait_until_frame_closed()

	_next_encounter_index = _active_encounter_index + 1
	_active_encounter_index = -1
	_restore_mining_after_buffer()


## Restores mining immediately or after the shared authored pause.
func _restore_mining_after_buffer() -> void:
	if encounter_config.post_dialogue_buffer_seconds > 0.0:
		var restore_timer := get_tree().create_timer(
			encounter_config.post_dialogue_buffer_seconds,
			true
		)
		restore_timer.timeout.connect(
			_finish_cinematic_flow,
			CONNECT_ONE_SHOT
		)
		return
	_finish_cinematic_flow()


## Instantiates the small fixed roster and rejects broken authored entries.
func _prepare_authored_characters() -> bool:
	if (
		encounter_config == null
		or mining_config == null
		or dialogue_director == null
		or character_scene == null
		or character_parent == null
		or pickaxe_progression == null
		or miner_rig == null
		or cinematic_flow == null
		or terrain_renderer == null
	):
		push_error("Character encounter references are incomplete.")
		return false
	if encounter_config.encounters.is_empty():
		push_error("At least one authored character encounter is required.")
		return false

	var previous_depth := -1
	var bottom_encounters := 0
	var gathering_encounters := 0
	for encounter_index in range(encounter_config.encounters.size()):
		var encounter := encounter_config.encounters[encounter_index]
		if (
			encounter == null
			or encounter.appearance == null
			or encounter.actor_id.is_empty()
		):
			push_error(
				"Character encounter %d is incomplete."
				% (encounter_index + 1)
			)
			return false
		var encounter_depth := encounter.resolve_depth(
			mining_config.total_run_depth
		)
		if encounter_depth <= previous_depth:
			push_error("Character encounters must be listed by depth.")
			return false
		if (
			not encounter.occurs_at_run_bottom
			and encounter.conversation == null
		):
			push_error(
				"Encounter '%s' requires a conversation."
				% encounter.encounter_id
			)
			return false
		if encounter.occurs_at_run_bottom:
			if (
				encounter.conversation != null
				or encounter.encrypted_conversation == null
			):
				push_error(
					"Bottom encounter '%s' requires its encrypted dialogue resource."
					% encounter.encounter_id
				)
				return false
			bottom_encounters += 1
		elif encounter.gathers_cast:
			gathering_encounters += 1
		previous_depth = encounter_depth
	if bottom_encounters != 1:
		push_error("Exactly one encounter must be at zero remaining depth.")
		return false
	if gathering_encounters != 1:
		push_error("Exactly one depth-authored cafe gathering is required.")
		return false
	if encounter_config.gathering_actor_ids.is_empty():
		push_error("The cafe gathering requires an identity-aware cast roster.")
		return false

	var cell_size := float(mining_config.terrain_cell_world_size)
	for encounter in encounter_config.encounters:
		var encounter_position := Vector2(
			(
				float(mining_config.terrain_width_cells) * 0.5
				+ float(encounter_config.encounter_horizontal_offset_cells)
			) * cell_size,
			float(
				mining_config.initial_surface_row
				+ encounter.resolve_depth(mining_config.total_run_depth)
			) * cell_size
		)
		_encounter_positions.append(encounter_position)
		var presenter: CharacterPresenter = (
			_presenters_by_actor_id.get(encounter.actor_id)
		)
		if presenter == null:
			presenter = character_scene.instantiate() as CharacterPresenter
			if presenter == null:
				push_error("Character presenter could not be instantiated.")
				return false
			character_parent.add_child(presenter)
			presenter.apply_appearance(encounter.appearance)
			presenter.position = encounter_position
			# Hidden until their own cutscene claims them.
			#
			# Every character is built up front and parked at the depth they are
			# owed, which is what lets one presenter be reused across repeat
			# visits and gathered for the cafe. Parked and visible, though, means
			# a player mining down to 300 finds Cheese Girl already standing in
			# the rock waiting for him, and then watches her teleport off screen
			# so she can walk back in. The stage's prepare() reveals whoever it
			# takes, and the cafe gathering shows its own roster explicitly.
			presenter.hide()
			_presenters_by_actor_id[encounter.actor_id] = presenter
			_speaker_slots_by_actor_id[encounter.actor_id] = (
				encounter.speaker_slot
			)
		_presenters.append(presenter)
		var stage: CharacterEncounterStage
		if encounter.stage_scene != null:
			stage = (
				encounter.stage_scene.instantiate()
				as CharacterEncounterStage
			)
			if stage == null:
				push_error(
					"Encounter '%s' stage is not a CharacterEncounterStage."
					% encounter.encounter_id
				)
				return false
			character_parent.add_child(stage)
			stage.position = encounter_position
			# Hand the stage its timeline and a way to reach the rest of the cast.
			#
			# The sequence lives on the encounter because that is where a designer
			# picks it, and the stage is the thing that can play it. Nothing wired
			# these two together before, so every authored timeline in the project
			# was an editor document that no run ever read.
			stage.sequence = (
				encounter.sequence
				if encounter.plays_authored_timeline
				else null
			)
			stage.cast_resolver = _resolve_cast_member
			_connect_once(
				stage.sequence_dialogue_requested,
				_on_sequence_dialogue_requested
			)
			_connect_once(
				stage.presentation_strike_requested,
				_on_character_stage_strike_requested
			)
			_connect_once(
				stage.presentation_rock_break_requested,
				_on_character_stage_rock_break_requested
			)
			_connect_once(
				stage.presentation_camera_pan_requested,
				_on_character_stage_camera_pan_requested
			)
			_connect_once(
				stage.sequence_camera_action_requested,
				_on_character_stage_camera_action_requested
			)
			_connect_once(
				stage.sequence_audio_action_requested,
				_on_character_stage_audio_action_requested
			)
			_connect_once(
				stage.sequence_vfx_action_requested,
				_on_character_stage_vfx_action_requested
			)
			# A stampede floors the miner for as long as it runs. The stage owns
			# the horde and knows when the last of them is gone; it does not own
			# the miner, so it says what happened and this decides what that
			# means for him.
			if stage is RatColonyEncounterStage:
				var colony_stage := stage as RatColonyEncounterStage
				_connect_once(
					colony_stage.stampede_started,
					_on_stampede_started
				)
				_connect_once(
					colony_stage.stampede_finished,
					_on_stampede_finished
				)
				_connect_once(
					colony_stage.stampede_rumble_started,
					_on_stampede_rumble_started
				)
				_connect_once(
					colony_stage.stampede_rumble_finished,
					_on_stampede_rumble_finished
				)
			if encounter.starts_rat_colony_support:
				if not stage is RatColonyEncounterStage:
					push_error(
						"Encounter '%s' requires a rat colony stage."
							% encounter.encounter_id
					)
					return false
				_connect_once(
					(stage as RatColonyEncounterStage)
						.persistent_colony_requested,
					_on_persistent_colony_requested
				)
		_stages.append(stage)
	for actor_id in encounter_config.gathering_actor_ids:
		if not _presenters_by_actor_id.has(actor_id):
			push_error(
				"Gathering actor '%s' has no authored encounter." % actor_id
			)
			return false
	_on_view_position_changed(Vector2(
		float(mining_config.terrain_width_cells) * 0.5,
		float(mining_config.initial_surface_row)
	))
	return true


## Reports whether the fixed-depth schedule already owns this mining beat.
func has_pending_or_active_interaction() -> bool:
	return (
		_pending_encounter_index >= 0
		or _active_encounter_index >= 0
		or cinematic_flow.is_owned_by(FLOW_OWNER)
	)


## Releases only this encounter's named ownership of mining and camera state.
func _finish_cinematic_flow() -> void:
	_reset_speech_reactions()
	terrain_renderer.set_trodden_floor(false)
	# Nobody is left face down when the shot releases him, whatever ended it. A
	# stampede that was cancelled mid-run never reaches its own finished signal,
	# and the miner would go back to mining lying on his face.
	miner_rig.release_cutscene_landing()
	miner_rig.exit_cutscene_draw_order()
	# Back to the mining grounding, so the shot's seating never follows him into
	# the rest of the run.
	miner_rig.show_intact_floor_grounding()
	_exit_cast_cutscene_draw_order()
	cinematic_flow.finish(FLOW_OWNER)


## Lifts the whole cast in front of the foreground rock for a cutscene, matching
## the order the miner takes.
##
## CharacterLayer sits at z 1 while terrain layer one draws at z 2, so a visitor
## walking up to the miner was drawn behind the rock in front of him. That is
## right for ordinary mining, where the foreground closing over things is what
## sells the depth, and wrong for a cutscene, which holds on the cast and needs
## them readable. The miner already did this; his conversation partner has to
## move with him or he steps in front of the person he is talking to.
func _enter_cast_cutscene_draw_order() -> void:
	if character_parent == null or _cast_rest_draw_order != _UNSET_DRAW_ORDER:
		return
	_cast_rest_draw_order = character_parent.z_index
	character_parent.z_index = miner_rig.cutscene_draw_order


## Puts the cast back at the order the scene authored for it.
func _exit_cast_cutscene_draw_order() -> void:
	if character_parent == null or _cast_rest_draw_order == _UNSET_DRAW_ORDER:
		return
	character_parent.z_index = _cast_rest_draw_order
	_cast_rest_draw_order = _UNSET_DRAW_ORDER


## Turns the authored dialogue cue into a live target without hiding its line.
func _arm_final_breakthrough() -> void:
	if (
		_is_final_breakthrough_armed
		or not cinematic_flow.is_owned_by(FLOW_OWNER)
		or not dialogue_director.begin_gameplay_handoff()
	):
		return
	_is_final_breakthrough_armed = true
	cinematic_flow.finish_with_presentation_fade(FLOW_OWNER, 0.35)


## A real resolved hit breaks the held line and starts the endless descent.
func _on_final_breakthrough_mined(
	depth_gained: int,
	_cells_removed: int,
	_combo: int,
	_combo_strength: float
) -> void:
	if not _is_final_breakthrough_armed or depth_gained <= 0:
		return
	_is_final_breakthrough_armed = false
	_is_final_breakthrough_resolving = true
	dialogue_director.finish_conversation()
	_is_final_breakthrough_resolving = false


func _complete_final_breakthrough() -> void:
	_reset_speech_reactions()
	dialogue_director.close_cinematic_frame()
	var encounter := encounter_config.encounters[_active_encounter_index]
	final_encounter_reached.emit(encounter.encounter_id)
	_next_encounter_index = _active_encounter_index + 1
	_active_encounter_index = -1
	_active_stage = null


func _reset_speech_reactions() -> void:
	for presenter in _presenters_by_actor_id.values():
		presenter.reset_speech_motion()
	miner_rig.reset_speech_motion()


## Returns any cast member by their stable actor id, for a timeline that names
## somebody other than the visitor its own stage is holding.
func _resolve_cast_member(actor_id: StringName) -> Node2D:
	return _presenters_by_actor_id.get(actor_id)


## Runs the conversation a timeline asked for, and remembers that the timeline is
## waiting on it.
##
## A DIALOGUE beat only requests; DialogueDirector stays the one thing that ever
## presents a line. The beat blocks until the conversation reports back, which is
## the only way a timeline can hold for exactly as long as the player takes to
## read.
func _on_sequence_dialogue_requested(
	conversation: DialogueConversation,
	line_range: Vector2i
) -> void:
	if conversation == null:
		return
	_active_conversation = conversation
	_sequence_is_awaiting_dialogue = dialogue_director.start_conversation(
		conversation,
		true,
		line_range
	)
	if not _sequence_is_awaiting_dialogue:
		push_error(
			"A timeline asked for dialogue '%s' that could not start."
			% conversation.conversation_id
		)
		# Release the beat rather than leaving the timeline held forever on a
		# conversation that is never going to arrive.
		if _active_stage != null:
			_active_stage.notify_dialogue_finished()


## Puts the miner on the floor while a horde runs over him.
func _on_stampede_started() -> void:
	miner_rig.hold_cutscene_landing()


## Picks him back up once the last of them has left the frame.
func _on_stampede_finished() -> void:
	miner_rig.release_cutscene_landing()


func _on_stampede_rumble_started(strength_px: float) -> void:
	stampede_rumble_started.emit(strength_px)


func _on_stampede_rumble_finished() -> void:
	stampede_rumble_finished.emit()


## Relays a stage-local action through the cross-system wiring boundary.
func _on_character_stage_strike_requested(
	screen_position: Vector2
) -> void:
	character_stage_strike_requested.emit(screen_position)


## Relays a stage's rock-breaking request the same way, so terrain stays owned by
## the mining wiring rather than being reached into from a cutscene stage.
func _on_character_stage_rock_break_requested(
	screen_position: Vector2,
	radius_cells: int
) -> void:
	character_stage_rock_break_requested.emit(screen_position, radius_cells)


## Relays a stage's camera pan the same way, because the framed view belongs to
## the mining wiring and a cutscene stage owns actors, props and local effects.
func _on_character_stage_camera_pan_requested(offset_cells: Vector2) -> void:
	character_stage_camera_pan_requested.emit(offset_cells)


func _on_character_stage_camera_action_requested(
	action: int,
	offset: Vector2,
	zoom: Vector2,
	shake_strength: float,
	duration_seconds: float
) -> void:
	character_stage_camera_action_requested.emit(
		action,
		offset,
		zoom,
		shake_strength,
		duration_seconds
	)


func _on_character_stage_audio_action_requested(
	action: int,
	stream: AudioStream,
	bus: StringName,
	volume_db: float,
	pitch_scale: float,
	fade_seconds: float
) -> void:
	character_stage_audio_action_requested.emit(
		action,
		stream,
		bus,
		volume_db,
		pitch_scale,
		fade_seconds
	)


func _on_character_stage_vfx_action_requested(
	action: int,
	effect_id: StringName,
	scene: PackedScene,
	world_position: Vector2,
	duration_seconds: float
) -> void:
	character_stage_vfx_action_requested.emit(
		action,
		effect_id,
		scene,
		world_position,
		duration_seconds
	)


## Relays the clean stage transition through the cross-system wiring boundary.
func _on_persistent_colony_requested() -> void:
	rat_colony_support_requested.emit()


## Restores reversible stage state and skips malformed authored dialogue.
func _fail_active_encounter() -> void:
	if (
		_prestaged_encounter_index >= 0
		and _prestaged_encounter_index < _presenters.size()
	):
		_presenters[_prestaged_encounter_index].hide()
	_prestaged_encounter_index = -1
	if _active_stage != null:
		_active_stage.cancel_and_restore()
		_active_stage = null
	dialogue_director.close_cinematic_frame()
	await dialogue_director.wait_until_frame_closed()
	_reset_speech_reactions()
	_active_conversation = null
	_is_final_breakthrough_armed = false
	_is_final_breakthrough_resolving = false
	if _active_encounter_index >= 0:
		_next_encounter_index = _active_encounter_index + 1
	_active_encounter_index = -1
	_finish_cinematic_flow()


func _connect_once(source_signal: Signal, target: Callable) -> void:
	if not source_signal.is_connected(target):
		source_signal.connect(target)
