extends SceneTree
# Screenshots of a wind stream (and riding it), moulted feathers, a crow
# flying past, and a loose plume. Never writes the player's saves.
# Run: godot --path . --max-fps 60 -s tests/stream_shots.gd -- --out=<dir>

var game: Node
var out := "user://stream_shots"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game.shots_mode = true
	_run.call_deferred()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)

func _run() -> void:
	game._configure(game.Mode.ENDLESS, 0)
	game._load_world(1234, 0.0, 5.5, 0.0, 0.0)
	game._play()
	game.weather.day_time = 0.3
	game.weather.locked = "sunny"
	game.weather.band = -1
	var p: Player = game.player
	# Find a climbing stream
	var sm: Dictionary = {}
	for k in range(2, 60):
		var pl := ChunkPlanner.plan(1234, k)
		if not pl.streams.is_empty() and pl.streams[0].pts[-1].y > pl.streams[0].pts[0].y + 6.0:
			sm = pl.streams[0]
			break
	var start: Vector3 = sm.pts[0]
	game.tower.stream(start.y, true)
	# Just below and outside its start, looking at it
	p.place(atan2(start.x, start.z), Vector2(start.x, start.z).length(), start.y - 2.5)
	p.set_physics_process(false)
	game.camera.snap()
	await create_timer(1.2).timeout
	await _snap("01_stream")
	# Drop it into the current and ride
	p.set_physics_process(true)
	p.y = start.y + 0.1
	p.vy = -0.1
	p.grounded = false
	await create_timer(0.7).timeout
	print("riding: ", not p.stream.is_empty())
	await _snap("02_riding")
	await create_timer(0.8).timeout
	await _snap("03_riding_later")
	# Feathers: a flap burst, a crow flying past, a plume drifting
	game.tower.stream(30.0, true)
	p.place(0.5, TowerShape.apothem(2) + 1.2, 30.0)
	p.set_physics_process(false)
	game.camera.snap()
	game.feathers.burst(p.world_position() + Vector3(0, 0.6, 0), 6)
	game.feathers.shed(p.world_position() + Vector3(1.8, 2.5, 0.5))
	game.feathers.pass_timer = 0.0
	await create_timer(0.5).timeout
	await _snap("04_feathers")
	await create_timer(1.3).timeout
	await _snap("05_crow_passing")
	quit()
