extends "res://scripts/ui.gd"

const Puzzle = preload("res://scripts/puzzle.gd")
const Store = preload("res://scripts/save_store.gd")
const Board = preload("res://scripts/board.gd")
const Atmosphere = preload("res://scripts/atmosphere.gd")
const Mark = preload("res://scripts/mark.gd")
const MUSIC := preload("res://assets/audio/stillwater.ogg")
const STEPS := [preload("res://assets/audio/step.wav"), preload("res://assets/audio/step_b.wav"), preload("res://assets/audio/step_c.wav")]
const SOUNDS := {
	"gate": preload("res://assets/audio/gate.wav"),
	"record": preload("res://assets/audio/record.wav"),
	"complete": preload("res://assets/audio/complete.wav")
}
const MOVE_SECONDS := [0.22, 0.13, 0.08]
const TITLE_SECONDS := [0.0, 1.0, 1.5, 2.0]
const PATH_OPACITY := [0.30, 0.50, 0.85]
const CHOICES := {
	"move_speed": ["Gentle", "Standard", "Quick"],
	"room_titles": ["Off", "1 s", "1.5 s", "2 s"],
	"path_weight": ["Faint", "Standard", "Bold"]
}
const ROMAN := ["I", "II", "III", "IV"]
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
var footfalls: AudioStreamPlayer
var music: AudioStreamPlayer
var music_fade: Tween
var music_position := 0.0
var closing := false
var hint_index := -1
var status_text := ""
var beat_label: Label
var capacity_label: Label
var message_label: Label
var seal_button: Button
var undo_button: Button
var setting_values: Dictionary = {}
var settings_section := "Audio"
var volume_dirty := false
var title_card: CenterContainer
var title_underlay: Control
var title_tween: Tween

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
	_start_audio()
	if DisplayServer.get_name() != "headless":
		get_tree().auto_accept_quit = false
		get_window().close_requested.connect(_close_game)
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
		var panel_width := minf(size.x - 52, modal_width * ui_scale())
		if modal_kind == "pause":
			modal_panel.offset_left = -panel_width
		else:
			modal_panel.custom_minimum_size.x = panel_width
		rescale_text(modal)

func _fresh_page(name_: String, landscape: String = "") -> void:
	_dismiss_room_title()
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
	ambient.set_chapter(landscape)
	ambient.modulate.a = 0.45 if screen == "chapters" else 1.0

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
	top.add_child(action("Settings", show_settings))
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
	var buttons := VBoxContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons.custom_minimum_size.x = 164 * ui_scale()
	buttons.add_theme_constant_override("separation", roundi(12 * ui_scale()))
	body.add_child(buttons)
	var resume := _session_index()
	buttons.add_child(home_action("Continue" if resume >= 0 else "Start", func(): open_level(resume if resume >= 0 else _next_unfinished(), true)))
	buttons.add_child(home_action("Chapters", show_chapters))
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
	heading.add_child(text_label(_chapter_label(chapter), 17, Atmosphere.WORLDS.get(chapter, {}).get("light", MUTED), alignment))
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

func _selection_page(screen_name: String, back_label: String, on_back: Callable, landscape: String = "") -> VBoxContainer:
	_fresh_page(screen_name, landscape)
	var body := _body()
	var header := HBoxContainer.new()
	body.add_child(header)
	header.add_child(action(back_label, on_back))
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
		var entry := action("", show_rooms.bind(chapter))
		entry.accessibility_name = chapter
		entry.accessibility_description = _chapter_label(chapter)
		item.add_child(entry)
		item.add_child(_chapter_heading(chapter, HORIZONTAL_ALIGNMENT_CENTER))
	_layout()

func show_rooms(chapter: String) -> void:
	var index := _selection_page("rooms", "← Chapters", show_chapters, chapter)
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

