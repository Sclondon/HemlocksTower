extends SceneTree
# Screenshots of the sky: puff clouds over the meadow and round a cloud deck.
# Run: godot --path . --max-fps 60 -s tests/sky_shots.gd -- --out=<dir>

var game: Node
var out := "user://sky_shots"

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

func _at(y: float, name: String) -> void:
	game.tower.stream(y, true)
	game.player.place(0.6, TowerShape.apothem(TowerShape.chunk_at(y)) + 1.5, y)
	game.camera.snap()
	await create_timer(1.5).timeout
	await _snap(name)

func _run() -> void:
	game._configure(game.Mode.ENDLESS, 0)
	game._load_world(99, 0.0, 5.5, 0.0, 0.0)
	game._play()
	var w: Weather = game.weather
	w.day_time = 0.3
	w.locked = "cloudy"
	w.band = -1
	await _at(40.0, "sky_meadow")
	await _at(112.0, "sky_deck_below")
	await _at(128.0, "sky_deck_above")
	await _at(300.0, "sky_high")
	quit()
