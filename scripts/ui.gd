extends Control

const INK := Color("e7ebee")
const MUTED := Color("9aa4ac")
const DIM := Color("717c85")
const ACCENT := Color("bbd1de")
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
	skin.set_color("font_color", "Label", INK)
	skin.set_color("font_color", "Button", INK)
	skin.set_color("font_hover_color", "Button", Color.WHITE)
	skin.set_color("font_pressed_color", "Button", ACCENT)
	skin.set_color("font_disabled_color", "Button", Color("616970"))
	skin.set_stylebox("normal", "Button", box(Color("101214"), Color("373d42")))
	skin.set_stylebox("hover", "Button", box(Color("20252a"), Color("87929b")))
	skin.set_stylebox("pressed", "Button", box(Color("293137"), ACCENT))
	skin.set_stylebox("disabled", "Button", box(Color("0b0c0d"), Color("26292b")))
	skin.set_stylebox("focus", "Button", box(Color.TRANSPARENT, Color("9aa8b1")))
	skin.set_constant("separation", "VBoxContainer", 8)
	skin.set_constant("separation", "HBoxContainer", 12)
	theme = skin

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

func text_label(value: String, px: int = 16, color: Color = INK, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = value
	node.horizontal_alignment = align
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_meta("base_px", px)
	node.add_theme_font_size_override("font_size", roundi(px * ui_scale()))
	node.add_theme_color_override("font_color", color)
	return node

func action(value: String, callback: Callable, width: float = 0, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(width, 40 * ui_scale())
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	if primary:
		button.add_theme_stylebox_override("normal", box(Color("d5dfe5"), Color("d5dfe5")))
		button.add_theme_stylebox_override("hover", box(Color("eff4f6"), Color.WHITE))
		button.add_theme_stylebox_override("pressed", box(ACCENT, ACCENT))
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(key, Color("141719"))
	return button

func spacer(horizontal: bool = true) -> Control:
	var space := Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if horizontal:
		space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return space

func ui_scale() -> float:
	return clampf(minf(size.x / 1280.0, size.y / 820.0), 0.86, 2.25)

func rescale_text(node: Node) -> void:
	if node.has_meta("base_px"):
		node.add_theme_font_size_override("font_size", roundi(int(node.get_meta("base_px")) * ui_scale()))
	for child in node.get_children():
		rescale_text(child)
