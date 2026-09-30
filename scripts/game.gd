extends Node
# Hemlock's Tower: a bird climbing a procedurally built tower.
# Builds the low-res 3D view and the UI, and runs the flow between the menus
# and the two ways to play:
#  - The Ascent: the tower is built one section (weather band) at a time.
#    Each ends in a summit beacon; land beside it and the tower throws you
#    off and grows the next section. Sections are fixed, so best times mean
#    something.
#  - Endless: a fresh random tower that never ends, dressed only in the
#    sections you've reached. One big fall ends the run; its height is the
#    score sent to the hosting web page.

enum State { TITLE, PLAYING, PAUSED, CINEMATIC, RESULTS }
enum Mode { ASCENT, ENDLESS, BOSS }

const SAVE_PATH := "user://climb.json"
const BEST_PATH := "user://best.save"
const PROGRESS_PATH := "user://progress.json"
const PIXEL_SCALE := 2               # 3D is drawn at 1/2 res and scaled up crisp
const AUTOSAVE_EVERY := 4.0
const SECTIONS := 7                  # one per kind of weather band
const ASCENT_SEED := 20241031        # the Ascent's tower is the same for everyone

var state := State.TITLE
var mode := Mode.ASCENT
var section := 0
var run_seed := 0
var run_time := 0.0
var falls := 0
var climbing := false                # Ascent from the meadow: left the hub yet? (the clock starts then)
var best := 0.0                      # Endless best height
var progress := {"cleared": 0, "times": {}, "beaten": false}
var last_band := -1
var autosave_timer := 0.0
var shots_mode := false
var record_mode := false             # attract-mode montage for the arcade preview video
var on_primary := Callable()         # what the results screen's main button does

var tower: TowerGenerator
var player: Player
var camera: OrbitCamera
var weather: Weather
var clouds: CloudLayers
var flocks: BackgroundBirds
var rivals: Climbers
var strikes: LightningStrikes
var summit: Summit
var feathers: Feathers
var stations: HubStations
var talk: BirdTalk
var boss: BossFight
var pending_station := ""
var hud: Hud
var touch: TouchControls
var menus: Menus
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
		_load_progress()
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
	feathers = Feathers.new()
	feathers.player = player
	world.add_child(feathers)
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
	# Events are commented on by the birds, not written on screen
	player.powered.connect(func(kind): talk.comment(kind))
	player.picked_up.connect(func(kind): if kind in ["feather", "poison", "plume"]: talk.comment(kind, true, 0.3 if kind == "plume" else 0.6))
	player.landed.connect(func(h): if h > Tuning.STUN_FALL and state == State.PLAYING: talk.comment("fall", true, 0.7))
	weather.changed.connect(func(_line):
		if state == State.PLAYING:
			var cold: bool = Weather.weather_of(weather.band).get("cold", false)
			talk.comment("snowy" if cold and weather.state_name == "rainy" else weather.state_name, true))


func _build_ui() -> void:
	summit = Summit.new()
	summit.visible = false
	tower.add_child(summit)
	talk = BirdTalk.new()
	talk.tower = tower
	talk.player = player
	talk.rivals = rivals
	talk.weather = weather
	add_child(talk)
	stations = HubStations.new()
	tower.add_child(stations)
	stations.entered.connect(_open_station)
	boss = BossFight.new()
	boss.tower = tower
	boss.player = player
	tower.add_child(boss)
	boss.player_hit.connect(func(h):
		hud.hurt()
		talk.say_self("hurt")
		hud.set_boss(true, 1.0 - float(boss.hits) / BossFight.HITS, h))
	boss.boss_hit.connect(func(n):
		camera.shake = 0.8
		talk.say_self("boss_hit")
		hud.set_boss(true, 1.0 - float(n) / BossFight.HITS, boss.hearts))
	camera.watch = boss.owl
	boss.won.connect(_boss_over.bind(true))
	boss.lost.connect(_boss_over.bind(false))
	player.landed.connect(func(h): if h > Tuning.STUN_FALL and state == State.PLAYING: falls += 1)

	var layer := CanvasLayer.new()
	add_child(layer)
	# Crows' speech bubbles, drawn crisp at full resolution under the rest of the UI
	var bubbles := Control.new()
	bubbles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bubbles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bubbles)
	SpeechBubble.overlay = bubbles
	SpeechBubble.view_scale = PIXEL_SCALE
	touch = TouchControls.new()
	touch.process_mode = Node.PROCESS_MODE_PAUSABLE
	layer.add_child(touch)
	hud = Hud.new()
	hud.theme = Menus.make_theme()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(hud)
	hud.pause_pressed.connect(_pause)

	menus = Menus.new()
	menus.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(menus)
	menus.continue_pressed.connect(_continue_climb)
	menus.section_chosen.connect(_start_section)
	menus.play_pressed.connect(_enter_hub)
	menus.sections_closed.connect(_close_station)
	menus.prompt_answered.connect(_on_prompt)
	menus.title_pressed.connect(_enter_title)
	menus.resume_pressed.connect(_resume)
	menus.end_pressed.connect(_end_climb)
	menus.primary_pressed.connect(func(): on_primary.call())
	menus.menu_pressed.connect(_enter_hub)

	debug_label = Hud.make_label(16, Color(0.7, 1, 0.7))
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	debug_label.position = Vector2(12, 120)
	debug_label.visible = false
	layer.add_child(debug_label)

