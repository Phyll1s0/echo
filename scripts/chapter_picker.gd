extends ScrollContainer
## A vertically scrolling chapter reel. Real buttons keep keyboard and screen
## reader navigation available; pointer gestures cancel taps during a swipe.
signal selected_changed(index: int)
signal chapter_opened(index: int)
const TAP_SLOP := 8.0
const FLICK_MEMORY_MS := 110
const WHEEL_SETTLE := 0.16

var index: VBoxContainer
var margin: MarginContainer
var entries: Array[Button] = []
var visuals: Array[Control] = []
var selected := 0
var stride := 180.0
var animated := true
var scale_factor := 1.0
var sliding: Tween
var touching := false
var idle := 0.0
var last_scroll := 0
var ready_layout := false
var pointer_id := -1
var pointer_start := Vector2.ZERO
var pointer_scroll := 0
var pointer_distance := 0.0
var sample_y := 0.0
var sample_ms := 0
var speed_y := 0.0
var scroll_position := 0.0
var last_wheel_ms := -1000

func _ready() -> void:
	clip_contents = true
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	follow_focus = false
	scroll_deadzone = 9
	resized.connect(_reflow)

func build(owner_ui, chapters: Array[String], start: int) -> void:
	animated = owner_ui.store.data.motion
	scale_factor = owner_ui.ui_scale()
	margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(margin)
	index = VBoxContainer.new()
	index.add_theme_constant_override("separation", 0)
	margin.add_child(index)
	for i in chapters.size():
		var chapter: String = chapters[i]
		var row := Button.new()
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.accessibility_name = tr(chapter)
		row.accessibility_description = owner_ui._chapter_label(chapter)
		row.pressed.connect(func(): chapter_opened.emit(i), CONNECT_DEFERRED)
		row.focus_entered.connect(func():
			if selected != i: center_on(i, true))
		index.add_child(row)
		entries.append(row)
		var centre := CenterContainer.new()
		centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(centre)
		centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var heading = owner_ui._chapter_heading(chapter, HORIZONTAL_ALIGNMENT_CENTER)
		centre.add_child(heading)
		heading.get_child(0).set_meta("base_px", 14 if owner_ui.compact_ui() else 17)
		heading.get_child(1).set_meta("base_px", 32 if owner_ui.compact_ui() else 48)
		visuals.append(centre)
	for i in entries.size():
		entries[i].focus_neighbor_top = entries[i].get_path_to(entries[maxi(0, i-1)])
		entries[i].focus_neighbor_bottom = entries[i].get_path_to(entries[mini(entries.size()-1, i+1)])
	selected = clampi(start, 0, entries.size() - 1)
	_reflow.call_deferred()

func _reflow() -> void:
	if entries.is_empty() or size.y < 1: return
	if sliding != null: sliding.kill()
	stride = roundf(clampf(size.y * 0.34, 112 * scale_factor, 260 * scale_factor))
	var padding := maxi(0, roundi((size.y - stride) * 0.5))
	margin.add_theme_constant_override("margin_top", padding)
	margin.add_theme_constant_override("margin_bottom", padding)
	for row in entries: row.custom_minimum_size.y = stride
	ready_layout = false
	_finish_reflow.call_deferred()

func _finish_reflow() -> void:
	scroll_vertical = roundi(selected * stride)
	scroll_position = scroll_vertical
	last_scroll = scroll_vertical
	ready_layout = true
	entries[selected].grab_focus()
	_update_visuals()

func center_on(which: int, ease: bool = false) -> void:
	if entries.is_empty(): return
	if sliding != null: sliding.kill()
	selected = clampi(which, 0, entries.size() - 1)
	selected_changed.emit(selected)
	entries[selected].grab_focus()
	var target := roundi(selected * stride)
	if animated and ease and absi(scroll_vertical - target) > 1:
		sliding = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		sliding.tween_property(self, "scroll_vertical", target, 0.19)
	else:
		scroll_vertical = target
	scroll_position = target
	idle = 0

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not ready_layout: return
	if event is InputEventScreenTouch:
		if event.pressed and get_global_rect().has_point(event.position):
			if not touching:
				_begin_pointer(event.position)
				pointer_id = event.index
			get_viewport().set_input_as_handled()
		elif not event.pressed and touching and pointer_id == event.index:
			_end_pointer(event.position, event.canceled)
			get_viewport().set_input_as_handled()
	if event is InputEventScreenDrag and touching and event.index == pointer_id:
		_drag_pointer(event.position)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and touching and pointer_id == -1:
		_drag_pointer(event.position)
		get_viewport().set_input_as_handled()
	if event is InputEventPanGesture and get_global_rect().has_point(event.position):
		_scroll_by(event.delta.y * stride * 0.24)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and (touching or get_global_rect().has_point(event.position)):
			if event.pressed and not touching:
				pointer_id = -1
				_begin_pointer(event.position)
			elif not event.pressed and touching and pointer_id == -1:
				_end_pointer(event.position)
			get_viewport().set_input_as_handled()
		if event.pressed and get_global_rect().has_point(event.position) and event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
			var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
			# Godot supplies smaller factors for high-resolution wheel input.
			var amount: float = event.factor if event.factor > 0 else 1.0
			var now := Time.get_ticks_msec()
			# One notched click should clear the midpoint; a sustained stream
			# uses a smaller gain without discarding any following events.
			var gain := 0.73 if now - last_wheel_ms > 160 and is_equal_approx(amount, 1.0) else 0.40
			last_wheel_ms = now
			_scroll_by(direction * stride * gain * minf(3.0, amount))
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		var code: Key = event.physical_keycode if event.physical_keycode else event.keycode
		if code in [KEY_ENTER, KEY_KP_ENTER]:
			chapter_opened.emit.call_deferred(selected)
			get_viewport().set_input_as_handled()
		if code in [KEY_UP, KEY_DOWN, KEY_HOME, KEY_END]:
			var target := selected + (1 if code == KEY_DOWN else -1)
			if code == KEY_HOME: target = 0
			elif code == KEY_END: target = entries.size() - 1
			center_on(target, true)
			get_viewport().set_input_as_handled()

