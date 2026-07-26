extends SceneTree

## How it works:
## - Loads Quibble's production encounter, stage, appearance, and dialogue.
## - Presents the Miner's canonical line through the stage notification.
## - Verifies immediate and repeating drink poses until the line advances.
## - Verifies line advance, cancellation, and closing restore cup-out safely.
## - The invariant is that no Quibble motion survives the encounter lifecycle.

const ENCOUNTER_PATH := (
	"res://resources/encounters/coffee_cat_first_encounter.tres"
)
const CANONICAL_LINES := [
	"I'M QUIB-QUIB-QUIB-QUIB-QUIBBLE!",
	"HAVE YOU SEEN SEEN SEEN THE CAFE? CAFE? COFFEE? COFFEE CAFE?",
	"...",
	"THIS IS IS IS TRAVEL COFFEE. T-T-TAKE IT.",
	"IT MAKES EV-EV-EV-EVERYTHING GO F-F-FASTER!",
]

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var encounter := load(ENCOUNTER_PATH) as DepthCharacterEncounter
	_expect(encounter != null, "Quibble's encounter did not load.")
	if encounter == null:
		_finish()
		return
	_verify_canon_and_retired_reward(encounter)

	var presenter_scene := load(
		"res://Scenes/dialogue/character_presenter.tscn"
	) as PackedScene
	var presenter := presenter_scene.instantiate() as CharacterPresenter
	var stage := encounter.stage_scene.instantiate() as QuibbleEncounterStage
	presenter.z_as_relative = true
	presenter.z_index = 0
	root.add_child(presenter)
	root.add_child(stage)
	await process_frame
	presenter.apply_appearance(encounter.appearance)

	var floor_sampler := func(_screen_x: float) -> float:
		return 0.0
	_expect(
		stage.prepare(presenter, floor_sampler),
		"Quibble's stage rejected its production presenter."
	)
	if not stage._is_active:
		stage.queue_free()
		presenter.queue_free()
		await process_frame
		_finish()
		return
	_expect(
		presenter.z_as_relative and presenter.z_index == 0,
		"Quibble borrowed an absolute draw order instead of following the "
			+ "shared cast layer."
	)

	var idle_texture := encounter.appearance.texture
	var hold_texture := encounter.appearance.pose_set.get_pose(&"hold_cup").texture
	var drink_texture := encounter.appearance.pose_set.get_pose(&"drink").texture

	stage.on_dialogue_line_presented(&"miner", 2)
	_expect(
		presenter.character_sprite.texture == drink_texture,
		"The Miner's dots did not start Quibble's chug immediately."
	)
	stage._process(QuibbleEncounterStage.DRINK_SECONDS)
	_expect(
		presenter.character_sprite.texture == hold_texture,
		"Continuous chugging did not enter its brief cup-held recovery."
	)
	stage._process(QuibbleEncounterStage.HOLD_CUP_SECONDS)
	_expect(
		presenter.character_sprite.texture == drink_texture,
		"Continuous chugging did not repeat while the Miner's dots remained."
	)

	stage.on_dialogue_line_presented(&"coffee_cat", 3)
	_expect(
		presenter.character_sprite.texture == idle_texture,
		"Advancing from the Miner's dots did not restore Quibble's cup-out pose."
	)
	stage._process(0.1)
	_expect(
		presenter.character_sprite.texture == idle_texture,
		"Quibble resumed drinking while presenting his next line."
	)

	stage.on_dialogue_line_presented(&"miner", 2)
	stage.cancel_and_restore()
	_expect(
		not stage.is_processing()
			and presenter.character_sprite.texture == idle_texture,
		"Cancellation left Quibble chugging or on a borrowed pose."
	)
	stage.queue_free()
	presenter.queue_free()
	await process_frame

	var closing_presenter := (
		presenter_scene.instantiate() as CharacterPresenter
	)
	closing_presenter.z_as_relative = true
	closing_presenter.z_index = 0
	var closing_stage := (
		encounter.stage_scene.instantiate() as QuibbleEncounterStage
	)
	root.add_child(closing_presenter)
	root.add_child(closing_stage)
	await process_frame
	closing_presenter.apply_appearance(encounter.appearance)
	_expect(
		closing_stage.prepare(closing_presenter, floor_sampler),
		"Fresh Quibble stage rejected the closing-handback fixture."
	)
	closing_stage.closing_move_seconds = 0.0
	closing_stage.on_dialogue_line_presented(&"miner", 2)
	await closing_stage.play_closing()
	_expect(
		not closing_stage.is_processing()
			and closing_presenter.character_sprite.texture == idle_texture
			and closing_presenter.z_as_relative
			and closing_presenter.z_index == 0,
		"Closing handback left Quibble chugging, on a borrowed pose, or on an "
			+ "absolute draw order."
	)

	closing_stage.queue_free()
	closing_presenter.queue_free()
	await process_frame
	_finish()


func _verify_canon_and_retired_reward(
	encounter: DepthCharacterEncounter
) -> void:
	_expect(
		not encounter.grants_coffee_speed_boost,
		"Quibble must not also apply the retired permanent speed boost; "
			+ "Encounter 7 now advances combo-target availability."
	)
	_expect(
		encounter.conversation != null
			and encounter.conversation.lines.size() == CANONICAL_LINES.size(),
		"Quibble's canonical dialogue line count changed."
	)
	if encounter.conversation == null:
		return
	for line_index in range(
		mini(encounter.conversation.lines.size(), CANONICAL_LINES.size())
	):
		_expect(
			encounter.conversation.lines[line_index].text
				== CANONICAL_LINES[line_index],
			"Quibble's canonical dialogue changed at line %d." % line_index
		)


func _expect(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)


func _finish() -> void:
	if _failures.is_empty():
		print("QUIBBLE_MINER_LINE_CHUG_VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print(
		"QUIBBLE_MINER_LINE_CHUG_VERIFY: FAIL (%d)"
		% _failures.size()
	)
	quit(1)
