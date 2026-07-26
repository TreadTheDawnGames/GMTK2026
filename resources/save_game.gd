extends Resource
class_name SaveGame

signal settings_applied(mute_bounce: bool)

const SAVE_PATH: String = "user://savegame.tres"
const MAX_VOLUME: float = 3.5
const MASTER_BUS: StringName = &"Master"
const MUSIC_BUS: StringName = &"Music"
const SFX_BUS: StringName = &"SFX"

@export var master_volume: float = 0.6
@export var master_mute: bool = false
@export var sfx_volume: float = 0.6
@export var sfx_mute: bool = false
@export var music_volume: float = 0.6
@export var music_mute: bool = false
@export var mute_bounce: bool = false
## Options stores the authored menu index: disabled, adaptive, then enabled.
@export_range(0, 2, 1) var vsync_mode: int = 0
## Sparse terrain-space gem records. GemOutcropField keeps these chunked while
## active, so saving the full map does not make review scrolling visit it all.
@export var gem_outcrops: Array[Dictionary] = []

var _storage_path: String = SAVE_PATH


## Persists this resource and reports failures to both callers and the log.
func write_savegame(storage_path: String = "") -> Error:
	if not storage_path.is_empty():
		_storage_path = storage_path
	var save_error := ResourceSaver.save(self, _storage_path)
	if save_error != OK:
		push_error(
			"Could not save game to %s: %s"
			% [_storage_path, error_string(save_error)]
		)
	return save_error


## Uses direct file existence so a stale ResourceLoader cache cannot fake a save.
static func save_exists(storage_path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(storage_path)


## Loads a fresh resource instance and safely falls back when data is invalid.
static func load_savegame(
	storage_path: String = SAVE_PATH,
	apply_settings: bool = true
) -> SaveGame:
	var loaded_save: SaveGame = null
	if save_exists(storage_path):
		loaded_save = ResourceLoader.load(
			storage_path,
			"",
			ResourceLoader.CACHE_MODE_IGNORE
		) as SaveGame
		if loaded_save == null:
			push_warning(
				"Save data at %s is invalid; defaults will be used."
				% storage_path
			)
	if loaded_save == null:
		loaded_save = SaveGame.new()
	loaded_save._storage_path = storage_path
	loaded_save._normalize_settings()
	if apply_settings:
		loaded_save.apply_runtime_settings()
	return loaded_save


## Applies saved options by bus name so audio-layout reordering stays safe.
func apply_runtime_settings() -> void:
	_apply_audio_bus(MASTER_BUS, master_volume, master_mute)
	_apply_audio_bus(MUSIC_BUS, music_volume, music_mute)
	_apply_audio_bus(SFX_BUS, sfx_volume, sfx_mute)
	apply_vsync_mode(vsync_mode)
	settings_applied.emit(mute_bounce)


## Maps the settings menu index to Godot's non-matching enum order.
static func apply_vsync_mode(saved_mode: int) -> void:
	match clampi(saved_mode, 0, 2):
		1:
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ADAPTIVE
			)
		2:
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED
			)
		_:
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_DISABLED
			)


## Keeps corrupted or legacy option values inside the authored UI range.
func _normalize_settings() -> void:
	master_volume = clampf(master_volume, 0.0, MAX_VOLUME)
	music_volume = clampf(music_volume, 0.0, MAX_VOLUME)
	sfx_volume = clampf(sfx_volume, 0.0, MAX_VOLUME)
	vsync_mode = clampi(vsync_mode, 0, 2)


## Applies one complete bus setting while tolerating a missing custom bus.
static func _apply_audio_bus(
	bus_name: StringName,
	volume: float,
	is_muted: bool
) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		push_error("Saved audio bus '%s' does not exist." % bus_name)
		return
	AudioServer.set_bus_volume_linear(bus_index, volume)
	AudioServer.set_bus_mute(bus_index, is_muted)
