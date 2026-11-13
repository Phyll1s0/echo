extends VBoxContainer
## Small, isolated puzzles replayed by the same rules and renderer as the game.
signal playback_changed

const Puzzle = preload("res://scripts/puzzle.gd")
const Board = preload("res://scripts/board.gd")
const PAGES := {
	"Afterimage": [{
		"title": "Leave an Echo",
		"body": "Each move advances one beat. Choose Leave an Echo to save your route and return to the start.\nThe hollow ring replays your steps, then fades one beat after its route ends.",
		"rows": ["#A###", "#.###", "#S..X"],
		"gates": [{"a": [3, 2], "b": [4, 2], "requires": ["A"]}],
		"steps": [
			["", "Move with the arrow keys or WASD. There is no time limit."],
			["U", "Walk a route to the plate."], ["U", "Now save this route with Leave an Echo."],
			["seal", "Back at the start. Your hollow echo remembers the route."],
			["R", "Your move also advances the echo one step."],
			["R", "The echo reaches A. The A gate opens."],
			["R", "Enter the outlined square to finish."]]
	}],
	"Resonance": [{
		"title": "Move Together",
		"body": "Record each route separately. Each new recording resets the beat; all echoes then move together.\nA + B opens only when both plates are occupied before your move.",
		"rows": ["A...B", "##.##", "##S..", "####X"],
		"gates": [{"a": [4, 2], "b": [4, 3], "requires": ["A", "B"]}],
		"recordings": ["UULL", "UURR"],
		"steps": [["", "Two routes recorded. Both begin at the same starting tile."],
			["R", "Both echoes advance with you."], ["L", "Backtracking takes a beat, too."],
			["R", "One echo takes the left branch; the other takes the right."],
			["R", "A and B are occupied together. The gate opens."],
			["D", "Cross on your next move."]]
	}],
	"Phase Shift": [{
		"title": "Arrow Gates",
		"body": "Cross an arrow gate in its marked direction. It reverses after the crossing.\nEchoes follow their recorded routes and can reverse arrows, too.",
		"rows": ["S..X"], "gates": [], "turnstiles": [[[1, 0], [2, 0]]],
		"steps": [["", "The arrow points to the right."], ["R", "Approach from the tail of the arrow."],
			["R", "Crossing turns the arrow to the left."], ["L", "You can now cross back to the left."],
			["R", "Each crossing reverses it again."], ["R", "Plan which direction you will need next."]]
	}, {
		"title": "Bridges",
		"body": "Step onto a diamond to swap the raised and folded bridges.\nEchoes trigger diamonds, too. Their recorded routes still cross bridges that have folded.",
		"rows": ["S*b.X", "##a##"], "gates": [],
		"steps": [["", "The bridge ahead is folded."], ["R", "The diamond raises one bank and folds the other."],
			["R", "You can enter the raised bridge."], ["R", "Another visit to a diamond would swap the banks again."],
			["R", "Watch both bridge banks when planning a route."]]
	}],
	"Penumbra": [{
		"title": "Meet on the Lens",
		"body": "L is a lens, marked by two overlapping circles. Two selves must share its tile to open an L gate.\nYou and an echo count, or two echoes while you move elsewhere.",
		"rows": ["##@.X", "##S##"],
		"gates": [{"a": [2, 0], "b": [3, 0], "requires": ["@"]}],
		"steps": [["", "Look for the overlapping circles."], ["U", "One self on L leaves the gate closed."],
			["seal", "Record that visit, then return to the lens."], ["U", "Two selves meet on L. The gate opens."],
			["R", "Cross on the next move, while L is active."], ["R", "The meeting only needs to last for the crossing."]]
	}],
	"Wonderland": [{
		"title": "Direction Switches",
		"body": "A round arrow switch flips its linked one-way doors. Crossing a door does not turn it.\nSend an echo to the switch while you take another branch.",
		"rows": ["!####", "S...X"], "gates": [],
		"turnstiles": [[[2, 1], [1, 1]]], "controlled_turnstiles": [0],
		"direction_switches": [{"at": [0, 0], "turnstiles": [0]}], "recordings": ["U"],
		"steps": [["", "The door faces left. An echo will visit the switch."],
			["R", "The echo steps on the switch. The door turns right."],
			["R", "Crossing leaves the arrow pointing right."],
			["R", "Only another switch visit can reverse it."],
			["R", "Plan when your echo should change the doors."]]
	}],
	"Inferno": [{
		"title": "Lava Cycle",
		"body": "Four groups take turns sinking. Match the dots on tiles to the numbered cycle.\nThe triangle marks the group sinking next. Land on a safe tile; a group can rise as you step onto it.",
		"rows": ["S2.X", "1.34"], "gates": [], "lava_groups": 4,
		"steps": [["", "Group 2 sinks next. Take the lower route."],
			["D", "Group 1 rises as group 2 sinks."],
			["R", "A detour advances the cycle, too."],
			["U", "Group 2 is safe again. You can step onto it."],
			["R", "The cycle repeats every four beats."],
			["R", "Take your time. Only your moves change the lava."]]
	}],
	"Slipstream": [{
		"title": "Portals",
		"body": "Matching broken rings form a portal pair. Step into either ring to appear at the other end on the same beat.\nThe exit does not send you straight back. Echoes remember the jump, too.",
		"rows": ["S.##.X"], "gates": [],
		"portals": [{"id": "I", "a": [1, 0], "b": [4, 0]}],
		"steps": [["", "The matching I rings connect these two islands."],
			["R", "One move takes you through both ends. Beat 1."],
			["R", "Step away from the exit ring normally."]]
	}, {
		"title": "Currents",
		"body": "Arrows carry you along until an ordinary tile. You cannot stop or steer in the middle.\nThe entire ride is one beat. A blocked gate or unsafe tile cancels the whole move.",
		"rows": ["S.>>>.X"], "gates": [],
		"steps": [["", "Approach the arrows."], ["R", "This ordinary step takes one beat."],
			["R", "The whole current takes one beat, too."],
			["R", "Your echoes advance once during a ride."]]
	}, {
		"title": "Chains",
		"body": "A portal exit can feed into a current, then another portal. Follow the chain to its final landing tile.\nEvery gate along the way uses the board before your move. The chain still costs only one beat.",
		"rows": ["S.####", "####>.", "###X.."], "gates": [],
		"portals": [{"id": "I", "a": [1, 0], "b": [4, 1]}, {"id": "II", "a": [5, 1], "b": [4, 2]}],
		"steps": [["", "One move can link two portal pairs."],
			["R", "Both jumps and the current cost one beat."],
			["L", "You stop on the first ordinary landing tile."]]
	}],
	"Looking Glass": [{
		"title": "Mirror Routes",
		"body": "An echo holds one wing while you climb the other. Look for the plate that opens the door across the mirror.",
		"rows": ["##X", "A#.", ".#.", ".S."],
		"gates": [{"a": [2, 1], "b": [2, 0], "requires": ["A"]}],
		"recordings": ["LUU"],
		"steps": [["", "An echo will climb the left wing. Take the right."],
			["R", "Each of you takes a different wing."],
			["U", "Climb in step with your reflection."],
			["U", "The echo reaches A. Your door opens."],
			["U", "Cross before the reflection fades."]]
	}],
	"Nocturne": [{
		"title": "Leave a Space",
		"body": "A gate marked −A needs A empty before you move. An echo can step away or fade to open it.\n−L needs a completely empty lens; even one self keeps it shut.",
		"rows": ["#A###", "#S..X"],
		"gates": [{"a": [2, 1], "b": [3, 1], "requires": ["A"]}, {"a": [3, 1], "b": [4, 1], "requires": [], "vacant": ["A"]}],
		"recordings": ["U"],
		"steps": [["", "This echo has a one-step route to A."], ["R", "A is occupied. A opens; −A stays closed."],
			["R", "Cross A. On this beat, the echo fades and −A opens."], ["R", "With A empty, you can cross −A."]]
	}]
}

