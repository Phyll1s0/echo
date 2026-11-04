extends Control

var ink := Color("292d2e")
var muted := Color("626a6d")
var dim := Color("969c9d")
var accent := Color("405c61")
var surface := Color("fcfcfb")
var edge := Color("d6dad8")
var dark := false
var regular: Font
var thin: Font

func setup_skin() -> void:
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	regular = preload("res://assets/fonts/Poppins-Regular.ttf").duplicate()
	thin = preload("res://assets/fonts/Poppins-Thin.ttf").duplicate()
	regular.fallbacks = [fallback]
	thin.fallbacks = [fallback]
	var skin := Theme.new()
	skin.default_font = regular
	skin.default_font_size = 15
	var bare := StyleBoxEmpty.new()
	bare.content_margin_left = 13
	bare.content_margin_right = 13
	bare.content_margin_top = 7
	bare.content_margin_bottom = 7
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		skin.set_stylebox(state, "Button", bare)
	skin.set_constant("separation", "VBoxContainer", 8)
	skin.set_constant("separation", "HBoxContainer", 12)
	theme = skin
	apply_palette(false)

func apply_palette(night: bool) -> void:
	dark = night
	ink = Color("f2f4f3") if dark else Color("292d2e")
	muted = Color("b2b9bc") if dark else Color("626a6d")
	dim = Color("858e93") if dark else Color("969c9d")
	accent = Color("d9e3e5") if dark else Color("405c61")
	surface = Color("101214") if dark else Color("fcfcfb")
	edge = Color("41474c") if dark else Color("d6dad8")
	theme.set_color("font_color", "Label", ink)
	theme.set_color("font_color", "Button", ink)
	for state in ["hover", "focus", "pressed", "hover_pressed"]:
		theme.set_color("font_" + state + "_color", "Button", Color.WHITE if dark else Color("101617"))
	theme.set_color("font_disabled_color", "Button", dim)
	for state in ["normal", "hover", "focus", "pressed", "hover_pressed"]:
		theme.set_color("icon_" + state + "_color", "Button", ink)
	theme.set_color("icon_disabled_color", "Button", dim)

func box(fill: Color, edge: Color, margin: float = 13) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func text_label(value: String, px: int = 16, color: Color = Color.TRANSPARENT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = tr(value)
	node.horizontal_alignment = align
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_meta("base_px", px)
	node.add_theme_font_size_override("font_size", roundi(px * ui_scale()))
	node.add_theme_color_override("font_color", ink if color == Color.TRANSPARENT else color)
	return node

func action(value: String, callback: Callable, width: float = 0, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = tr(value)
	button.custom_minimum_size = Vector2(width, 40 * ui_scale())
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	if primary:
		button.set_meta("base_px", 18)
		button.add_theme_font_size_override("font_size", roundi(18 * ui_scale()))
		button.add_theme_color_override("font_color", ink)
	button.draw.connect(_draw_action_line.bind(button))
	return button

func _draw_action_line(button: Button) -> void:
	if button.disabled or not (button.is_hovered() or button.has_focus() or button.button_pressed):
		return
	var px := button.get_theme_font_size("font_size")
	var width := button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var y := button.size.y * 0.5 + px * 0.66
	if button.text.is_empty():
		# Icon buttons and chapter titles use a short mark below their content.
		width = 20 * ui_scale()
		y = button.size.y - 2
	var x := (button.size.x - width) * 0.5
	if button.alignment == HORIZONTAL_ALIGNMENT_LEFT:
		x = button.get_theme_stylebox("normal").get_content_margin(SIDE_LEFT)
	button.draw_line(Vector2(x, y), Vector2(x + width, y), accent, 1.0, true)

func spacer(horizontal: bool = true) -> Control:
	var space := Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if horizontal:
		space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return space

func list_action(value: String, callback: Callable) -> Button:
	var button := action(value, callback)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return button

func home_action(value: String, callback: Callable) -> Button:
	var button := action(value, callback)
	button.set_meta("base_px", 22)
	button.add_theme_color_override("font_color", ink)
	return button

func ui_scale() -> float:
	return clampf(minf(size.x / 1280.0, size.y / 820.0), 0.86, 2.25)

func rescale_text(node: Node) -> void:
	if node.has_meta("base_px"):
		node.add_theme_font_size_override("font_size", roundi(int(node.get_meta("base_px")) * ui_scale()))
	if node.has_meta("icon_px"):
		node.add_theme_constant_override("icon_max_width", roundi(int(node.get_meta("icon_px")) * ui_scale()))
	for child in node.get_children():
		rescale_text(child)
