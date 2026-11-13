extends "res://tests/test_ui.gd"

func _run() -> void:
	root.min_size = Vector2i.ONE
	ui = preload("res://scenes/main.tscn").instantiate()
	ui.store = Store.new(path)
	ui.store.data.sound = false
	ui.store.data.motion = false
	ui.store.data.room_titles = 0
	root.add_child(ui)
	await settle()
	for dimensions in [Vector2i(1280,820),Vector2i(390,664),Vector2i(320,568),Vector2i(844,300)]:
		root.size = dimensions
		ui.touch_controls = dimensions.x != 1280
		await settle()
		for i in ui.levels.size():
			ui.open_level(i, false, false)
			await settle()
			var bounds := Rect2(Vector2.ZERO, ui.board.size)
			for gate in ui.session.gates:
				for chip in ui.board.condition_layout(gate):
					verify(bounds.encloses(Rect2(chip.center - Vector2.ONE * chip.radius, Vector2.ONE * chip.radius * 2)), "Gate conditions stay inside the board: %s / %s" % [ui.session.level.id,dimensions])
		ui.open_level(28, false, false)
		await settle()
		var snapshot: Dictionary = ui.session.snapshot()
		var gate: Dictionary = ui.session.gates[-1]
		var middle: Vector2 = (ui.board.center_of(gate.a) + ui.board.center_of(gate.b)) * 0.5
		await click(ui.board.global_position + middle)
		verify(ui.board.selected_gate == ui.session.gates.size()-1 and ui.status_text == "Gate requires B  −A", "A door edge reveals its full occupied and empty conditions")
		verify(ui.session.snapshot() == snapshot, "Inspecting a door costs no beat and changes no recording")
		ui.open_level(27, false, false)
		await settle()
		await click(ui.board.global_position + ui.board.center_of(ui.session.plates["@"]))
		verify(ui.board.selected_plate == "@" and ui.board.selected_portal == ui.session.plates["@"], "An overlapping lens and portal can both be inspected")
	# The twofold composition offers distinct, legal plans for either door.
	root.size = Vector2i(390,664)
	for plan in JSON.parse_string(FileAccess.get_file_as_string("res://tests/composition_routes.json")):
		ui.open_level(int(plan.id)-1, false, false)
		await settle()
		for tape in plan.recordings:
			await walk(tape)
			await key(KEY_ENTER)
		await walk(plan.final)
		verify(ui.session.cleared(), "Kaleidoscope's alternate approach finishes through real input")
	DirAccess.remove_absolute(path)
	print("ECHO composition: %d checks; %d failures." % [checks, failures])
	quit(1 if failures else 0)
