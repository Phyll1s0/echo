extends Control

var animated := true
var clock := 0.0
var elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if not animated:
		return
	elapsed += delta
	if elapsed >= 1.0 / 24.0:
		clock += elapsed
		elapsed = 0.0
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var span := maxf(size.x, size.y)
	var center := Vector2(size.x * 0.14, size.y * 0.86)
	for i in 4:
		var radius := span * (0.33 + i * 0.12) + sin(clock * 0.12 + i) * 3
		draw_arc(center, radius, -1.72, 0.46, 150, Color(0.75, 0.82, 0.86, 0.055 + i * 0.006), 1.0, true)
