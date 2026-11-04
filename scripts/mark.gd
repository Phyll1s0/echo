extends Control

var clock := 0.0
var elapsed := 0.0
var motion := true
var ink := Color("292d2e")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if not motion:
		return
	elapsed += delta
	if elapsed > 1.0 / 24.0:
		clock += elapsed
		elapsed = 0.0
		queue_redraw()

func _draw() -> void:
	var r := minf(size.y * 0.33, size.x * 0.13)
	var shift := r * (0.49 + 0.07 * sin(clock * 0.5))
	for i in 3:
		var c := size * 0.5 + Vector2((i - 1) * shift, 0)
		draw_arc(c, r, 0, TAU, 96, Color(ink, 0.18 + i * 0.3), 1.5, true)
	draw_circle(size * 0.5 + Vector2(shift, 0), maxf(2, r * 0.13), ink, true, -1, true)
