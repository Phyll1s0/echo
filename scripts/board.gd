extends Control
## A view of the puzzle; animations never write to the rules.
signal move_requested(delta: Vector2i)
signal motion_finished
signal inspection_changed(message: String)

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
var selected_portal := VOID_CELL
var selected_gate := -1
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
	var stretch := 1.0
	if not puzzle.draft_steps.is_empty():
		stretch = minf(2.5, 1.0 + (puzzle.draft_steps.back().path.size() - 2) * 0.3)
	phase = minf(1.0, phase + delta / (move_seconds * stretch))
	queue_redraw()
	if phase >= 1.0:
		set_process(false)
		motion_finished.emit()

func cell_size() -> float:
	if puzzle == null:
		return 1.0
	return maxf(1.0, minf(size.x / (puzzle.columns + 0.85), (size.y - _lava_header()) / (puzzle.rows + 0.8)))

func _lava_header() -> float:
	return minf(32.0, size.y * 0.16) if puzzle != null and puzzle.lava_groups > 0 else 0.0

func origin() -> Vector2:
	return (size - Vector2(0, _lava_header()) - Vector2(puzzle.columns, puzzle.rows) * cell_size()) * 0.5 + Vector2(0, _lava_header())

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
		var gate_index := gate_at(event.position)
		selected_gate = -1
		selected_plate = ""
		selected_switch = VOID_CELL
		selected_portal = VOID_CELL
		if gate_index >= 0:
			selected_gate = gate_index
			inspection_changed.emit("Gate requires " + gate_condition(puzzle.gates[gate_index]))
		elif absi(delta.x) + absi(delta.y) == 1 and cell in puzzle.floor_cells:
			move_requested.emit(delta)
		elif cell in puzzle.plates.values():
			selected_plate = puzzle.plates.find_key(cell)
			if cell in puzzle.portals: selected_portal = cell
		elif cell in puzzle.switches or cell in puzzle.direction_switches:
			selected_switch = cell
		elif cell in puzzle.portals:
			selected_portal = cell
		queue_redraw()
		accept_event()

func gate_at(point: Vector2) -> int:
	if puzzle == null: return -1
	var unit := cell_size()
	for i in puzzle.gates.size():
		var gate: Dictionary = puzzle.gates[i]
		var a := center_of(gate.a)
		var b := center_of(gate.b)
		var middle := (a+b) * 0.5
		var half := (b-a).normalized().orthogonal() * unit * 0.38
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, middle-half, middle+half)) < maxf(5, unit * 0.10): return i
	return -1

func gate_condition(gate: Dictionary) -> String:
	var parts: Array[String] = []
	for id in gate.requires: parts.append(str(id).replace(puzzle.LENS, "L"))
	var result := " + ".join(parts)
	for id in gate.vacant: result += ("  " if not result.is_empty() else "") + "−" + str(id).replace(puzzle.LENS, "L")
	return result

func _highlight_cell(cell: Vector2i, unit: float) -> void:
	var rect := Rect2(center_of(cell) - Vector2.ONE * unit * 0.44, Vector2.ONE * unit * 0.88)
	draw_rect(rect, Color(active, 0.10))
	draw_rect(rect, active, false, maxf(1.6, unit * 0.025), true)

func _draw_tile_edges(cell: Vector2i, rect: Rect2, color: Color, unit: float) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var neighbors := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for i in 4:
		var outside: bool = cell + neighbors[i] not in puzzle.floor_cells
		draw_line(corners[i], corners[(i+1)%4], Color(color, 0.90 if outside else 0.32), maxf(1.3, unit * 0.018) if outside else 0.8, true)

