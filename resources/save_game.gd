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

func write_savegame() -> void:
	ResourceSaver.save(self, save_path)
	print("saved")

static func save_exists() -> bool:
	return ResourceLoader.exists(save_path)

static func load_savegame() -> Resource:
	var loaded_save
	if save_exists():
		loaded_save = load(save_path)
		print("loaded existing")
	else:
		printerr("No save exists")
		return null
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
