extends Resource
class_name SaveGame

const save_path : String = "user://savegame.tres"

@export var master_volume : float  = 0.6
@export var master_mute : bool  = false
@export var sfx_volume : float  = 0.6
@export var sfx_mute : bool  = false
@export var music_volume : float  = 0.6
@export var music_mute : bool  = false
@export var mute_bounce : bool = false
@export var vsync_mode : int = 0
## Sparse terrain-space gem records. GemOutcropField keeps these chunked while
## active, so saving the full map does not make review scrolling visit it all.
@export var gem_outcrops: Array[Dictionary] = []

func write_savegame() -> void:
	ResourceSaver.save(self, save_path)
	print("saved")

static func save_exists() -> bool:
	return ResourceLoader.exists(save_path)

static func load_savegame() -> SaveGame:
	var loaded_save: SaveGame
	if save_exists():
		loaded_save = load(save_path) as SaveGame
		print("loaded existing")
	if loaded_save == null:
		printerr("No save exists")
		loaded_save = SaveGame.new()
	print("---- Save ----",
	"\nmaster_audio_level: ", loaded_save.master_volume,
	"\nsfx_audio_level: ", loaded_save.sfx_volume,
	"\nmusic_audio_level: ", loaded_save.music_volume,
	"\nmute_bounce: ", loaded_save.mute_bounce,
	"\nvsync_mode: ", loaded_save.vsync_mode)
	AudioServer.set_bus_volume_linear(0, loaded_save.master_volume)
	AudioServer.set_bus_volume_linear(1, loaded_save.music_volume)
	AudioServer.set_bus_volume_linear(2, loaded_save.sfx_volume)
	AudioServer.set_bus_mute(0, loaded_save.master_mute)
	AudioServer.set_bus_mute(1, loaded_save.music_mute)
	AudioServer.set_bus_mute(2, loaded_save.sfx_mute)
	
	return loaded_save
