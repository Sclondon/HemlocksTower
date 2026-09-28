extends Node
# Hemlock's Tower: a bird climbing an endless procedurally built tower.
# Builds the low-res 3D view and the UI, and runs the title / play / pause
# flow, saving, and the score hook for the hosting web page.

enum State { TITLE, PLAYING, PAUSED }

const SAVE_PATH := "user://climb.json"
const BEST_PATH := "user://best.save"
const PIXEL_SCALE := 2               # 3D is drawn at 1/2 res and scaled up crisp
const AUTOSAVE_EVERY := 4.0

var state := State.TITLE
var run_seed := 0
var best := 0.0
var last_band := -1
var autosave_timer := 0.0
var shots_mode := false
var record_mode := false             # attract-mode montage for the arcade preview video

var tower: TowerGenerator
var player: Player
var camera: OrbitCamera
var weather: Weather
var clouds: CloudLayers
var flocks: BackgroundBirds
var rivals: Climbers
var strikes: LightningStrikes
var hud: Hud
var touch: TouchControls
var title_panel: Control
var pause_panel: Control
var continue_button: Button
var new_button: Button
var resume_button: Button
var debug_label: Label
var view: SubViewport

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	var args := OS.get_cmdline_user_args()
	Tuning.low_quality = args.has("--low") or OS.has_feature("mobile") or OS.has_feature("web_android") \
		or OS.has_feature("web_ios") or DisplayServer.is_touchscreen_available()
	shots_mode = OS.is_debug_build() and args.has("--shots")
	record_mode = OS.is_debug_build() and args.has("--record")
	if not record_mode:
		_load_best()
	_build_view()
	_build_ui()
	if shots_mode:
		_take_shots()
	elif record_mode:
		_record_attract()
	else:
		_enter_title()

# --- setup --------------------------------------------------------------------

func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_in": [KEY_W, KEY_UP], "move_out": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE, KEY_K, KEY_Z], "pause": [KEY_ESCAPE, KEY_P],
	}
	var axes := {
		"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_in": [JOY_AXIS_LEFT_Y, -1.0], "move_out": [JOY_AXIS_LEFT_Y, 1.0],
	}
	for action in keys:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, 0.25)
		for key in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = key
			InputMap.action_add_event(action, e)
		if axes.has(action):
			var j := InputEventJoypadMotion.new()
			j.axis = axes[action][0]
			j.axis_value = axes[action][1]
			InputMap.action_add_event(action, j)
	var ja := InputEventJoypadButton.new()
	ja.button_index = JOY_BUTTON_A
	InputMap.action_add_event("jump", ja)
	var js := InputEventJoypadButton.new()
	js.button_index = JOY_BUTTON_START
	InputMap.action_add_event("pause", js)

