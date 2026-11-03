extends "res://scripts/ui.gd"

const Puzzle = preload("res://scripts/puzzle.gd")
const Store = preload("res://scripts/save_store.gd")
const Board = preload("res://scripts/board.gd")
const Atmosphere = preload("res://scripts/atmosphere.gd")
const Mark = preload("res://scripts/mark.gd")
const SOUNDS := {
	"step": preload("res://assets/audio/step.wav"),
	"gate": preload("res://assets/audio/gate.wav"),
	"record": preload("res://assets/audio/record.wav"),
	"complete": preload("res://assets/audio/complete.wav")
}
const ROMAN := ["I", "II", "III"]
var chapters: Array[String] = []
var levels: Array
var store
var session
var level_index := 0
var screen := ""
var ambient
var page: Control
var modal: ColorRect
var modal_kind := ""
var modal_panel: PanelContainer
var modal_width := 570.0
var board
var chapter_index: VBoxContainer
var mark
var audio: AudioStreamPlayer
var hint_index := -1
var status_text := ""
var beat_label: Label
var capacity_label: Label
var message_label: Label
var seal_button: Button
var undo_button: Button
var setting_values: Dictionary = {}

func _ready() -> void:
	TranslationServer.set_locale("en")
	setup_skin()
	if store == null:
		store = Store.new()
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json"))
	if not catalog is Array or catalog.is_empty():
		push_error("ECHO: level catalog missing")
		add_child(text_label("Could not load the rooms."))
		return
	levels = catalog
	for info in levels:
		if info.chapter not in chapters:
			chapters.append(info.chapter)
	if store.data.fullscreen:
		_apply_fullscreen(true)
	ambient = Atmosphere.new()
	add_child(ambient)
	ambient.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	audio = AudioStreamPlayer.new()
	add_child(audio)
	resized.connect(_layout)
	show_home()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			var number := arg.trim_prefix("--level=").to_int()
			if number >= 1 and number <= levels.size():
				open_level(number - 1, false)

func _layout() -> void:
	if theme != null:
		theme.default_font_size = roundi(15 * ui_scale())
	if is_instance_valid(page):
		rescale_text(page)
	if is_instance_valid(chapter_index):
		var gap := 32 if screen == "chapters" else 17
		chapter_index.add_theme_constant_override("separation", roundi(gap * ui_scale()))
		chapter_index.custom_minimum_size.x = minf(480 * ui_scale(), size.x - 110 * ui_scale())
	if is_instance_valid(modal_panel):
		modal_panel.custom_minimum_size.x = minf(size.x - 52, modal_width * ui_scale())
		rescale_text(modal)

func _fresh_page(name_: String) -> void:
	_close_modal()
	if is_instance_valid(page):
		remove_child(page)
		page.queue_free()
	board = null
	chapter_index = null
	mark = null
	screen = name_
	page = Control.new()
	add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ambient.animated = bool(store.data.motion) and screen == "home"
	ambient.visible = screen != "game"
	ambient.modulate.a = 0.45 if screen in ["chapters", "rooms"] else 1.0

func _body() -> VBoxContainer:
	var margin := MarginContainer.new()
	page.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, roundi(38 * ui_scale()))
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, roundi(22 * ui_scale()))
	var body := VBoxContainer.new()
	margin.add_child(body)
	return body

func _session_index() -> int:
	var id = store.data.session.get("level_id", "")
	for i in levels.size():
		if levels[i].id == id:
			return i
	return -1

func _next_unfinished() -> int:
	for i in levels.size():
		if not store.data.completed.has(levels[i].id):
			return i
	return 0

