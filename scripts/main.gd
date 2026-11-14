extends "res://scripts/ui.gd"

const Puzzle = preload("res://scripts/puzzle.gd")
const Store = preload("res://scripts/save_store.gd")
const Board = preload("res://scripts/board.gd")
const Atmosphere = preload("res://scripts/atmosphere.gd")
const Mark = preload("res://scripts/mark.gd")
const REPOSITORY_URL := "https://github.com/Phyll1s0/echo"
const ChapterGuide = preload("res://scripts/chapter_guide.gd")
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
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
const EXTRA := "Extra"
var chapters: Array[String] = []
var campaign_levels: Array
var extra_levels: Array
var levels: Array
var store
var session
var level_index := 0
var screen := ""
# Keep the entry page when restarting or advancing to another room.
var room_return: Callable
var entered_from_rooms := false
var ambient
var page: Control
var modal: ColorRect
var modal_kind := ""
var modal_panel: PanelContainer
var modal_width := 570.0
var board
var chapter_index: VBoxContainer
var chapter_picker
var chapter_focus := 0
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
var layout_profile := ""
var modal_scroll: ScrollContainer
var direction_pad: Control
var guide_demo
var guide_page := 0

func _ready() -> void:
	if OS.has_feature("web"):
		add_child(preload("res://scripts/web_viewport.gd").new())
	else:
		touch_controls = DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()
	setup_skin()
	if store == null:
		store = Store.new()
	TranslationServer.set_locale(store.data.language)
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json"))
	if not catalog is Array or catalog.is_empty():
		push_error("ECHO: level catalog missing")
		add_child(text_label("Could not load the rooms."))
		return
	campaign_levels = catalog
	levels = campaign_levels
	extra_levels = JSON.parse_string(FileAccess.get_file_as_string("res://data/extra.json"))
	for info in levels:
		if info.chapter not in chapters:
			chapters.append(info.chapter)
	if store.data.fullscreen and not OS.has_feature("web"):
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
		if arg.begins_with("--extra-room="):
			var requested := arg.trim_prefix("--extra-room=")
			for index in extra_levels.size():
				if extra_levels[index].id == requested:
					show_rooms(EXTRA)
					open_level(index, true)
					return
			for index in campaign_levels.size():
				if campaign_levels[index].get("legacy_id", "") == requested:
					show_rooms(campaign_levels[index].chapter)
					open_level(index, true)
					return
		elif arg.begins_with("--level=") or arg.begins_with("--number="):
			var index: int
			if arg.begins_with("--number="):
				index = arg.trim_prefix("--number=").to_int() - 1
			else:
				index = room_index("%02d" % arg.trim_prefix("--level=").to_int())
			if index >= 0 and index < levels.size():
				show_rooms(levels[index].chapter)
				open_level(index, true)
				return

func _profile() -> String:
	return "%s:%s:%s:%s:%s:%s" % [compact_ui(), touch_controls, touch_landscape(), size.x < 360, size.y < 500, size.y < 360]

func _adapt_layout() -> void:
	if not is_instance_valid(page) or layout_profile == _profile(): return
	var previous_modal := modal_kind
	var previous_guide_page := guide_page
	var previous_guide_step: int = guide_demo.step_index if is_instance_valid(guide_demo) else 0
	var previous_guide_playing: bool = guide_demo.playing if is_instance_valid(guide_demo) else false
	var return_page := room_return
	match screen:
		"home": show_home()
		"chapters": show_chapters()
		"rooms": show_rooms(ambient.chapter)
		"game": _show_game()
	room_return = return_page
	match previous_modal:
		"settings": show_settings()
		"pause": show_pause()
		"help": show_help()
		"guide":
			show_chapter_guide(previous_guide_page)
			for i in previous_guide_step: guide_demo.advance()
			guide_demo.playing = previous_guide_playing
			guide_demo.playback_changed.emit()
		"complete":
			if modal == null: show_complete()

