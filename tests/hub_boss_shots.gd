extends SceneTree
# Screenshots of the meadow hub (the two cauldrons, Hemlock's plinth,
# the forest and mountains) and of the Hemlock boss fight.
# Never writes the player's saves.
# Run: godot --path . --max-fps 60 -s tests/hub_boss_shots.gd -- --out=<dir>

var game: Node
var out := "user://hub_boss_shots"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game.shots_mode = true
	_run.call_deferred()

func _seconds(s: float) -> void:
	await create_timer(s).timeout

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)

func _stand(theta: float, r: float) -> void:
	game.player.place(theta, r, 0.0)
	game.camera.snap()
	await _seconds(1.2)

func _run() -> void:
	game.progress = {"cleared": 4, "times": {}, "beaten": false}
	game._enter_title()
	game.weather.day_time = 0.3
	await _seconds(3.0)
	await _snap("01_title")
	game._enter_hub()
	game.weather.day_time = 0.3
	await _stand(0.0, 5.5)
	await _snap("02_door")
	await _stand(HubStations.TRAVEL.x, HubStations.TRAVEL.y + 5.0)
	await _snap("03_blue_cauldron")
	await _stand(HubStations.DREAM.x, HubStations.DREAM.y + 5.0)
	await _snap("04_green_cauldron")
	# Drop into the green stew: its prompt opens; "not yet" spits you out
	game.player.place(HubStations.DREAM.x, HubStations.DREAM.y, 3.2)
	game.player.vy = -1.0
	game.player.grounded = false
	await _seconds(0.6)
	print("in the cauldron, menu: ", game.menus.current)
	await _snap("04b_cauldron_prompt")
	game._on_prompt(false)
	await _seconds(0.5)
	await _snap("04c_spat_out")
	await _stand(HubStations.HEMLOCK.x, HubStations.HEMLOCK.y + 4.5)
	await _snap("05_hemlock_4of7")
	await _stand(2.8, 29.0)
	await _snap("06_forest_edge")
	game.talk.comment("windy")
	await _seconds(0.6)
	await _snap("07_bird_comment")
	# All parts: walking up to him opens the prompt
	game.progress.cleared = 7
	game.stations.set_parts(7, false)
	await _stand(HubStations.HEMLOCK.x, HubStations.HEMLOCK.y + 4.5)
	await _snap("08_hemlock_whole")
	game.player.place(HubStations.HEMLOCK.x, HubStations.HEMLOCK.y + 1.0, 0.0)
	await _seconds(0.6)
	await _snap("09_hemlock_prompt")
	game._on_prompt(true)
	await _seconds(2.0)
	await _snap("10_boss_intro")
	await _seconds(3.5)
	await _snap("11_boss_circle")
	while game.boss.state != "beam" and game.boss.state != "gears":
		await process_frame
	await _seconds(1.3)
	await _snap("12_boss_" + game.boss.state)
	while not (game.boss.state == "perch" and game.boss.t > 1.5):
		game.boss.invuln = 999.0
		await process_frame
	await _snap("13_boss_perched")
	quit()
