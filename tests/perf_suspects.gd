extends SceneTree
# Mid-climb in phone quality: counts the engine-side things that run every
# frame (CPU particles, animated sprites, tweens), then switches each kind
# off in turn to see how much process time it was costing.
var game: Node

func _initialize() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game.shots_mode = true
	_run.call_deferred()

func _all(n: Node, cls: String, out: Array) -> void:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		_all(c, cls, out)

func _proc_ms() -> float:
	await create_timer(0.5).timeout
	var total := 0.0
	for i in 120:
		await process_frame
		total += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	return total / 120.0

func _run() -> void:
	game._enter_hub()
	game.tower.stream(60.0, true)
	game.player.place(0.5, TowerShape.apothem(5) + 1.2, 60.0)
	game.camera.snap()
	await create_timer(1.5).timeout
	var parts := []
	_all(root, "CPUParticles3D", parts)
	var sprites := []
	_all(root, "AnimatedSprite3D", sprites)
	var amount := 0
	for p in parts:
		amount += p.amount
	print("CPU particle systems: %d (%d particles), animated sprites: %d, tweens: %d" % [parts.size(), amount, sprites.size(), get_processed_tweens().size()])
	print("baseline:            %.2f ms" % await _proc_ms())
	for p in parts:
		p.process_mode = Node.PROCESS_MODE_DISABLED
	print("particles off:       %.2f ms" % await _proc_ms())
	for s in sprites:
		s.process_mode = Node.PROCESS_MODE_DISABLED
	print("+ sprites off:       %.2f ms" % await _proc_ms())
	for t in get_processed_tweens():
		t.pause()
	print("+ tweens paused:     %.2f ms" % await _proc_ms())
	game.set_process(false)
	print("+ game._process off: %.2f ms" % await _proc_ms())
	quit()