# --- flow ---------------------------------------------------------------------

func unlocked() -> int:
	return mini(int(progress.cleared) + 1, SECTIONS)

static func section_name(s: int) -> String:
	return Weather.TYPES[s % Weather.TYPES.size()].name

static func _start_y(s: int) -> float:
	return s * TowerShape.BAND_H + (0.5 if s > 0 else 0.0)

static func _start_r(s: int) -> float:
	return TowerShape.apothem(s * TowerShape.CHUNKS_PER_BAND) + (1.5 if s == 0 else 1.0)

# Sets the tower up for a mode before a world is loaded: where it ends, and
# (for Endless) which sections' looks it cycles through
func _configure(m: Mode, s: int, styles := 0) -> void:
	mode = m
	section = s
	TowerShape.style_count = styles
	tower.cap_chunk = (s + 1) * TowerShape.CHUNKS_PER_BAND if m == Mode.ASCENT else -1
	tower.reveal_top = INF
	summit.visible = m == Mode.ASCENT
	if summit.visible:
		summit.build(tower.cap_chunk)
	weather.band = -1
	weather.locked = ""
	rivals.process_mode = Node.PROCESS_MODE_INHERIT
	boss.stop()
	hud.set_boss(false, 1.0, 0)
	stations.set_parts(int(progress.cleared), bool(progress.beaten))

func _enter_title() -> void:
	state = State.TITLE
	get_tree().paused = false
	var save := _read_save()
	if save.is_empty():
		# The meadow, as a backdrop
		_configure(Mode.ASCENT, 0)
		_load_world(ASCENT_SEED, 0.0, _start_r(0), 0.0, 0.0)
		climbing = false
		run_time = 0.0
		falls = 0
	else:
		var m := Mode.ENDLESS if save.get("mode", "endless") == "endless" else Mode.ASCENT
		_configure(m, int(save.get("section", 0)), int(save.get("styles", 0)))
		_load_world(int(save.seed), save.theta, save.r, save.y, save.max_y,
			save.get("max_stamina", Tuning.BASE_STAMINA), save.get("feathers", []))
		run_time = float(save.get("time", 0.0))
		falls = int(save.get("falls", 0))
		climbing = bool(save.get("climbing", true))
	player.active = false
	camera.orbit_idle = true
	camera.idle_time = 0.0
	hud.visible = false
	touch.visible = false
	menus.show_title({
		"continue_text": "" if save.is_empty() else "Continue  ·  %d m" % int(save.y),
		"cleared": int(progress.cleared), "sections": SECTIONS, "endless_best": int(best),
	})

func _load_world(new_seed: int, theta: float, r: float, y: float, max_y: float, bucket := Tuning.BASE_STAMINA, taken: Array = []) -> void:
	run_seed = new_seed
	tower.reset(run_seed, taken)
	rivals.clear()
	player.max_stamina = bucket
	player.visible = true
	player.set_physics_process(true)
	clouds.clear()
	feathers.clear()
	tower.stream(y, true)
	player.max_y = max_y
	player.place(theta, r, y)
	camera.cine = false
	camera.shake = 0.0
	camera.snap()
	last_band = TowerShape.band_at(y)