func _layout() -> void:
	if not screen.is_empty() and layout_profile != _profile():
		call_deferred("_adapt_layout")
	if theme != null:
		theme.default_font_size = roundi(15 * ui_scale())
	if is_instance_valid(page):
		rescale_text(page)
	if is_instance_valid(chapter_index) and screen != "chapters":
		var gap := (24 if size.y >= 720 else 14) if screen == "chapters" else 17
		chapter_index.add_theme_constant_override("separation", roundi(gap * ui_scale()))
		chapter_index.custom_minimum_size.x = minf(480 * ui_scale(), size.x - (40 if compact_ui() else 110 * ui_scale()))
	if is_instance_valid(modal_panel):
		var panel_width := minf(size.x - (24 if compact_ui() else 52), modal_width * ui_scale())
		if modal_kind == "pause":
			modal_panel.offset_left = -panel_width
		else:
			modal_panel.custom_minimum_size.x = panel_width
		rescale_text(modal)
		if is_instance_valid(modal_scroll) and modal_kind != "pause":
			modal_scroll.custom_minimum_size.y = minf(modal_scroll.get_child(0).get_combined_minimum_size().y, maxf(100, size.y - 70))

func _fresh_page(name_: String, landscape: String = "") -> void:
	_dismiss_room_title()
	_close_modal()
	if is_instance_valid(page):
		remove_child(page)
		page.queue_free()
	board = null
	direction_pad = null
	chapter_index = null
	chapter_picker = null
	mark = null
	apply_palette(Atmosphere.WORLDS.get(landscape, {}).get("dark", false))
	screen = name_
	layout_profile = _profile()
	page = Control.new()
	add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ambient.animated = bool(store.data.motion) and screen == "home"
	ambient.set_chapter(landscape)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("document.body.style.background = '%s'; document.querySelector('meta[name=theme-color]').content = '%s'" % ["#08090a" if dark else "#fcfcfb", "#08090a" if dark else "#fcfcfb"])

func _body() -> VBoxContainer:
	var margin := MarginContainer.new()
	page.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, (14 if size.x < 360 else 18) if compact_ui() else roundi(38 * ui_scale()))
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, (8 if size.y < 500 else 14) if compact_ui() else roundi(22 * ui_scale()))
	var body := VBoxContainer.new()
	margin.add_child(body)
	return body

func _session_index() -> int:
	return room_index(store.data.session.get("level_id", ""))

# Public links and saves use permanent room IDs; catalog order is the play order.
func room_index(id: String) -> int:
	for i in levels.size():
		if levels[i].id == id:
			return i
	return -1

func room_number(index: int) -> String:
	if levels[index].chapter == EXTRA:
		return levels[index].id
	return "%02d" % (index + 1)

func _next_unfinished() -> int:
	for i in levels.size():
		if not store.data.completed.has(levels[i].id):
			return i
	return 0