func show_home() -> void:
	_fresh_page("home")
	var body := _body()
	var top := HBoxContainer.new()
	body.add_child(top)
	top.add_child(spacer())
	top.add_child(quiet_action("Settings", show_settings))
	body.add_child(spacer(false))
	mark = Mark.new()
	mark.motion = store.data.motion
	mark.custom_minimum_size.y = 94 * ui_scale()
	body.add_child(mark)
	var title := text_label("E C H O", 100, INK, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_font_override("font", thin)
	body.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size.y = 20 * ui_scale()
	body.add_child(gap)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(buttons)
	var resume := _session_index()
	buttons.add_child(action("Continue" if resume >= 0 else "Start", func(): open_level(resume if resume >= 0 else _next_unfinished(), true), 126, true))
	buttons.add_child(action("Chapters", show_chapters, 110))
	body.add_child(spacer(false))
	_layout()

func _chapter_label(chapter: String) -> String:
	var order := chapters.find(chapter)
	var numeral: String = ROMAN[order] if order >= 0 and order < ROMAN.size() else str(order + 1)
	return "Chapter " + numeral

func _chapter_heading(chapter: String, alignment: HorizontalAlignment) -> VBoxContainer:
	var heading := VBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("separation", 0)
	heading.add_child(text_label(_chapter_label(chapter), 17, MUTED, alignment))
	heading.add_child(text_label(chapter, 42, INK, alignment))
	return heading

func _chapter_progress(chapter: String) -> Vector2i:
	var progress := Vector2i.ZERO
	for info in levels:
		if info.chapter == chapter:
			progress.y += 1
			if store.data.completed.has(info.id):
				progress.x += 1
	return progress

func _selection_page(screen_name: String, back_label: String, on_back: Callable) -> VBoxContainer:
	_fresh_page(screen_name)
	var body := _body()
	var header := HBoxContainer.new()
	body.add_child(header)
	header.add_child(quiet_action(back_label, on_back))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	chapter_index = VBoxContainer.new()
	center.add_child(chapter_index)
	return chapter_index

func show_chapters() -> void:
	var index := _selection_page("chapters", "← Home", show_home)
	for chapter in chapters:
		var item := MarginContainer.new()
		index.add_child(item)
		var entry := quiet_action("", show_rooms.bind(chapter))
		entry.accessibility_name = chapter
		entry.accessibility_description = _chapter_label(chapter)
		item.add_child(entry)
		item.add_child(_chapter_heading(chapter, HORIZONTAL_ALIGNMENT_CENTER))
	_layout()

func show_rooms(chapter: String) -> void:
	var index := _selection_page("rooms", "← Chapters", show_chapters)
	var heading := HBoxContainer.new()
	index.add_child(heading)
	heading.add_child(_chapter_heading(chapter, HORIZONTAL_ALIGNMENT_LEFT))
	heading.add_child(spacer())
	var count := _chapter_progress(chapter)
	heading.add_child(text_label("%d / %d" % [count.x, count.y], 18, MUTED))
	for i in levels.size():
		var info: Dictionary = levels[i]
		if info.chapter != chapter:
			continue
		var done: bool = store.data.completed.has(info.id)
		var unlocked: bool = done or i == 0 or info.get("chapter_entry", false) or store.data.completed.has(levels[i-1].id)
		var room := list_action("%s    %s" % [info.id, info.title], open_level.bind(i, true))
		room.set_meta("base_px", 21)
		room.disabled = not unlocked
		var state := "Complete" if done else ("Locked" if not unlocked else "")
		room.accessibility_description = state
		room.tooltip_text = state
		if done:
			_row_value(room, "✓")
		index.add_child(room)
	_layout()

func _row_value(button: Button, value: String) -> Label:
	var caption := text_label(value, 16, ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	button.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.offset_right = -13
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return caption

func open_level(index: int, resume: bool = false) -> void:
	if index < 0 or index >= levels.size():
		return
	level_index = index
	session = Puzzle.new(levels[index])
	if resume and _session_index() == index:
		session.restore(store.data.session)
	_fresh_page("game")
	hint_index = -1
	status_text = ""
	var body := _body()
	var top := HBoxContainer.new()
	body.add_child(top)
	var room_title := VBoxContainer.new()
	room_title.add_theme_constant_override("separation", 0)
	top.add_child(room_title)
	room_title.add_child(text_label("%s   /   %s" % [_chapter_label(session.level.chapter), session.level.chapter], 17, MUTED))
	room_title.add_child(text_label("%s   %s" % [session.level.id, session.level.title], 26))
	top.add_child(spacer())
	top.add_child(quiet_action("Menu", show_pause))
	var hud := HBoxContainer.new()
	body.add_child(hud)
	hud.alignment = BoxContainer.ALIGNMENT_CENTER
	beat_label = text_label("", 25)
	hud.add_child(beat_label)
	capacity_label = text_label("", 18, MUTED)
	hud.add_child(capacity_label)
	board = Board.new()
	board.puzzle = session
	board.font = regular
	board.motion = store.data.motion
	body.add_child(board)
	board.move_requested.connect(try_move)
	board.motion_finished.connect(_animation_done)
	message_label = text_label("", 18, INK, HORIZONTAL_ALIGNMENT_CENTER)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size.y = 38 * ui_scale()
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_child(message_label)
	var actions := HFlowContainer.new()
	actions.alignment = FlowContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("h_separation", 10)
	body.add_child(actions)
	seal_button = action("Leave an Echo", seal_route, 134, true)
	undo_button = action("Undo", undo_move, 90)
	actions.add_child(seal_button)
	actions.add_child(undo_button)
	_save_session()
	_refresh()
	_layout()

func _play(id: String) -> void:
	if store.data.sound and DisplayServer.get_name() != "headless":
		audio.stream = SOUNDS[id]
		audio.play()

func _save_session() -> void:
	if session.cleared():
		store.data.completed[session.level.id] = {"echoes": session.echoes.size(), "beats": session.tick()}
		store.data.session = {}
	else:
		store.data.session = session.snapshot()
	if not store.flush():
		status_text = store.last_error

func _refresh() -> void:
	if screen != "game":
		return
	beat_label.text = "Beat %02d" % session.tick()
	capacity_label.text = "  /  Echoes  %d / %d" % [session.echoes.size(), session.level.max_echoes]
	message_label.text = status_text
	seal_button.disabled = not session.can_seal()
	undo_button.disabled = not session.can_undo()
	board.show_routes = store.data.paths
	board.queue_redraw()
	if session.cleared() and board.phase >= 1.0 and modal == null:
		show_complete()

func try_move(delta: Vector2i) -> void:
	if screen != "game" or modal != null or session.cleared():
		return
	# A deliberate new input can finish the previous tween; never drop a beat
	# solely because the player pressed faster than the cosmetic interpolation.
	if board.phase < 1.0:
		board.cancel_animation()
	var before: Array = session.actors()
	var mechanisms: int = session.mechanism_state()
	var gate_states: Array = []
	for gate in session.gates:
		gate_states.append(session.gate_open(gate))
	if not session.move(delta):
		status_text = session.blocked_reason(delta)
		_refresh()
		return
	status_text = ""
	var sound := "step" if mechanisms == session.mechanism_state() else "gate"
	for i in session.gates.size():
		if not gate_states[i] and session.gate_open(session.gates[i]):
			sound = "gate"
	_play(sound)
	board.animate_from(before, gate_states, mechanisms)
	_save_session()
	_refresh()

func _animation_done() -> void:
	if screen == "game":
		_refresh()

func seal_route() -> void:
	if screen != "game" or modal != null:
		return
	if not session.seal():
		status_text = "Take a step first." if session.tick() == 0 else "All echo slots are full. You can edit your last echo."
		_refresh()
		return
	board.cancel_animation()
	status_text = ""
	_play("record")
	_save_session()
	_refresh()

func undo_move() -> void:
	if session.undo():
		board.cancel_animation()
		status_text = ""
		_save_session()
		_refresh()

func restart_room() -> void:
	open_level(level_index, false)

func edit_last() -> void:
	if not session.edit_origin.is_empty():
		if session.cancel_edit():
			board.cancel_animation()
			status_text = ""
			_save_session()
			_refresh()
		return
	if session.rerecord_last():
		board.cancel_animation()
		status_text = "Press Z to return to the step you want to change."
		_save_session()
		_refresh()

func toggle_routes() -> void:
	_toggle_setting("paths")

func next_hint() -> void:
	var tips: Array = [session.level.intro] + session.level.hints
	hint_index = (hint_index + 1) % tips.size()
	status_text = tips[hint_index]
	_refresh()

func _close_modal() -> void:
	if is_instance_valid(modal):
		remove_child(modal)
		modal.queue_free()
	modal = null
	modal_kind = ""
	modal_panel = null
	setting_values.clear()
	if is_instance_valid(page):
		page.process_mode = Node.PROCESS_MODE_INHERIT

func _panel(kind: String, title: String, width: float = 570) -> VBoxContainer:
	_close_modal()
	modal_kind = kind
	page.process_mode = Node.PROCESS_MODE_DISABLED
	modal = ColorRect.new()
	modal.color = Color(0, 0, 0, 0.85)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Underlying controls cannot consume keyboard focus while a dialog is visible.
	if get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_release_focus()
	var center := CenterContainer.new()
	modal.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	modal_panel = panel
	modal_width = width
	panel.custom_minimum_size.x = minf(size.x - 52, width * ui_scale())
	panel.add_theme_stylebox_override("panel", box(Color("101214"), Color("41474c"), 28))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 17)
	panel.add_child(content)
	content.add_child(Control.new())
	content.add_child(text_label(title, 31))
	return content

func _dialog(kind: String, title: String, description: String, choices: Array) -> void:
	var content := _panel(kind, title)
	if not description.is_empty():
		var desc := text_label(description, 18, MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(desc)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 9)
	buttons.add_theme_constant_override("v_separation", 8)
	content.add_child(buttons)
	for i in choices.size():
		var choice: Array = choices[i]
		buttons.add_child(action(choice[0], choice[1], 0, i == 0))
	content.add_child(Control.new())
	_focus_dialog(buttons.get_child(0))

func _focus_dialog(first: Button) -> void:
	var buttons := modal.find_children("*", "Button", true, false)
	for i in buttons.size():
		var button: Button = buttons[i]
		button.focus_next = button.get_path_to(buttons[(i+1) % buttons.size()])
		button.focus_previous = button.get_path_to(buttons[posmod(i-1, buttons.size())])
		button.focus_neighbor_right = button.focus_next
		button.focus_neighbor_left = button.focus_previous
		button.focus_neighbor_bottom = button.focus_next
		button.focus_neighbor_top = button.focus_previous
	first.grab_focus()

func _apply_fullscreen(enabled: bool) -> void:
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_FULLSCREEN if enabled else Window.MODE_WINDOWED

func _window_fullscreen() -> bool:
	if DisplayServer.get_name() == "headless":
		return store.data.fullscreen
	return get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]

