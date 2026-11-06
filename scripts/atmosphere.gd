extends Control

# Quiet landscapes on paper, an ink-black chapter, and a coral-pink fairground.
const WORLDS := {
	"Afterimage": {"sky": Color("f2f6ef"), "far": Color("dce7d8"), "near": Color("c9dac6"), "ink": Color("617f63"), "tile": Color("e0eadb"), "grid": Color("6f866f"), "light": Color("335f40")},
	"Resonance": {"sky": Color("f0f5f8"), "far": Color("d8e6ee"), "near": Color("c1d7e3"), "ink": Color("567d92"), "tile": Color("deebf2"), "grid": Color("6b8697"), "light": Color("2d607a")},
	"Phase Shift": {"sky": Color("faf5eb"), "far": Color("ecdfc5"), "near": Color("dfccaa"), "ink": Color("92764b"), "tile": Color("efe2c9"), "grid": Color("96805b"), "light": Color("7d572e")},
	"Penumbra": {"sky": Color("f5f2f9"), "far": Color("e4ddef"), "near": Color("d5c9e2"), "ink": Color("806c9d"), "tile": Color("e8dff1"), "grid": Color("877599"), "light": Color("63477d")},
	"Extra": {"sky": Color("f1f0ec"), "far": Color("dfded7"), "near": Color("d4d2c9"), "ink": Color("646864"), "tile": Color("e4e3da"), "grid": Color("7e8176"), "light": Color("595940")},
	"Wonderland": {"sky": Color("fff4f3"), "far": Color("f5dce0"), "near": Color("ecc3cd"), "ink": Color("b66b80"), "tile": Color("f2d5dc"), "grid": Color("a5687b"), "light": Color("923c56")},
	"Nocturne": {"dark": true, "sky": Color("08090a"), "far": Color("111315"), "near": Color("171a1c"), "ink": Color("899295"), "tile": Color("171a1c"), "grid": Color("748083"), "light": Color("e3e8e8")}
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
			"Nocturne": _nocturne(colors)
			"Wonderland": _wonderland(colors)
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("fcfcfb"))
	# Sparse dots suggest the echo rings, leaving a clean centre for the title.
	var span := maxf(size.x, size.y)
	var spacing := maxf(18, span / 64)
	for row in range(ceili(size.y / spacing)):
		for col in range(ceili(size.x / spacing)):
			var point := Vector2((col + 0.5) * spacing, (row + 0.5) * spacing)
			var quiet := smoothstep(0.18, 0.48, point.distance_to(size * 0.5) / span)
			var wave := 0.5 + 0.5 * sin(point.distance_to(size * Vector2(0.16, 0.86)) * 0.023 - clock * 0.05)
			draw_circle(point, 0.8, Color(0.35, 0.42, 0.42, quiet * (0.025 + wave * 0.045)), true, -1, true)

func _wonderland(c: Dictionary) -> void:
	# A still Ferris wheel and low scalloped canopies, outside the playing field.
	var centre := Vector2(0.88, 0.23) * size
	var radius := minf(size.x * 0.075, size.y * 0.085)
	draw_arc(centre, radius, 0, TAU, 72, Color(c.ink, 0.30), 1.2, true)
	for i in 8:
		var tip := centre + Vector2.from_angle(i * TAU / 8) * radius
		draw_line(centre, tip, Color(c.ink, 0.20), 1, true)
		draw_circle(tip, radius * 0.085, c.far, true, -1, true)
		draw_arc(tip, radius * 0.085, 0, TAU, 20, Color(c.ink, 0.38), 1, true)
	for side in [-1, 1]:
		draw_line(centre, centre + Vector2(side * radius * 0.55, radius * 1.6), Color(c.ink, 0.25), 1.2, true)
	for layer in 2:
		var ridge := PackedVector2Array()
		for n in 121:
			var x := n / 120.0
			var y := 0.91 + layer * 0.065 - 0.026 * cos(x * TAU * 3 + layer)
			ridge.append(Vector2(x, y) * size)
		_bank(ridge, c.far if layer == 0 else c.near, Color(c.ink, 0.24))

func _nocturne(c: Dictionary) -> void:
	var centre := Vector2(0.13, 0.25) * size
	var radius := size.y * 0.063
	draw_arc(centre, radius, 0, TAU, 80, Color(c.ink, 0.20), 1, true)
	draw_circle(centre + Vector2(radius, 0), 2.0, Color(c.light, 0.68), true, -1, true)
	for layer in 5:
		var line := PackedVector2Array()
		for n in 101:
			var x := n / 100.0
			var y := 0.87 + layer * 0.029 + 0.012 * sin(x * 9.0 + layer * 0.22)
			line.append(Vector2(x, y) * size)
		draw_polyline(line, Color(c.ink, 0.10 + layer * 0.018), 1, true)

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