func _start_section(s: int) -> void:
	_configure(Mode.ASCENT, s)
	weather.reset_clock()
	_load_world(ASCENT_SEED, 0.0, _start_r(s), _start_y(s), _start_y(s))
	run_time = 0.0
	falls = 0
	climbing = s > 0
	_play()

# The meadow at the tower's foot: the hub, and the start of the Ascent
func _enter_hub() -> void:
	_start_section(0)

func _start_endless() -> void:
	_configure(Mode.ENDLESS, 0, unlocked())
	weather.reset_clock()
	_load_world(randi(), 0.0, _start_r(0), 0.0, 0.0)
	run_time = 0.0
	falls = 0
	climbing = true
	_play()

func _continue_climb() -> void:
	_play()

func _play() -> void:
	state = State.PLAYING
	get_tree().paused = false
	player.active = true
	camera.orbit_idle = false
	camera.cine = false
	menus.hide_all()
	hud.visible = true
	touch.visible = true
	_update_hud()
	hud.show_banner(Weather.band_name(TowerShape.band_at(player.y)))
	_write_save()

func _pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	touch.release_all()
	get_tree().paused = true
	if mode == Mode.BOSS:
		menus.show_pause("HEMLOCK  ·  THE CLOCKWORK OWL", "Flee to the Meadow")
	elif mode == Mode.ENDLESS:
		menus.show_pause("ENDLESS  ·  %d M" % int(player.max_y), "End Climb")
	elif climbing:
		menus.show_pause("SECTION %s  ·  %s" % [Menus.NUMERALS[section], section_name(section).to_upper()], "Return to the Meadow")
	else:
		menus.show_pause("THE MEADOW")
	_write_save()

func _resume() -> void:
	if state == State.PAUSED:
		state = State.PLAYING
		get_tree().paused = false
		menus.hide_all()

func _end_climb() -> void:
	get_tree().paused = false
	if mode == Mode.ENDLESS:
		_endless_over(false)
	else:
		_enter_hub()

# The bird walked into one of the meadow's stations
func _open_station(id: String) -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	touch.release_all()
	get_tree().paused = true
	if id == "travel":
		var names := []
		for i in SECTIONS:
			names.append(section_name(i))
		menus.set_sections(names, int(progress.cleared), progress.times)
		menus.show_screen("sections")
	elif id == "hemlock":
		menus.show_prompt("HEMLOCK STIRS",
			"Every piece of him is back where it belongs. Wind his key and he'll fly to the top of the tower, and he won't go quietly."
				if not progress.beaten else "He sleeps, but the key still turns. Wake him for another round?",
			"Wind the Key", "Not Yet")
	elif mode == Mode.ENDLESS:
		menus.show_prompt("WAKE UP?", "A splash of the green stew and the dream ends here, at %d m." % int(player.max_y),
			"Wake Up", "Keep Dreaming")
	else:
		var n := unlocked()
		menus.show_prompt("THE DREAMING STEW",
			"Sink into the brew and dream a tower that never ends, built from the %d section%s you've reached. One long fall, and you wake."
				% [n, "" if n == 1 else "s"], "Dive In", "Not Yet")
	pending_station = id

func _close_station() -> void:
	if state == State.PAUSED:
		state = State.PLAYING
		get_tree().paused = false
		menus.hide_all()
		if pending_station in ["travel", "dream"]:
			stations.spit_out(player)     # "not yet": the cauldron spits you back out

func _on_prompt(yes: bool) -> void:
	if not yes:
		_close_station()
	elif pending_station == "hemlock":
		_start_boss()
	elif mode == Mode.ENDLESS:
		get_tree().paused = false
		_endless_over(false)
	else:
		_start_endless()

# --- the boss -----------------------------------------------------------------

# On top of the fully grown tower, in a storm at night
func _start_boss() -> void:
	_configure(Mode.ASCENT, SECTIONS - 1)
	mode = Mode.BOSS
	weather.reset_clock()
	weather.day_time = 0.72
	weather.locked = "storm"
	var y := tower.cap_chunk * TowerShape.CHUNK_H
	_load_world(ASCENT_SEED, 0.0, TowerShape.wall_r(tower.cap_chunk, 0.0, 1.0), y + 0.5, y)
	rivals.process_mode = Node.PROCESS_MODE_DISABLED
	run_time = 0.0
	falls = 0
	climbing = true
	_play()
	boss.start(tower.cap_chunk, y)
	hud.set_boss(true, 1.0, boss.hearts)
	hud.show_banner("")
	menus.show_caption("HEMLOCK", "THE CLOCKWORK OWL", 2.0)

