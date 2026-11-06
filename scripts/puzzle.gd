extends RefCounted
## Deterministic, turn-based rules. A route contains the starting cell at t = 0.
## Gates use occupancy before a move; route exhaustion removes an echo on the
## next beat. Adding newer actors never invalidates an older recording.

const DIRECTIONS := {"U": Vector2i.UP, "D": Vector2i.DOWN, "L": Vector2i.LEFT, "R": Vector2i.RIGHT}
const LENS := "@"
var level: Dictionary
var floor_cells: Array[Vector2i] = []
var plates: Dictionary = {}
var gates: Array = []
var turnstiles: Array = []
var direction_switches: Dictionary = {}
var controlled_turnstiles: Array[int] = []
var switches: Array[Vector2i] = []
var bridges: Dictionary = {}
# Bit 0 selects the bridge bank. The remaining bits reverse individual arrows.
# Keep one state per beat so undo is exact even after every echo has faded.
var mechanism_history: Array[int] = [0]
var start := Vector2i.ZERO
var goal := Vector2i.ZERO
var columns := 0
var rows := 0
var echoes: Array = []
var draft: Array[Vector2i] = []
var edit_origin: Dictionary = {}

func _init(data: Dictionary = {}) -> void:
	if not data.is_empty():
		configure(data)

func configure(data: Dictionary) -> void:
	level = data.duplicate(true)
	floor_cells.clear()
	plates.clear()
	gates.clear()
	turnstiles.clear()
	direction_switches.clear()
	controlled_turnstiles.clear()
	for index in level.get("controlled_turnstiles", []): controlled_turnstiles.append(int(index))
	switches.clear()
	bridges.clear()
	rows = level.rows.size()
	columns = 0
	for y in rows:
		var line: String = level.rows[y]
		columns = maxi(columns, line.length())
		for x in line.length():
			var mark := line.substr(x, 1)
			if mark == "#":
				continue
			var cell := Vector2i(x, y)
			floor_cells.append(cell)
			if mark == "S":
				start = cell
			elif mark == "X":
				goal = cell
			elif mark == "*":
				switches.append(cell)
			elif mark == "!":
				pass # Direction switches are linked explicitly below.
			elif mark == "a" or mark == "b":
				bridges[cell] = 0 if mark == "a" else 1
			elif mark != ".":
				plates[mark] = cell
	for item in level.gates:
		gates.append({"a": Vector2i(int(item.a[0]), int(item.a[1])), "b": Vector2i(int(item.b[0]), int(item.b[1])), "requires": item.requires.duplicate(), "vacant": item.get("vacant", []).duplicate()})
	for edge in level.get("turnstiles", []):
		turnstiles.append([Vector2i(int(edge[0][0]), int(edge[0][1])), Vector2i(int(edge[1][0]), int(edge[1][1]))])
	for control in level.get("direction_switches", []):
		var mask := 0
		for index in control.turnstiles: mask |= 2 << int(index)
		direction_switches[Vector2i(int(control.at[0]), int(control.at[1]))] = mask
	reset_all()

func reset_all() -> void:
	echoes.clear()
	edit_origin.clear()
	restart_round()

func restart_round() -> void:
	draft.assign([start])
	mechanism_history.assign([0])

func tick() -> int:
	return draft.size() - 1

func player() -> Vector2i:
	return draft.back()

func cleared() -> bool:
	return player() == goal

func echo_position(index: int, at_tick: int = -1) -> Variant:
	var at := tick() if at_tick < 0 else at_tick
	if index < 0 or index >= echoes.size() or at >= echoes[index].size():
		return null
	return echoes[index][at]

func occupied() -> Array[Vector2i]:
	var result: Array[Vector2i] = [player()]
	for i in echoes.size():
		var position = echo_position(i)
		if position != null:
			result.append(position)
	return result

func plate_on(id: String) -> bool:
	if id == LENS:
		return plates.has(id) and occupied().count(plates[id]) >= 2
	return plates.has(id) and plates[id] in occupied()

func gate_open(gate: Dictionary) -> bool:
	for id in gate.requires:
		if not plate_on(id):
			return false
	for id in gate.vacant:
		if plates[id] in occupied():
			return false
	return true

func mechanism_state() -> int:
	return mechanism_history.back()

func bridge_active(cell: Vector2i, state: int) -> bool:
	return not bridges.has(cell) or bridges[cell] == (state & 1)

func turn_direction(index: int, state: int) -> Vector2i:
	var edge: Array = turnstiles[index]
	var direction: Vector2i = edge[1] - edge[0]
	return -direction if (state & (2 << index)) != 0 else direction

func _turn_index(origin: Vector2i, target: Vector2i) -> int:
	for i in turnstiles.size():
		var edge: Array = turnstiles[i]
		if (origin == edge[0] and target == edge[1]) or (origin == edge[1] and target == edge[0]):
			return i
	return -1

