class_name Feathers
extends Node3D
# Feathers, in two kinds:
#  - Moulted ones: a few shake loose when a bird flaps, lands hard or gets
#    hit, and drift down swaying side to side (flipping at each swing, the
#    way a real feather rocks) before fading.
#  - Loose plumes you can catch: they top your stamina up. They grow on the
#    tower where seeds used to, and crows shed them: a crow flying past now
#    and then, rivals flapping near you, crows startled off a wire.
# One of these lives in the world; anything can reach it through `the`.

const PLUME_CATCH := 1.3             # how close a plume has to be to catch it
const PLUME_LIFE := 14.0
const DRIFT_LIFE := 2.6
const MAX_DRIFT := 40
const PASS_EVERY := Vector2(14.0, 28.0)   # seconds between crows flying past

static var the: Feathers

var player: Player
var drift: Array = []                # {node, v, phase, age}
var plumes: Array = []               # {node, v, phase, age}
var crows: Array = []                # {node, theta, r, y, dir, age, sheds}
var pass_timer := 10.0

static var _dark: Texture2D
static var _pale: Texture2D

func _ready() -> void:
	the = self
	top_level = true

# A moulted feather: dark, with a paler quill so it shows against the walls
static func dark_texture() -> Texture2D:
	if _dark == null:
		_dark = MeshUtil.pixel_texture([
			"....oq.",
			"...ooq.",
			"..oooqo",
			"..ooqoo",
			".oooqoo",
			".ooqoo.",
			"oooqoo.",
			"ooqoo..",
			"oqoo...",
			".qo....",
			".q.....",
			"q......",
		], {"o": Color(0.16, 0.12, 0.22), "q": Color(0.62, 0.58, 0.72)})
	return _dark

# A loose plume to catch: pale and outlined, so it reads as a pickup
static func pale_texture() -> Texture2D:
	if _pale == null:
		_pale = MeshUtil.pixel_texture([
			".....kk.",
			"....kwqk",
			"...kwwqk",
			"..kwwqwk",
			"..kwqwwk",
			".kwwqwk.",
			".kwqwwk.",
			"kwwqwk..",
			"kwqwk...",
			".kqk....",
			".kq.....",
			"kq......",
		], {"k": Color(0.2, 0.18, 0.3), "w": Color(0.93, 0.95, 1.0), "q": Color(0.62, 0.66, 0.8)})
	return _pale

func _sprite(tex: Texture2D, size: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = size / tex.get_height()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	s.double_sided = true
	add_child(s)
	return s

# A few moulted feathers shaken loose at `at`
func burst(at: Vector3, n: int) -> void:
	for i in n:
		if drift.size() >= MAX_DRIFT:
			var old: Dictionary = drift.pop_front()
			old.node.queue_free()
		var s := _sprite(dark_texture(), randf_range(0.45, 0.6))
		s.global_position = at + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.4), randf_range(-0.3, 0.3))
		drift.append({"node": s, "v": Vector3(randf_range(-1.5, 1.5), randf_range(0.8, 2.2), randf_range(-1.5, 1.5)),
			"phase": randf() * TAU, "age": 0.0, "swing": randf_range(2.4, 3.4)})

# A catchable plume at `at` (a crow shed it)
func shed(at: Vector3) -> void:
	var s := _sprite(pale_texture(), 0.7)
	s.global_position = at
	plumes.append({"node": s, "v": Vector3(randf_range(-0.8, 0.8), 0.6, randf_range(-0.8, 0.8)),
		"phase": randf() * TAU, "age": 0.0, "swing": randf_range(1.8, 2.4)})

# A bird flapped somewhere: moult, and a rival near you may shed a plume
func on_flap(bird: Player) -> void:
	var at := bird.world_position() + Vector3(0, 0.6, 0)
	burst(at, randi_range(1, 2))
	if bird.is_npc and player and at.distance_to(player.world_position()) < 10.0 and randf() < 0.2:
		shed(at)

func clear() -> void:
	for list in [drift, plumes]:
		for d in list:
			d.node.queue_free()
		list.clear()
	for c in crows:
		c.node.queue_free()
	crows.clear()