func open_level(index: int, resume: bool = false, introduce: bool = true) -> void:
	if index < 0 or index >= levels.size():
		return
	level_index = index
	session = Puzzle.new(levels[index])
	if resume and _session_index() == index:
		session.restore(store.data.session)
	_fresh_page("game", session.level.chapter)
	hint_index = -1
	status_text = ""
	var body := _body()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", roundi(22 * ui_scale()))
	body.add_child(top)
	var exit_button := action("←  Exit Room", show_home, 120 * ui_scale())
	exit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	exit_button.accessibility_name = "Exit Room"
	exit_button.tooltip_text = "Return to Home"
	exit_button.set_meta("base_px", 18)
	top.add_child(exit_button)
	var room_title := VBoxContainer.new()
	room_title.add_theme_constant_override("separation", 0)
	top.add_child(room_title)
	room_title.add_child(text_label("%s   /   %s" % [_chapter_label(session.level.chapter), session.level.chapter], 17, MUTED))
	room_title.add_child(text_label("%s   %s" % [session.level.id, session.level.title], 26))
	top.add_child(spacer())
	var pause := action("", show_pause)
	pause.icon = preload("res://assets/pause.svg")
	pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause.custom_minimum_size = Vector2(46, 44) * ui_scale()
	pause.accessibility_name = "Pause"
	pause.tooltip_text = "Pause (Esc)"
	top.add_child(pause)
	var hud := HBoxContainer.new()
	body.add_child(hud)
	hud.alignment = BoxContainer.ALIGNMENT_CENTER
	beat_label = text_label("", 25)
	hud.add_child(beat_label)
	capacity_label = text_label("", 18, MUTED)
	hud.add_child(capacity_label)
	board = Board.new()
	board.puzzle = session
	if Atmosphere.WORLDS.has(session.level.chapter):
		board.set_colors(Atmosphere.WORLDS[session.level.chapter])
	board.font = regular
	_apply_board_preferences()
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
	undo_button.set_meta("base_px", 18)
	actions.add_child(seal_button)
	actions.add_child(undo_button)
	_save_session()
	_refresh()
	_layout()

	if introduce:
		_show_room_title(body.get_parent())

func _show_room_title(underlay: Control) -> void:
	var seconds: float = TITLE_SECONDS[store.data.room_titles]
	if seconds == 0:
		return
	title_underlay = underlay
	title_underlay.modulate.a = 0
	title_card = CenterContainer.new()
	title_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(title_card)
	title_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", roundi(10 * ui_scale()))
	title_card.add_child(stack)
	var color: Color = Atmosphere.WORLDS.get(session.level.chapter, {}).get("light", MUTED)
	var reference := "%s   /   Room %s" % [_chapter_label(session.level.chapter), session.level.id]
	stack.add_child(text_label(reference, 19, color, HORIZONTAL_ALIGNMENT_CENTER))
	stack.add_child(text_label(session.level.title, 60, INK, HORIZONTAL_ALIGNMENT_CENTER))
	title_tween = page.create_tween()
	var fade := minf(0.40, seconds * 0.25) if store.data.motion else 0.0
	title_tween.tween_interval(seconds - fade)
	if fade > 0:
		title_tween.tween_property(title_card, "modulate:a", 0.0, fade)
		title_tween.parallel().tween_property(title_underlay, "modulate:a", 1.0, fade)
	title_tween.tween_callback(_dismiss_room_title)

func _dismiss_room_title() -> void:
	if title_tween != null:
		title_tween.kill()
		title_tween = null
	if is_instance_valid(title_underlay):
		title_underlay.modulate.a = 1
	title_underlay = null
	if is_instance_valid(title_card):
		title_card.hide()
		title_card.queue_free()
	title_card = null

func _apply_board_preferences() -> void:
	board.motion = store.data.motion
	board.move_seconds = MOVE_SECONDS[store.data.move_speed]
	board.path_opacity = PATH_OPACITY[store.data.path_weight]

func _start_audio() -> void:
	audio = AudioStreamPlayer.new()
	add_child(audio)
	var bank := AudioStreamRandomizer.new()
	bank.playback_mode = AudioStreamRandomizer.PLAYBACK_SEQUENTIAL
	for clip in STEPS:
		bank.add_stream(bank.streams_count, clip)
	footfalls = AudioStreamPlayer.new()
	footfalls.stream = bank
	footfalls.max_polyphony = 2
	add_child(footfalls)
	_apply_volume()
	music = AudioStreamPlayer.new()
	music.stream = MUSIC
	music.volume_db = -72.0
	add_child(music)
	_mix_music(1.4)

func _apply_volume() -> void:
	audio.volume_db = linear_to_db(maxf(0.0001, store.data.volume / 100.0))
	footfalls.volume_db = audio.volume_db
	if store.data.volume == 0:
		audio.stop()
		footfalls.stop()

func _close_game() -> void:
	if closing: return
	closing = true
	_commit_volume()
	audio.stop()
	footfalls.stop()
	if music_fade != null: music_fade.kill()
	var out := create_tween()
	out.tween_property(music, "volume_db", -72.0, 0.16)
	out.tween_callback(music.stop)
	# Let the mixer release the Vorbis playback before the window exits.
	out.tween_interval(0.16)
	out.tween_callback(get_tree().quit)

