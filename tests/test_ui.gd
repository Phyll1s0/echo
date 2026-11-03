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
		if button.text == value and button.is_visible_in_tree():
			await click(button.get_global_rect().get_center())
			return
	verify(false, "Missing button: " + value)

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

func test_room_restart() -> void:
	ui.open_level(ui.levels.size()-1, false)
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
	await click_named("Restart Room")
	verify_fresh_room(initial, completed, "Gameplay button")
	await walk("LL")
	await key(KEY_ENTER)
	await walk("L")
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
	verify(ui.screen=="home", "Home opens")
	verify(TranslationServer.get_locale()=="en", "The game opens in English even with a Chinese system locale")
	await capture("home")
	await click_named("Start")
	verify(ui.screen=="game" and ui.level_index==0, "Start opens the first room")
	if ui.screen!="game":
		quit(1)
		return
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
	await click_named("How to Play")
	verify(ui.modal_kind=="help", "Pause opens rules")
	await click_named("Got It")
	verify(ui.modal_kind=="pause", "Rules return to pause")
	await key(KEY_ESCAPE)
	await walk("RR")
	verify(ui.modal_kind=="complete" and ui.store.data.completed.has("01"), "Completion saved")
	await key(KEY_Z)
	verify(ui.modal==null and ui.session.tick()==3, "Undo after completion")
	await walk("R")
	await click_named("Next Room")
	verify(ui.level_index==1, "Next room opens")
	await click_named("← Rooms")
	verify(not ui.cards.get_child(6).disabled and ui.cards.get_child(7).disabled, "The advanced entry is available before completing the tutorials")
	await click(ui.cards.get_child(6).get_global_rect().get_center())
	verify(ui.level_index==6, "Advanced room opens through room selection")
	for i in range(1,ui.levels.size()):
		ui.open_level(i,false)
		await settle()
		for route in ui.session.level.recordings:
			await walk(route)
			await key(KEY_ENTER)
		var final: String = ui.session.level.final
		await walk(final.substr(0,final.length()-1))
		if i==5:
			await key(KEY_T)
			await capture("room-06")
			var restored = Store.new(path)
			var fresh = preload("res://scripts/puzzle.gd").new(ui.session.level)
			verify(fresh.restore(restored.data.session) and fresh.snapshot()==ui.session.snapshot(), "Play saves an exact in-progress checkpoint")
		if i==8 or i==9:
			await key(KEY_T)
			await capture("room-"+ui.session.level.id)
		await walk(final.right(1))
		verify(ui.modal_kind=="complete", "Room completed through keyboard: "+ui.session.level.id)
	verify(ui.store.data.completed.size()==ui.levels.size(), "All rooms completed")
	await capture("completion")
	ui.show_levels()
	await settle()
	verify(ui.cards.get_child_count()==ui.levels.size() and not ui.cards.get_child(-1).disabled, "All cleared rooms unlocked")
	await capture("rooms")
	root.size = Vector2i(720,600)
	ui.open_level(ui.levels.size()-1,false)
	await settle()
	verify(ui.seal_button.get_global_rect().end.y <= root.size.y and ui.board.size.y>=145, "Board and actions fit small window")
	var window_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	for button in ui.page.find_children("*", "Button", true, false):
		verify(window_rect.encloses(button.get_global_rect()), "English control fits the small window: "+button.text)
	await capture("small")
	await key(KEY_ESCAPE)
	await click_named("How to Play")
	for label in ui.modal.find_children("*", "Label", true, false):
		verify(window_rect.encloses(label.get_global_rect()), "English help fits the small window")
	await capture("help-small")
	await click_named("Got It")
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
	DirAccess.remove_absolute(path)
	print("ECHO UI: %d checks; %d failures." % [checks, failures])
	quit(1 if failures else 0)
