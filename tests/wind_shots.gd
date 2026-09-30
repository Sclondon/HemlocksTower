extends SceneTree
# Screenshots of the wind ribbons in windy weather, a beat apart.
# Run: godot --path . -s tests/wind_shots.gd -- --out=<dir>

var game: Node
var out := "user://wind_shots"

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
	await create_timer(0.3).timeout
	game._start_section(0)
	var w: Weather = game.weather
	w.day_time = 0.3
	w.state_from = Weather.STATES.windy
	w.state_to = Weather.STATES.windy
	w.state_blend = 1.0
	w.state_name = "windy"
	w.state_timer = 999.0
	game.player.place(0.4, TowerShape.apothem(2) + 1.0, 26.0)
	game.player.set_physics_process(false)
	game.camera.snap()
	for i in 6:
		for f in 27:
			w.state_name = "windy"
			w.state_to = Weather.STATES.windy
			w.state_from = Weather.STATES.windy
			w.state_timer = 999.0
			w.band = 0
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/wind_%d.png" % [out, i])
	quit()