func _process(delta: float) -> void:
	# Moulted feathers: a slow fall, rocking side to side
	for i in range(drift.size() - 1, -1, -1):
		var d: Dictionary = drift[i]
		if _sway(d, delta, 1.1) or d.age > DRIFT_LIFE:
			d.node.queue_free()
			drift.remove_at(i)
			continue
		d.node.modulate.a = clamp((DRIFT_LIFE - d.age) / 0.6, 0.0, 1.0)
	# Plumes: slower still, and caught by flying (or walking) into them
	var bird := player.world_position() + Vector3(0, 0.5, 0) if player else Vector3.INF
	for i in range(plumes.size() - 1, -1, -1):
		var p: Dictionary = plumes[i]
		var gone: bool = _sway(p, delta, 0.6) or p.age > PLUME_LIFE
		if not gone and p.node.global_position.distance_to(bird) < PLUME_CATCH:
			player.stamina = min(player.stamina + Tuning.PLUME_STAMINA, player.max_stamina)
			player.picked_up.emit("plume")
			burst(p.node.global_position, 2)
			gone = true
		if gone:
			p.node.queue_free()
			plumes.remove_at(i)
			continue
		p.node.modulate.a = clamp((PLUME_LIFE - p.age) / 1.5, 0.0, 1.0)
	_passing_crows(delta)

# Moves a drifting feather; true once it's reached the ground
func _sway(d: Dictionary, delta: float, sink: float) -> bool:
	d.age += delta
	d.phase += delta * d.swing
	# Settle into a slow fall, the sideways fling dying away
	d.v.x = move_toward(d.v.x, 0.0, 2.0 * delta)
	d.v.z = move_toward(d.v.z, 0.0, 2.0 * delta)
	d.v.y = move_toward(d.v.y, -sink, 4.0 * delta)
	var s: Sprite3D = d.node
	var cam := get_viewport().get_camera_3d()
	var side := cam.global_transform.basis.x if cam else Vector3.RIGHT
	var swing := cos(d.phase)
	s.global_position += d.v * delta + side * swing * 1.1 * delta
	# ...dipping at each end of the swing, and flipping as it turns
	s.global_position.y -= abs(sin(d.phase)) * 0.25 * delta
	s.flip_h = swing < 0.0
	return s.global_position.y < 0.0

# Every so often a crow flies across near the bird, and sheds a plume or two
func _passing_crows(delta: float) -> void:
	for i in range(crows.size() - 1, -1, -1):
		var c: Dictionary = crows[i]
		c.age += delta
		c.theta += c.dir * 7.5 / c.r * delta
		var at := Vector3(sin(c.theta) * c.r, c.y + sin(c.age * 5.0) * 0.3, cos(c.theta) * c.r)
		c.node.global_position = at
		if c.sheds.size() > 0 and c.age >= c.sheds[0]:
			c.sheds.pop_front()
			shed(at)
		if c.age > 4.0:
			c.node.queue_free()
			crows.remove_at(i)
	if player == null or not player.active:
		return
	pass_timer -= delta
	if pass_timer > 0.0:
		return
	pass_timer = randf_range(PASS_EVERY.x, PASS_EVERY.y)
	var dir := 1.0 if randf() < 0.5 else -1.0
	var crow := AnimatedSprite3D.new()
	crow.sprite_frames = Npc.recoloured(Player.FLAP_FRAMES, Npc.TINTS.values().pick_random())
	crow.pixel_size = 0.085
	crow.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	crow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	crow.shaded = false
	crow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	crow.speed_scale = 2.5
	crow.flip_h = dir > 0.0
	crow.play("default")
	add_child(crow)
	var r := player.r + randf_range(1.5, 4.0)
	crows.append({"node": crow, "theta": player.theta - dir * 15.0 / r, "r": r, "y": player.y + randf_range(2.0, 4.5),
		"dir": dir, "age": 0.0, "sheds": [randf_range(1.2, 1.8)] + ([randf_range(2.0, 2.6)] if randf() < 0.5 else [])})