func _begin_pointer(point: Vector2) -> void:
	touching = true
	pointer_start = point
	pointer_scroll = scroll_vertical
	pointer_distance = 0
	sample_y = point.y
	sample_ms = Time.get_ticks_msec()
	speed_y = 0
	if sliding != null: sliding.kill()

func _scroll_by(amount: float) -> void:
	if sliding != null and sliding.is_running():
		sliding.kill()
		scroll_position = scroll_vertical
	scroll_position = clampf(scroll_position + amount, 0.0, (entries.size() - 1) * stride)
	scroll_vertical = roundi(scroll_position)
	idle = 0
	_track_selection()

func _track_selection() -> void:
	var nearest := clampi(roundi(scroll_vertical / stride), 0, entries.size()-1)
	if selected != nearest:
		selected = nearest
		selected_changed.emit(selected)
		entries[selected].grab_focus()

func _drag_pointer(point: Vector2) -> void:
	pointer_distance = maxf(pointer_distance, point.distance_to(pointer_start))
	if pointer_distance < TAP_SLOP: return
	# Match the finger's travel in pixels; only the two ends limit how far it goes.
	scroll_position = clampf(pointer_scroll + pointer_start.y - point.y, 0.0, (entries.size()-1)*stride)
	scroll_vertical = roundi(scroll_position)
	_track_selection()
	var now := Time.get_ticks_msec()
	if not is_equal_approx(sample_y, point.y):
		speed_y = (sample_y - point.y) * 1000.0 / maxf(16.0, now - sample_ms)
		sample_y = point.y
		sample_ms = now

func _end_pointer(point: Vector2, canceled: bool = false) -> void:
	_drag_pointer(point)
	touching = false
	if pointer_distance >= TAP_SLOP or canceled:
		var coast := 0.0
		if animated and not canceled and Time.get_ticks_msec() - sample_ms < FLICK_MEMORY_MS:
			coast = clampf(speed_y * 0.09, -stride * 0.65, stride * 0.65)
		center_on(roundi((scroll_vertical + coast) / stride), true)
	elif get_global_rect().has_point(point):
		var tapped := roundi((scroll_vertical + point.y - get_global_rect().get_center().y) / stride)
		chapter_opened.emit.call_deferred(clampi(tapped, 0, entries.size() - 1))
	idle = 0

func _process(delta: float) -> void:
	if not ready_layout: return
	_update_visuals()
	if scroll_vertical != last_scroll:
		idle = 0
		last_scroll = scroll_vertical
	else: idle += delta
	if not touching and idle > WHEEL_SETTLE and (sliding == null or not sliding.is_running()):
		var nearest := clampi(roundi(scroll_vertical / stride), 0, entries.size() - 1)
		if absi(scroll_vertical - roundi(nearest * stride)) > 1 or nearest != selected:
			center_on(nearest, true)

func _update_visuals() -> void:
	for i in visuals.size():
		var distance := absf((i * stride - scroll_vertical) / stride)
		visuals[i].pivot_offset = visuals[i].size * 0.5
		visuals[i].scale = Vector2.ONE * lerpf(1.0, 0.70, minf(distance, 1.5) / 1.5)
		visuals[i].modulate.a = clampf(1.0 - distance * 0.66, 0.04, 1.0)
	queue_redraw()

func _draw() -> void:
	if entries.is_empty(): return
	for i in entries.size():
		var centre := Vector2(size.x - 4, size.y * 0.5 + (i - (entries.size() - 1) * 0.5) * 13)
		var color := Color("405c61") if i == selected else Color("d4d9d7")
		draw_line(centre + Vector2(0, -3 if i == selected else -1), centre + Vector2(0, 3 if i == selected else 1), color, 2, true)
