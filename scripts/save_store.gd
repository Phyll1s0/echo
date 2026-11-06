extends RefCounted

var path := "user://progress.json"
const DEFAULT_MUSIC_VOLUME := 36
const LEGACY_ROOMS := {"X01": "18", "X02": "19", "X03": "20"}
const OPTION_MAX := {"volume": 100, "music_volume": 100, "move_speed": 2, "room_titles": 3, "path_weight": 2}
var data := {"version": 1, "language": "en", "completed": {}, "session": {}, "extra_completed": {}, "extra_sessions": {}, "sound": true, "motion": true, "paths": false, "fullscreen": false,
	"volume": 100, "music_volume": DEFAULT_MUSIC_VOLUME, "step_sounds": true, "move_speed": 1, "room_titles": 2, "path_weight": 1}
var last_error := ""

func _init(custom_path: String = "") -> void:
	if not custom_path.is_empty():
		path = custom_path
	elif OS.has_feature("web"):
		# Other Godot games on phyll1s0.com share the same browser origin.
		# Keep ECHO's progress separate from their user://progress.json files.
		DirAccess.make_dir_recursive_absolute("user://echo")
		path = "user://echo/progress.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("version") == 1:
			if parsed.get("language") in ["en", "zh_CN"]:
				data.language = parsed.language
			for key in ["completed", "session", "extra_completed", "extra_sessions"]:
				if parsed.get(key) is Dictionary:
					data[key] = parsed[key]
			for key in ["sound", "motion", "paths", "fullscreen", "step_sounds"]:
				if parsed.get(key) is bool:
					data[key] = parsed[key]
			for key in OPTION_MAX:
				var value = parsed.get(key)
				if (value is int or value is float) and is_finite(value):
					data[key] = roundi(clampf(value, 0, OPTION_MAX[key]))
			if not parsed.has("music_volume"):
				data.music_volume = roundi(DEFAULT_MUSIC_VOLUME * data.volume / 100.0)
	# Keep unopened drafts under their old keys until that room is resumed.
	for old_id in LEGACY_ROOMS:
		if data.extra_completed.has(old_id):
			var new_id: String = LEGACY_ROOMS[old_id]
			if not data.completed.has(new_id): data.completed[new_id] = data.extra_completed[old_id]
			data.extra_completed.erase(old_id)

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
	if OS.has_feature("web"): JavaScriptBridge.force_fs_sync()
	return true
