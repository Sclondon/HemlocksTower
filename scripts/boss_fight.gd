class_name BossFight
extends Node3D
# Hemlock, rebuilt, fights the bird on the summit ring at the top of the
# fully grown tower. He circles off to one side and attacks:
#  - gears: spinning cogs lobbed at the ring; each lands on a red mark and
#    bursts a moment later,
#  - beam: his lantern eyes sweep a beam right round the ring at ankle
#    height; jump it as it passes,
#  - swoop: he climbs above the bird, marks the spot, and dives through it.
# After a few attacks he clings to the ring's edge, spent, his wind-up key
# glowing over the walkway: land on the key to wind him down. Three times
# and he's still. The bird has three hearts; falling off the ring costs one.

signal player_hit(hearts: int)
signal boss_hit(hits: int)
signal won
signal lost

const HITS := 3
const HEARTS := 3
const SCALE := 1.6
const ORBIT_R := 11.0                 # well inside the camera's orbit, so he's in shot
const GEAR_FLIGHT := 0.9
const GEAR_FUSE := 0.7
const GEAR_BLAST := 1.8
const MARK := Color(1.0, 0.25, 0.15, 0.55)

var tower: TowerGenerator
var player: Player
var owl: HemlockOwl
var active := false
var ring_k := 0
var ring_y := 0.0
var hits := 0
var hearts := HEARTS
var invuln := 0.0
var state := ""
var t := 0.0                         # seconds in this state
var side := 1.0                      # which side of the bird he hangs about
var attacks_left := 0
var last_attack := ""
var pos := Vector3.ZERO              # where the owl's feet are
var face := Vector3.ZERO             # what he's looking at
var gears: Array = []                # {node, marker, from, to, t}
var thrown := 0
var beam: MeshInstance3D
var beam_theta := 0.0
var beam_dir := 1.0
var swoop_from := Vector3.ZERO
var swoop_to := Vector3.ZERO
var swoop_mark: MeshInstance3D
var perch_theta := 0.0
var key_glow: OmniLight3D

func _ready() -> void:
	owl = HemlockOwl.new()
	owl.scale = Vector3.ONE * SCALE
	owl.visible = false
	add_child(owl)
	key_glow = OmniLight3D.new()
	key_glow.light_color = HemlockOwl.GLOW
	key_glow.omni_range = 5.0
	key_glow.visible = false
	owl.key.add_child(key_glow)
	beam = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.5, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.7, 0.3, 0.95)
	bm.material = m
	beam.mesh = bm
	beam.top_level = true
	beam.visible = false
	add_child(beam)
	swoop_mark = _marker()
	swoop_mark.visible = false

func start(k: int, y: float) -> void:
	stop()
	active = true
	ring_k = k
	ring_y = y
	hits = 0
	hearts = HEARTS
	invuln = 0.0
	owl.visible = true
	owl.show_parts(HemlockOwl.PARTS.size())
	owl.awake = 1.0
	owl.rotation = Vector3.ZERO
	side = 1.0
	pos = _orbit_point(player.theta + 1.2, ring_y - 12.0)
	_enter("intro")

func stop() -> void:
	active = false
	owl.visible = false
	beam.visible = false
	swoop_mark.visible = false
	key_glow.visible = false
	for g in gears:
		g.node.queue_free()
		g.marker.queue_free()
	gears.clear()

func _enter(s: String) -> void:
	state = s
	t = 0.0
	thrown = 0

# --- helpers --------------------------------------------------------------------

func _orbit_point(theta: float, y: float, r := ORBIT_R) -> Vector3:
	return Vector3(sin(theta) * r, y, cos(theta) * r)

func _ring_point(theta: float, d := 1.0) -> Vector3:
	var p := TowerShape.ring_point(ring_k, theta, d)
	return Vector3(p.x, ring_y, p.y)

func _bird() -> Vector3:
	return player.world_position()

func _marker() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = GEAR_BLAST * 0.8
	c.bottom_radius = GEAR_BLAST * 0.8
	c.height = 0.04
	c.radial_segments = 16
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = MARK
	c.material = m
	mi.mesh = c
	mi.top_level = true
	add_child(mi)
	return mi

func _cog() -> Node3D:
	var st := MeshUtil.begin()
	MeshUtil.box(st, Vector3.ZERO, Vector3(0.7, 0.18, 0.7), 0.0, HemlockOwl.BRASS)
	for i in 8:
		var a := TAU * i / 8.0
		MeshUtil.box(st, Vector3(sin(a), 0, cos(a)) * 0.48, Vector3(0.2, 0.18, 0.2), a, HemlockOwl.COPPER)
	var mi := MeshUtil.commit(st, MeshUtil.flat_material(Color.WHITE))
	mi.top_level = true
	add_child(mi)
	return mi

