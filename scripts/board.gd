extends Control
## A view of the puzzle; animations never write to the rules.
signal move_requested(delta: Vector2i)
signal motion_finished

var ink := Color("f2f6f8")
var muted := Color("abb9c3")
var active := Color("c7e0ec")
var player_fill := Color("e5f0f7")
var floor_color := Color("161a1d")
var grid_color := Color("6a7780")
var piece_edge := Color.WHITE
var second_echo_edge := Color("d5efff")
var piece_shadow := Color("0c1115")
const VOID_CELL := Vector2i(-999, -999)
var puzzle
var font: Font
var show_routes := false
var path_opacity := 0.5
var motion := true
var move_seconds := 0.13
var selected_plate := ""
var selected_switch := VOID_CELL
var hover := VOID_CELL
var previous: Array = []
var previous_gates: Array = []
var previous_mechanisms := 0
var phase := 1.0

func set_colors(colors: Dictionary) -> void:
	floor_color = colors.tile
	grid_color = colors.grid
	active = colors.light
	var night: bool = colors.get("dark", false)
	ink = Color("f2f4f3") if night else Color("242d30")
	muted = Color("abb9c3") if night else Color("66777c")
	player_fill = Color("e5f0f7") if night else Color("263135")
	piece_edge = Color.WHITE if night else Color("17262a")
	second_echo_edge = Color("d5efff") if night else Color("53696f")
	piece_shadow = Color("0c1115") if night else Color("fffefa")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 145)
	resized.connect(queue_redraw)
	mouse_exited.connect(func(): hover = VOID_CELL; queue_redraw())
	set_process(false)

func animate_from(actors: Array, gates: Array, mechanisms: int) -> void:
	previous = actors
	previous_gates = gates
	previous_mechanisms = mechanisms
	phase = 0.0 if motion else 1.0
	set_process(phase < 1.0)
	queue_redraw()

func cancel_animation() -> void:
	phase = 1.0
	previous.clear()
	previous_gates.clear()
	set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	phase = minf(1.0, phase + delta / move_seconds)
	queue_redraw()
	if phase >= 1.0:
		set_process(false)
		motion_finished.emit()

func cell_size() -> float:
	if puzzle == null:
		return 1.0
	return maxf(1.0, minf(size.x / (puzzle.columns + 0.85), size.y / (puzzle.rows + 0.8)))

func origin() -> Vector2:
	return (size - Vector2(puzzle.columns, puzzle.rows) * cell_size()) * 0.5

func center_of(cell: Vector2i) -> Vector2:
	return origin() + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size()

func cell_at(point: Vector2) -> Vector2i:
	var local := (point - origin()) / cell_size()
	return Vector2i(floori(local.x), floori(local.y))

func _gui_input(event: InputEvent) -> void:
	if puzzle == null:
		return
	if event is InputEventMouseMotion:
		var cell := cell_at(event.position)
		if cell != hover:
			hover = cell
			queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := cell_at(event.position)
		var delta: Vector2i = cell - puzzle.player()
		if absi(delta.x) + absi(delta.y) == 1 and cell in puzzle.floor_cells:
			move_requested.emit(delta)
		elif cell in puzzle.plates.values():
			var id: String = puzzle.plates.find_key(cell)
			selected_plate = "" if selected_plate == id else id
			selected_switch = VOID_CELL
		elif cell in puzzle.switches or cell in puzzle.direction_switches:
			selected_switch = VOID_CELL if selected_switch == cell else cell
			selected_plate = ""
		else:
			selected_plate = ""
			selected_switch = VOID_CELL
		queue_redraw()
		accept_event()

