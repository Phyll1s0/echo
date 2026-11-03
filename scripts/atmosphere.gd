extends Control

# The background, floor, grid and active hardware share a palette. Actors
# and closed gates keep their original white silhouettes in every landscape.
const WORLDS := {
	"Afterimage": {"sky": Color("071510"), "far": Color("142d24"), "near": Color("0c211a"), "ink": Color("93bb97"), "tile": Color("172720"), "grid": Color("738e7e"), "light": Color("bfe6c6")},
	"Resonance": {"sky": Color("071620"), "far": Color("133748"), "near": Color("102a39"), "ink": Color("87becb"), "tile": Color("122833"), "grid": Color("6c90a1"), "light": Color("aee7f2")},
	"Phase Shift": {"sky": Color("1b1411"), "far": Color("3b2c23"), "near": Color("2c211c"), "ink": Color("d0a578"), "tile": Color("2c231d"), "grid": Color("a18a73"), "light": Color("f3d5aa")},
	"Penumbra": {"sky": Color("100e20"), "far": Color("2c2947"), "near": Color("1d1a30"), "ink": Color("aaa2d4"), "tile": Color("211f32"), "grid": Color("87849f"), "light": Color("dbd4ff")}
}

var animated := true
var clock := 0.0
var elapsed := 0.0
var chapter := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_chapter(value: String) -> void:
	chapter = value
	queue_redraw()

func _process(delta: float) -> void:
	if not animated:
		return
	elapsed += delta
	if elapsed >= 1.0 / 24.0:
		clock += elapsed
		elapsed = 0.0
		queue_redraw()

func _draw() -> void:
	if WORLDS.has(chapter):
		var colors: Dictionary = WORLDS[chapter]
		draw_rect(Rect2(Vector2.ZERO, size), colors.sky)
		match chapter:
			"Afterimage": _forest(colors)
			"Resonance": _ocean(colors)
			"Phase Shift": _desert(colors)
			"Penumbra": _eclipse(colors)
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var span := maxf(size.x, size.y)
	var center := Vector2(size.x * 0.14, size.y * 0.86)
	for i in 4:
		var radius := span * (0.33 + i * 0.12) + sin(clock * 0.12 + i) * 3
		draw_arc(center, radius, -1.72, 0.46, 150, Color(0.75, 0.82, 0.86, 0.055 + i * 0.006), 1.0, true)

# Fill the landscape down to the bottom edge, preserving the upper contour.
func _bank(line: PackedVector2Array, fill: Color, edge: Color) -> void:
	var polygon := line.duplicate()
	polygon.append(Vector2(size.x, size.y * 1.2))
	polygon.append(Vector2(0, size.y * 1.2))
	draw_colored_polygon(polygon, fill)
	draw_polyline(line, edge, 1.2, true)

func _forest(c: Dictionary) -> void:
	for layer in 2:
		var ridge := PackedVector2Array()
		for n in 65:
			var x := n / 64.0
			var y := 0.84 + layer * 0.105 - 0.045 * cos(x * TAU + layer)
			ridge.append(Vector2(x, y) * size)
		var fill: Color = c.far if layer == 0 else c.near
		_bank(ridge, fill, Color(c.ink, 0.20))
		for n in 27:
			var x := fmod(n * 0.0731 + layer * 0.027, 1.0)
			if x > 0.26 and x < 0.77: continue
			var y := 0.84 + layer * 0.105 - 0.045 * cos(x * TAU + layer)
			var h := size.y * (0.048 + 0.075 * absf(sin(n * 2.3 + layer)))
			var base := Vector2(x, y) * size
			var pine := PackedVector2Array()
			for pt in [Vector2(0,-1), Vector2(0.14,-0.54), Vector2(0.08,-0.59), Vector2(0.21,-0.25), Vector2(0.12,-0.32), Vector2(0.26,0.02), Vector2(-0.26,0.02), Vector2(-0.12,-0.32), Vector2(-0.21,-0.25), Vector2(-0.08,-0.59), Vector2(-0.14,-0.54)]:
				pine.append(base + pt * h)
			draw_colored_polygon(pine, fill)
			draw_line(base - Vector2(0,h), base + Vector2(-0.14,-0.54)*h, Color(c.ink, 0.23), 1, true)

func _ocean(c: Dictionary) -> void:
	var moon := Vector2(0.13, 0.29) * size
	var r := size.y * 0.036
	draw_circle(moon, r, c.far, true, -1, true)
	draw_arc(moon, r, PI*0.98, PI*1.93, 48, Color(c.ink, 0.55), 1.4, true)
	for layer in 4:
		var crest := PackedVector2Array()
		for n in 121:
			var x := n / 120.0
			var y := 0.77 + layer * 0.057 + 0.033 * sin(x * 8.0 + layer * 0.84) + 0.009 * sin(x * 18.0 + layer)
			crest.append(Vector2(x, y) * size)
		_bank(crest, c.far.lerp(c.near, layer / 3.0), Color(c.ink, 0.32))
		for n in range(6 + layer * 3, 110, 29):
			draw_line(crest[n] + Vector2(0,5), crest[n+4] + Vector2(0,5), Color(c.ink, 0.32), 1, true)

func _desert(c: Dictionary) -> void:
	var sun := Vector2(0.86, 0.24) * size
	var r := size.y * 0.058
	draw_circle(sun, r, c.far, true, -1, true)
	draw_arc(sun, r, PI, TAU, 64, Color(c.ink, 0.62), 1.4, true)
	for layer in 3:
		var ridge := PackedVector2Array()
		for n in 101:
			var x := n / 100.0
			var y := 0.78 + layer * 0.083 + 0.072 * sin(4.7*x - 1.08*layer) + 0.025 * sin(9.4*x - 2.16*layer)
			ridge.append(Vector2(x, y) * size)
		_bank(ridge, c.far.lerp(c.near, layer / 2.0), Color(c.ink, 0.39))
	# Short wind grooves follow the slip face of the nearest dune.
	for n in 8:
		var p := Vector2(0.07+n*0.017, 0.91+n*0.005) * size
		draw_line(p, p + Vector2(size.x*0.021, -size.y*0.018), Color(c.ink, 0.20), 1, true)

func _eclipse(c: Dictionary) -> void:
	var sun := Vector2(0.85, 0.24) * size
	var r := size.y * 0.052
	draw_arc(sun, r*1.35, 0, TAU, 72, Color(c.ink, 0.12), 1, true)
	draw_circle(sun, r, Color(c.ink, 0.56), true, -1, true)
	draw_circle(sun + Vector2(r*0.24,-r*0.08), r*0.98, c.sky, true, -1, true)
	draw_arc(sun + Vector2(r*0.24,-r*0.08), r*0.98, 0, TAU, 72, Color(c.ink, 0.22), 1, true)
	var stars := PackedVector2Array()
	for pos in [Vector2(0.035,0.62), Vector2(0.08,0.76), Vector2(0.16,0.71), Vector2(0.21,0.82), Vector2(0.27,0.78)]:
		stars.append(pos*size)
	draw_polyline(stars, Color(c.ink, 0.20), 1, true)
	for p in stars:
		draw_circle(p, 2.1, Color(c.ink, 0.67), true, -1, true)
	for n in 26:
		var p := Vector2(fmod(0.13+n*0.38197,1.0), fmod(0.08+n*0.2731,1.0))
		if p.x < 0.25 or p.x > 0.78:
			draw_circle(p * size, 1 + n % 2, Color(c.ink, 0.26), true, -1, true)