func _burst(at: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = Tuning.particles(24)
	p.lifetime = 0.7
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -12, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	q.material = m
	p.mesh = q
	p.top_level = true
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.5, false).timeout.connect(p.queue_free)

func _hurt_bird() -> void:
	if invuln > 0.0 or not active:
		return
	hearts -= 1
	invuln = 1.6
	player.stun = 0.5
	player.knock.x += 6.0 * side
	player.vy = max(player.vy, 6.0)
	player._leave_ground()
	player_hit.emit(hearts)
	if hearts <= 0:
		_finish(false)

func _finish(win: bool) -> void:
	beam.visible = false
	swoop_mark.visible = false
	key_glow.visible = false
	for g in gears:
		g.node.queue_free()
		g.marker.queue_free()
	gears.clear()
	if win:
		_enter("dying")
		won.emit()
	else:
		active = false
		lost.emit()

# --- per frame ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not active or player == null:
		return
	t += delta
	invuln = max(invuln - delta, 0.0)
	var bird := _bird()
	var speed := 1.0 + 0.25 * hits
	var target := pos
	owl.flap = 1.0
	match state:
		"intro":
			target = _orbit_point(player.theta + 1.2 * side, ring_y + 6.0)
			if t > 3.0:
				attacks_left = 2
				_enter("circle")
		"circle":
			target = _orbit_point(player.theta + 1.1 * side, ring_y + 5.0 + sin(t * 2.0) * 0.8)
			if t > 1.6 / speed:
				if attacks_left <= 0:
					perch_theta = player.theta + 1.8 * side
					_enter("perch")
				else:
					attacks_left -= 1
					var choices := ["gears", "beam", "swoop"]
					choices.erase(last_attack)
					last_attack = choices[randi() % choices.size()]
					if last_attack == "beam":
						beam_theta = atan2(pos.x, pos.z)
						beam_dir = signf(wrapf(player.theta - beam_theta, -PI, PI))
					elif last_attack == "swoop":
						swoop_to = bird - Vector3(0, 1.5 * SCALE, 0)     # his body passes through the bird
						swoop_from = _orbit_point(player.theta, ring_y + 11.0, 9.0)
						var d: float = clamp(player.r - TowerShape.wall_r(ring_k, player.theta, 0.0), 0.2, 1.8)
						swoop_mark.global_position = _ring_point(player.theta, d) + Vector3(0, 0.06, 0)
						swoop_mark.visible = true
					_enter(last_attack)
		"gears":
			target = _orbit_point(player.theta + 1.1 * side, ring_y + 6.0)
			var count := 3 + hits
			if thrown < count and t > 0.3 + thrown * 0.45 / speed:
				thrown += 1
				var aim := player.theta + randf_range(-0.3, 0.3) * (0.0 if thrown == 1 else 1.0)
				var d: float = clamp(player.r - TowerShape.wall_r(ring_k, aim, 0.0), 0.2, 1.8)
				var land := _ring_point(aim, d)
				var mk := _marker()
				mk.global_position = land + Vector3(0, 0.06, 0)
				gears.append({"node": _cog(), "marker": mk, "from": owl.global_position + Vector3(0, 3.0 * SCALE, 0), "to": land, "t": 0.0})
			if thrown >= count and gears.is_empty():
				_enter("circle")
		"beam":
			# Charge (eyes flare), then sweep one full turn round the ring
			var charge := 1.0 / speed
			var omega := 1.3 * speed
			if t > charge:
				beam_theta += beam_dir * omega * delta
			target = _orbit_point(beam_theta, ring_y + 1.8)
			beam.visible = true
			var eye := owl.global_position + owl.global_basis.y * 2.9 + owl.global_basis.z * 0.8
			var hit_at := _ring_point(beam_theta, 0.0) + Vector3(0, 0.6, 0)
			beam.global_position = (eye + hit_at) * 0.5
			beam.look_at_from_position(beam.global_position, hit_at, Vector3.UP)
			beam.scale = Vector3(1.0 if t > charge else 0.3, 1.0 if t > charge else 0.3, eye.distance_to(hit_at))
			if t > charge:
				var off: float = abs(wrapf(player.theta - beam_theta, -PI, PI)) * player.r
				if off < 0.45 and player.y < ring_y + 1.0 and player.y > ring_y - 1.5:
					_hurt_bird()
			if t > charge + TAU / omega:
				beam.visible = false
				_enter("circle")
		"swoop":
			var rise := 0.9 / speed
			var dive := 0.55 / speed
			if t < rise:
				target = swoop_from
			else:
				var k: float = clamp((t - rise) / dive, 0.0, 1.6)
				pos = swoop_from.lerp(swoop_to, k)
				target = pos
				if k <= 1.1 and (owl.global_position + Vector3(0, 1.5 * SCALE, 0)).distance_to(bird) < 2.2:
					_hurt_bird()
				if k >= 1.6:
					swoop_mark.visible = false
					_enter("circle")
		"perch":
			# Clings to the ring's outer edge, leaning in over the walkway
			var edge := TowerShape.wall_r(ring_k, perch_theta, 2.0) + 1.0
			target = _orbit_point(perch_theta, ring_y - 2.6, edge)
			if t > 1.2:
				owl.flap = 0.0
				target = pos
				key_glow.visible = true
				key_glow.light_energy = 2.0 + sin(t * 8.0)
				var key_top := owl.key.global_position + owl.global_basis.y * 0.6    # (the basis carries his scale)
				var flat := Vector2(bird.x - key_top.x, bird.z - key_top.z).length()
				if player.vy <= 0.0 and flat < 1.3 and bird.y > key_top.y - 0.5 and bird.y < key_top.y + 1.2:
					_wound()
				elif t > 1.2 + 5.0 - hits * 0.8:
					key_glow.visible = false
					attacks_left = 2 + hits
					side = -side
					_enter("circle")
		"hurt":
			target = _orbit_point(player.theta + 1.3 * side, ring_y + 7.0)
			if t > 1.4:
				_enter("circle")
		"dying":
			owl.flap = 0.0
			owl.awake = max(owl.awake - delta * 0.5, 0.0)
			target = pos
	if state != "swoop" or t < 0.9 / speed:
		pos = pos.lerp(target, 1.0 - exp(-3.0 * delta))
	owl.global_position = pos

	# Face the bird (or the ring when perched), leaning in when spent
	var look := bird - pos
	owl.rotation = Vector3(0.0, atan2(look.x, look.z), 0.0)
	if state == "perch" and t > 1.2 or state == "dying":
		var inward := -Vector3(pos.x, 0, pos.z).normalized()
		owl.rotation = Vector3(0.45, atan2(inward.x, inward.z), 0.0)

	# Gears in flight, then on their fuses
	for i in range(gears.size() - 1, -1, -1):
		var g: Dictionary = gears[i]
		g.t += delta
		var k: float = min(g.t / GEAR_FLIGHT, 1.0)
		var p: Vector3 = g.from.lerp(g.to, k) + Vector3(0, sin(k * PI) * 4.0, 0)
		g.node.global_position = p + Vector3(0, 0.1, 0)
		g.node.rotation.y += delta * 9.0
		var mat := (g.marker.mesh as CylinderMesh).material as StandardMaterial3D
		mat.albedo_color.a = MARK.a * (0.5 + 0.5 * sin(g.t * 20.0)) if k >= 1.0 else MARK.a * 0.5
		if g.t > GEAR_FLIGHT + GEAR_FUSE:
			_burst(g.to + Vector3(0, 0.4, 0), Color(1.0, 0.6, 0.2))
			if bird.distance_to(g.to) < GEAR_BLAST and bird.y < g.to.y + 2.0:
				_hurt_bird()
			g.node.queue_free()
			g.marker.queue_free()
			gears.remove_at(i)

	# Knocked off the ring: back on, a heart the poorer
	if active and player.y < ring_y - 3.0:
		var away := atan2(pos.x, pos.z) + PI
		player.place(away, TowerShape.wall_r(ring_k, away, 1.0), ring_y + 0.5)
		invuln = 0.0
		_hurt_bird()
		invuln = 1.6

func _wound() -> void:
	hits += 1
	key_glow.visible = false
	player.bounce(15.0)
	_burst(owl.key.global_position, HemlockOwl.GLOW)
	# A piece of him breaks away
	var lose: int = [1, 2, 3][min(hits - 1, 2)]
	owl.parts[lose].visible = false
	_burst(owl.parts[lose].global_position + Vector3(0, 1.5 * SCALE, 0), HemlockOwl.BRASS)
	boss_hit.emit(hits)
	if hits >= HITS:
		_finish(true)
	else:
		attacks_left = 2 + hits
		side = -side
		_enter("hurt")
