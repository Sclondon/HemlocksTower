extends SceneTree
# Screenshots of the menus and the Ascent's summit sequence: title, section
# select, how to play, the meadow, the summit crown, the tower growing, and
# the results screens. Never writes the player's saves.
# Run: godot --path . -s tests/flow_shots.gd -- --out=<dir>

var game: Node
var out := "user://flow_shots"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game.shots_mode = true
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)

func _run() -> void:
	game.progress = {"cleared": 2, "times": {"0": 151.0, "1": 204.0}}
	game.weather.day_time = 0.3
	game._enter_title()
	await _frames(240)
	await _snap("01_title")
	game.menus.show_screen("sections")
	await _frames(30)
	await _snap("02_sections")
	game.menus.show_screen("howto")
	await _frames(30)
	await _snap("03_howto")
	# The meadow and its trees
	game._start_section(0)
	game.weather.day_time = 0.3
	await _frames(90)
	await _snap("04_meadow")
	game.player.place(0.8, 24.0, 0.0)
	game.camera.snap()
	await _frames(60)
	await _snap("05_meadow_edge")
	# Section II: straight to its summit
	game._start_section(1)
	game.weather.day_time = 0.3
	await _frames(20)
	var cap: int = game.tower.cap_chunk
	var y: float = cap * TowerShape.CHUNK_H
	game.tower.stream(y, true)
	game.player.place(0.3, TowerShape.apothem(cap) + 1.0, y + 3.0)
	game.camera.snap()
	await _frames(40)
	await _snap("06_summit_crown")
	await _frames(200)
	await _snap("07_summit_caption")
	await _frames(170)
	await _snap("08_bumped")
	await _frames(170)
	await _snap("09_growing")
	await _frames(420)
	await _snap("10_ascent_results")
	# Endless, ended with a long fall
	game._start_endless()
	await _frames(30)
	game.player.max_y = 212.0
	game.player.fall_from = 250.0
	game.player.y = 200.0
	game.player.grounded = false
	await _frames(200)
	await _snap("11_endless_results")
	quit()
