extends SceneTree
# Times each system's per-frame work on its own (mid-climb, rain), to find
# what eats the frame. Run in phone quality: -- --low
var game: Node

func _initialize() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game.shots_mode = true
	_run.call_deferred()

func _time(label: String, f: Callable) -> void:
	var n := 200
	var t0 := Time.get_ticks_usec()
	for i in n:
		f.call()
	print("%-22s %7.3f ms" % [label, (Time.get_ticks_usec() - t0) / 1000.0 / n])

func _run() -> void:
	game._enter_hub()
	game.weather.locked = "rainy"
	game.weather.band = -1
	game.tower.stream(60.0, true)
	game.player.place(0.5, TowerShape.apothem(5) + 1.2, 60.0)
	game.camera.snap()
	await create_timer(1.5).timeout
	var d := 1.0 / 60.0
	var g = game
	var focus: Vector3 = g._focus()
	_time("weather.update", func(): g.weather.update(d, focus, g.camera.cam_theta))
	_time("forest params", func():
		for m in TowerChunk.forest_materials:
			m.set_shader_parameter("haze", g.weather.env.fog_light_color)
			m.set_shader_parameter("fade_far", 300.0))
	_time("clouds.update", func(): g.clouds.update(focus.y, g.weather.cloud_tint, g.camera.global_position))
	_time("flocks.update", func(): g.flocks.update(d, g.camera, focus.y, 0.0))
	_time("tower.tick_npcs", func(): g.tower.tick_npcs(d, focus))
	_time("meadow.update", func(): g.tower.meadow.update(d, focus.y, 0.0, g.camera.global_position))
	_time("stations.update", func(): g.stations.update(d, g.player, false, true))
	_time("tower.tick (phys)", func(): g.tower.tick(d))
	_time("tower.stream (phys)", func(): g.tower.stream(focus.y))
	_time("strikes.update", func(): g.strikes.update(d))
	_time("feathers", func(): g.feathers._process(d))
	_time("bird talk", func(): g.talk._process(d))
	_time("camera", func(): g.camera._process(d))
	_time("hud", func(): g.hud._process(d))
	_time("player _process", func(): g.player._process(d))
	_time("gusts", func(): g.weather.gusts.update(d, 3.0, focus, g.camera.cam_theta))
	var n := 0
	for k in g.tower.chunks:
		n += g.tower.chunks[k].streams.size()
	print("chunks loaded: ", g.tower.chunks.size(), "  streams in them: ", n)
	quit()
