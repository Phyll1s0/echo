extends SceneTree

const Puzzle = preload("res://scripts/puzzle.gd")
const Guide = preload("res://scripts/chapter_guide.gd")
var checks := 0
var failures := 0

func verify(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(reason)

func walk(puzzle, directions: String) -> void:
	for letter in directions:
		verify(puzzle.move(Puzzle.DIRECTIONS[letter]), "Projected route accepts " + letter)

func fixture(data: Dictionary):
	data = data.duplicate(true)
	data.id = "projection-test"
	data.max_echoes = 2
	return Puzzle.new(data)

func _initialize() -> void:
	var room = fixture(Guide.PAGES.Nexus[0])
	walk(room, "RR")
	var before: Dictionary = room.snapshot()
	verify(not room.move(Vector2i.RIGHT) and room.snapshot() == before, "Inactive projection rejects a move without advancing a beat")
	room.reset_all()
	walk(room, "UU")
	verify(room.seal(), "Record the projector visit")
	walk(room, "RR")
	verify(room.projection_active(Vector2i(4,2)), "Pre-move occupancy turns on the bridge")
	room.move(Vector2i.RIGHT)
	verify(not room.projection_active(room.player()) and room.echo_position(0) == null, "The last recorded visit supports a crossing even as the echo fades")
	var restored = fixture(Guide.PAGES.Nexus[0])
	verify(restored.restore(room.snapshot()) and restored.snapshot() == room.snapshot(), "Reload restores a player on an extinguished projection")
	verify(restored.move(Vector2i.RIGHT) and restored.cleared(), "The player can leave an extinguished bridge")
	verify(room.undo() and room.projection_active(Vector2i(4,2)), "Undo restores the projector and its last live frame")
	walk(room, "RR")
	verify(room.cleared(), "Replay after undo reaches the exit")
	room.reset_all()
	verify(room.echoes.is_empty() and not room.projection_active(Vector2i(4,2)), "Restart clears the light and both routes")

	var lens = fixture({"rows":["@.X","S.."], "gates":[], "projections":[{"cells":[[1,0]],"requires":["@"]}]})
	walk(lens, "U")
	verify(not lens.move(Vector2i.RIGHT), "One actor on a lens cannot project a bridge")
	verify(lens.seal(), "Save a lens visit")
	walk(lens, "URR")
	verify(lens.cleared(), "Two selves on the lens support the crossing")

	var portal = fixture({"rows":["A#S.##.X","....####"], "gates":[],
		"portals":[{"id":"I","a":[3,0],"b":[6,0]}], "projections":[{"cells":[[6,0]],"requires":["A"]}]})
	before = portal.snapshot()
	verify(not portal.move(Vector2i.RIGHT) and portal.snapshot() == before, "A dark portal landing cancels the entire jump")
	walk(portal, "DLLU")
	verify(portal.seal(), "Record a remote projector")
	walk(portal, "DUDU")
	before = portal.snapshot()
	walk(portal, "R")
	verify(portal.player() == Vector2i(6,0) and not portal.projection_active(portal.player()), "Portal landing uses the same pre-move light")
	verify(portal.undo() and portal.snapshot() == before, "Undo recovers an entire projected portal step")
	walk(portal, "RR")
	verify(portal.cleared(), "The remote bridge can be exited after fading")

	var current = fixture({"rows":["##A####","S.>>>.X"], "gates":[],
		"projections":[{"cells":[[3,1]],"requires":["A"]}]})
	walk(current, "R")
	before = current.snapshot()
	verify(not current.move(Vector2i.RIGHT) and current.snapshot() == before, "An unpowered intermediate current tile cancels the complete ride")

	print("ECHO projections: %d checks; %d failures." % [checks, failures])
	quit(1 if failures else 0)
