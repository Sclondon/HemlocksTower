extends SceneTree
# How long building one chunk of tower takes (the work done as you climb
# into new territory), and how that splits between its parts.
var game: Node

func _initialize() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game.shots_mode = true
	_run.call_deferred()

func _run() -> void:
	await create_timer(0.5).timeout
	var total := 0.0
	var worst := 0.0
	var n := 0
	for k in range(3, 43):
		var c := TowerChunk.new()
		c.setup(ChunkPlanner.plan(4242, k), {})
		game.tower.add_child(c)
		var t0 := Time.get_ticks_usec()
		c.build()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		worst = max(worst, ms)
		n += 1
		c.queue_free()
	var t1 := Time.get_ticks_usec()
	for k in range(3, 43):
		ChunkPlanner.plan(4242, k)
	print("plan: %.2f ms avg" % ((Time.get_ticks_usec() - t1) / 1000.0 / 40.0))
	print("build: %.2f ms avg, %.2f ms worst (%d chunks)" % [total / n, worst, n])
	quit()
