extends SceneTree
# Screenshots of the meadow as a new climb starts (dawn): the forest's fog
# fall-off, and a rival bird's colouring beside the player's.
# Run: godot --path . --max-fps 60 -s tests/meadow_look.gd -- --out=<dir>

var game: Node
var out := "user://meadow_look"

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
	game.weather.locked = "sunny"      # (clear air, so shots compare fairly)
	game.weather.band = -1
	var b := ClimberBird.new()
	b.tower = game.tower
	b.make(false)
	game.rivals.add_child(b)
	b.place(0.25, TowerShape.apothem(0) + 1.5, 0.0)
	b.active = false
	game.camera.snap()
	await create_timer(1.0).timeout
	await _snap("01_dawn_start")
	game.player.place(2.8, 26.0, 0.0)
	game.camera.snap()
	await create_timer(1.0).timeout
	await _snap("02_forest_dawn")
	game.weather.day_time = 0.25
	await create_timer(1.0).timeout
	await _snap("03_forest_noon")
	quit()