func show_home() -> void:
	levels = campaign_levels
	room_return = show_home
	entered_from_rooms = false
	_fresh_page("home")
	var body := _body()
	var top := HBoxContainer.new()
	body.add_child(top)
	top.add_child(spacer())
	var settings := action("", show_settings)
	settings.icon = preload("res://assets/settings.svg")
	settings.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings.expand_icon = true
	settings.set_meta("icon_px", 22)
	settings.custom_minimum_size = Vector2(46, 40) * ui_scale()
	settings.accessibility_name = tr("Settings")
	settings.tooltip_text = tr("Settings")
	top.add_child(settings)
	var github := Button.new()
	github.icon = preload("res://assets/github.svg")
	github.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	github.expand_icon = true
	github.set_meta("icon_px", 21)
	github.custom_minimum_size = Vector2(46, 44) * ui_scale()
	github.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	github.accessibility_name = "GitHub"
	github.accessibility_description = tr("Open the ECHO repository")
	github.tooltip_text = tr("Open the ECHO repository")
	github.draw.connect(_draw_action_line.bind(github))
	# Keep browser activation synchronous; this callback does not replace UI nodes.
	github.pressed.connect(_open_repository)
	top.add_child(github)
	body.add_child(spacer(false))
	mark = Mark.new()
	mark.ink = ink
	mark.motion = store.data.motion
	mark.custom_minimum_size.y = (40 if size.y < 500 else 68) if compact_ui() else 94 * ui_scale()
	body.add_child(mark)
	var title := text_label("E C H O", 54 if compact_ui() else 100, ink, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_font_override("font", thin)
	body.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8 if compact_ui() else 20 * ui_scale()
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

func _open_repository() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('%s', '_blank', 'noopener,noreferrer')" % REPOSITORY_URL, true)
	else:
		OS.shell_open(REPOSITORY_URL)

func _chapter_label(chapter: String) -> String:
	if chapter == EXTRA: return tr(EXTRA)
	var order := chapters.find(chapter)
	var numeral: String = ROMAN[order] if order >= 0 and order < ROMAN.size() else str(order + 1)
	return tr("Chapter %s") % numeral

func _chapter_heading(chapter: String, alignment: HorizontalAlignment) -> VBoxContainer:
	var heading := VBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("separation", 0)
	var chapter_color: Color = Atmosphere.WORLDS.get(chapter, {}).get("light", muted)
	if chapter == "Nocturne" and not dark: chapter_color = muted
	if chapter == "Orbit" and not dark: chapter_color = Color("48617e")
	if chapter == "Nexus" and not dark: chapter_color = Color("276977")
	if chapter == "Inferno" and not dark: chapter_color = Color("a34c35")
	if chapter != EXTRA:
		heading.add_child(text_label(_chapter_label(chapter), 17, chapter_color, alignment))
	heading.add_child(text_label(chapter, 30 if compact_ui() else (36 if screen == "chapters" else 42), ink, alignment))
	return heading

func _completed_rooms(chapter: String) -> Dictionary:
	return store.data.extra_completed if chapter == EXTRA else store.data.completed

func _chapter_progress(chapter: String) -> Vector2i:
	var progress := Vector2i.ZERO
	for info in levels:
		if info.chapter == chapter:
			progress.y += 1
			if _completed_rooms(chapter).has(info.id):
				progress.x += 1
	return progress

func _selection_page(screen_name: String, back_label: String, on_back: Callable, landscape: String = "") -> VBoxContainer:
	_fresh_page(screen_name, landscape)
	var body := _body()
	var header := HBoxContainer.new()
	body.add_child(header)
	header.add_child(action(back_label, on_back))
	if screen_name == "chapters":
		header.add_child(spacer())
		header.add_child(action(EXTRA, show_rooms.bind(EXTRA)))
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
	levels = campaign_levels
	room_return = show_chapters
	_fresh_page("chapters")
	var body := _body()
	var header := HBoxContainer.new()
	body.add_child(header)
	header.add_child(action("← Home", show_home))
	header.add_child(spacer())
	header.add_child(action(EXTRA, show_rooms.bind(EXTRA)))
	chapter_picker = preload("res://scripts/chapter_picker.gd").new()
	body.add_child(chapter_picker)
	chapter_picker.build(self, chapters, chapter_focus)
	chapter_index = chapter_picker.index
	chapter_picker.selected_changed.connect(func(which): chapter_focus = which)
	chapter_picker.chapter_opened.connect(func(which): show_rooms(chapters[which]))
	_layout()

func show_rooms(chapter: String) -> void:
	if chapter in chapters: chapter_focus = chapters.find(chapter)
	levels = extra_levels if chapter == EXTRA else campaign_levels
	entered_from_rooms = true
	room_return = show_rooms.bind(chapter)
	var index := _selection_page("rooms", "← Chapters", show_chapters, chapter)
	var heading := HBoxContainer.new()
	index.add_child(heading)
	heading.add_child(_chapter_heading(chapter, HORIZONTAL_ALIGNMENT_LEFT))
	heading.add_child(spacer())
	var count := _chapter_progress(chapter)
	heading.add_child(text_label("%d / %d" % [count.x, count.y], 18, muted))
	for i in levels.size():
		var info: Dictionary = levels[i]
		if info.chapter != chapter:
			continue
		var done: bool = _completed_rooms(chapter).has(info.id)
		var unlocked: bool = chapter == EXTRA or done or i == 0 or info.get("chapter_entry", false) or store.data.completed.has(levels[i-1].id) or store.data.completed.has(info.get("also_unlock_after", ""))
		var room := list_action("%s    %s" % [room_number(i), tr(info.title)], open_level.bind(i, true))
		room.set_meta("base_px", 18 if compact_ui() else 21)
		room.disabled = not unlocked
		var state := tr("Complete") if done else (tr("Locked") if not unlocked else "")
		room.accessibility_description = state
		room.tooltip_text = state
		if done:
			_row_value(room, "✓")
		index.add_child(room)
	_layout()

func _row_value(button: Button, value: String) -> Label:
	var caption := text_label(value, 16, accent, HORIZONTAL_ALIGNMENT_RIGHT)
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
	if entered_from_rooms:
		room_return = show_rooms.bind(session.level.chapter)
	var saved: Variant = store.data.session
	if session.level.chapter == EXTRA:
		saved = store.data.extra_sessions.get(session.level.id, {})
	elif saved.get("level_id") != session.level.id and session.level.has("legacy_id"):
		saved = store.data.extra_sessions.get(session.level.legacy_id, {}).duplicate(true)
		if not saved.is_empty():
			saved.level_id = session.level.id
			if saved.get("edit_origin") is Dictionary and not saved.edit_origin.is_empty():
				saved.edit_origin.level_id = session.level.id
	var needs_new_route := false
	if resume and saved is Dictionary and saved.get("level_id") == session.level.id:
		needs_new_route = not session.restore(saved)
	hint_index = -1
	status_text = "This route no longer matches the room. Begin a new route." if needs_new_route else ""
	_save_session()
	_show_game(introduce)

func _show_game(introduce: bool = false) -> void:
	_fresh_page("game", session.level.chapter)
	var body := _body()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8 if compact_ui() else roundi(22 * ui_scale()))
	body.add_child(top)
	var back := action("←", room_return, 46 * ui_scale())
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.accessibility_name = tr("Back")
	back.tooltip_text = tr("Back")
	back.set_meta("base_px", 26)
	top.add_child(back)
	var room_title := VBoxContainer.new()
	room_title.add_theme_constant_override("separation", 0)
	room_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(room_title)
	var chapter_text := _chapter_label(session.level.chapter) if compact_ui() or session.level.chapter == EXTRA else "%s   /   %s" % [_chapter_label(session.level.chapter), tr(session.level.chapter)]
	room_title.add_child(text_label(chapter_text, 13 if compact_ui() else 17, muted))
	var name_label := text_label("%s   %s" % [room_number(level_index), tr(session.level.title)], 18 if compact_ui() else 26)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room_title.add_child(name_label)
	if _has_chapter_guide():
		var guide := action("?", show_chapter_guide)
		guide.custom_minimum_size = Vector2(44, 44) * ui_scale()
		guide.set_meta("base_px", 24)
		guide.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		guide.accessibility_name = tr("Chapter Guide")
		guide.tooltip_text = tr("Chapter Guide")
		top.add_child(guide)
	var pause := action("", show_pause)
	pause.icon = preload("res://assets/pause.svg")
	pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause.custom_minimum_size = Vector2(46, 44) * ui_scale()
	pause.accessibility_name = tr("Pause")
	pause.tooltip_text = tr("Pause (Esc)")
	top.add_child(pause)
	var hud := HBoxContainer.new()
	body.add_child(hud)
	hud.alignment = BoxContainer.ALIGNMENT_CENTER
	beat_label = text_label("", 18 if compact_ui() else 25)
	hud.add_child(beat_label)
	capacity_label = text_label("", 14 if compact_ui() else 18, muted)
	hud.add_child(capacity_label)
	board = Board.new()
	board.puzzle = session
	if Atmosphere.WORLDS.has(session.level.chapter):
		board.set_colors(Atmosphere.WORLDS[session.level.chapter])
	board.font = regular
	_apply_board_preferences()
	var arena := BoxContainer.new()
	arena.vertical = not touch_landscape()
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena.add_theme_constant_override("separation", 14)
	body.add_child(arena)
	var playfield := VBoxContainer.new()
	playfield.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playfield.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena.add_child(playfield)
	playfield.add_child(board)
	if compact_ui(): board.custom_minimum_size.y = 60
	board.move_requested.connect(try_move)
	board.inspection_changed.connect(func(message: String): status_text = message; _refresh())
	board.motion_finished.connect(_animation_done)
	message_label = text_label("", 14 if compact_ui() else 18, ink, HORIZONTAL_ALIGNMENT_CENTER)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size.y = 24 if compact_ui() else 38 * ui_scale()
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	playfield.add_child(message_label)
	var controls := BoxContainer.new()
	controls.vertical = touch_landscape() and size.y >= 360
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	controls.add_theme_constant_override("separation", 8 if size.x < 360 else 18)
	arena.add_child(controls)
	if touch_controls:
		direction_pad = preload("res://scripts/direction_pad.gd").new()
		direction_pad.ink = ink
		direction_pad.rim = Color(accent, 0.22)
		var diameter := 132 if touch_landscape() else (144 if size.x < 360 else 168)
		direction_pad.custom_minimum_size = Vector2.ONE * diameter
		direction_pad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		controls.add_child(direction_pad)
		direction_pad.move_requested.connect(func(delta): _dismiss_room_title(); try_move(delta))
	var actions := HFlowContainer.new()
	actions.alignment = FlowContainer.ALIGNMENT_CENTER
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_theme_constant_override("h_separation", 10)
	if touch_controls:
		actions.custom_minimum_size.x = (112 if size.y < 360 else 166) if touch_landscape() else (120 if size.x < 360 else 142)
	else:
		actions.custom_minimum_size.x = 300 * ui_scale()
	controls.add_child(actions)
	seal_button = action("Echo" if touch_landscape() else "Leave an Echo", seal_route, 0 if touch_controls else 134, true)
	if touch_controls:
		seal_button.accessibility_name = tr("Leave an Echo")
		seal_button.set_meta("base_px", 14 if size.x < 360 else 16)
	undo_button = action("Undo", undo_move, 0 if touch_controls else 90)
	undo_button.set_meta("base_px", 16 if touch_controls else 18)
	actions.add_child(seal_button)
	actions.add_child(undo_button)
	if touch_controls and (not touch_landscape() or size.y < 360):
		seal_button.custom_minimum_size.x = actions.custom_minimum_size.x
		undo_button.custom_minimum_size.x = actions.custom_minimum_size.x
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
	var color: Color = Atmosphere.WORLDS.get(session.level.chapter, {}).get("light", muted)
	var reference := tr("%s   /   Room %s") % [_chapter_label(session.level.chapter), room_number(level_index)]
	stack.add_child(text_label(reference, 19, color, HORIZONTAL_ALIGNMENT_CENTER))
	var title_name := text_label(session.level.title, 32 if compact_ui() else 60, ink, HORIZONTAL_ALIGNMENT_CENTER)
	stack.custom_minimum_size.x = minf(size.x - 40, 700)
	title_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(title_name)
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
	if session.level.has("legacy_id"):
		store.data.extra_sessions.erase(session.level.legacy_id)
	var is_extra: bool = session.level.chapter == EXTRA
	if session.cleared():
		var completed := _completed_rooms(session.level.chapter)
		completed[session.level.id] = {"echoes": session.echoes.size(), "beats": session.tick()}
		if is_extra: store.data.extra_sessions.erase(session.level.id)
		else: store.data.session = {}
	elif is_extra:
		store.data.extra_sessions[session.level.id] = session.snapshot()
	else:
		store.data.session = session.snapshot()
	if not store.flush():
		status_text = store.last_error

