extends SceneTree

const Store = preload("res://scripts/save_store.gd")
const KEYS := {"U": KEY_UP, "D": KEY_DOWN, "L": KEY_LEFT, "R": KEY_RIGHT}
var ui
var failures := 0
var checks := 0
var path := "user://ui-test-%d.json" % OS.get_process_id()

func _initialize() -> void:
	call_deferred("_run")

func verify(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func settle() -> void:
	await process_frame
	await process_frame

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
	await settle()

func click(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = down
		Input.parse_input_event(event)
	await settle()

func click_named(value: String) -> void:
	var scope: Control = ui.modal if ui.modal != null else ui.page
	for button in scope.find_children("*", "Button", true, false):
		if (button.text == value or button.accessibility_name == value) and button.is_visible_in_tree():
			await click(button.get_global_rect().get_center())
			return
	verify(false, "Missing button: " + value)

func room_card(i: int) -> Button:
	for item in ui.chapter_index.find_children("*", "Button", true, false):
		if item.text.begins_with(ui.levels[i].id + " "):
			return item
	return null

func test_home_settings() -> void:
	verify(ui.page.find_children("*", "Button", true, false).size()==3, "Home shows three actions")
	await click_named("Settings")
	verify(ui.modal_kind=="settings", "Settings open from the home screen")
	await click_named("Motion")
	verify(ui.ambient.animated and ui.mark.motion and Store.new(path).data.motion, "Motion changes live and persists")
	await click_named("Sound")
	verify(Store.new(path).data.sound and ui.setting_values.sound.text=="On", "Sound is saved and the row reflects its state")
	await capture("settings")
	await click_named("Sound")
	await click_named("Motion")
	await click_named("How to Play")
	await key(KEY_ESCAPE)
	verify(ui.modal_kind=="settings", "Rules return to settings")
	await click_named("Back")
	verify(ui.modal==null and ui.screen=="home", "Settings return to home")

func walk(letters: String) -> void:
	for letter in letters:
		var t: int = ui.session.tick()
		await key(KEYS[letter])
		verify(ui.session.tick() == t+1, "Input advances exactly one beat: "+letter)

func capture(id: String) -> void:
	if DisplayServer.get_name() == "headless" or "--capture" not in OS.get_cmdline_user_args():
		return
	await settle()
	RenderingServer.force_draw()
	var image := root.get_texture().get_image()
	verify(not image.is_empty() and image.save_png("res://builds/"+id+".png")==OK, "Capture "+id)

func verify_fresh_room(expected: Dictionary, completed: Dictionary, entry: String) -> void:
	verify(ui.modal == null and ui.session.snapshot() == expected, entry + " clears all tapes, the draft and any edit backup")
	verify(ui.session.mechanism_state() == 0 and not ui.session.can_undo(), entry + " restores devices and undo history")
	var disk = Store.new(path)
	var reloaded = preload("res://scripts/puzzle.gd").new(ui.session.level)
	verify(reloaded.restore(disk.data.session) and reloaded.snapshot() == expected, entry + " resumes at the start of the room")
	verify(disk.data.completed == completed, entry + " keeps campaign progress")

func test_previous_save() -> void:
	var file := FileAccess.open(path+".legacy", FileAccess.WRITE)
	file.store_string('{"version":1,"completed":{"01":{"beats":4,"echoes":1}},"sound":false,"motion":false,"session":{"version":1,"level_id":"07","echoes":[[[0,2],[0,1],[0,0]]],"draft":[[0,2],[1,2]]}}')
	file.close()
	var old = Store.new(path+".legacy")
	var puzzle = preload("res://scripts/puzzle.gd").new(ui.levels[6])
	verify(puzzle.restore(old.data.session) and puzzle.echoes.size()==1 and puzzle.tick()==1, "The renamed room resumes an earlier version's tape and draft")
	verify(old.data.completed.has("01") and not old.data.sound and not old.data.motion and not old.data.paths and not old.data.fullscreen, "Earlier progress and preferences survive the settings upgrade")
	DirAccess.remove_absolute(path+".legacy")

func test_room_restart() -> void:
	ui.open_level(9, false)
	await settle()
	var initial: Dictionary = ui.session.snapshot()
	var completed: Dictionary = Store.new(path).data.completed
	for route in ui.session.level.recordings:
		await walk(route)
		await key(KEY_ENTER)
	await walk("LLLUUR")
	verify(ui.session.echoes.size()==2 and ui.session.mechanism_state()!=0, "Two tapes and changed devices before restart")
	await key(KEY_R)
	verify_fresh_room(initial, completed, "R")
	if not ui.session.echoes.is_empty():
		return
	await walk("LL")
	await key(KEY_ENTER)
	await walk("L")
	await click_named("Menu")
	await click_named("Restart Room")
	verify_fresh_room(initial, completed, "Room menu")
	await walk("LL")
	await key(KEY_ENTER)
	await walk("L")
	await click_named("Menu")
	await click_named("Edit Last Echo")
	verify(not ui.session.edit_origin.is_empty(), "Pending edit before restart from pause")
	await key(KEY_ESCAPE)
	await click_named("Restart Room")
	verify_fresh_room(initial, completed, "Pause button")

func _run() -> void:
	root.size = Vector2i(1280,820)
	TranslationServer.set_locale("zh_CN")
	ui = load("res://scenes/main.tscn").instantiate()
	ui.store = Store.new(path)
	ui.store.data.motion = false
	ui.store.data.sound = false
	root.add_child(ui)
	await settle()
	test_previous_save()
	verify(ui.screen=="home", "Home opens")
	verify(TranslationServer.get_locale()=="en", "The game opens in English even with a Chinese system locale")
	await capture("home")
	await test_home_settings()
	await click_named("Chapters")
	verify(ui.screen=="chapters" and ui.chapter_index.get_child_count()==4 and room_card(0)==null, "The index only offers chapter names")
	await capture("chapters")
	await click_named("Penumbra")
	verify(not room_card(10).disabled and room_card(11).disabled, "Penumbra starts at First Contact without requiring earlier chapters")
	await click_named("← Chapters")
	await click_named("Resonance")
	verify(ui.screen=="rooms" and room_card(4).disabled and room_card(5).disabled and room_card(6)==null, "An unopened chapter can be browsed and its rooms stay locked")
	await key(KEY_ESCAPE)
	verify(ui.screen=="chapters", "Escape from rooms returns to the chapter names")
	await key(KEY_ESCAPE)
	verify(ui.screen=="home", "Escape from the chapter index returns home")
	await click_named("Start")
	verify(ui.screen=="game" and ui.level_index==0, "Start opens the first room")
	if ui.screen!="game":
		quit(1)
		return
	verify(ui.page.find_children("*", "Button", true, false).size()==3, "The board only shows Menu, Leave an Echo and Undo")
	await click_named("Menu")
	await click_named("Hint")
	verify(ui.message_label.text==ui.session.level.intro, "Hint displays the English room introduction on demand")
	await key(KEY_UP)
	verify(ui.message_label.text.is_empty(), "The hint clears after a move")
	await click(ui.board.global_position + ui.board.center_of(ui.session.plates.A))
	verify(ui.session.tick()==2 and ui.session.player()==ui.session.plates.A, "Pointer moves to adjacent plate")
	await key(KEY_ENTER)
	verify(ui.session.echoes.size()==1 and ui.session.tick()==0, "Enter records the path")
	await walk("RR")
	verify(ui.session.gate_open(ui.session.gates[0]), "Door open for one beat")
	await capture("room-01")
	await key(KEY_ESCAPE)
	var snapshot: Dictionary = ui.session.snapshot()
	await key(KEY_LEFT)
	verify(ui.modal_kind=="pause" and ui.session.snapshot()==snapshot, "Pause isolates puzzle input")
	await click_named("Settings")
	await key(KEY_DOWN)
	await click_named("Echo Paths")
	verify(ui.board.show_routes and Store.new(path).data.paths, "Changing paths in settings updates the board and persists")
	await click_named("Motion")
	verify(ui.board.motion, "Board motion changes before returning to play")
	await click_named("Motion")
	await click_named("How to Play")
	verify(ui.modal_kind=="help", "In-game settings open rules")
	await click_named("Got It")
	verify(ui.modal_kind=="settings", "Rules return to game settings")
	await key(KEY_ESCAPE)
	verify(ui.modal_kind=="pause" and ui.session.snapshot()==snapshot, "Settings return to the same room and beat")
	var restored_puzzle = preload("res://scripts/puzzle.gd").new(ui.session.level)
	verify(restored_puzzle.restore(Store.new(path).data.session) and restored_puzzle.snapshot()==snapshot, "The checkpoint still restores after settings changes")
	await key(KEY_ESCAPE)
	await key(KEY_T)
	verify(not ui.board.show_routes and not Store.new(path).data.paths, "Path shortcut shares the setting")
	await walk("RR")
	verify(ui.modal_kind=="complete" and ui.store.data.completed.has("01"), "Completion saved")
	await key(KEY_Z)
	verify(ui.modal==null and ui.session.tick()==3, "Undo after completion")
	await walk("R")
	await click_named("Next Room")
	verify(ui.level_index==1, "Next room opens")
	await click_named("Menu")
	await click_named("Choose Room")
	verify(ui.screen=="rooms" and room_card(6)==null, "The game menu returns to the current chapter")
	verify(room_card(0).accessibility_description=="Complete" and not room_card(1).disabled and room_card(2).disabled, "Earlier progress still unlocks the following room")
	await capture("chapter-afterimage")
	await click_named("← Chapters")
	await click_named("Phase Shift")
	verify(room_card(0)==null and not room_card(6).disabled and room_card(7).disabled, "Only the advanced chapter's rooms appear, with its entry unlocked")
	await click(room_card(6).get_global_rect().get_center())
	verify(ui.level_index==6, "Advanced room opens through room selection")
	for i in range(1,ui.levels.size()):
		ui.open_level(i,false)
		await settle()
		for route in ui.session.level.recordings:
			await walk(route)
			await key(KEY_ENTER)
		var final: String = ui.session.level.final
		if ui.session.level.id == "14":
			await walk(final.left(7))
			await capture("room-14")
			await walk(final.substr(7, final.length()-8))
		else:
			await walk(final.substr(0,final.length()-1))
		if i==5:
			await key(KEY_T)
			await capture("room-06")
			var restored = Store.new(path)
			var fresh = preload("res://scripts/puzzle.gd").new(ui.session.level)
			verify(fresh.restore(restored.data.session) and fresh.snapshot()==ui.session.snapshot(), "Play saves an exact in-progress checkpoint")
		if i in [8,9]:
			if not ui.board.show_routes: await key(KEY_T)
			await capture("room-"+ui.session.level.id)
		await walk(final.right(1))
		verify(ui.modal_kind=="complete", "Room completed through keyboard: "+ui.session.level.id)
		if i in [3,5,9]:
			await click_named("Next Chapter")
			verify(ui.level_index==i+1 and ui.modal==null, "Chapter completion opens the next chapter")
	verify(ui.store.data.completed.size()==ui.levels.size(), "All rooms completed")
	await capture("completion")
	await click_named("Chapters")
	verify(ui.screen=="chapters", "Finishing the campaign opens the chapter index")
	for chapter in ui.chapters:
		await click_named(chapter)
		for i in ui.levels.size():
			if ui.levels[i].chapter == chapter:
				verify(not room_card(i).disabled and room_card(i).accessibility_description=="Complete", "Cleared room remains selectable: "+ui.levels[i].id)
			else:
				verify(room_card(i)==null, "Other chapters stay on their own pages")
		await click_named("← Chapters")
	root.size = Vector2i(720,600)
	await settle()
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	for button in ui.chapter_index.get_children():
		verify(viewport_rect.encloses(button.get_global_rect()), "Chapter selection fits the small window")
	await capture("chapters-small")
	await click_named("Phase Shift")
	verify(viewport_rect.encloses(room_card(6).get_global_rect()) and viewport_rect.encloses(room_card(9).get_global_rect()), "All four rooms fit the small window")
	await capture("rooms-small")
	ui.open_level(13,false)
	await settle()
	await click_named("Menu")
	await click_named("Settings")
	await click_named("How to Play")
	for label in ui.modal.find_children("*", "Label", true, false):
		verify(viewport_rect.encloses(label.get_global_rect()), "Lens and bridge rules fit the small window")
	ui.open_level(9,false)
	await settle()
	verify(ui.seal_button.get_global_rect().end.y <= root.size.y and ui.board.size.y>=145, "Board and actions fit small window")
	var window_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	for button in ui.page.find_children("*", "Button", true, false):
		verify(window_rect.encloses(button.get_global_rect()), "English control fits the small window: "+button.text)
	await capture("small")
	await key(KEY_ESCAPE)
	await click_named("Settings")
	for button in ui.modal.find_children("*", "Button", true, false):
		verify(window_rect.encloses(button.get_global_rect()), "Settings stay within the small window: "+button.text)
	await click_named("How to Play")
	for label in ui.modal.find_children("*", "Label", true, false):
		verify(window_rect.encloses(label.get_global_rect()), "English help fits the small window")
	await capture("help-small")
	await click_named("Got It")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	# A move may be undone while its visual interpolation is in flight.
	ui.board.motion = true
	ui.try_move(Vector2i.LEFT)
	ui.try_move(Vector2i.LEFT)
	verify(ui.session.tick()==2, "Rapid distinct inputs are not lost during interpolation")
	ui.undo_move()
	ui.undo_move()
	await create_timer(0.16).timeout
	verify(ui.session.tick()==0 and ui.board.phase==1.0, "No stale movement after undo")
	await test_room_restart()
	await key(KEY_ESCAPE)
	await click_named("Settings")
	await click_named("Fullscreen")
	verify(Store.new(path).data.fullscreen and ui.setting_values.fullscreen.text=="On", "Fullscreen setting persists")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.8).timeout
		verify(root.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN], "Fullscreen switches the native window")
	await key(KEY_F11)
	verify(not Store.new(path).data.fullscreen and ui.setting_values.fullscreen.text=="Off", "F11 updates the same setting")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.8).timeout
		verify(root.mode==Window.MODE_WINDOWED, "F11 returns the native window to windowed mode")
	DirAccess.remove_absolute(path)
	print("ECHO UI: %d checks; %d failures." % [checks, failures])
	quit(1 if failures else 0)