func _draw() -> void:
	if puzzle == null or font == null:
		return
	var unit := cell_size()
	var gap := clampf(unit * 0.045, 2.0, 5.5)
	var text_size := maxi(11, roundi(unit * 0.18))
	var player: Vector2i = puzzle.player()
	var state: int = puzzle.mechanism_state()
	for cell in puzzle.floor_cells:
		var rect := Rect2(center_of(cell) - Vector2.ONE * (unit - gap) * 0.5, Vector2.ONE * (unit - gap))
		if puzzle.bridges.has(cell):
			_draw_bridge(cell, rect, state)
			continue
		var fill := floor_color
		var edge := grid_color
		if cell == hover and puzzle.can_move(cell - player):
			fill = floor_color.lerp(active, 0.14)
			edge = muted
		draw_rect(rect, fill)
		draw_rect(rect, edge, false, maxf(1.0, unit * 0.012), true)
	var linked_switch: Vector2i = hover if hover in puzzle.switches or hover in puzzle.direction_switches else selected_switch
	if linked_switch in puzzle.switches:
		for cell in puzzle.bridges:
			draw_dashed_line(center_of(linked_switch), center_of(cell), Color(active, 0.38), 1.25, 5.0, true, true)
	elif linked_switch in puzzle.direction_switches:
		for i in puzzle.turnstiles.size():
			if int(puzzle.direction_switches[linked_switch]) & (2 << i):
				var midpoint := (center_of(puzzle.turnstiles[i][0]) + center_of(puzzle.turnstiles[i][1])) * 0.5
				draw_dashed_line(center_of(linked_switch), midpoint, Color(active, 0.5), 1.25, 5.0, true, true)
	for cell in puzzle.switches:
		_draw_switch(center_of(cell), unit, state)
	for cell in puzzle.direction_switches:
		_draw_direction_switch(center_of(cell), unit)
	var inspected := selected_plate
	if hover in puzzle.plates.values():
		inspected = puzzle.plates.find_key(hover)
	for gate in puzzle.gates:
		if inspected in gate.requires or inspected in gate.vacant:
			var midpoint := (center_of(gate.a) + center_of(gate.b)) * 0.5
			draw_dashed_line(center_of(puzzle.plates[inspected]), midpoint, Color(active, 0.4), 1.25, 5.0, true, true)
	for id in puzzle.plates:
		var center := center_of(puzzle.plates[id])
		var enabled: bool = puzzle.plate_on(id)
		var r := unit * 0.30
		var edge: Color = active if enabled else muted
		var caption: String = id
		if id == puzzle.LENS:
			caption = "L"
			draw_circle(center, r, Color(active, 0.24 if enabled else 0.045), true, -1, true)
			for side in [-1,1]:
				draw_arc(center + Vector2(side*r*0.39,0), r*0.77, 0, TAU, 48, edge, maxf(1.6, unit*0.024), true)
		else:
			draw_circle(center, r, Color(active, 0.11 if enabled else 0.035), true, -1, true)
			draw_arc(center, r, 0, TAU, 64, edge, maxf(1.3, unit * 0.018), true)
		var base := center + Vector2(-unit * 0.38, -unit * 0.25)
		draw_string(font, base, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, edge)
	var exit_center := center_of(puzzle.goal)
	var exit_rect := Rect2(exit_center - Vector2.ONE * unit * 0.205, Vector2.ONE * unit * 0.41)
	draw_rect(exit_rect, ink, false, maxf(1.3, unit * 0.019), true)
	var start_center := center_of(puzzle.start)
	draw_circle(start_center, unit * 0.065, Color(muted, 0.55), false, 1, true)
	var exit_gates: Array = puzzle.gates.filter(func(gate): return gate.a == puzzle.goal or gate.b == puzzle.goal)
	for i in puzzle.gates.size():
		var gate: Dictionary = puzzle.gates[i]
		var a := center_of(gate.a)
		var b := center_of(gate.b)
		var middle := (a + b) * 0.5
		var normal := (b - a).normalized().orthogonal()
		var end := normal * unit * 0.45
		var open: bool = previous_gates[i] if phase < 1.0 and i < previous_gates.size() else puzzle.gate_open(gate)
		var width := maxf(2.2, unit * 0.04)
		if open:
			draw_line(middle - end, middle - end * 0.72, active, width, true)
			draw_line(middle + end, middle + end * 0.72, active, width, true)
		else:
			draw_line(middle - end, middle + end, ink, width, true)
		var name := "+".join(PackedStringArray(gate.requires))
		for id in gate.vacant:
			name += ("  " if not name.is_empty() else "") + "−" + id
		name = name.replace(puzzle.LENS, "L")
		var anchor := middle + Vector2(5.0, -unit * 0.49) if absf(a.y - b.y) < 1.0 else middle + Vector2(unit * 0.53, -3)
		var caption_size := maxi(11, roundi(unit * 0.15))
		if exit_gates.size() > 1 and gate in exit_gates:
			# Place each caption on its own approach instead of crowding the exit.
			var outside: Vector2i = gate.a if gate.b == puzzle.goal else gate.b
			var width_px := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x
			var tile_center := center_of(outside)
			anchor = tile_center + Vector2(-width_px / 2, -unit * 0.26)
		draw_string(font, anchor, name, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size, active if open else muted)
	# Keep the direction readable when an edge also has a pressure condition.
	for i in puzzle.turnstiles.size():
		_draw_turnstile(i, unit, state)
	if show_routes:
		for i in puzzle.echoes.size():
			var route: Array = puzzle.echoes[i]
			for j in range(1, route.size()):
				draw_dashed_line(center_of(route[j-1]), center_of(route[j]), Color(muted, path_opacity), 1.3, 5.0, true, true)
	var now: Array = puzzle.actors()
	var eased := smoothstep(0.0, 1.0, phase)
	# Draw older actors first, then the solid player on top of overlapping rings.
	for n in range(now.size() - 1, -1, -1):
		var target = now[n]
		var old = previous[n] if n < previous.size() and phase < 1.0 else target
		if target == null and (old == null or phase >= 1.0):
			continue
		var center := center_of(old if target == null else target)
		if old != null and target != null:
			center = center_of(old).lerp(center_of(target), eased)
		if n == 0:
			var radius := unit * 0.125
			draw_circle(center, radius, player_fill, true, -1, true)
			draw_arc(center, radius, 0, TAU, 64, piece_edge, maxf(1.6, unit * 0.024), true)
		else:
			var alpha := 1.0 - eased if target == null else 1.0
			var radius := unit * (0.18 + (n - 1) * 0.065)
			var width := maxf(2.0, unit * 0.036)
			# Separate the echo ring from a plate or bridge underneath it.
			draw_arc(center, radius, 0, TAU, 64, Color(piece_shadow, alpha), width + 2.0, true)
			draw_arc(center, radius, 0, TAU, 64, Color(piece_edge if n == 1 else second_echo_edge, alpha), width, true)