func _toggle_setting(id: String) -> void:
	store.data[id] = not _window_fullscreen() if id == "fullscreen" else not store.data[id]
	match id:
		"sound":
			if store.data.sound: _play("record")
			else: audio.stop()
		"motion":
			ambient.animated = store.data.motion and screen == "home"
			if is_instance_valid(mark): mark.motion = store.data.motion
			if is_instance_valid(board): board.motion = store.data.motion
		"fullscreen":
			_apply_fullscreen(store.data.fullscreen)
	if not store.flush():
		status_text = store.last_error
	if setting_values.has(id):
		var label: Label = setting_values[id]
		label.text = "On" if store.data[id] else "Off"
		label.get_parent().accessibility_description = label.text
	if screen == "game": _refresh()

func show_settings() -> void:
	# The native window controls can also change fullscreen outside the game.
	var fullscreen := _window_fullscreen()
	if store.data.fullscreen != fullscreen:
		store.data.fullscreen = fullscreen
		store.flush()
	var content := _panel("settings", "Settings", 440)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	content.add_child(rows)
	var prefs := {"sound": "Sound", "motion": "Motion", "paths": "Echo Paths", "fullscreen": "Fullscreen"}
	for id in prefs:
		var button := list_action(prefs[id], _toggle_setting.bind(id))
		rows.add_child(button)
		var value := "On" if store.data[id] else "Off"
		button.accessibility_description = value
		setting_values[id] = _row_value(button, value)
	var foot := HBoxContainer.new()
	content.add_child(foot)
	foot.add_child(action("Back", _leave_settings))
	foot.add_child(spacer())
	foot.add_child(quiet_action("How to Play", show_help))
	content.add_child(Control.new())
	_focus_dialog(rows.get_child(0))

