extends Control
## Four generous touch targets, one deliberate move per press, no auto-repeat.
signal move_requested(delta: Vector2i)
var ink := Color("292d2e")
var rim := Color("405c6128")
var buttons: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var button := Button.new()
		button.accessibility_name = tr({Vector2i.UP: "Move up", Vector2i.DOWN: "Move down", Vector2i.LEFT: "Move left", Vector2i.RIGHT: "Move right"}[direction])
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.focus_mode = Control.FOCUS_NONE
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		button.pressed.connect(func(): move_requested.emit(direction))
		button.draw.connect(_draw_arrow.bind(button, direction))
		buttons[direction] = button
		add_child(button)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var unit := minf(size.x, size.y) / 3.0
	for direction in buttons:
		buttons[direction].size = Vector2.ONE * unit
		buttons[direction].position = size / 2 + Vector2(direction) * unit - Vector2.ONE * unit / 2
	queue_redraw()

func _draw() -> void:
	var center := size / 2
	draw_arc(center, minf(size.x, size.y) * 0.45, 0, TAU, 96, rim, 1.0, true)
	draw_circle(center, 2.5, Color(ink, 0.28), true, -1, true)

func _draw_arrow(button: Button, direction: Vector2i) -> void:
	var center := button.size / 2
	var forward := Vector2(direction)
	var side := forward.orthogonal()
	var color := ink if button.is_pressed() else Color(ink, 0.76)
	if button.is_pressed(): button.draw_circle(center, 21, Color(ink, 0.09), true, -1, true)
	button.draw_line(center - forward * 8, center + forward * 8, color, 1.8, true)
	button.draw_polyline(PackedVector2Array([center - forward * 0 + side * 6, center + forward * 8, center - side * 6]), color, 1.8, true)
