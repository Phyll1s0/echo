extends RefCounted

var path := "user://progress.json"
var data := {"version": 1, "completed": {}, "session": {}, "sound": true, "motion": true}
var last_error := ""

func _init(custom_path: String = "") -> void:
	if not custom_path.is_empty():
		path = custom_path
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("version") == 1:
			if parsed.get("completed") is Dictionary:
				data.completed = parsed.completed
			if parsed.get("session") is Dictionary:
				data.session = parsed.session
			for key in ["sound", "motion"]:
				if parsed.get(key) is bool:
					data[key] = parsed[key]

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
