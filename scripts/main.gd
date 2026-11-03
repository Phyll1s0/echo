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
var levels: Array
var store
var session
var level_index := 0
var screen := ""
var ambient
var page: Control
var modal: ColorRect
var modal_kind := ""
var board
var cards: GridContainer
var mark
var audio: AudioStreamPlayer
var hint_index := -1
var status_text := ""
var routes_visible := false
var beat_label: Label
var capacity_label: Label
var message_label: Label
var seal_button: Button
var undo_button: Button
var edit_button: Button
var trace_button: Button

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
	if is_instance_valid(cards) and screen == "levels":
		cards.columns = 3 if size.x >= 980 else 2

func _fresh_page(name_: String) -> void:
	_close_modal()
	if is_instance_valid(page):
		remove_child(page)
		page.queue_free()
	board = null
	cards = null
	mark = null
	screen = name_
	page = Control.new()
	add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ambient.animated = bool(store.data.motion) and screen == "home"
	ambient.visible = screen != "game"

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
	var sound := action("Sound · On" if store.data.sound else "Sound · Off", func():
		store.data.sound = not store.data.sound
		store.flush()
		show_home()
		_play("record"))
	top.add_child(sound)
	top.add_child(action("Motion · On" if store.data.motion else "Motion · Off", func():
		store.data.motion = not store.data.motion
		store.flush()
		show_home()))
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
	buttons.add_child(action("Rooms", show_levels, 110))
	body.add_child(spacer(false))
	var foot := HBoxContainer.new()
	body.add_child(foot)
	foot.add_child(spacer())
	foot.add_child(action("How to Play", show_help))
	_layout()

func show_levels() -> void:
	_fresh_page("levels")
	var body := _body()
	var header := HBoxContainer.new()
	body.add_child(header)
	header.add_child(action("← Home", show_home))
	header.add_child(spacer())
	header.add_child(text_label("%02d  /  %02d" % [store.data.completed.size(), levels.size()], 20, MUTED))
	body.add_child(text_label("Rooms", 42))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	cards = GridContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("h_separation", 14)
	cards.add_theme_constant_override("v_separation", 14)
	scroll.add_child(cards)
	for i in levels.size():
		var info: Dictionary = levels[i]
		var unlocked: bool = i == 0 or info.get("chapter_entry", false) or store.data.completed.has(levels[i-1].id)
		var done: bool = store.data.completed.has(info.id)
		var card := action("", open_level.bind(i, true))
		card.custom_minimum_size = Vector2(0, 110 * ui_scale())
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.disabled = not unlocked
		card.tooltip_text = info.title + (" · Complete" if done else (" · Locked" if not unlocked else ""))
		cards.add_child(card)
		var caption := "%s   %s" % [info.id, info.title]
		if done:
			caption += "   ✓"
		var title := text_label(caption, 24, INK if unlocked else DIM, HORIZONTAL_ALIGNMENT_CENTER)
		card.add_child(title)
		title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_layout()

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
	routes_visible = false
	var body := _body()
	var top := HBoxContainer.new()
	body.add_child(top)
	top.add_child(action("← Rooms", show_levels))
	top.add_child(text_label("%s   /   %s" % [session.level.id, session.level.title], 19))
	top.add_child(spacer())
	trace_button = action("Paths", toggle_routes)
	top.add_child(trace_button)
	top.add_child(action("Hint", next_hint))
	top.add_child(action("Pause", show_pause))
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
	edit_button = action("Edit Last Echo", edit_last, 120)
	actions.add_child(seal_button)
	actions.add_child(undo_button)
	actions.add_child(action("Restart Room", restart_room, 110))
	actions.add_child(edit_button)
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
	edit_button.text = "Cancel Edit" if not session.edit_origin.is_empty() else "Edit Last Echo"
	edit_button.disabled = session.echoes.is_empty() and session.edit_origin.is_empty()
	trace_button.text = "Paths · On" if routes_visible else "Paths · Off"
	board.show_routes = routes_visible
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
	routes_visible = not routes_visible
	_refresh()

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
	if is_instance_valid(page):
		page.process_mode = Node.PROCESS_MODE_INHERIT

func _dialog(kind: String, title: String, description: String, choices: Array) -> void:
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
	panel.custom_minimum_size.x = minf(size.x - 52, 570 * ui_scale())
	panel.add_theme_stylebox_override("panel", box(Color("101214"), Color("41474c"), 28))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 17)
	panel.add_child(content)
	content.add_child(Control.new())
	content.add_child(text_label(title, 31))
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
	for i in buttons.get_child_count():
		var button: Button = buttons.get_child(i)
		button.focus_next = button.get_path_to(buttons.get_child((i+1) % buttons.get_child_count()))
		button.focus_previous = button.get_path_to(buttons.get_child(posmod(i-1, buttons.get_child_count())))
		button.focus_neighbor_right = button.focus_next
		button.focus_neighbor_left = button.focus_previous
	content.add_child(Control.new())
	buttons.get_child(0).grab_focus()

func show_help() -> void:
	var back: Callable = show_pause if screen == "game" else _close_modal
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
	_dialog("pause", "Paused", "", [["Resume", _resume_game], ["Restart Room", restart_room], ["Back to Rooms", show_levels], ["How to Play", func(): show_help()]])

func _resume_game() -> void:
	_close_modal()
	_refresh()

func show_complete() -> void:
	_play("complete")
	var next := "Next Room" if level_index + 1 < levels.size() else "All Rooms"
	_dialog("complete", "Room Complete", "Beats  %d    ·    Echoes  %d" % [session.tick(), session.echoes.size()], [[next, func():
		if level_index + 1 < levels.size(): open_level(level_index + 1, true)
		else: show_levels()], ["Play Again", restart_room], ["Undo", func(): _close_modal(); undo_move()]])

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var code: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code == KEY_F11:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif modal != null:
		if code == KEY_ESCAPE:
			if modal_kind == "complete": show_levels()
			elif modal_kind == "help" and screen == "game": show_pause()
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
	elif screen == "levels" and code == KEY_ESCAPE:
		show_home()
	else:
		return
	get_viewport().set_input_as_handled()
