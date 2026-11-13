extends "res://tests/test_ui.gd"
## Use real UI geometry for browser touch tests; every room must fit a phone.
var geometry := {}

func point(control: Control) -> Dictionary:
	var center := control.get_global_rect().get_center()
	return {"x": center.x, "y": center.y}

func _run() -> void:
	root.min_size = Vector2i(1, 1)
	ui = preload("res://scenes/main.tscn").instantiate()
	ui.store = Store.new(path)
	ui.store.data.sound = false
	ui.store.data.motion = false
	ui.store.data.room_titles = 0
	root.add_child(ui)
	ui.touch_controls = true
	for dimensions in [Vector2i(390,664), Vector2i(320,568), Vector2i(844,390), Vector2i(844,300), Vector2i(750,279), Vector2i(768,1024)]:
		root.size = dimensions
		for i in 8: await process_frame
		ui.show_home()
		await settle()
		var key_ := "%dx%d" % [dimensions.x,dimensions.y]
		var bounds := Rect2(Vector2.ZERO,Vector2(dimensions))
		geometry[key_] = {"start": point(button_named("Start") if button_named("Start") != null else button_named("Continue")), "settings": point(button_named("Settings")), "github": point(button_named("GitHub")), "chapters": point(button_named("Chapters"))}
		for i in ui.levels.size():
			ui.open_level(i,false,false)
			for frame in 5: await process_frame
			verify(bounds.encloses(ui.board.get_global_rect()), "Board fits phone "+key_+" / "+str(i))
			verify(ui.board.cell_size() >= 12, "Tiles stay legible "+key_+" / "+str(i))
			for button in ui.page.find_children("*", "Button", true, false):
				verify(bounds.encloses(button.get_global_rect()), "Phone button fits "+key_+" / "+button.text)
			if ui.session.level.id in ["21","22"]:
				geometry[key_]["guide"+ui.session.level.id] = point(button_named("Chapter Guide"))
				ui.show_chapter_guide()
				await settle()
				geometry[key_]["guide"+ui.session.level.id+"_close"] = point(button_named("Close Guide"))
				ui._close_modal()
			if i == 0:
				geometry[key_]["guide"] = point(button_named("Chapter Guide"))
				ui.show_chapter_guide()
				await settle()
				geometry[key_]["guide_close"] = point(button_named("Close Guide"))
				geometry[key_]["guide_next"] = point(button_named("Next Step"))
				ui._close_modal()
				geometry[key_]["up"] = point(ui.direction_pad.buttons[Vector2i.UP])
				geometry[key_]["right"] = point(ui.direction_pad.buttons[Vector2i.RIGHT])
				geometry[key_]["down"] = point(ui.direction_pad.buttons[Vector2i.DOWN])
				geometry[key_]["left"] = point(ui.direction_pad.buttons[Vector2i.LEFT])
				geometry[key_]["echo"] = point(ui.seal_button)
				geometry[key_]["undo"] = point(ui.undo_button)
				geometry[key_]["pause"] = point(button_named("Pause"))
				geometry[key_]["back"] = point(button_named("Back"))
				await click(ui.direction_pad.buttons[Vector2i.UP].get_global_rect().get_center())
				verify(ui.session.tick()==1, "Direction press advances once "+key_)
				ui.show_pause()
				await settle()
				geometry[key_]["resume"] = point(button_named("Resume"))
				geometry[key_]["pause_settings"] = point(button_named("Settings"))
				ui.show_settings()
				for frame in 8: await process_frame
				verify(bounds.encloses(ui.modal_panel.get_global_rect()), "Phone settings fit "+key_)
				geometry[key_]["chinese"] = point(button_named("中文"))
				geometry[key_]["settings_back"] = point(button_named("Back"))
				ui._close_modal()
		ui.show_rooms("Inferno")
		await settle()
		geometry[key_]["inferno22"] = point(room_card(ui.room_index("22")))
		ui.show_chapters()
		await settle()
		geometry[key_]["extra"] = point(button_named("Extra"))
		await click_named("Extra")
		for i in ui.levels.size():
			geometry[key_][ui.levels[i].id] = point(room_card(i))
		geometry[key_]["chapters_back"] = point(button_named("← Chapters"))

		for i in ui.levels.size():
			ui.open_level(i, false, false)
			await settle()
			verify(bounds.encloses(ui.board.get_global_rect()) and ui.board.cell_size() >= 12, "Extra board fits " + key_)
			for button in ui.page.find_children("*", "Button", true, false):
				verify(bounds.encloses(button.get_global_rect()), "Extra controls fit " + key_)
		if dimensions == Vector2i(390,664): await capture("extra-switchyard-phone")
		ui.show_home()
		ui.open_level(ui.room_index("17"),false,false)
		await settle()
		await capture("mobile-"+key_)
	ui.touch_controls = false
	root.size = Vector2i(1280,820)
	for i in 8: await process_frame
	ui.show_home()
	await settle()
	geometry["1280x820"] = {"start": point(button_named("Continue"))}
	ui.open_level(0,false,false)
	await settle()
	verify(ui.direction_pad == null, "Desktop has no touch pad")
	geometry["1280x820"]["pause"] = point(button_named("Pause"))
	var file := FileAccess.open("res://builds/web-controls.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(geometry,"\t"))
	file.close()
	DirAccess.remove_absolute(path)
	print("ECHO mobile: %d checks; %d failures." % [checks,failures])
	if DisplayServer.get_name() != "headless" and failures == 0: root.close_requested.emit()
	else: quit(1 if failures else 0)