func _boss_over(win: bool) -> void:
	state = State.CINEMATIC
	player.active = false
	touch.release_all()
	touch.visible = false
	var time := run_time
	var hearts_left := boss.hearts
	if win:
		progress.beaten = true
		_save_progress()
		menus.show_caption("THE CLOCKWORK STILLS", "", 2.0)
		await _wait(3.5)
	else:
		menus.show_caption("HEMLOCK PREVAILS", "", 1.4)
		await _wait(2.6)
		boss.stop()
	hud.visible = false
	state = State.RESULTS
	camera.orbit_idle = true
	on_primary = _start_boss
	menus.show_results({
		"title": "HEMLOCK RESTS" if win else "WOUND DOWN",
		"sub": "THE CLOCKWORK OWL",
		"rows": [["Time", Menus.clock(time)], ["Hearts left", str(max(hearts_left, 0))], ["Key turns", "%d / %d" % [boss.hits, BossFight.HITS]]],
		"note": "The storm breaks. The tower is quiet at last." if win else "Stomp the glowing key when he clings to the ring, spent.",
		"primary": "Fight Again" if win else "Try Again",
	})

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout

# Endless: one fall too many (or the player ended it). Scores the run.
func _endless_over(fell: bool) -> void:
	state = State.CINEMATIC
	player.active = false
	touch.release_all()
	touch.visible = false
	menus.hide_all()
	var score := int(player.max_y)
	var old_best := best
	_update_best()
	_clear_save()
	# Tell the hosting page (e.g. the arcade cabinet site) how high we got
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.parent.postMessage({ type: 'PLAYER_DIED', score: %d }, '*')" % score, true)
	if fell:
		talk.say_self("long_fall")
		await _wait(2.0)
	hud.visible = false
	state = State.RESULTS
	camera.orbit_idle = true
	on_primary = _start_endless
	menus.show_results({
		"title": "CLIMB OVER",
		"sub": "ENDLESS  ·  %d OF %d SECTIONS" % [TowerShape.style_count, SECTIONS],
		"rows": [["Height", "%d m" % score, score > old_best], ["Best", "%d m" % int(best)],
			["Time", Menus.clock(run_time)], ["Gold feathers", str(tower.collected.size())]],
		"note": "A new best!" if score > old_best and old_best > 0 else "",
		"primary": "Climb Again",
	})