func _leave_settings() -> void:
	if screen == "game": show_pause()
	else: _close_modal()

func show_help() -> void:
	var back: Callable = show_settings
	if screen == "game" and (not session.turnstiles.is_empty() or not session.switches.is_empty()):
		var rules := PackedStringArray(["Move one tile per beat. Press Enter to leave an echo. Z undoes a beat. R restarts the room and clears all echoes."])
		if not session.turnstiles.is_empty():
			rules.append("Cross an arrow in its marked direction. It reverses after the crossing.")
		if not session.switches.is_empty():
			rules.append("Step onto a diamond to swap the raised and folded bridges. If the bridge beneath you folds, you can step off it.")
		rules.append("Echoes follow their recorded routes and still trigger devices. If two actors trigger the same device on one beat, it changes once.")
		_dialog("help", "How to Play", "\n\n".join(rules), [["Got It", back]])
		return
	_dialog("help", "How to Play", "Move one tile with the arrow keys, WASD, or a click on an adjacent tile. Each move advances one beat.\n\nPress Enter to leave an echo and return to the start. It retraces your steps, then fades on the beat after its last move.\n\nA plate opens its matching gate. Cross while the gate is open. Guide the solid dot into the outlined square to finish.\n\nZ undoes a step. R restarts the room and clears all echoes.", [["Got It", back]])