func _build_view() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.stretch_shrink = PIXEL_SCALE
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	view = SubViewport.new()
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	container.add_child(view)

	var world := Node3D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	view.add_child(world)
	weather = Weather.new()
	world.add_child(weather)
	clouds = CloudLayers.new()
	world.add_child(clouds)
	flocks = BackgroundBirds.new()
	world.add_child(flocks)
	tower = TowerGenerator.new()
	world.add_child(tower)
	# In record mode the rival-bird AI flies the player's own bird
	if record_mode:
		player = ClimberBird.new()
	else:
		player = Player.new()
	player.is_npc = false
	player.tower = tower
	world.add_child(player)
	strikes = LightningStrikes.new()
	strikes.tower = tower
	strikes.player = player
	strikes.weather = weather
	world.add_child(strikes)
	rivals = Climbers.new()
	rivals.tower = tower
	rivals.player = player
	world.add_child(rivals)
	camera = OrbitCamera.new()
	camera.player = player
	world.add_child(camera)
	camera.make_current()

	weather.lightning.connect(func():
		hud.flash()
		if randf() < 0.7:
			flocks.spawn(camera, player.y))
	player.flap_denied.connect(func(): hud.deny())
	player.picked_up.connect(func(kind): hud.pickup(kind))
	player.boosted.connect(func(): hud.pickup("feather"))
	player.powered.connect(func(kind): hud.show_banner(Hud.POWER_NAMES[kind]))
	weather.changed.connect(func(line): if state == State.PLAYING: hud.show_banner(line))

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	touch = TouchControls.new()
	touch.process_mode = Node.PROCESS_MODE_PAUSABLE
	layer.add_child(touch)
	hud = Hud.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(hud)
	hud.pause_pressed.connect(_pause)

	title_panel = _panel(layer)
	var box := title_panel.get_child(0).get_child(0)
	box.add_child(_text("HEMLOCK'S\nTOWER", 64, Color(0.95, 0.4, 0.45)))
	box.add_child(_text("How high can a small bird climb?", 22, Color(1, 0.9, 0.75)))
	continue_button = _button(box, "Continue", _continue_climb)
	new_button = _button(box, "New Climb", _new_climb)
	box.add_child(_text("A / D  or  Left / Right:  around the tower\nW / S  or  Up / Down:  in and out\nSpace:  jump, then flap in the air\n\nPhone: left thumb steers, right thumb jumps", 18, Color(0.85, 0.85, 1)))

	pause_panel = _panel(layer)
	box = pause_panel.get_child(0).get_child(0)
	box.add_child(_text("PAUSED", 56, Color(0.95, 0.4, 0.45)))
	resume_button = _button(box, "Resume", _resume)
	_button(box, "End Climb", _end_climb)

	debug_label = Hud.make_label(16, Color(0.7, 1, 0.7))
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	debug_label.position = Vector2(12, 120)
	debug_label.visible = false
	layer.add_child(debug_label)

func _panel(layer: CanvasLayer) -> Control:
	# A dimmed full-screen backdrop with a centred column; returns the backdrop
	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.02, 0.1, 0.45)
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	panel.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	panel.visible = false
	return panel

func _text(t: String, font_size: int, color: Color) -> Label:
	var l := Hud.make_label(font_size, color)
	l.text = t
	return l