func _mix_music(seconds: float) -> void:
	if DisplayServer.get_name() == "headless" or closing:
		return
	if music_fade != null:
		music_fade.kill()
	var audible: bool = store.data.sound and store.data.music_volume > 0
	if audible:
		if not music.playing:
			music.play(music_position)
	elif not music.playing:
		return
	var gain := linear_to_db(store.data.music_volume / 100.0) if audible else -72.0
	music_fade = music.create_tween()
	music_fade.tween_property(music, "volume_db", gain, seconds)
	if not audible:
		music_fade.tween_callback(func():
			music_position = fposmod(music.get_playback_position(), MUSIC.get_length())
			music.stop())

func _play(id: String) -> void:
	if not store.data.sound or store.data.volume == 0 or DisplayServer.get_name() == "headless":
		return
	if id == "step":
		if store.data.step_sounds: footfalls.play()
	else:
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
	open_level(level_index, false, false)

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
	_commit_volume()
	if is_instance_valid(modal):
		remove_child(modal)
		modal.queue_free()
	modal = null
	modal_kind = ""
	modal_panel = null
	setting_values.clear()
	if is_instance_valid(page):
		page.process_mode = Node.PROCESS_MODE_INHERIT

func _begin_modal(kind: String) -> void:
	_close_modal()
	_dismiss_room_title()
	modal_kind = kind
	page.process_mode = Node.PROCESS_MODE_DISABLED
	modal = ColorRect.new()
	modal.color = Color(0, 0, 0, 0.42 if kind == "pause" else 0.85)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Underlying controls cannot consume keyboard focus while a dialog is visible.
	if get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_release_focus()

func _panel(kind: String, title: String, width: float = 570) -> VBoxContainer:
	_begin_modal(kind)
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

func _focus_dialog(first: Control) -> void:
	var buttons: Array[Control] = []
	for control in modal.find_children("*", "Control", true, false):
		if control.focus_mode != Control.FOCUS_ALL or (control is BaseButton and control.disabled) or (control is Slider and not control.editable):
			continue
		buttons.append(control)
	for i in buttons.size():
		var button: Control = buttons[i]
		button.focus_next = button.get_path_to(buttons[(i+1) % buttons.size()])
		button.focus_previous = button.get_path_to(buttons[posmod(i-1, buttons.size())])
		if not button is Slider:
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
			_mix_music(0.35)
			if store.data.sound:
				_play("record")
			else:
				audio.stop()
				footfalls.stop()
		"step_sounds":
			if store.data.step_sounds: _play("step")
			else: footfalls.stop()
		"motion":
			ambient.animated = store.data.motion and screen == "home"
			if is_instance_valid(mark): mark.motion = store.data.motion
			if is_instance_valid(board): _apply_board_preferences()
		"fullscreen":
			_apply_fullscreen(store.data.fullscreen)
	_save_preferences()
	if setting_values.has(id):
		if id in ["sound", "motion", "paths"]:
			show_settings(id)
		else:
			_update_option_label(id)
	if screen == "game": _refresh()

func _cycle_setting(id: String) -> void:
	store.data[id] = (int(store.data[id]) + 1) % CHOICES[id].size()
	if is_instance_valid(board):
		_apply_board_preferences()
		board.queue_redraw()
	_save_preferences()
	_update_option_label(id)

func _save_preferences() -> void:
	if not store.flush():
		status_text = store.last_error

func _update_option_label(id: String) -> void:
	var label: Label = setting_values[id]
	if CHOICES.has(id):
		label.text = CHOICES[id][store.data[id]]
	else:
		label.text = "On" if store.data[id] else "Off"
	var button: Button = label.get_parent()
	button.accessibility_description = label.text
	if button.disabled:
		label.add_theme_color_override("font_color", DIM)

func _add_option(rows: VBoxContainer, id: String, title: String, enabled: bool = true) -> Button:
	var change := _cycle_setting if CHOICES.has(id) else _toggle_setting
	var button := list_action(title, change.bind(id))
	button.disabled = not enabled
	rows.add_child(button)
	setting_values[id] = _row_value(button, "")
	_update_option_label(id)
	return button

func _commit_volume() -> void:
	if volume_dirty:
		volume_dirty = false
		_save_preferences()

