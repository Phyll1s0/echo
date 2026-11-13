extends SceneTree

const Puzzle = preload("res://scripts/puzzle.gd")
const Board = preload("res://scripts/board.gd")
const Guide = preload("res://scripts/chapter_guide.gd")
var checks := 0
var failures := 0

func verify(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(reason)

func fixture(data: Dictionary):
	data = data.duplicate(true)
	data.id = "transport-test"
	data.max_echoes = 2
	return Puzzle.new(data)

func _initialize() -> void:
	var portal = fixture(Guide.PAGES.Slipstream[0])
	verify(portal.move(Vector2i.RIGHT) and portal.tick() == 1 and portal.player() == Vector2i(4,0), "A portal jump is one beat; the exit does not bounce")
	verify(portal.seal() and portal.move(Vector2i.RIGHT) and portal.echo_position(0) == portal.player(), "Echoes remember a non-adjacent landing")
	verify(portal.move(Vector2i.RIGHT) and portal.cleared() and portal.echo_position(0) == null, "A transported echo fades after its last beat")
	verify(portal.undo() and portal.echo_position(0) == Vector2i(4,0), "Undo restores both transported actors")
	var old_plan: Dictionary = portal.snapshot()
	verify(portal.rerecord_last() and portal.draft_steps.back().jumps == [2], "Editing restores the actual jump path")
	verify(portal.cancel_edit() and portal.snapshot() == old_plan, "Cancel restores the plan after editing a portal recording")
	var chain = fixture(Guide.PAGES.Slipstream[2])
	verify(chain.move(Vector2i.RIGHT) and chain.tick() == 1 and chain.player() == Vector2i(4,2), "Two portals and a current resolve on the same beat")
	verify(chain.draft_steps.back().jumps.size() == 2 and chain.draft_steps.back().path.size() == 5, "The recording retains both jumps and the intermediate current")
	var copy = fixture(Guide.PAGES.Slipstream[2])
	verify(copy.restore(JSON.parse_string(JSON.stringify(chain.snapshot()))) and copy.draft_steps == chain.draft_steps, "JSON saves replay the original input and reconstruct the full chain")
	var forged: Dictionary = chain.snapshot()
	forged.draft_inputs = "L"
	verify(not copy.restore(forged) and copy.player() == chain.player(), "A forged input cannot legitimize a distant saved landing")
	var view := Board.new()
	view.puzzle = chain
	view.size = Vector2(600,300)
	var path: Array = chain.draft_steps[0].path
	for jump in chain.draft_steps[0].jumps:
		view.phase = (jump - 0.5) / (path.size() - 1.0)
		var pose: Dictionary = view._actor_pose(0, chain.start, chain.player())
		verify(pose.alpha < 0.001 and (pose.center.is_equal_approx(view.center_of(path[jump-1])) or pose.center.is_equal_approx(view.center_of(path[jump]))), "Teleport animation fades at an endpoint, never slides across the void")
	view.free()
	var blocked = fixture({"rows": ["S>>>A.X"], "gates": [{"a": [2,0], "b": [3,0], "requires": ["A"]}]})
	var before: Dictionary = blocked.snapshot()
	verify(not blocked.move(Vector2i.RIGHT) and blocked.snapshot() == before, "A gate halfway down a current rejects the entire move")
	var lava = fixture({"rows": ["S>2.X"], "gates": [], "lava_groups": 4})
	verify(not lava.move(Vector2i.RIGHT) and lava.tick() == 0, "A sinking intermediate tile also rejects the entire move")
	var folded = fixture({"rows": ["S>b.X", "*a###"], "gates": []})
	verify(not folded.move(Vector2i.RIGHT) and folded.mechanism_state() == 0, "A folded intermediate bridge cannot be skipped")
	var loop = fixture({"rows": ["S><X"], "gates": []})
	verify(not loop.move(Vector2i.RIGHT) and loop.tick() == 0, "A forced cycle is rejected without hanging or advancing time")
	var still = fixture({"rows": ["S<.X"], "gates": []})
	verify(not still.move(Vector2i.RIGHT), "A current cannot turn a move into waiting at the starting tile")
	var devices = fixture({"rows": ["S.##*bX"], "gates": [], "portals": [{"id": "I", "a": [1,0], "b": [4,0]}]})
	verify(devices.move(Vector2i.RIGHT) and devices.mechanism_state() == 1, "A portal landing triggers its diamond")
	verify(devices.seal() and devices.move(Vector2i.RIGHT) and devices.mechanism_state() == 1, "Simultaneous player and echo landings trigger a switch once")
	verify(devices.move(Vector2i.RIGHT) and devices.player() == Vector2i(5,0), "The resulting bridge bank applies to the next beat")
	var arrows = fixture({"rows": ["S>>>.X", "..####"], "gates": [], "turnstiles": [[[1,0],[2,0]], [[2,0],[3,0]]]})
	verify(arrows.move(Vector2i.RIGHT) and arrows.mechanism_state() == 6, "Every crossed arrow updates at the end of the current")
	verify(arrows.seal() and arrows.move(Vector2i.DOWN) and arrows.mechanism_state() == 6, "An echo replays all intermediate arrow crossings while the player goes elsewhere")
	verify(arrows.undo() and arrows.tick() == 0 and arrows.mechanism_state() == 0, "Undo restores all intermediate device effects together")
	print("ECHO transport: %d checks; %d failures." % [checks, failures])
	quit(1 if failures else 0)