func _draw_direction_switch(center: Vector2, unit: float) -> void:
	var r := unit * 0.31
	draw_arc(center, r, 0, TAU, 64, active, maxf(1.5, unit * 0.025), true)
	for side in [-1, 1]:
		var a := center + Vector2(-0.17 * side, -0.09 * side) * unit
		var b := center + Vector2(0.17 * side, -0.09 * side) * unit
		draw_line(a, b, active, 1.6, true)
		draw_polyline(PackedVector2Array([b + Vector2(-0.07 * side, -0.06) * unit, b, b + Vector2(-0.07 * side, 0.06) * unit]), active, 1.6, true)

func _draw_switch(center: Vector2, unit: float, state: int) -> void:
	var r := unit * 0.32
	var diamond := PackedVector2Array([center + Vector2.UP*r, center + Vector2.RIGHT*r, center + Vector2.DOWN*r, center + Vector2.LEFT*r, center + Vector2.UP*r])
	draw_polyline(diamond, active, maxf(1.4, unit*0.025), true)
	var side := Vector2.LEFT if (state & 1) == 0 else Vector2.RIGHT
	draw_colored_polygon(PackedVector2Array([center + Vector2.UP*r*0.82, center + side*r*0.82, center + Vector2.DOWN*r*0.82]), Color(active, 0.4))

func _draw_bridge(cell: Vector2i, rect: Rect2, state: int) -> void:
	var raised: bool = puzzle.bridge_active(cell, state)
	var strength := 1.0 if raised else 0.0
	if phase < 1.0 and puzzle.bridge_active(cell, previous_mechanisms) != raised:
		strength = lerpf(1.0-strength, strength, smoothstep(0.0, 1.0, phase))
	var unit := cell_size()
	var center := rect.get_center()
	# The rails expand into a deck. A folded bridge leaves only two short rails.
	var deck := rect.grow(-unit*0.04)
	deck.size.y *= 0.22 + 0.78*strength
	deck.position.y = center.y - deck.size.y*0.5
	draw_rect(deck, floor_color.lerp(active, 0.04 + 0.18*strength))
	draw_rect(deck, Color(muted, 0.56+0.42*strength), false, maxf(1.2,unit*0.022), true)
	var slope := 1 if puzzle.bridges[cell] == 0 else -1
	for n in [-1, 0, 1]:
		var x: float = center.x + n*unit*0.20
		draw_line(Vector2(x-unit*0.08, center.y-slope*deck.size.y*0.30), Vector2(x+unit*0.08, center.y+slope*deck.size.y*0.30), Color(active, 0.3+0.4*strength), maxf(1.0,unit*0.021), true)

func _draw_turnstile(index: int, unit: float, state: int) -> void:
	var edge: Array = puzzle.turnstiles[index]
	var middle := (center_of(edge[0]) + center_of(edge[1])) * 0.5
	var dir := Vector2(puzzle.turn_direction(index, state))
	var normal := dir.orthogonal()
	var half := unit*0.36
	draw_line(middle-normal*half, middle+normal*half, muted, maxf(1.3,unit*0.025), true)
	if phase < 1.0 and puzzle.turn_direction(index, previous_mechanisms) != puzzle.turn_direction(index, state):
		dir = Vector2(puzzle.turn_direction(index, previous_mechanisms)).rotated(PI*smoothstep(0.0, 1.0, phase))
	normal = dir.orthogonal()
	draw_circle(middle, unit*0.21, floor_color, true, -1, true)
	draw_arc(middle, unit*0.21, 0, TAU, 48, muted, maxf(1,unit*0.014), true)
	if index in puzzle.controlled_turnstiles:
		# A second rim matches the linked switch and distinguishes it from a turnstile.
		draw_arc(middle, unit*0.26, 0, TAU, 48, Color(active, 0.55), maxf(1,unit*0.012), true)
	var tip := middle + dir*unit*0.135
	draw_line(middle-dir*unit*0.13, tip, active, maxf(1.5,unit*0.032), true)
	draw_polyline(PackedVector2Array([tip-dir*unit*0.09+normal*unit*0.085, tip, tip-dir*unit*0.09-normal*unit*0.085]), active, maxf(1.5,unit*0.032), true)