func _button(box: Node, t: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(280, 64)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(action)
	var c := CenterContainer.new()
	c.add_child(b)
	box.add_child(c)
	return b

# --- flow ---------------------------------------------------------------------

func _enter_title() -> void:
	state = State.TITLE
	get_tree().paused = false
	var save := _read_save()
	if save.is_empty():
		_load_world(randi(), 0.0, TowerShape.apothem(0) + 1.5, 0.0, 0.0)
	else:
		_load_world(int(save.seed), save.theta, save.r, save.y, save.max_y,
			save.get("max_stamina", Tuning.BASE_STAMINA), save.get("feathers", []))
	player.active = false
	camera.orbit_idle = true
	continue_button.get_parent().visible = not save.is_empty()
	if not save.is_empty():
		continue_button.text = "Continue  (%d m)" % int(save.y)
	title_panel.visible = true
	pause_panel.visible = false
	hud.visible = false
	touch.visible = false
	(continue_button if not save.is_empty() else new_button).grab_focus()

func _load_world(new_seed: int, theta: float, r: float, y: float, max_y: float, bucket := Tuning.BASE_STAMINA, feathers: Array = []) -> void:
	run_seed = new_seed
	tower.reset(run_seed, feathers)
	rivals.clear()
	player.max_stamina = bucket
	clouds.clear()
	tower.stream(y, true)
	player.max_y = max_y
	player.place(theta, r, y)
	camera.snap()
	last_band = TowerShape.band_at(y)

func _new_climb() -> void:
	weather.reset_clock()
	_load_world(randi(), 0.0, TowerShape.apothem(0) + 1.5, 0.0, 0.0)
	_play()

func _continue_climb() -> void:
	_play()

func _play() -> void:
	state = State.PLAYING
	get_tree().paused = false
	player.active = true
	camera.orbit_idle = false
	title_panel.visible = false
	pause_panel.visible = false
	hud.set_heights(player.y, max(best, player.max_y))
	hud.visible = true
	touch.visible = true
	hud.show_banner(Weather.band_name(TowerShape.band_at(player.y)))
	_write_save()

func _pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	touch.release_all()
	get_tree().paused = true
	pause_panel.visible = true
	resume_button.grab_focus()
	_write_save()

func _resume() -> void:
	if state == State.PAUSED:
		state = State.PLAYING
		get_tree().paused = false
		pause_panel.visible = false

func _end_climb() -> void:
	var score := int(player.max_y)
	_update_best()
	# Tell the hosting page (e.g. the arcade cabinet site) how high we got
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.parent.postMessage({ type: 'PLAYER_DIED', score: %d }, '*')" % score, true)
	_clear_save()
	_enter_title()

# --- per frame ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if state == State.PLAYING:
			_pause()
		elif state == State.PAUSED:
			_resume()
	elif OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo:
		_debug_key(event.physical_keycode)

func _physics_process(delta: float) -> void:
	if state == State.PAUSED:
		return
	tower.stream(player.y)
	tower.tick(delta)
	strikes.update(delta)

func _process(delta: float) -> void:
	weather.update(delta, player.world_position(), camera.cam_theta)
	player.weather_wind = weather.wind
	tower.set_glow(weather.current.glow)
	clouds.update(player.y, weather.cloud_tint, camera.global_position)
	flocks.update(delta, camera, player.y, weather.current.lightning)
	tower.tick_npcs(delta, player.world_position())
	tower.meadow.update(delta, player.y, 1.0 - weather.dayness, camera.global_position)

	if state != State.PLAYING:
		return
	hud.set_heights(player.y, max(best, player.max_y))
	hud.set_stamina(player.stamina, player.max_stamina)
	hud.set_powers(player.powers)
	var band := TowerShape.band_at(player.y)
	if band > last_band:
		hud.show_banner(Weather.band_name(band))
	last_band = band
	autosave_timer += delta
	if autosave_timer > AUTOSAVE_EVERY and player.grounded:
		autosave_timer = 0.0
		_write_save()
	if debug_label.visible:
		debug_label.text = "fps %d\ny %.1f  band %d (%d sides)\ntheta %.2f  r %.2f\nstamina %.2f  wind %.2f\nchunks %d" % [
			Engine.get_frames_per_second(), player.y, band, TowerShape.sides(TowerShape.chunk_at(player.y)),
			player.theta, player.r, player.stamina, weather.wind, tower.chunks.size()]

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if touch:
			touch.release_all()
		if state == State.PLAYING:
			_pause()

# --- saving -------------------------------------------------------------------

# On the web, saves go to localStorage: Godot's user:// is backed by IndexedDB
# and a write made just before the tab closes (or right after another) can be
# lost. Native builds use plain files in user://.
func _store(key: String, path: String, text: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('hemlock_%s', %s)" % [key, JSON.stringify(text)], true)
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)

func _fetch(key: String, path: String) -> String:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("localStorage.getItem('hemlock_%s')" % key, true)
		return v if v is String else ""
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

func _update_best() -> void:
	if player.max_y > best:
		best = player.max_y
		_store("best", BEST_PATH + ".txt", str(int(best)))

func _load_best() -> void:
	best = float(_fetch("best", BEST_PATH + ".txt").to_int())
	# Best scores from the previous version were a raw 32-bit int in best.save
	var f := FileAccess.open(BEST_PATH, FileAccess.READ)
	if f:
		best = max(best, f.get_32())

func _clear_save() -> void:
	_store("climb", SAVE_PATH, "{}")

func _write_save() -> void:
	if shots_mode or record_mode:
		return
	_update_best()
	_store("climb", SAVE_PATH, JSON.stringify({
		"seed": run_seed, "theta": player.theta, "r": player.r, "y": player.y, "max_y": player.max_y,
		"max_stamina": player.max_stamina, "feathers": tower.collected.keys(),
	}))

func _read_save() -> Dictionary:
	var data = JSON.parse_string(_fetch("climb", SAVE_PATH))
	if data is Dictionary and data.has_all(["seed", "theta", "r", "y", "max_y"]):
		return data
	return {}

# --- debug (debug builds only) --------------------------------------------------

func _debug_key(key: int) -> void:
	match key:
		KEY_F1, KEY_F2:
			# Hop to the ring at the start of the next / previous band
			var b := TowerShape.band_at(player.y) + (1 if key == KEY_F1 else -1)
			b = max(b, 0)
			var y := b * TowerShape.BAND_H + (0.0 if b == 0 else 0.5)
			tower.stream(y, true)
			player.place(player.theta, TowerShape.apothem(b * TowerShape.CHUNKS_PER_BAND) + 1.0, y)
			camera.snap()
		KEY_F3:
			debug_label.visible = not debug_label.visible

# Renders each band from a fixed seed and saves screenshots, then quits.
# Run: godot --path . -- --shots
func _take_shots() -> void:
	var dir := ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	_load_world(1234, 0.0, TowerShape.apothem(0) + 1.5, 0.0, 0.0)
	title_panel.visible = false
	hud.visible = true
	touch.visible = true
	touch.used = true                # show the phone controls too
	state = State.PLAYING
	# Each weather band from its start, then one of each special platform
	var spots: Array = [["ground", 0.0]]
	for b in range(1, 8):
		spots.append(["band%d" % b, b * TowerShape.BAND_H + 0.5])
	spots.push_front(["meadow_night", 0.0])
	var wanted := [ChunkPlanner.Kind.PROP, ChunkPlanner.Kind.ORBIT, ChunkPlanner.Kind.RETRACT, ChunkPlanner.Kind.CATWALK]
	var roof_found := false
	var wire_found := false
	var rings_found := false
	for k in range(1, 60):
		var pl := ChunkPlanner.plan(run_seed, k)
		for s in pl.surfaces:
			if s.kind in wanted:
				wanted.erase(s.kind)
				spots.append([ChunkPlanner.Kind.keys()[s.kind].to_lower(), s.top, s.id])
			elif s.kind == ChunkPlanner.Kind.TURRET and s.get("roof", false) and not roof_found:
				roof_found = true
				spots.append(["roofed_turret", s.top, s.id])
		if not wire_found and not pl.wires.is_empty() and pl.wires[0].birds > 0:
			wire_found = true
			var m: Vector3 = TowerChunk.wire_point(pl.wires[0], 0.35)
			spots.append(["wire", m.y + 0.6, "", {"theta": atan2(m.x, m.z), "r": Vector2(m.x, m.z).length(), "up": true, "y0": m.y + 0.6}])
		if not rings_found and not pl.rings.is_empty():
			rings_found = true
			var rg: Dictionary = pl.rings[0]
			spots.append(["rings", rg.y - 0.8, "", {"theta": rg.theta - rg.dir * 2.5 / rg.r, "r": rg.r, "up": true, "y0": rg.y - 0.8}])
	# An updraft column, seen from inside it
	for k in range(2, 40):
		var ups: Array = ChunkPlanner.plan(run_seed, k).drafts.filter(func(d): return d.up)
		if not ups.is_empty():
			spots.append(["updraft", ups[0].y0 + 3.0, "", ups[0]])
			break
	# Mid-air just under a ledge: shows the shadow and the see-through silhouette
	var under: Dictionary = ChunkPlanner.plan(run_seed, 3).surfaces[2]
	spots.append(["airborne", under.top - 1.2, under.id])
	for i in spots.size():
		var y: float = spots[i][1]
		tower.stream(y, true)
		var s: Dictionary = tower.chunk(TowerShape.chunk_at(y)).surfaces[0]
		if spots[i].size() > 2:
			for cand in tower.chunk(TowerShape.chunk_at(y)).surfaces:
				if cand.id == spots[i][2]:
					s = cand
		var a: float = (s.a0 + s.a1) * 0.5
		var r: float = TowerShape.wall_r(s.k, a, 1.0)
		if ChunkPlanner.is_outer(s):
			a = atan2(s.cx, s.cz)
			r = Vector2(s.cx, s.cz).length()
		elif s.kind == ChunkPlanner.Kind.GROUND or s.kind == ChunkPlanner.Kind.RING:
			a = 0.0
			r = TowerShape.apothem(s.k) + 1.0
		# Deep night for the meadow shot, early evening for the rest
		weather.day_time = 0.75 if spots[i][0] == "meadow_night" else 0.3
		var airborne: bool = spots[i][0] in ["airborne", "updraft", "wire", "rings"]
		if spots[i][0] in ["updraft", "wire", "rings"]:
			var d: Dictionary = spots[i][3]
			player.place(d.theta, d.r, y)
		else:
			player.place(a, r, s.top - (1.2 if airborne else 0.0))
		player.set_physics_process(not airborne)
		camera.snap()
		for f in 60:
			await get_tree().process_frame
		if spots[i][0] == "ground":
			# A rival bird on the ground beside you
			var b := ClimberBird.new()
			b.tower = tower
			b.dress(ClimberBird.TINTS[2])
			rivals.add_child(b)
			b.place(-0.35, TowerShape.apothem(0) + 1.2, 0.0)
			b.active = false
			for f in 5:
				await get_tree().process_frame
		if spots[i][0] == "band3":
			# A storm flock, caught in a lightning flash
			flocks.spawn(camera, player.y)
			for f in 150:
				await get_tree().process_frame
			# ...and a bolt hitting a ledge beside the bird
			strikes.pending.append({"pos": player.world_position() + Vector3(0, 3.0, 0), "t": 0.0, "fx": null})
			for f in 3:
				await get_tree().process_frame
			weather.flash = 1.0
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := dir.path_join("shot_%02d_%s.png" % [i, spots[i][0]])
		img.save_png(path)
		print("saved ", path)
	get_tree().quit()

# Attract mode for the arcade cabinet's preview video: the camera follows one
# of the climbing birds (the rival AI flying the player's bird) up the tower,
# cutting up through the levels: the meadow, the Misty Spires, the
# Stormcrown, Above the Clouds and the Aurora Vault. Record it landscape
# (Movie Maker uses the project's window size, so override it) with
#   override.cfg: [display] window/size/viewport_width=1280, viewport_height=720
#   godot --path . --write-movie out.avi --fixed-fps 30 -- --record
func _record_attract() -> void:
	var fps := 30
	var run := 4242
	var climber := player as ClimberBird
	climber.speed_mult = 1.35
	climber.patience_max = 0.1
	climber.regen_rate = 200.0
	touch.visible = false
	# [band, seconds]; the first clip runs a second long, for the video's trim
	var clips: Array = [[0, 4.2], [1, 3.2], [3, 3.2], [5, 3.2], [6, 3.2]]
	for clip in clips:
		var band: int = clip[0]
		if band == 0:
			_load_world(run, 0.0, TowerShape.apothem(0) + 1.5, 0.0, 0.0, Tuning.STAMINA_CAP)
		else:
			var s := _route_spot(run, band * TowerShape.CHUNKS_PER_BAND + 1, -1)
			var a: float = (s.a0 + s.a1) * 0.5
			_load_world(run, a, TowerShape.wall_r(s.k, a, min(1.0, s.d1 * 0.5)), s.top, s.top, Tuning.STAMINA_CAP)
		_play()
		rivals.spawn_timer = 0.3
		if band == 3:
			# Make sure the storm shows off: lightning (and a flock) straight away
			weather.lightning_timer = 0.6
			flocks.spawn(camera, player.y)
		await _frames(int(clip[1] * fps))
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

# The route surface to start a clip on: the one just before a surface of
# `kind` in chunk k (when `before` is set), or else chunk k's first ledge
func _route_spot(run: int, k: int, kind: int, before := false) -> Dictionary:
	var path: Array = ChunkPlanner.plan(run, k).surfaces.filter(func(s): return s.path)
	if kind < 0:
		return path[min(1, path.size() - 1)] if k > 0 else path[0]
	for i in range(1, path.size()):
		if path[i].kind == kind:
			return path[i - 1] if before else path[i]
	return {}