# Ascent: the bird has landed at the summit beacon. The tower shudders,
# throws it off, and grows the next section up under its crown.
func _summit_reached() -> void:
	state = State.CINEMATIC
	player.active = false
	touch.release_all()
	touch.visible = false
	hud.visible = false
	var s := section
	var key := str(s)
	var time := run_time
	var record: bool = not progress.times.has(key) or time < float(progress.times[key])
	if record:
		progress.times[key] = time
	var first_clear: bool = int(progress.cleared) <= s
	progress.cleared = maxi(int(progress.cleared), s + 1)
	_save_progress()
	_clear_save()
	var top := tower.cap_chunk * TowerShape.CHUNK_H

	menus.show_caption("SUMMIT", section_name(s).to_upper(), 1.3)
	await _wait(2.2)
	camera.shake = 1.0
	await _wait(1.1)
	# Shrugged off: flung outward and up, tumbling
	player._leave_ground()
	player.knock.y += 16.0
	player.vy = 14.0
	player.stun = 3.0
	camera.cine = true
	camera.cine_y = top + 2.0
	await _wait(1.2)
	player.visible = false
	player.set_physics_process(false)

	var new_cap := tower.cap_chunk + TowerShape.CHUNKS_PER_BAND
	tower.reveal_top = top
	tower.set_cap(new_cap)
	camera.shake = 0.7
	var grow := create_tween()
	grow.tween_method(_grow_to, top, float(new_cap) * TowerShape.CHUNK_H, 5.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await grow.finished
	tower.reveal_top = INF
	for k in tower.chunks:
		tower.chunks[k].position.y = 0.0
	summit.build(new_cap)
	camera.shake = 0.5
	menus.show_caption("THE TOWER GROWS", "", 1.2)
	await _wait(2.3)
	if first_clear:
		# A piece of Hemlock was up here all along
		menus.show_caption("RECOVERED", HemlockOwl.part_name(s).to_upper(), 1.4)
		await _wait(2.4)

	state = State.RESULTS
	var last := s + 1 >= SECTIONS
	var note := ""
	if first_clear:
		note = "%s waits for you in the meadow. " % HemlockOwl.part_name(s)
	if last:
		note += "Hemlock is whole again. Wind his key, if you dare."
	elif first_clear:
		note += "%s is open to climb." % section_name(s + 1)
	on_primary = _start_boss if last else _start_section.bind(s + 1)
	menus.show_results({
		"title": "SUMMIT REACHED",
		"sub": "SECTION %s  ·  %s" % [Menus.NUMERALS[s], section_name(s).to_upper()],
		"rows": [["Time", Menus.clock(time), record], ["Best time", Menus.clock(float(progress.times[key]))],
			["Big falls", str(falls)], ["Gold feathers", str(tower.collected.size())]],
		"note": ("A new best time!  " if record and not first_clear else "") + note,
		"primary": "Face Hemlock" if last else "Climb On",
	})

func _grow_to(y: float) -> void:
	summit.position.y = y
	tower.reveal_top = y
	# The newest chunk slides up out of the one below, its top under the crown
	for k in tower.chunks:
		tower.chunks[k].position.y = min(0.0, y - (k + 1) * TowerShape.CHUNK_H)
	camera.cine_y = y - 3.0
	camera.shake = max(camera.shake, 0.35)

# --- per frame ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if state == State.PLAYING:
			_pause()
		elif state == State.PAUSED and menus.current == "pause":
			_resume()
	elif OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo:
		_debug_key(event.physical_keycode)

# Where the action is: the bird, or the crown while the camera watches it
func _focus() -> Vector3:
	if camera.cine:
		return Vector3(sin(camera.cam_theta) * 6.0, camera.cine_y, cos(camera.cam_theta) * 6.0)
	return player.world_position()

func _physics_process(delta: float) -> void:
	if state == State.PAUSED:
		return
	tower.stream(_focus().y)
	tower.tick(delta)
	if mode != Mode.BOSS:
		strikes.update(delta)

func _process(delta: float) -> void:
	var focus := _focus()
	weather.update(delta, focus, camera.cam_theta)
	# The forest fades toward the fog's own colour with distance (see forest.gdshader)
	for m in TowerChunk.forest_materials:
		m.set_shader_parameter("haze", weather.env.fog_light_color)
		m.set_shader_parameter("fade_far", clamp(weather.env.fog_depth_end, 200.0, 420.0))
	player.weather_wind = weather.wind
	tower.set_glow(weather.current.glow)
	clouds.update(focus.y, weather.cloud_tint, camera.global_position)
	flocks.update(delta, camera, focus.y, weather.current.lightning)
	tower.tick_npcs(delta, focus)
	tower.meadow.update(delta, focus.y, 1.0 - weather.dayness, camera.global_position)

	SpeechBubble.overlay.visible = menus.current == ""
	stations.active = mode == Mode.ENDLESS or section == 0
	talk.enabled = state == State.PLAYING
	stations.update(delta, player, mode == Mode.ENDLESS, state == State.PLAYING)
	if state != State.PLAYING:
		return
	# The Ascent's clock starts once the bird leaves the meadow
	if not climbing and player.y > Tuning.HUB_TOP:
		climbing = true
		run_time = 0.0
		falls = 0
	if climbing:
		run_time += delta
	_update_hud()
	var band := TowerShape.band_at(player.y)
	if band > last_band:
		hud.show_banner(Weather.band_name(band))
	last_band = band
	autosave_timer += delta
	if autosave_timer > AUTOSAVE_EVERY and player.grounded:
		autosave_timer = 0.0
		_write_save()
	if mode == Mode.ASCENT:
		if player.grounded and player.ground.get("k", -1) == tower.cap_chunk:
			_summit_reached()
			return
		# Fell out of the bottom of the section: back to its start
		if section > 0 and player.y < section * TowerShape.BAND_H - Tuning.SECTION_FALL_OUT:
			falls += 1
			tower.stream(_start_y(section), true)
			player.place(0.0, _start_r(section), _start_y(section))
			camera.snap()
			talk.comment("carried")
	elif mode == Mode.ENDLESS and not player.grounded and player.fall_from - player.y > Tuning.ENDLESS_FALL:
		_endless_over(true)
		return
	if debug_label.visible:
		debug_label.text = "fps %d\ny %.1f  band %d (%d sides)\ntheta %.2f  r %.2f\nstamina %.2f  wind %.2f\nchunks %d" % [
			Engine.get_frames_per_second(), player.y, band, TowerShape.sides(TowerShape.chunk_at(player.y)),
			player.theta, player.r, player.stamina, weather.wind, tower.chunks.size()]

func _update_hud() -> void:
	if mode == Mode.ASCENT and not climbing:
		hud.set_heights(player.y, 0.0, "The Meadow")
	elif mode == Mode.ASCENT:
		hud.set_heights(player.y, 0.0, "Summit %d m   ·   %s" % [int(tower.cap_chunk * TowerShape.CHUNK_H), Menus.clock(run_time)])
	else:
		hud.set_heights(player.y, max(best, player.max_y))
	hud.set_stamina(player.stamina, player.max_stamina)
	hud.set_powers(player.powers)

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
	if shots_mode or record_mode:
		return                       # test runs never touch the player's saves
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

# (Endless only: the Ascent keeps best times instead)
func _update_best() -> void:
	if mode == Mode.ENDLESS and player.max_y > best:
		best = player.max_y
		_store("best", BEST_PATH + ".txt", str(int(best)))

func _load_best() -> void:
	best = float(_fetch("best", BEST_PATH + ".txt").to_int())
	# Best scores from the previous version were a raw 32-bit int in best.save
	var f := FileAccess.open(BEST_PATH, FileAccess.READ)
	if f:
		best = max(best, f.get_32())

func _load_progress() -> void:
	var text := _fetch("progress", PROGRESS_PATH)
	var data = JSON.parse_string(text) if text != "" else null
	if data is Dictionary:
		progress.cleared = clampi(int(data.get("cleared", 0)), 0, SECTIONS)
		progress.beaten = bool(data.get("beaten", false))
		if data.get("times") is Dictionary:
			progress.times = data.times

func _save_progress() -> void:
	if not (shots_mode or record_mode):
		_store("progress", PROGRESS_PATH, JSON.stringify(progress))

func _clear_save() -> void:
	_store("climb", SAVE_PATH, "{}")

func _write_save() -> void:
	if shots_mode or record_mode or mode == Mode.BOSS:
		return
	_update_best()
	_store("climb", SAVE_PATH, JSON.stringify({
		"mode": "endless" if mode == Mode.ENDLESS else "ascent", "section": section, "styles": TowerShape.style_count,
		"seed": run_seed, "theta": player.theta, "r": player.r, "y": player.y, "max_y": player.max_y,
		"max_stamina": player.max_stamina, "feathers": tower.collected.keys(), "time": run_time, "falls": falls, "climbing": climbing,
	}))

func _read_save() -> Dictionary:
	var text := _fetch("climb", SAVE_PATH)
	var data = JSON.parse_string(text) if text != "" else null
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
		KEY_F4:
			# Ascent: drop onto the summit ledge
			if mode == Mode.ASCENT and state == State.PLAYING:
				var y := tower.cap_chunk * TowerShape.CHUNK_H
				tower.stream(y, true)
				player.place(0.0, TowerShape.apothem(tower.cap_chunk) + 1.0, y + 0.5)
				camera.snap()

# Renders each band from a fixed seed and saves screenshots, then quits.
# Run: godot --path . -- --shots
func _take_shots() -> void:
	var dir := ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	_configure(Mode.ENDLESS, 0)
	_load_world(1234, 0.0, TowerShape.apothem(0) + 1.5, 0.0, 0.0)
	menus.hide_all()
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
	var streams_found := false
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
		if not streams_found and not pl.streams.is_empty():
			streams_found = true
			var p0: Vector3 = pl.streams[0].pts[1]
			spots.append(["streams", p0.y, "", {"theta": atan2(p0.x, p0.z), "r": Vector2(p0.x, p0.z).length(), "up": true, "y0": p0.y}])
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
		var airborne: bool = spots[i][0] in ["airborne", "updraft", "wire", "streams"]
		if spots[i][0] in ["updraft", "wire", "streams"]:
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
	_configure(Mode.ENDLESS, 0)
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