func _draw_plate(id: String, unit: float) -> void:
	var cell: Vector2i = puzzle.plates[id]
	var center := center_of(cell)
	var enabled: bool = puzzle.plate_on(id)
	var color: Color = active if enabled else muted
	if id == puzzle.LENS:
		draw_circle(center, unit * 0.25, Color(active, 0.12 if enabled else 0.025), true, -1, true)
		for side in [-1,1]:
			draw_arc(center + Vector2(side * unit * 0.075, 0), unit * 0.17, 0, TAU, 40, color, maxf(1.6, unit * 0.023), true)
		return
	var r := unit * 0.25
	draw_circle(center, r, Color(active, 0.16 if enabled else 0.025), true, -1, true)
	draw_arc(center, r, 0, TAU, 48, color, maxf(1.5, unit * 0.022), true)
	var px := maxi(11, roundi(unit * 0.24))
	var width := font.get_string_size(id, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var base := center + Vector2(-width * 0.5, px * 0.35)
	if cell in puzzle.occupied():
		px = maxi(10, roundi(unit * 0.18))
		base = center + Vector2(-unit * 0.39, -unit * 0.29)
	draw_string(font, base, id, HORIZONTAL_ALIGNMENT_LEFT, -1, px, active if enabled else ink)

func condition_layout(gate: Dictionary) -> Array:
	var cell: Vector2i = gate.b if gate.a == puzzle.goal else gate.a
	if gate.b != puzzle.goal and cell in puzzle.plates.values(): cell = gate.b
	var unit := cell_size()
	var center := center_of(cell) + Vector2(0, -unit * 0.31)
	var exit_gates: Array = puzzle.gates.filter(func(g): return g.a == puzzle.goal or g.b == puzzle.goal)
	if exit_gates.size() > 1 and gate in exit_gates and exit_gates.all(func(g): return g.requires == gate.requires and g.vacant == gate.vacant):
		# Equal entrances share a single condition, centred above the exit.
		if gate != exit_gates[0]: return []
		center = center_of(puzzle.goal) + Vector2(0, -unit * 0.65)
	var radius := unit * 0.10 if unit < 26 else clampf(unit * 0.12, 4.4, 10)
	var gap := maxf(1.5, unit * 0.045)
	var result: Array = []
	var span := 0.0
	for vacant in [false, true]:
		for id in gate.vacant if vacant else gate.requires:
			var minus := unit * 0.12 if vacant else 0.0
			result.append({"id": str(id), "vacant": vacant, "center": Vector2(span + minus + radius, 0), "radius": radius, "minus": minus})
			span += radius * 2 + minus + gap
	span -= gap
	for item in result: item.center += center - Vector2(span * 0.5, 0)
	return result

func _draw_gate_conditions(gate: Dictionary, unit: float, highlighted: bool) -> void:
	for item in condition_layout(gate):
		var center: Vector2 = item.center
		var r: float = item.radius
		var met: bool = not puzzle.plate_on(item.id) if item.vacant else puzzle.plate_on(item.id)
		if item.vacant: met = puzzle.plates[item.id] not in puzzle.occupied()
		var color: Color = active if met or highlighted else muted
		if unit < 26:
			draw_circle(center, maxf(1.1, r * 0.70), color, not item.vacant, 1.0 if item.vacant else -1.0, true)
			continue
		draw_circle(center, r + 1, floor_color, true, -1, true)
		if item.id == puzzle.LENS:
			for side in [-1, 1]: draw_arc(center + Vector2(side * r * 0.30, 0), r * 0.62, 0, TAU, 24, color, 1.0, true)
		else:
			var px := maxi(11, roundi(unit * 0.18))
			var width := font.get_string_size(item.id, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			draw_string(font, center + Vector2(-width * 0.5, px * 0.34), item.id, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
		if item.vacant:
			draw_line(center - Vector2(r + item.minus, 0), center - Vector2(r + 1, 0), color, 1.4, true)

# Printed scenery sits behind every tile; it never covers a door or marks a move.
func _draw_room_print(unit: float) -> void:
	var centre := center_of(Vector2i(puzzle.columns >> 1, puzzle.rows >> 1))
	var line := Color(active, 0.27)
	match puzzle.level.get("art", ""):
		"sugar_spiral":
			var candy := center_of(Vector2i(4, 3))
			var ribbon := PackedVector2Array()
			for i in 121:
				var t := i / 120.0
				var angle := 1.5 + t * TAU * 1.55
				ribbon.append(candy + Vector2.from_angle(angle) * lerpf(0.24, 4.0, t) * unit)
			draw_polyline(ribbon, Color(active, 0.17), maxf(2.2, unit * 0.11), true)
			draw_arc(candy, 3.92 * unit, 0.14, TAU - 0.12, 120, line, 1.4, true)
		"afterglow":
			var outline := PackedVector2Array()
			for n in 8:
				var radius := (4.28 if n % 2 == 0 else 1.85) * unit
				outline.append(centre + Vector2.from_angle(n * TAU / 8 - PI/2) * radius)
			outline.append(outline[0])
			draw_polyline(outline, Color(active, 0.34), maxf(1.2, unit * 0.027), true)
		"cloudbreak":
			for cell in [Vector2i(2,2),Vector2i(4,1),Vector2i(6,2),Vector2i(10,3)]:
				var crest := center_of(cell)
				draw_arc(crest, unit * 1.15, PI * 1.04, TAU * 0.98, 40, Color(active,0.22), maxf(1.1, unit*0.03), true)
		"ferris_wheel":
			var radius := unit * 3.88
			for side in [-1,1]:
				var foot := centre + Vector2(side * 2.35, 4.45) * unit
				draw_line(centre, foot, Color(active, 0.38), maxf(1.4, unit * 0.045), true)
				draw_line(foot - Vector2(unit*0.32,0), foot + Vector2(unit*0.32,0), line, 2, true)
			draw_arc(centre, radius, 0, TAU, 128, line, maxf(1.3, unit * 0.036), true)
			draw_arc(centre, radius - unit * 0.18, 0, TAU, 128, Color(active, 0.14), 1, true)
			for n in 8:
				var tip := centre + Vector2.from_angle(n * TAU / 8) * radius
				draw_line(centre, tip, Color(active, 0.17), maxf(1, unit*0.024), true)
				var cabin := Rect2(tip + Vector2(-0.21,0.18)*unit, Vector2(0.42,0.26)*unit)
				draw_line(tip, tip + Vector2.DOWN * unit * 0.18, line, 1, true)
				draw_rect(cabin, floor_color)
				draw_rect(cabin, line, false, 1.2, true)
		"rose_window":
			for n in 4:
				var dir := Vector2.from_angle(n * TAU / 4)
				var normal := dir.orthogonal()
				var pane := PackedVector2Array()
				for j in 64:
					var theta := TAU*j/64.0
					var axial := (1.0 - cos(theta))*0.5
					var width := sin(theta) * (0.62 + axial * 0.55)
					pane.append(centre + (dir * (0.75 + axial * 4.25) + normal * width) * unit)
				draw_colored_polygon(pane, Color(Color("9e82bb") if n%2 == 0 else Color("72aaaa"), 0.22))
				pane.append(pane[0])
				draw_polyline(pane, Color(active,0.30), 1.2, true)

func _draw() -> void:
	if puzzle == null or font == null:
		return
	var unit := cell_size()
	var gap := clampf(unit * 0.045, 2.0, 5.5)
	var player: Vector2i = puzzle.player()
	var state: int = puzzle.mechanism_state()
	var inspected := selected_plate
	if hover in puzzle.plates.values(): inspected = puzzle.plates.find_key(hover)
	var linked_switch: Vector2i = hover if hover in puzzle.switches or hover in puzzle.direction_switches else selected_switch
	var inspected_portal: Vector2i = hover if hover in puzzle.portals else selected_portal
	var inspected_gate := gate_at(get_local_mouse_position()) if hover != VOID_CELL else -1
	if inspected_gate < 0: inspected_gate = selected_gate
	if puzzle.level.has("art"): _draw_room_print(unit)
	if puzzle.lava_groups > 0: _draw_lava_cycle()
	for cell in puzzle.floor_cells:
		var rect := Rect2(center_of(cell) - Vector2.ONE * (unit - gap) * 0.5, Vector2.ONE * (unit - gap))
		if puzzle.lava.has(cell):
			_draw_lava(cell, rect)
			continue
		if puzzle.bridges.has(cell):
			_draw_bridge(cell, rect, state)
			continue
		var fill := floor_color
		match puzzle.level.get("art", ""):
			"sugar_spiral":
				if cell.y >= 8 or posmod(cell.x - cell.y, 5) <= 1:
					fill = floor_color.lerp(Color("fff8ed"), 0.70)
			"cloudbreak":
				fill = floor_color.lerp(Color.WHITE, 0.28 if cell.y < 4 else 0.12)
			"afterglow":
				var glow: float = 0.18 if puzzle.plate_on("A") else 0.045
				fill = floor_color.lerp(Color("f6dcb5"), glow)
		var edge := grid_color
		if cell == hover and puzzle.can_move(cell - player):
			fill = floor_color.lerp(active, 0.14)
			edge = muted
		draw_rect(rect, fill)
		_draw_tile_edges(cell, rect, edge, unit)
	for cell in puzzle.portals:
		_draw_portal(cell, unit)
	for cell in puzzle.currents:
		_draw_current(center_of(cell), Vector2(puzzle.currents[cell]), unit)
	if inspected_portal in puzzle.portals:
		_highlight_cell(inspected_portal, unit)
		_highlight_cell(puzzle.portals[inspected_portal], unit)
	if hover != VOID_CELL:
		var preview: Dictionary = puzzle.resolve_move(hover - player)
		if preview.reason.is_empty() and preview.path.size() > 2:
			_draw_transit(preview, Color(active, 0.55))
			var landing := center_of(preview.path.back())
			draw_rect(Rect2(landing - Vector2.ONE * unit * 0.43, Vector2.ONE * unit * 0.86), active, false, 2, true)
	if linked_switch in puzzle.switches:
		for cell in puzzle.bridges: _highlight_cell(cell, unit)
	elif linked_switch in puzzle.direction_switches:
		for i in puzzle.turnstiles.size():
			if int(puzzle.direction_switches[linked_switch]) & (2 << i):
				var midpoint := (center_of(puzzle.turnstiles[i][0]) + center_of(puzzle.turnstiles[i][1])) * 0.5
				draw_circle(midpoint, unit * 0.19, Color(active, 0.16), true, -1, true)
	for cell in puzzle.switches:
		_draw_switch(center_of(cell), unit, state)
	for cell in puzzle.direction_switches:
		_draw_direction_switch(center_of(cell), unit)
	for id in puzzle.plates:
		var cell: Vector2i = puzzle.plates[id]
		_draw_plate(id, unit)
		if id == inspected: _highlight_cell(cell, unit)
		if inspected_gate >= 0 and (id in puzzle.gates[inspected_gate].requires or id in puzzle.gates[inspected_gate].vacant):
			_highlight_cell(cell, unit)
	var exit_center := center_of(puzzle.goal)
	var exit_rect := Rect2(exit_center - Vector2.ONE * unit * 0.205, Vector2.ONE * unit * 0.41)
	draw_rect(exit_rect, ink, false, maxf(1.3, unit * 0.019), true)
	var start_center := center_of(puzzle.start)
	draw_circle(start_center, unit * 0.065, Color(muted, 0.55), false, 1, true)
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
		var highlighted: bool = i == inspected_gate or inspected in gate.requires or inspected in gate.vacant
		if highlighted:
			draw_line(middle - end, middle + end, Color(active, 0.35), width + 5, true)
		_draw_gate_conditions(gate, unit, highlighted)

	# Keep the direction readable when an edge also has a pressure condition.
	for i in puzzle.turnstiles.size():
		_draw_turnstile(i, unit, state)
	if show_routes:
		for i in puzzle.echoes.size():
			for step in puzzle.echo_steps[i]:
				_draw_transit(step, Color(muted, path_opacity))
	var now: Array = puzzle.actors()
	var eased := smoothstep(0.0, 1.0, phase)
	# Draw older actors first, then the solid player on top of overlapping rings.
	for n in range(now.size() - 1, -1, -1):
		var target = now[n]
		var old = previous[n] if n < previous.size() and phase < 1.0 else target
		if target == null and (old == null or phase >= 1.0):
			continue
		var center := center_of(old if target == null else target)
		var scale_ := 1.0
		var visibility := 1.0
		if old != null and target != null:
			var pose := _actor_pose(n, old, target)
			center = pose.center
			scale_ = pose.scale
			visibility = pose.alpha
		if n == 0:
			var radius := unit * 0.125 * scale_
			draw_circle(center, radius, Color(player_fill, visibility), true, -1, true)
			draw_arc(center, radius, 0, TAU, 64, Color(piece_edge, visibility), maxf(1.6, unit * 0.024), true)
		else:
			var alpha := (1.0 - eased if target == null else 1.0) * visibility
			var radius := unit * (0.18 + (n - 1) * 0.065) * scale_
			var width := maxf(2.0, unit * 0.036)
			# Separate the echo ring from a plate or bridge underneath it.
			draw_arc(center, radius, 0, TAU, 64, Color(piece_shadow, alpha), width + 2.0, true)
			draw_arc(center, radius, 0, TAU, 64, Color(piece_edge if n == 1 else second_echo_edge, alpha), width, true)

func _actor_pose(index: int, old: Vector2i, target: Vector2i) -> Dictionary:
	var result := {"center": center_of(target), "scale": 1.0, "alpha": 1.0}
	if phase >= 1.0: return result
	var step: Dictionary = puzzle.actor_step(index)
	if step.is_empty() or step.path.front() != old or step.path.back() != target:
		result.center = center_of(old).lerp(center_of(target), smoothstep(0, 1, phase))
		return result
	var progress: float = phase * (step.path.size() - 1)
	var segment := mini(floori(progress), step.path.size() - 2)
	var fraction := smoothstep(0, 1, progress - segment)
	if segment + 1 in step.jumps:
		result.center = center_of(step.path[segment] if fraction < 0.5 else step.path[segment+1])
		result.alpha = absf(fraction * 2 - 1)
		result.scale = lerpf(0.2, 1.0, result.alpha)
	else:
		result.center = center_of(step.path[segment]).lerp(center_of(step.path[segment+1]), fraction)
	return result

func _draw_transit(step: Dictionary, color: Color) -> void:
	for j in range(1, step.path.size()):
		if j not in step.jumps:
			draw_dashed_line(center_of(step.path[j-1]), center_of(step.path[j]), color, 1.3, 5.0, true, true)

func _draw_portal(cell: Vector2i, unit: float) -> void:
	var center := center_of(cell)
	var overlay: bool = cell in puzzle.plates.values() or cell in puzzle.currents
	var r := unit * (0.38 if overlay else 0.31)
	var color := active if puzzle.portal_labels[cell] == "I" else muted
	if not overlay: draw_circle(center, r, Color(color, 0.035), true, -1, true)
	for side in 2:
		var begin := side * PI + 0.28
		var span := PI * (0.42 if overlay else 0.70)
		draw_arc(center, r, begin, begin + span, 40, color, maxf(1.6, unit * 0.025), true)
		var tip := center + Vector2.from_angle(begin + span) * r
		draw_circle(tip, maxf(1.7, unit * 0.025), color, true, -1, true)
	var px := maxi(11, roundi(unit * (0.16 if overlay else 0.23)))
	var width := font.get_string_size(puzzle.portal_labels[cell], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var base := center + Vector2(unit * 0.39 - width, unit * 0.37) if overlay or cell in puzzle.occupied() else center + Vector2(-width * 0.5, px * 0.35)
	draw_string(font, base, puzzle.portal_labels[cell], HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)

func _draw_current(center: Vector2, direction: Vector2, unit: float) -> void:
	var normal := direction.orthogonal()
	draw_line(center - direction * unit * 0.40, center + direction * unit * 0.40, Color(active, 0.12), unit * 0.16, true)
	var tip := center + direction * unit * 0.12
	draw_polyline(PackedVector2Array([tip - direction * unit * 0.17 + normal * unit * 0.14, tip, tip - direction * unit * 0.17 - normal * unit * 0.14]), active, maxf(1.7, unit * 0.025), true)

func _draw_lava_cycle() -> void:
	var count: int = puzzle.lava_groups
	var y := _lava_header() * 0.5
	var radius := minf(10.0, y * 0.65)
	for group in count:
		var centre := Vector2(size.x * 0.5 + (group - (count - 1) * 0.5) * 34, y)
		var current: bool = group == puzzle.lava_phase()
		var next: bool = group == puzzle.lava_phase(puzzle.tick() + 1)
		if current: draw_circle(centre, radius, Color("ff8155"), true, -1, true)
		else: draw_arc(centre, radius, 0, TAU, 40, Color("ffc18a") if next else grid_color, 1.3, true)
		draw_string(font, centre + Vector2(-3.5, 4), str(group + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("251216") if current else ink)
		if next:
			var tip := centre + Vector2(0, radius + 2)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-3, 4), tip + Vector2(3, 4)]), Color("ffc18a"))

func _draw_lava(cell: Vector2i, rect: Rect2) -> void:
	var unit := cell_size()
	var group: int = puzzle.lava[cell]
	var hot: bool = group == puzzle.lava_phase()
	var warning: bool = group == puzzle.lava_phase(puzzle.tick() + 1)
	var heat := 1.0 if hot else 0.0
	if phase < 1.0:
		var old_hot: bool = group == puzzle.lava_phase(puzzle.tick() - 1)
		heat = lerpf(1.0 if old_hot else 0.0, heat, smoothstep(0.0, 1.0, phase))
	draw_rect(rect, floor_color.lerp(Color("79291f"), heat))
	draw_rect(rect, Color("ffc18a") if warning else grid_color.lerp(Color("ff8155"), heat), false, maxf(1.3, unit * (0.035 if warning else 0.018)), true)
	if heat > 0:
		draw_line(rect.get_center() + Vector2(-0.20,0.05) * unit, rect.get_center() + Vector2(0.20,0.05) * unit, Color(Color("ff9b64"), heat * 0.7), maxf(1.3, unit * 0.025), true)
	if warning:
		var corner := rect.position + Vector2(rect.size.x - unit * 0.09, unit * 0.09)
		draw_colored_polygon(PackedVector2Array([corner, corner + Vector2(-0.14, 0) * unit, corner + Vector2(0, 0.14) * unit]), Color("ffc18a"))
	for n in group + 1:
		var point := rect.position + Vector2(unit * (0.12 + n * 0.12), rect.size.y - unit * 0.12)
		draw_circle(point, maxf(1.0, unit * 0.022), Color("ffc18a") if warning else ink, true, -1, true)

func _draw_direction_switch(center: Vector2, unit: float) -> void:
	var r := unit * 0.25
	draw_arc(center, r, 0, TAU, 64, active, maxf(1.5, unit * 0.025), true)
	for side in [-1, 1]:
		var a := center + Vector2(-0.17 * side, -0.09 * side) * unit
		var b := center + Vector2(0.17 * side, -0.09 * side) * unit
		draw_line(a, b, active, 1.6, true)
		draw_polyline(PackedVector2Array([b + Vector2(-0.07 * side, -0.06) * unit, b, b + Vector2(-0.07 * side, 0.06) * unit]), active, 1.6, true)

func _draw_switch(center: Vector2, unit: float, state: int) -> void:
	var r := unit * 0.24
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
	var horizontal: bool = cell + Vector2i.LEFT in puzzle.floor_cells or cell + Vector2i.RIGHT in puzzle.floor_cells
	var deck := rect.grow(-unit * 0.04)
	if horizontal: deck.size.y *= 0.20 + 0.80 * strength
	else: deck.size.x *= 0.20 + 0.80 * strength
	deck.position = center - deck.size * 0.5
	draw_rect(deck, floor_color.lerp(active, 0.04 + 0.10 * strength))
	draw_rect(deck, Color(grid_color, 0.65 + 0.35 * strength), false, maxf(1.2, unit * 0.018), true)
	for n in [-1, 1]:
		var offset := Vector2(n * unit * 0.16, 0) if horizontal else Vector2(0, n * unit * 0.16)
		var half := Vector2(0, deck.size.y * 0.34) if horizontal else Vector2(deck.size.x * 0.34, 0)
		draw_line(center + offset - half, center + offset + half, Color(active, 0.38 + 0.30 * strength), maxf(1.0, unit * 0.018), true)

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
	# One rim denotes a self-reversing door. Controlled doors use a quiet dot.
	if index not in puzzle.controlled_turnstiles:
		draw_arc(middle, unit * 0.19, 0.35, TAU - 0.35, 40, Color(muted, 0.65), maxf(1, unit * 0.014), true)
	else:
		draw_circle(middle - dir * unit * 0.16, maxf(1.3, unit * 0.025), active, true, -1, true)
	var tip := middle + dir*unit*0.135
	draw_line(middle-dir*unit*0.13, tip, active, maxf(1.5,unit*0.032), true)
	draw_polyline(PackedVector2Array([tip-dir*unit*0.09+normal*unit*0.085, tip, tip-dir*unit*0.09-normal*unit*0.085]), active, maxf(1.5,unit*0.032), true)
