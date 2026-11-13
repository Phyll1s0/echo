extends "res://tests/test_ui.gd"

func _run() -> void:
	root.min_size = Vector2i(1, 1)
	ui = preload("res://scenes/main.tscn").instantiate()
	ui.store = Store.new(path)
	ui.store.data.sound = false
	ui.store.data.motion = false
	root.add_child(ui)
	await settle()
	for locale in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		ui.store.data.language = locale
		for dimensions in [Vector2i(1280,820),Vector2i(390,664),Vector2i(320,568),Vector2i(844,300)]:
			root.size = dimensions
			ui.touch_controls = dimensions.x < 1000
			ui.show_chapters()
			await settle()
			await key(KEY_HOME)
			verify(ui.chapter_picker.selected == 0, "Home focuses the first chapter")
			for i in ui.chapters.size():
				if i > 0: await key(KEY_DOWN)
				var reel = ui.chapter_picker
				verify(reel.selected == i and ui.chapter_focus == i, "Down selects the next chapter")
				verify(reel.get_global_rect().encloses(reel.entries[i].get_global_rect()), "Selected chapter fits " + str(dimensions))
				verify(absf(reel.entries[i].get_global_rect().get_center().y - reel.get_global_rect().get_center().y) < 3, "Chapter snaps to the vertical centre")
				verify(reel.visuals[i].modulate.a > 0.99 and reel.visuals[maxi(0,i-1)].modulate.a <= 1, "The centred title is legible")
			await key(KEY_ENTER)
			verify(ui.screen == "rooms" and ui.ambient.chapter == ui.chapters.back(), "Enter opens the selected chapter")
			await click_named("← Chapters")
			verify(ui.chapter_picker.selected == ui.chapters.size()-1, "Returning restores the same chapter")
			await key(KEY_HOME)
			var wheel := InputEventMouseButton.new()
			wheel.position = ui.chapter_picker.get_global_rect().get_center()
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			Input.parse_input_event(wheel)
			for burst in 8: Input.parse_input_event(wheel.duplicate())
			await settle()
			verify(ui.chapter_picker.selected == 1, "A rapid wheel burst selects exactly one chapter")
			var centre: Vector2 = ui.chapter_picker.get_global_rect().get_center()
			var begin := InputEventScreenTouch.new()
			begin.index = 17
			begin.position = centre + Vector2(0, ui.chapter_picker.stride * 0.45)
			begin.pressed = true
			Input.parse_input_event(begin)
			var drag := InputEventScreenDrag.new()
			drag.index = 17
			drag.position = centre - Vector2(0, ui.chapter_picker.stride * 0.45)
			Input.parse_input_event(drag)
			var end := InputEventScreenTouch.new()
			end.index = 17
			end.position = drag.position
			Input.parse_input_event(end)
			await settle()
			verify(ui.screen == "chapters" and ui.chapter_picker.selected == 2, "A real swipe settles without opening a chapter")
			begin.position = centre
			Input.parse_input_event(begin)
			drag.position = centre - Vector2(0, ui.chapter_picker.stride * 4)
			Input.parse_input_event(drag)
			end.position = drag.position
			Input.parse_input_event(end)
			await settle()
			verify(ui.screen == "chapters" and ui.chapter_picker.selected == 3, "A long swipe advances at most one chapter")
			if dimensions.x in [390,1280]: await capture("chapter-reel-%s-%d" % [locale,dimensions.x])
	ui.store.data.motion = true
	root.size = Vector2i(390,664)
	ui.show_chapters()
	await settle()
	await key(KEY_END)
	await create_timer(.35).timeout
	verify(ui.chapter_picker.selected == ui.chapters.size()-1 and absf(ui.chapter_picker.scroll_vertical - ui.chapter_picker.stride * (ui.chapters.size()-1)) < 3, "Animated scrolling reaches the final chapter")
	root.size = Vector2i(844,390)
	await settle()
	verify(ui.chapter_picker.selected == ui.chapters.size()-1, "Rotation preserves the selected chapter")
	DirAccess.remove_absolute(path)
	print("ECHO chapters: %d checks; %d failures." % [checks, failures])
	quit(1 if failures else 0)
