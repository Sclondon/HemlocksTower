extends SceneTree
# Measures what a frame costs in a few places: draw calls, triangles, and
# script time for processing and physics (averaged over a couple of seconds).
# Run it in phone quality to see what phones pay:
#   godot --path . -s tests/perf_probe.gd -- --low

var game: Node

func _initialize() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game.shots_mode = true
	_run.call_deferred()

func _measure(label: String) -> void:
	await create_timer(1.5).timeout
	var draws := 0.0
	var prims := 0.0
	var proc := 0.0
	var phys := 0.0
	var worst := 0.0
	var n := 0
	var last := Time.get_ticks_usec()
	for i in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = max(worst, (now - last) / 1000.0)
		last = now
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		n += 1
	print("%-18s draws %5.0f  tris %8.0f  process %5.2f ms  physics %5.2f ms  worst frame %5.1f ms  nodes %d" % [
		label, draws / n, prims / n, proc / n, phys / n, worst, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])

func _run() -> void:
	print("low quality: ", Tuning.low_quality)
	game._enter_hub()
	game.weather.day_time = 0.3
	await _measure("meadow")
	game.tower.stream(60.0, true)
	game.player.place(0.5, TowerShape.apothem(5) + 1.2, 60.0)
	game.camera.snap()
	await _measure("mid-climb 60m")
	game.weather.locked = "rainy"
	game.weather.band = -1
	await _measure("rain 60m")
	game.tower.stream(118.0, true)
	game.player.place(0.5, TowerShape.apothem(9) + 1.2, 118.0)
	game.camera.snap()
	await _measure("cloud deck 118m")
	quit()
