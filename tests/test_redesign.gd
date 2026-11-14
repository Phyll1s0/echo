extends "res://tests/test_ui.gd"

func _run() -> void:
	ui = preload("res://scenes/main.tscn").instantiate()
	ui.store = Store.new(path)
	ui.store.data.sound = false
	ui.store.data.motion = false
	ui.store.data.room_titles = 0
	root.add_child(ui)
	await settle()
	var old_drafts = JSON.parse_string(FileAccess.get_file_as_string("res://tests/redesign_legacy.json"))
	for locale in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		ui.store.data.language = locale
		for old in old_drafts:
			var index: int = ui.room_index(old.level_id)
			var fresh = ui.Puzzle.new(ui.levels[index])
			var clean: Dictionary = fresh.snapshot()
			verify(not fresh.restore(old) and fresh.snapshot() == clean, "Incompatible old plans are rejected atomically: " + old.level_id)
			ui.store.data.completed[old.level_id] = {"echoes": old.echoes.size(), "beats": 20}
			ui.store.data.session = old.duplicate(true)
			ui.open_level(index, true, false)
			await settle()
			verify(ui.session.snapshot() == clean, "A redesigned room opens a valid fresh route")
			verify(ui.message_label.text == tr("This route no longer matches the room. Begin a new route."), "The reset is explained in the selected language")
			verify(Store.new(path).data.completed.has(old.level_id), "Completed progress survives the redesign")
			var first: String = ui.session.level.recordings[0][0]
			verify(fresh.move(ui.Puzzle.DIRECTIONS[first]), "A short compatible draft remains legal")
			var compatible: Dictionary = fresh.snapshot()
			ui.store.data.session = compatible
			ui.open_level(index, true, false)
			verify(ui.session.snapshot() == compatible and ui.status_text.is_empty(), "Valid drafts resume without a reset notice")
	root.min_size = Vector2i.ONE
	ui.touch_controls = true
	for dimensions in [Vector2i(320,568), Vector2i(844,300)]:
		root.size = dimensions
		ui.store.data.session = old_drafts[0].duplicate(true)
		ui.open_level(ui.room_index("37"), true, false)
		await settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		verify(bounds.encloses(ui.board.get_global_rect()), "The reset explanation leaves room for the board on a phone")
		verify(bounds.encloses(ui.message_label.get_global_rect()), "The translated reset explanation wraps inside the phone")
		await capture("redesign-notice-%dx%d" % [dimensions.x,dimensions.y])
	DirAccess.remove_absolute(path)
	print("ECHO redesign: %d checks; %d failures." % [checks, failures])
	quit(1 if failures else 0)