func _refresh() -> void:
	if screen != "game":
		return
	beat_label.text = tr("Beat %02d") % session.tick()
	capacity_label.text = tr("  /  Echoes  %d / %d") % [session.echoes.size(), session.level.max_echoes]
	message_label.text = tr(status_text)
	message_label.visible = not compact_ui() or not status_text.is_empty()
	if status_text.begins_with("Projection requires "):
		message_label.text = tr("Projection requires %s") % status_text.trim_prefix("Projection requires ")
	if status_text.begins_with("Gate requires "):
		message_label.text = tr("Gate requires %s") % status_text.trim_prefix("Gate requires ")
	elif status_text.begins_with("Gate needs empty "):
		message_label.text = tr("Gate needs empty %s") % status_text.trim_prefix("Gate needs empty ")
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
	modal_scroll = null
	guide_demo = null
	setting_values.clear()
	if is_instance_valid(page):
		page.process_mode = Node.PROCESS_MODE_INHERIT

func _begin_modal(kind: String) -> void:
	_close_modal()
	_dismiss_room_title()
	modal_kind = kind
	page.process_mode = Node.PROCESS_MODE_DISABLED
	modal = ColorRect.new()
	modal.color = Color(0, 0, 0, 0.42 if kind == "pause" else 0.85) if dark else Color("fcfcfbd4" if kind != "pause" else "fcfcfb65")
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
	panel.custom_minimum_size.x = minf(size.x - (24 if compact_ui() else 52), width * ui_scale())
	panel.add_theme_stylebox_override("panel", box(surface, edge, 16 if compact_ui() else 28))
	center.add_child(panel)
	modal_scroll = ScrollContainer.new()
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_scroll.follow_focus = true
	panel.add_child(modal_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12 if compact_ui() else 17)
	modal_scroll.add_child(content)
	content.minimum_size_changed.connect(func(): _layout.call_deferred())
	call_deferred("_layout")
	content.add_child(Control.new())
	content.add_child(text_label(title, 31))
	return content

