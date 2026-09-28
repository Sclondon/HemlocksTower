extends SceneTree
# Screenshots of the hub: the crow by the door talking, walking hops, the far
# meadow with its wires and crows, and just after a flapping landing.
# Run: godot --path . -s tests/hub_shots.gd -- --out=<dir>

var game: Node
var out := "user://hub_shots"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])

func _run() -> void:
	await _frames(10)
	game._new_climb()
	game.weather.day_time = 0.3
	var p: Player = game.player
	await _frames(30)
	# Walk right toward the door crow: bubble opens, and mid-hop
	Input.action_press("move_right")
	await _frames(14)
	await _snap("walk_hop")
	await _frames(20)
	Input.action_release("move_right")
	await _frames(30)
	await _snap("door_crow")
	# Out in the hub
	p.place(1.3, 13.0, 0.0)
	game.camera.snap()
	await _frames(60)
	await _snap("hub_talker")
	p.place(0.9, 17.0, 0.0)
	game.camera.snap()
	await _frames(60)
	await _snap("hub_wires")
	p.place(0.35 + TAU / 9.0 * 0.5, 26.0, 0.0)
	game.camera.snap()
	await _frames(60)
	await _snap("hub_edge")
	# Jump, flap twice, land, and look at the ground a second later
	p.place(0.0, 6.0, 0.0)
	game.camera.snap()
	await _frames(20)
	for i in 3:
		Input.action_press("jump")
		await _frames(2)
		Input.action_release("jump")
		await _frames(24)
	for i in 120:
		await process_frame
		if p.grounded:
			break
	await _frames(20)
	await _snap("landed_0.3s")
	await _frames(60)
	await _snap("landed_1.3s")
	await _frames(120)
	await _snap("landed_3.3s")
	# Empty stamina: still jumps
	p.stamina = 0.0
	var y0 := p.y
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	await _frames(12)
	print("jump with no stamina rose ", p.y - y0, " m")
	quit()
