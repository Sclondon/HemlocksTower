extends SceneTree
# A look out over the forest to the horizon from partway up the tower (clear
# weather), to judge how full the wood looks in the distance.
# Run: godot --path . --max-fps 60 -s tests/horizon_look.gd -- --out=<dir>

var game: Node
var out := "user://horizon_look"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game.shots_mode = true
	_run.call_deferred()

func _run() -> void:
	game._enter_hub()
	game.weather.locked = "sunny"
	game.weather.band = -1
	game.weather.day_time = 0.25
	var cam: OrbitCamera = game.camera
	cam.set_process(false)
	for i in 2:
		var a := 1.0 + i * 2.5
		var from := Vector3(sin(a), 0, cos(a)) * 8.0 + Vector3(0, 30.0, 0)
		cam.global_position = from
		cam.look_at(from + Vector3(sin(a), -0.12, cos(a)) * 100.0, Vector3.UP)
		cam.fov = 70.0
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/horizon_%d.png" % [out, i])
	quit()
