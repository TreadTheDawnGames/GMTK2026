extends SceneTree

## How it works:
## - Loads Encounter 1 and the shared cafe encounter as shipped resources.
## - Verifies Encounter 1 uses the normal layered terrain, not cafe floor shaders.
## - Verifies its Miner depth override and legacy fallback resolution.
## - The invariant is that release restores gameplay layers and existing rooms
##   keep their established staging unless they explicitly opt into an offset.

const _ENCOUNTER_PATH := (
	"res://resources/encounters/cheese_girl_first_encounter.tres"
)
const _CAFE_PATH := "res://resources/encounters/cafe_gathering_encounter.tres"
const _EXPECTED_MINER_DEPTH_OFFSET := 28.0
const _LEGACY_CAFE_DEPTH_OFFSET := 56.0

var _failures: PackedStringArray = []


func _initialize() -> void:
	var encounter := load(_ENCOUNTER_PATH) as DepthCharacterEncounter
	var cafe := load(_CAFE_PATH) as DepthCharacterEncounter
	_expect(encounter != null, "Encounter 1 resource must load.")
	_expect(cafe != null, "Cafe encounter resource must load.")
	if encounter != null:
		_verify_encounter_one(encounter)
	if cafe != null:
		_verify_legacy_fallback(cafe)
	if _failures.is_empty():
		print("CHEESE_GIRL_FLOOR_STAGING_PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _verify_encounter_one(encounter: DepthCharacterEncounter) -> void:
	_expect(
		not encounter.dresses_trodden_floor,
		"Encounter 1 must not leave persistent trodden-floor dressing."
	)
	_expect(
		not encounter.lights_floor_as_plane,
		"Encounter 1 must preserve the normal layered terrain floor."
	)
	_expect(
		is_equal_approx(
			encounter.resolve_miner_cutscene_depth_offset(0.0),
			_EXPECTED_MINER_DEPTH_OFFSET
		),
		"Encounter 1 must move only the Miner 28px toward the camera."
	)
	_expect(
		encounter.keeps_miner_grounding_after_release,
		"Encounter 1 must keep its room-seated Miner baseline after release."
	)


func _verify_legacy_fallback(cafe: DepthCharacterEncounter) -> void:
	_expect(
		is_equal_approx(
			cafe.resolve_miner_cutscene_depth_offset(
				_LEGACY_CAFE_DEPTH_OFFSET
			),
			_LEGACY_CAFE_DEPTH_OFFSET
		),
		"Unconfigured gathering encounters must preserve cafe Miner depth."
	)
	var default_encounter := DepthCharacterEncounter.new()
	_expect(
		is_zero_approx(
			default_encounter.resolve_miner_cutscene_depth_offset(0.0)
		),
		"Unconfigured ordinary encounters must preserve their shared floor."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