var puzzle
var board
var caption: Label
var info: Dictionary
var step_index := 0
var playing := true
var elapsed := 0.0
var duration := 2.0
var touch := false

func configure(data: Dictionary, font: Font, colors: Dictionary, animated: bool, on_touch: bool) -> void:
	info = data
	playing = animated
	touch = on_touch
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 12)
	board = Board.new()
	board.font = font
	board.set_colors(colors)
	board.motion = animated
	board.move_seconds = 0.3
	board.custom_minimum_size.y = 180
	add_child(board)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption = Label.new()
	caption.set_meta("base_px", 15)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size.y = 56
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	reset_demo()

func reset_demo() -> void:
	var data := info.duplicate(true)
	data.id = "guide"
	data.max_echoes = 2
	puzzle = Puzzle.new(data)
	for route in info.get("recordings", []):
		for letter in route:
			var moved: bool = puzzle.move(Puzzle.DIRECTIONS[letter])
			assert(moved, "Invalid guide recording")
		var sealed: bool = puzzle.seal()
		assert(sealed, "Invalid guide recording")
	board.puzzle = puzzle
	board.cancel_animation()
	step_index = 0
	elapsed = 0
	_update_caption()

func _update_caption() -> void:
	var source: String = info.steps[step_index][1]
	if touch and source == "Move with the arrow keys or WASD. There is no time limit.":
		source = "Tap a direction on the pad. There is no time limit."
	caption.text = tr(source)
	duration = 3.0 if step_index == info.steps.size() - 1 else 2.0

func advance() -> void:
	elapsed = 0
	if step_index == info.steps.size() - 1:
		reset_demo()
		return
	step_index += 1
	var command: String = info.steps[step_index][0]
	var actors: Array = puzzle.actors()
	var gates: Array = puzzle.gates.map(func(gate): return puzzle.gate_open(gate))
	var state: int = puzzle.mechanism_state()
	# Evaluate outside assert so release exports execute the demonstrations, too.
	var accepted: bool = puzzle.seal() if command == "seal" else puzzle.move(Puzzle.DIRECTIONS[command])
	assert(accepted, "Invalid guide step")
	if command == "seal": board.cancel_animation()
	else: board.animate_from(actors, gates, state)
	_update_caption()

func toggle_playback() -> void:
	playing = not playing
	elapsed = 0
	playback_changed.emit()

func next_step() -> void:
	playing = false
	advance()
	playback_changed.emit()

func _process(delta: float) -> void:
	if not playing: return
	elapsed += delta
	if elapsed >= duration: advance()