func _add_volume(rows: VBoxContainer, id: String, title: String) -> void:
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_left", 12)
	inset.add_theme_constant_override("margin_right", 12)
	rows.add_child(inset)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 48 * ui_scale()
	inset.add_child(row)
	var caption := text_label(title, 16)
	caption.custom_minimum_size.x = 66 * ui_scale()
	row.add_child(caption)
	var slider := HSlider.new()
	slider.accessibility_name = title + " Volume"
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = store.data[id]
	slider.editable = store.data.sound
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := StyleBoxFlat.new()
	track.bg_color = Color("3b454b")
	track.set_corner_radius_all(2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	slider.add_theme_stylebox_override("slider", track)
	var filled: StyleBoxFlat = track.duplicate()
	filled.bg_color = MUTED if slider.editable else DIM
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	row.add_child(slider)
	var percent := text_label("%d%%" % int(slider.value), 16, ACCENT if slider.editable else DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	percent.custom_minimum_size.x = 52 * ui_scale()
	row.add_child(percent)
	slider.value_changed.connect(func(value: float):
		store.data[id] = roundi(value)
		percent.text = "%d%%" % roundi(value)
		if id == "music_volume": _mix_music(0.10)
		else: _apply_volume()
		volume_dirty = true
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_commit_volume()
			if id == "volume": _play("record"))
	slider.drag_ended.connect(func(changed: bool):
		_commit_volume()
		if changed and id == "volume": _play("record"))

func _select_settings(section: String) -> void:
	settings_section = section
	show_settings()

func show_settings(focus_id: String = "") -> void:
	var fullscreen := _window_fullscreen()
	if store.data.fullscreen != fullscreen:
		store.data.fullscreen = fullscreen
		_save_preferences()
	var content := _panel("settings", "Settings", 525)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	content.add_child(tabs)
	var current_tab: Button
	for section in ["Audio", "Display", "Puzzle"]:
		var tab := list_action(section, _select_settings.bind(section))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab.toggle_mode = true
		tab.set_pressed_no_signal(section == settings_section)
		tab.add_theme_color_override("font_color", MUTED)
		tab.add_theme_color_override("font_pressed_color", Color.WHITE)
		if section == settings_section:
			current_tab = tab
			tab.accessibility_description = "Selected"
		tabs.add_child(tab)
	var rows := VBoxContainer.new()
	rows.custom_minimum_size.y = 148 * ui_scale()
	rows.add_theme_constant_override("separation", 6)
	content.add_child(rows)
	match settings_section:
		"Audio":
			_add_option(rows, "sound", "Sound")
			_add_volume(rows, "volume", "Effects")
			_add_volume(rows, "music_volume", "Music")
			_add_option(rows, "step_sounds", "Footsteps", store.data.sound)
		"Display":
			_add_option(rows, "fullscreen", "Fullscreen")
			_add_option(rows, "motion", "Motion")
			_add_option(rows, "move_speed", "Move Animation", store.data.motion)
		"Puzzle":
			_add_option(rows, "room_titles", "Room Titles")
			_add_option(rows, "paths", "Echo Paths")
			_add_option(rows, "path_weight", "Path Contrast", store.data.paths)
	var foot := HBoxContainer.new()
	content.add_child(foot)
	foot.add_child(action("Back", _leave_settings))
	foot.add_child(spacer())
	foot.add_child(action("How to Play", show_help))
	content.add_child(Control.new())
	var first: Control = setting_values[focus_id].get_parent() if setting_values.has(focus_id) else current_tab
	_focus_dialog(first)

func _leave_settings() -> void:
	if screen == "game": show_pause()
	else: _close_modal()

func show_help() -> void:
	var back: Callable = show_settings
	if screen == "game" and (not session.turnstiles.is_empty() or not session.switches.is_empty() or session.plates.has(Puzzle.LENS)):
		var rules := PackedStringArray(["Move one tile per beat. Press Enter to leave an echo. Z undoes a beat. R restarts the room and clears all echoes."])
		if session.plates.has(Puzzle.LENS):
			rules.append("L is a lens. Two selves on its tile open the L gate for the next move. Two echoes count, even when you are elsewhere.")
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
	_begin_modal("pause")
	modal_width = 362
	modal_panel = PanelContainer.new()
	modal.add_child(modal_panel)
	modal_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	modal_panel.offset_left = -minf(size.x - 52, modal_width * ui_scale())
	var surface := box(Color("101519"), Color("55616a"), 26 * ui_scale())
	surface.set_corner_radius_all(0)
	surface.set_border_width_all(0)
	surface.border_width_left = 1
	modal_panel.add_theme_stylebox_override("panel", surface)
	if store.data.motion:
		var left := modal_panel.offset_left
		var slide := modal_panel.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		slide.tween_property(modal_panel, "offset_left", left, 0.16).from(left + 20)
		slide.tween_property(modal_panel, "offset_right", 0.0, 0.16).from(20.0)
	modal.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not modal_panel.get_rect().has_point(event.position):
			get_viewport().set_input_as_handled()
			_resume_game())
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", roundi(14 * ui_scale()))
	modal_panel.add_child(content)
	content.add_child(text_label("Room %s   /   %s" % [session.level.id, session.level.title], 16, MUTED))
	content.add_child(text_label("Paused", 34))
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
	if title_card != null and ((event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed)):
		_dismiss_room_title()
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
