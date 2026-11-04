extends RefCounted

var path := "user://progress.json"
const DEFAULT_MUSIC_VOLUME := 36
const OPTION_MAX := {"volume": 100, "music_volume": 100, "move_speed": 2, "room_titles": 3, "path_weight": 2}
var data := {"version": 1, "language": "en", "completed": {}, "session": {}, "sound": true, "motion": true, "paths": false, "fullscreen": false,
	"volume": 100, "music_volume": DEFAULT_MUSIC_VOLUME, "step_sounds": true, "move_speed": 1, "room_titles": 2, "path_weight": 1}
var last_error := ""

func _init(custom_path: String = "") -> void:
	if not custom_path.is_empty():
		path = custom_path
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("version") == 1:
			if parsed.get("language") in ["en", "zh_CN"]:
				data.language = parsed.language
			if parsed.get("completed") is Dictionary:
				data.completed = parsed.completed
			if parsed.get("session") is Dictionary:
				data.session = parsed.session
			for key in ["sound", "motion", "paths", "fullscreen", "step_sounds"]:
				if parsed.get(key) is bool:
					data[key] = parsed[key]
			for key in OPTION_MAX:
				var value = parsed.get(key)
				if (value is int or value is float) and is_finite(value):
					data[key] = roundi(clampf(value, 0, OPTION_MAX[key]))
			if not parsed.has("music_volume"):
				data.music_volume = roundi(DEFAULT_MUSIC_VOLUME * data.volume / 100.0)

func flush() -> bool:
	last_error = ""
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "Could not write the save file."
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	file.close()
	var error := DirAccess.rename_absolute(path + ".tmp", path)
	if error != OK:
		last_error = "Could not save your progress."
		return false
	return true