func _dialog(kind: String, title: String, description: String, choices: Array) -> void:
	var content := _panel(kind, title)
	if not description.is_empty():
		var desc := text_label(description, 15 if compact_ui() else 18, muted)
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
		label.text = tr(CHOICES[id][store.data[id]])
	else:
		label.text = tr("On") if store.data[id] else tr("Off")
	var button: Button = label.get_parent()
	button.accessibility_description = label.text
	if button.disabled:
		label.add_theme_color_override("font_color", dim)

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
	for icon_state in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_theme_icon_override(icon_state, preload("res://assets/slider-grip.svg"))
	slider.accessibility_name = tr("%s Volume") % tr(title)
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = store.data[id]
	slider.editable = store.data.sound
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := StyleBoxFlat.new()
	track.bg_color = Color("3b454b") if dark else Color("d7dcdb")
	track.set_corner_radius_all(2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	slider.add_theme_stylebox_override("slider", track)
	var filled: StyleBoxFlat = track.duplicate()
	filled.bg_color = muted if slider.editable else dim
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	row.add_child(slider)
	var percent := text_label("%d%%" % int(slider.value), 16, accent if slider.editable else dim, HORIZONTAL_ALIGNMENT_RIGHT)
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

func _set_language(locale: String) -> void:
	if store.data.language == locale:
		return
	store.data.language = locale
	_save_preferences()
	TranslationServer.set_locale(locale)
	# Rebuild only the view. Keep the live puzzle, undo stack and edit backup.
	match screen:
		"home": show_home()
		"chapters": show_chapters()
		"rooms": show_rooms(ambient.chapter)
		"game": _show_game()
	show_settings("language")

func show_settings(focus_id: String = "") -> void:
	var fullscreen := _window_fullscreen()
	if store.data.fullscreen != fullscreen:
		store.data.fullscreen = fullscreen
		_save_preferences()
	var content := _panel("settings", "Settings", 525)
	var languages := HBoxContainer.new()
	content.add_child(languages)
	languages.add_child(text_label("Language", 16))
	languages.add_child(spacer())
	var language_group := ButtonGroup.new()
	var current_language: Button
	for locale in ["en", "zh_CN"]:
		var language := action("English" if locale == "en" else "中文", _set_language.bind(locale))
		language.toggle_mode = true
		language.button_group = language_group
		language.set_pressed_no_signal(locale == store.data.language)
		language.add_theme_color_override("font_color", muted)
		language.add_theme_color_override("font_pressed_color", ink)
		if locale == store.data.language:
			current_language = language
			language.accessibility_description = tr("Selected")
		languages.add_child(language)
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
		tab.add_theme_color_override("font_color", muted)
		tab.add_theme_color_override("font_pressed_color", ink)
		if section == settings_section:
			current_tab = tab
			tab.accessibility_description = tr("Selected")
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
	if focus_id == "language": first = current_language
	_focus_dialog(first)

func _leave_settings() -> void:
	if screen == "game": show_pause()
	else: _close_modal()

func _has_chapter_guide() -> bool:
	return session != null and ChapterGuide.PAGES.has(session.level.chapter) and (session.level.get("guide", false) or level_index == 0 or levels[level_index - 1].chapter != session.level.chapter)

func show_chapter_guide(index: int = -1) -> void:
	if screen != "game" or not _has_chapter_guide(): return
	if index < 0: index = int(session.level.get("guide_page", 0))
	guide_page = clampi(index, 0, ChapterGuide.PAGES[session.level.chapter].size() - 1)
	var info: Dictionary = ChapterGuide.PAGES[session.level.chapter][guide_page]
	var content := _panel("guide", "", 620)
	# An unframed sheet, with the same quiet text controls as the rest of ECHO.
	var style := box(surface, Color.TRANSPARENT, 18 if compact_ui() else 32)
	style.set_border_width_all(0)
	modal_panel.add_theme_stylebox_override("panel", style)
	var placeholder := content.get_child(1)
	content.remove_child(placeholder)
	placeholder.queue_free()
	var header := HBoxContainer.new()
	content.add_child(header)
	header.add_child(text_label(_chapter_label(session.level.chapter), 14, muted))
	header.add_child(spacer())
	var close := action("×", _close_chapter_guide)
	close.custom_minimum_size = Vector2(44, 44)
	close.set_meta("base_px", 25)
	close.accessibility_name = tr("Close Guide")
	close.tooltip_text = tr("Close Guide")
	header.add_child(close)
	var heading := text_label(info.title, 25 if compact_ui() else 32)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(heading)
	var explanation := text_label(info.body, 16 if compact_ui() else 18, muted)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(explanation)
	if ChapterGuide.PAGES[session.level.chapter].size() > 1:
		var tabs := HBoxContainer.new()
		content.add_child(tabs)
		for i in ChapterGuide.PAGES[session.level.chapter].size():
			var tab := action(ChapterGuide.PAGES[session.level.chapter][i].title, show_chapter_guide.bind(i))
			tab.toggle_mode = true
			tab.set_pressed_no_signal(i == guide_page)
			tab.add_theme_color_override("font_color", muted)
			tabs.add_child(tab)
	guide_demo = ChapterGuide.new()
	content.add_child(guide_demo)
	guide_demo.configure(info, regular, Atmosphere.WORLDS[session.level.chapter], store.data.motion, touch_controls)
	guide_demo.board.custom_minimum_size.y = (150 if size.x < 360 else 180) * ui_scale()
	guide_demo.caption.add_theme_color_override("font_color", ink)
	var controls := HBoxContainer.new()
	content.add_child(controls)
	var playback := action("", guide_demo.toggle_playback)
	controls.add_child(playback)
	controls.add_child(spacer())
	controls.add_child(action("Next Step", guide_demo.next_step))
	guide_demo.playback_changed.connect(func():
		playback.text = tr("Pause Demo" if guide_demo.playing else "Play Demo"))
	guide_demo.playback_changed.emit()
	content.add_child(Control.new())
	_focus_dialog(close)
	_layout()

func _close_chapter_guide() -> void:
	_close_modal()
	for button in page.find_children("*", "Button", true, false):
		if button.accessibility_name == tr("Chapter Guide"):
			button.grab_focus()
	_refresh()

func show_help() -> void:
	var back: Callable = show_settings
	var silence: bool = screen == "game" and session.gates.any(func(gate): return not gate.vacant.is_empty())
	if screen == "game" and (not session.projections.is_empty() or silence or session.lava_groups > 0 or not session.turnstiles.is_empty() or not session.switches.is_empty() or session.plates.has(Puzzle.LENS) or not session.portals.is_empty() or not session.currents.is_empty()):
		var rules := PackedStringArray(["Choose a direction each beat. Tap Leave an Echo to record your route. Undo takes back a beat; Pause offers hints and Restart Room." if touch_controls else "Choose a direction each beat. Press Enter to leave an echo. Z undoes a beat. R restarts the room and clears all echoes."])
		if not session.portals.is_empty() or not session.currents.is_empty():
			rules.append("Matching portal rings connect distant tiles. Arrows carry you to an ordinary tile. A whole chain is one beat; if any part is blocked, the move is cancelled. Echoes remember the complete route.")
		if not session.projections.is_empty():
			rules.append("A projector makes its matching holographic tiles solid before your move. When its last occupant leaves, the light fades. You can step off a vanished tile; echoes finish their recorded routes.")
		if session.lava_groups > 0:
			rules.append("Lava advances one group per move. Match the dots on tiles to the cycle above the board. The triangle marks the group sinking next; choose a tile that is safe when you land. Invalid moves cost no beat.")
		if silence:
			rules.append("A gate marked −A needs A empty before you move. −L needs an empty lens; even one echo keeps it shut. A fading echo can open the way.")
		if session.plates.has(Puzzle.LENS):
			rules.append("L is a lens. Two selves on its tile open the L gate for the next move. Two echoes count, even when you are elsewhere.")
		if session.turnstiles.size() > session.controlled_turnstiles.size():
			rules.append("Cross an arrow in its marked direction. It reverses after the crossing.")
		if not session.direction_switches.is_empty():
			rules.append("A round arrow switch flips its linked one-way doors. Crossing a door does not turn it. Echoes can operate the switch from another branch.")
		if not session.switches.is_empty():
			rules.append("Step onto a diamond to swap the raised and folded bridges. If the bridge beneath you folds, you can step off it.")
		rules.append("Echoes follow their recorded routes and still trigger devices. If two actors trigger the same device on one beat, it changes once.")
		for i in rules.size():
			rules[i] = tr(rules[i])
		_dialog("help", "How to Play", "\n\n".join(rules), [["Got It", back]])
		return
	if touch_controls:
		_dialog("help", "How to Play", "Tap a direction on the pad, or an adjacent tile, to move one step. Each move advances one beat.\n\nTap Leave an Echo to record your route and return to the start. Your echo retraces your steps, then fades after its last move.\n\nA plate opens its matching gate. Guide the solid dot into the outlined square to finish.\n\nUndo takes back a step. Open Pause for hints or Restart Room.", [["Got It", back]])
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
	modal_panel.offset_left = -minf(size.x - (24 if compact_ui() else 52), modal_width * ui_scale())
	var panel_style := box(surface, edge, 26 * ui_scale())
	panel_style.set_corner_radius_all(0)
	panel_style.set_border_width_all(0)
	panel_style.border_width_left = 1
	modal_panel.add_theme_stylebox_override("panel", panel_style)
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
	modal_scroll = ScrollContainer.new()
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_scroll.follow_focus = true
	modal_panel.add_child(modal_scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_scroll.add_child(content)
	var pause_caption := text_label(tr("Room %s   /   %s") % [room_number(level_index), tr(session.level.title)], 16, muted)
	pause_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(pause_caption)
	content.add_child(text_label("Paused", 34))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	content.add_child(rows)
	var resume := list_action("Resume", _resume_game)
	rows.add_child(resume)
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
		title = tr("%s Complete") % tr(session.level.chapter)
	var next_label := "Next Room"
	var advance := open_level.bind(level_index + 1, true)
	if not has_next:
		if session.level.chapter == EXTRA:
			next_label = EXTRA
			advance = show_rooms.bind(EXTRA)
		else:
			next_label = "Chapters"
			advance = show_chapters
	elif at_boundary:
		next_label = "Next Chapter"
	_dialog("complete", title, tr("Beats  %d    ·    Echoes  %d") % [session.tick(), session.echoes.size()], [[next_label, advance], ["Undo", func(): _close_modal(); undo_move()]])


func _input(event: InputEvent) -> void:
	if title_card != null and ((event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)):
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
			elif modal_kind == "guide": _close_chapter_guide()
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
