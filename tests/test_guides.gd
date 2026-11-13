extends "res://tests/test_ui.gd"

func click_named(value: String) -> void:
	var button := button_named(value)
	if button != null and ui.modal_scroll != null:
		ui.modal_scroll.ensure_control_visible(button)
		await settle()
	await super.click_named(value)

func _run() -> void:
	root.min_size = Vector2i(1, 1)
	ui = preload("res://scenes/main.tscn").instantiate()
	ui.store = Store.new(path)
	ui.store.data.sound = false
	ui.store.data.motion = false
	ui.store.data.room_titles = 0
	root.add_child(ui)
	await settle()
	var entry_rooms := [0, 4, 6, 10, 14, 17, 20, 21, 25, 26, 28]
	for i in ui.levels.size():
		ui.open_level(i, false, false)
		await settle()
		verify((button_named("Chapter Guide") != null) == (i in entry_rooms), "Only chapter openings have a guide: " + str(i))
	for locale in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		ui.store.data.language = locale
		for dimensions in [Vector2i(1280,820), Vector2i(390,664), Vector2i(320,568), Vector2i(844,300)]:
			root.size = dimensions
			ui.touch_controls = dimensions.x != 1280
			await settle()
			for i in entry_rooms:
				ui.open_level(i, false, false)
				await settle()
				var snapshot: Dictionary = ui.session.snapshot()
				var saved: Dictionary = ui.store.data.duplicate(true)
				await click_named("Chapter Guide")
				verify(ui.modal_kind == "guide", "Question mark opens chapter guide")
				var count: int = ui.ChapterGuide.PAGES[ui.session.level.chapter].size()
				for tab in count:
					if tab > 0:
						await click_named(ui.ChapterGuide.PAGES[ui.session.level.chapter][tab].title)
					await settle()
					var demo = ui.guide_demo
					verify(not demo.playing, "Motion off starts a manual demo")
					var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
					verify(bounds.encloses(ui.modal_panel.get_global_rect()), "Guide fits viewport " + str(dimensions))
					verify(bounds.encloses(button_named("Close Guide").get_global_rect()), "Close remains reachable")
					verify(demo.board.cell_size() >= 30, "Demo tiles stay readable")
					for node in ui.modal.find_children("*", "Label", true, false):
						verify(node.get_global_rect().end.x <= dimensions.x, "Guide text wraps horizontally")
					for cycle in 2:
						for step in range(1, demo.info.steps.size()):
							demo.advance()
							if locale == "zh_CN": verify(demo.caption.text != demo.info.steps[step][1], "Demo captions are translated")
						verify(demo.puzzle.cleared(), "Every demo reaches its illustrated goal")
						demo.advance()
						verify(demo.step_index == 0 and demo.puzzle.tick() == 0, "Loop restores demo start")
					verify(ui.session.snapshot() == snapshot and ui.store.data == saved, "Demo does not alter the room or progress")
					await key(KEY_R)
					await key(KEY_UP)
					await key(KEY_Z)
					verify(ui.modal_kind == "guide" and ui.session.snapshot() == snapshot, "Guide blocks gameplay keyboard input")
					if dimensions.y >= 568:
						await click_named("Next Step")
						verify(demo.step_index == 1 and not demo.playing, "Next Step advances once and pauses")
						await click_named("Play Demo")
						verify(demo.playing, "Playback can be started manually")
						demo._process(2.1)
						verify(demo.step_index == 2, "Playback advances its isolated puzzle")
						demo.playing = false
					if dimensions == Vector2i(390,664) or dimensions == Vector2i(1280,820):
						await capture("guide-%s-%s-%d-%d" % [locale, str(dimensions.x), i, tab])
				await key(KEY_ESCAPE)
				verify(ui.modal == null and ui.session.snapshot() == snapshot, "Esc closes guide without altering the round")
				verify(get_root().gui_get_focus_owner().accessibility_name == tr("Chapter Guide"), "Focus returns to question mark")
	# Reflow a live demo while the real room has an echo and an undo history.
	TranslationServer.set_locale("en")
	ui.store.data.language = "en"
	ui.store.data.motion = true
	root.size = Vector2i(390,664)
	ui.open_level(0, false, false)
	await settle()
	await walk("UU")
	ui.seal_route()
	ui.try_move(Vector2i.RIGHT)
	var live = ui.session
	var snapshot: Dictionary = live.snapshot()
	await click_named("Chapter Guide")
	verify(ui.guide_demo.playing, "Motion on loops automatically")
	ui.guide_demo.next_step()
	ui.guide_demo.next_step()
	root.size = Vector2i(844,390)
	await settle()
	verify(ui.modal_kind == "guide" and ui.guide_demo.step_index == 2 and not ui.guide_demo.playing, "Rotation preserves demo step and playback state")
	await click_named("Close Guide")
	verify(ui.session == live and ui.session.snapshot() == snapshot, "Closing after rotation preserves the live room")
	ui.undo_move()
	verify(ui.session.tick() == 0 and ui.session.echoes.size() == 1, "Undo still works after guide")
	var old_room: Dictionary = ui.campaign_levels[17].duplicate(true)
	old_room.id = "X01"
	old_room.chapter = "Extra"
	var old_puzzle = ui.Puzzle.new(old_room)
	old_puzzle.move(Vector2i.UP)
	old_puzzle.move(Vector2i.UP)
	old_puzzle.seal()
	old_puzzle.move(Vector2i.UP)
	old_puzzle.rerecord_last()
	ui.store.data.extra_sessions.X01 = old_puzzle.snapshot()
	ui.store.data.extra_completed.X02 = {"echoes": 2, "beats": 9}
	var campaign: Dictionary = ui.store.data.session.duplicate(true)
	ui.store.flush()
	ui.store = Store.new(path)
	verify(ui.store.data.completed.has("19") and not ui.store.data.extra_completed.has("X02"), "Old Extra completion migrates to Wonderland")
	verify(ui.store.data.session == JSON.parse_string(JSON.stringify(campaign)) and ui.store.data.extra_sessions.has("X01"), "Migration preserves the current campaign and unopened draft")
	ui.show_rooms("Wonderland")
	ui.open_level(17, true, false)
	verify(ui.session.level.id == "18" and ui.session.tick() == 2 and ui.session.player() == old_puzzle.player(), "Wonderland resumes the old Extra draft")
	verify(not ui.store.data.extra_sessions.has("X01") and ui.store.data.session.level_id == "18", "Opening the migrated room stores its new identity")
	verify(ui.session.cancel_edit() and ui.session.echoes.size() == 1 and ui.session.tick() == 1, "A migrated edit can still restore the previous plan")
	DirAccess.remove_absolute(path)
	print("ECHO guides: %d checks; %d failures." % [checks, failures])
	quit(1 if failures else 0)