func show_pause() -> void:
	if screen != "game":
		return
	board.cancel_animation()
	if session.cleared():
		_refresh()
		return
	var content := _panel("pause", "Room Menu", 410)
	var resume := action("Resume", _resume_game, 0, true)
	content.add_child(resume)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	content.add_child(rows)
	rows.add_child(list_action("Hint", func(): _close_modal(); next_hint()))
	if not session.echoes.is_empty() or not session.edit_origin.is_empty():
		var edit := "Cancel Edit" if not session.edit_origin.is_empty() else "Edit Last Echo"
		rows.add_child(list_action(edit, func(): _close_modal(); edit_last()))
	rows.add_child(list_action("Restart Room", restart_room))
	rows.add_child(list_action("Choose Room", show_rooms.bind(session.level.chapter)))
	rows.add_child(list_action("Settings", show_settings))
	content.add_child(Control.new())
	_focus_dialog(resume)

func _resume_game() -> void:
	_close_modal()
	_refresh()

func show_complete() -> void:
	_play("complete")
	var has_next := level_index + 1 < levels.size()
	var at_boundary: bool = not has_next or levels[level_index+1].chapter != session.level.chapter
	var progress := _chapter_progress(session.level.chapter)
	var title := "Room Complete"
	if at_boundary and progress.x == progress.y:
		title = "%s Complete" % session.level.chapter
	var next := "Next Room" if not at_boundary else ("Next Chapter" if has_next else "Chapters")
	_dialog("complete", title, "Beats  %d    ·    Echoes  %d" % [session.tick(), session.echoes.size()], [[next, func():
		if has_next: open_level(level_index + 1, true)
		else: show_chapters()], ["Undo", func(): _close_modal(); undo_move()]])

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var code: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code == KEY_F11:
		_toggle_setting("fullscreen")
	elif modal != null:
		if code == KEY_ESCAPE:
			if modal_kind == "complete": show_rooms(session.level.chapter)
			elif modal_kind == "help": show_settings()
			elif modal_kind == "settings": _leave_settings()
			elif modal_kind == "pause": _resume_game()
			else: _close_modal()
		elif code == KEY_Z and modal_kind == "complete":
			_close_modal()
			undo_move()
		elif code == KEY_R and modal_kind in ["pause", "complete"]:
			restart_room()
		else:
			return
	elif screen == "game":
		match code:
			KEY_UP, KEY_W: try_move(Vector2i.UP)
			KEY_DOWN, KEY_S: try_move(Vector2i.DOWN)
			KEY_LEFT, KEY_A: try_move(Vector2i.LEFT)
			KEY_RIGHT, KEY_D: try_move(Vector2i.RIGHT)
			KEY_ENTER, KEY_KP_ENTER: seal_route()
			KEY_Z, KEY_BACKSPACE: undo_move()
			KEY_R: restart_room()
			KEY_T: toggle_routes()
			KEY_H: next_hint()
			KEY_ESCAPE: show_pause()
			_: return
	elif screen == "rooms" and code == KEY_ESCAPE:
		show_chapters()
	elif screen == "chapters" and code == KEY_ESCAPE:
		show_home()
	else:
		return
	get_viewport().set_input_as_handled()
