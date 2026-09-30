extends SceneTree
# Close-ups of the meadow's paper trees, from a camera parked out by the
# wood's edge (the game camera never gets this close).
# Run: godot --path . --max-fps 60 -s tests/tree_closeup.gd -- --out=<dir>

var game: Node
var out := "user://tree_closeup"

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
	game._enter_hub()
	game.weather.day_time = 0.25
	game.weather.locked = "sunny"
	game.weather.band = -1
	var cam: OrbitCamera = game.camera
	cam.set_process(false)
	for i in 3:
		var a := 0.8 + i * 2.1
		cam.global_position = Vector3(sin(a) * 30.0, 6.0, cos(a) * 30.0)
		cam.look_at(Vector3(sin(a) * 60.0, 9.0, cos(a) * 60.0), Vector3.UP)
		cam.fov = 60.0
		await create_timer(1.0).timeout
		await _snap("close_%d" % i)
	quit()
