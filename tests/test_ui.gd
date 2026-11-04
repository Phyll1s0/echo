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
	await click_named("Sound")
	verify(Store.new(path).data.sound and ui.setting_values.sound.text=="On", "Sound is saved and the row reflects its state")
	var volume: HSlider = ui.modal.find_children("*", "HSlider", true, false)[0]
	var bounds := volume.get_global_rect()
	await click(bounds.position + bounds.size * Vector2(0.67,0.5))
	var saved_volume: int = Store.new(path).data.volume
	verify(saved_volume > 50 and saved_volume < 80 and is_equal_approx(ui.audio.volume_db, linear_to_db(saved_volume / 100.0)), "Volume slider persists and applies the selected gain")
	var music_volume: HSlider = ui.modal.find_children("*", "HSlider", true, false)[1]
	bounds = music_volume.get_global_rect()
	await click(bounds.position + bounds.size * Vector2(0.43, 0.5))
	var saved_music: int = Store.new(path).data.music_volume
	verify(saved_music > 33 and saved_music < 53 and Store.new(path).data.volume==saved_volume, "Music and effects levels persist independently")
	verify(ui.music.stream.loop and absf(ui.music.stream.get_length()-96.0) < 0.02, "The score is a complete looping 96-second recording")
	if DisplayServer.get_name() != "headless":
		await create_timer(.20).timeout
		verify(ui.music.playing and is_equal_approx(ui.music.volume_db, linear_to_db(saved_music / 100.0)), "Music slider applies the selected gain")
		ui.music.seek(95.85)
		await create_timer(.50).timeout
		verify(ui.music.playing and ui.music.get_playback_position() < 2.0, "The music crosses its loop point without stopping")
		ui.music.seek(21.0)
		await click(Vector2(bounds.position.x, bounds.get_center().y))
		await create_timer(.20).timeout
		verify(not ui.music.playing and Store.new(path).data.music_volume==0, "Zero music volume pauses the score independently")
		await click(bounds.position + bounds.size * Vector2(.43,.5))
		await create_timer(.20).timeout
		verify(ui.music.playing and not ui.music.stream_paused and ui.music.get_playback_position() >= 21, "Raising music resumes the same phrase")
	await click_named("Footsteps")
	verify(not Store.new(path).data.step_sounds and ui.footfalls.stream.streams_count==3, "All three step sounds use the independent footsteps control")
	if DisplayServer.get_name() != "headless":
		verify(ui.music.playing and not ui.music.stream_paused, "Disabling footsteps leaves the music running")
	await capture("settings")
	await click_named("Sound")
	if DisplayServer.get_name() != "headless":
		await create_timer(.45).timeout
		verify(not ui.music.playing, "Master mute also silences music")
	await click_named("Display")
	await click_named("Motion")
	verify(ui.ambient.animated and ui.mark.motion and Store.new(path).data.motion, "Motion changes live and persists")
	await click_named("Move Animation")
	verify(Store.new(path).data.move_speed==2, "Animation speed persists")
	await click_named("Puzzle")
	await click_named("Room Titles")
	verify(Store.new(path).data.room_titles==3, "Title duration persists")
	await click_named("Room Titles")
	verify(Store.new(path).data.room_titles==0, "Titles can be turned off")
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
	verify(old.data.room_titles==2 and old.data.volume==100 and old.data.music_volume==36 and old.data.move_speed==1, "Older saves receive the standard title, volume and motion speed")
	file = FileAccess.open(path+".legacy", FileAccess.WRITE)
	file.store_string('{"version":1,"volume":0}')
	file.close()
	verify(Store.new(path+".legacy").data.music_volume==0, "An older zero-volume preference also keeps new music silent")
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
	await click_named("Pause")
	await click_named("Restart Room")
	verify_fresh_room(initial, completed, "Room menu")
	await walk("LL")
	await key(KEY_ENTER)
	await walk("L")
	await click_named("Pause")
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
	await capture("home-start")
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
	verify(ui.title_card==null and is_equal_approx(ui.board.move_seconds, 0.08), "New rooms apply title and animation preferences")
	await key(KEY_R)
	await click_named("Back")
	verify(ui.screen=="home", "Back returns to the entry page after restarting a room from Home")
	await click_named("Continue")
	await click_named("Pause")
	await click_named("Settings")
	await click_named("Room Titles")
	await click_named("Room Titles")
	await click_named("Back")
	await click_named("Choose Room")
	await click(room_card(0).get_global_rect().get_center())
	verify(ui.title_card!=null and ui.session.tick()==0, "Selecting the room shows its title at beat zero")
	var shows_name := false
	for label in ui.title_card.find_children("*", "Label", true, false):
		if label.text == ui.session.level.title: shows_name = true
	verify(shows_name, "The title belongs to the selected room")
	ui.title_tween.pause()
	ui.title_tween.custom_step(1.30)
	verify(ui.title_card.modulate.a > 0 and ui.title_card.modulate.a < 1, "The default introduction crossfades before the 1.5 second mark")
	ui.title_tween.play()
	await create_timer(0.55).timeout
	verify(ui.title_card==null and ui.session.tick()==0, "Title dismisses on its own without advancing the puzzle")
	await click_named("Pause")
	await click_named("Settings")
	await click_named("Display")
	await click_named("Motion")
	await click_named("Back")
	await click_named("Resume")
	verify(ui.page.find_children("*", "Button", true, false).size()==4, "The board shows Back, Pause, Leave an Echo and Undo")
	await click_named("Pause")
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
	var snapshot: Dictionary = ui.session.snapshot()
	await click_named("Back")
	verify(ui.screen=="rooms" and room_card(0)!=null and room_card(6)==null, "Back returns to the original chapter's room list")
	await click(room_card(0).get_global_rect().get_center())
	verify(ui.session.snapshot()==snapshot, "Returning through the room list restores the same beat and echo")
	await click_named("Back")
	await click_named("← Chapters")
	await click_named("← Home")
	await capture("home")
	await click_named("Continue")
	verify(ui.screen=="game" and ui.level_index==0 and ui.session.snapshot()==snapshot and ui.session.gate_open(ui.session.gates[0]), "Continue restores the same room, beat, echo and open gate")
	await key(KEY_ESCAPE)
	await key(KEY_LEFT)
	verify(ui.modal_kind=="pause" and ui.session.snapshot()==snapshot, "Pause isolates puzzle input")
	verify(ui.modal_panel.get_rect().position.x > root.size.x/2, "Pause uses a right hand panel")
	await capture("pause")
	await click(Vector2(50, 140))
	verify(ui.modal==null and ui.session.snapshot()==snapshot, "Backdrop resumes without moving")
	await key(KEY_ESCAPE)
	await click_named("Settings")
	await click_named("Puzzle")
	await click_named("Echo Paths")
	verify(ui.board.show_routes and Store.new(path).data.paths, "Changing paths in settings updates the board and persists")
	await click_named("Path Contrast")
	verify(is_equal_approx(ui.board.path_opacity, 0.85) and Store.new(path).data.path_weight==2, "Path visibility updates the board and save")
	await click_named("Path Contrast")
	await click_named("Path Contrast")
	await click_named("Display")
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
	verify(ui.level_index==1 and ui.title_card!=null, "Next room opens with a fresh title")
	await key(KEY_UP)
	verify(ui.title_card==null and ui.session.tick()==1, "The first move dismisses the title and advances exactly once")
	var next_snapshot: Dictionary = ui.session.snapshot()
	await click_named("Back")
	verify(ui.screen=="home", "Next Room retains Home as the entry page")
	await click_named("Continue")
	verify(ui.level_index==1 and ui.session.snapshot()==next_snapshot, "Continue restores progress after returning from the next room")
	await click_named("Pause")
	await click_named("Choose Room")
	verify(ui.screen=="rooms" and room_card(6)==null, "The game menu returns to the current chapter")
	verify(room_card(0).accessibility_description=="Complete" and not room_card(1).disabled and room_card(2).disabled, "Earlier progress still unlocks the following room")
	await capture("chapter-afterimage")
	await click_named("← Chapters")
	await click_named("Phase Shift")
	verify(room_card(0)==null and not room_card(6).disabled and room_card(7).disabled, "Only the advanced chapter's rooms appear, with its entry unlocked")
	await click(room_card(6).get_global_rect().get_center())
	verify(ui.level_index==6, "Advanced room opens through room selection")
	await key(KEY_R)
	await click_named("Back")
	verify(ui.screen=="rooms" and room_card(6)!=null and room_card(0)==null, "Restart retains the selected chapter as the return destination")
	await click(room_card(6).get_global_rect().get_center())
	for i in range(1,ui.levels.size()):
		ui.open_level(i,false)
		await settle()
		if ui.session.level.id == "14": await capture("room-intro")
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
	await click_named("Pause")
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
	await click_named("Display")
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
	if DisplayServer.get_name() != "headless":
		await click_named("Audio")
		await click_named("Sound")
		ui.music.seek(41.0)
		await click_named("Back")
		await click_named("Choose Room")
		await click(room_card(9).get_global_rect().get_center())
		await key(KEY_ESCAPE)
		verify(ui.modal_kind=="pause" and ui.music.playing and ui.music.get_playback_position() >= 41.0, "Opening a room and pausing keep the score on the same phrase")
	DirAccess.remove_absolute(path)
	print("ECHO UI: %d checks; %d failures." % [checks, failures])
	if DisplayServer.get_name() != "headless" and failures == 0:
		root.close_requested.emit()
	else:
		quit(1 if failures else 0)
