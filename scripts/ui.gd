extends Control

const INK := Color("f2f6f8")
const MUTED := Color("b2bec7")
const DIM := Color("8996a0")
const ACCENT := Color("cbe1ed")
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
	skin.set_color("font_disabled_color", "Button", Color("7e8991"))
	skin.set_stylebox("normal", "Button", box(Color("101214"), Color("56616a")))
	skin.set_stylebox("hover", "Button", box(Color("252c31"), Color("acbac4")))
	skin.set_stylebox("pressed", "Button", box(Color("293137"), ACCENT))
	skin.set_stylebox("disabled", "Button", box(Color("0b0c0d"), Color("343b40")))
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

# Quiet navigation: the underline defines the row; the full surface still takes focus.
func list_action(value: String, callback: Callable) -> Button:
	var button := action(value, callback)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal", "hover", "pressed", "disabled"]:
		var highlighted: bool = state in ["hover", "pressed"]
		var style := box(Color("1b2024") if highlighted else Color.TRANSPARENT, MUTED if highlighted else Color("40494f"), 12)
		style.set_border_width_all(0)
		style.border_width_bottom = 1
		style.set_corner_radius_all(0)
		button.add_theme_stylebox_override(state, style)
	return button

func quiet_action(value: String, callback: Callable) -> Button:
	var button := action(value, callback)
	button.flat = true
	return button

func home_action(value: String, callback: Callable) -> Button:
	var button := action(value, callback)
	button.set_meta("base_px", 22)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		button.add_theme_stylebox_override(state, empty)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE)
	button.draw.connect(func():
		if not (button.is_hovered() or button.has_focus()): return
		var font := button.get_theme_font("font")
		var px := button.get_theme_font_size("font_size")
		var half_width := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x * 0.5
		var baseline := Vector2(button.size.x * 0.5, button.size.y * 0.5 + px * 0.66)
		button.draw_line(baseline - Vector2(half_width, 0), baseline + Vector2(half_width, 0), Color.WHITE, 1.0, true))
	return button

func ui_scale() -> float:
	return clampf(minf(size.x / 1280.0, size.y / 820.0), 0.86, 2.25)

func rescale_text(node: Node) -> void:
	if node.has_meta("base_px"):
		node.add_theme_font_size_override("font_size", roundi(int(node.get_meta("base_px")) * ui_scale()))
	for child in node.get_children():
		rescale_text(child)