func _triggers(origin: Vector2i, target: Vector2i) -> int:
	var mask := 1 if target in switches else 0
	mask |= int(direction_switches.get(target, 0))
	var index := _turn_index(origin, target)
	if index >= 0 and index not in controlled_turnstiles:
		mask |= 2 << index
	return mask

func _state_after(at: int, origin: Vector2i, target: Vector2i) -> int:
	var triggered := _triggers(origin, target)
	for route in echoes:
		if at+1 < route.size():
			triggered |= _triggers(route[at], route[at+1])
	return mechanism_state() ^ triggered

func blocked_reason(delta: Vector2i) -> String:
	if cleared() or absi(delta.x) + absi(delta.y) != 1:
		return "No move available."
	var destination := player() + delta
	if destination not in floor_cells:
		return "No tile there."
	if not bridge_active(destination, mechanism_state()):
		return "This bridge is folded."
	var turn := _turn_index(player(), destination)
	if turn >= 0 and delta != turn_direction(turn, mechanism_state()):
		return "Follow the arrow."
	for gate in gates:
		if (player() == gate.a and destination == gate.b) or (player() == gate.b and destination == gate.a):
			if not gate_open(gate):
				if LENS in gate.requires and not plate_on(LENS):
					return "Two selves must meet on L."
				for id in gate.vacant:
					if plates[id] in occupied():
						return "Gate needs empty " + id.replace(LENS, "L")
				return "Gate requires " + " + ".join(PackedStringArray(gate.requires)).replace(LENS, "L")
	return ""

func can_move(delta: Vector2i) -> bool:
	return blocked_reason(delta).is_empty()

func move(delta: Vector2i) -> bool:
	if not can_move(delta):
		return false
	var target := player() + delta
	mechanism_history.append(_state_after(tick(), player(), target))
	draft.append(target)
	return true

func can_seal() -> bool:
	return draft.size() > 1 and echoes.size() < int(level.max_echoes) and not cleared()

func seal() -> bool:
	if not can_seal():
		return false
	echoes.append(draft.duplicate())
	edit_origin.clear()
	restart_round()
	return true

func can_undo() -> bool:
	return draft.size() > 1 or not echoes.is_empty()

func undo() -> bool:
	if draft.size() > 1:
		draft.pop_back()
		mechanism_history.pop_back()
		return true
	return _unseal_last()

func rerecord_last() -> bool:
	if echoes.is_empty():
		return false
	if edit_origin.is_empty():
		edit_origin = snapshot()
	return _unseal_last()

func cancel_edit() -> bool:
	if edit_origin.is_empty():
		return false
	return restore(edit_origin.duplicate(true))

func _unseal_last() -> bool:
	if echoes.is_empty():
		return false
	draft.assign(echoes.pop_back())
	mechanism_history.assign([0])
	for t in range(draft.size()-1):
		mechanism_history.append(_state_after(t, draft[t], draft[t+1]))
	return true

func actors() -> Array:
	var result: Array = [player()]
	for i in echoes.size():
		result.append(echo_position(i))
	return result

func snapshot() -> Dictionary:
	var recordings: Array = []
	for route in echoes:
		recordings.append(_encode(route))
	var result := {"version": 1, "level_id": level.id, "echoes": recordings, "draft": _encode(draft)}
	if not edit_origin.is_empty():
		result["edit_origin"] = edit_origin.duplicate(true)
	return result

func _encode(route: Array) -> Array:
	var result: Array = []
	for cell in route:
		result.append([cell.x, cell.y])
	return result

func _replay(encoded: Variant) -> bool:
	if not encoded is Array or encoded.is_empty():
		return false
	if not _valid_coordinate(encoded[0]) or Vector2i(int(encoded[0][0]), int(encoded[0][1])) != start:
		return false
	for i in range(1, encoded.size()):
		if not _valid_coordinate(encoded[i]):
			return false
		var target := Vector2i(int(encoded[i][0]), int(encoded[i][1]))
		if not move(target - player()):
			return false
	return true

func _valid_coordinate(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int) and value[0] == int(value[0]) and value[1] == int(value[1])

func restore(data: Dictionary) -> bool:
	# Validate in a temporary puzzle, including each recording against its prefix.
	if data.get("version") != 1 or data.get("level_id") != level.id:
		return false
	var records = data.get("echoes")
	if not records is Array or records.size() > int(level.max_echoes):
		return false
	var candidate = get_script().new(level)
	for route in records:
		if not candidate._replay(route) or not candidate.seal():
			return false
	if not candidate._replay(data.get("draft")):
		return false
	var origin = data.get("edit_origin", {})
	if not origin is Dictionary or origin.has("edit_origin"):
		return false
	if not origin.is_empty():
		var original = get_script().new(level)
		if not original.restore(origin):
			return false
	echoes = candidate.echoes.duplicate(true)
	draft.assign(candidate.draft)
	mechanism_history.assign(candidate.mechanism_history)
	edit_origin = origin.duplicate(true)
	return true
