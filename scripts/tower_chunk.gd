class_name TowerChunk
extends Node3D
# One 12 m slice of tower built from a ChunkPlanner plan. Holds the runtime
# state of its surfaces (moving, bobbing and crumbling ones) and pickups.

const Kind = ChunkPlanner.Kind
const GLASS_SHADER := preload("res://shaders/stained_glass.gdshader")

const CRUMBLE_DELAY := 1.0           # crusty ledge: falls this long after you touch it
const FRAGILE_DELAY := 0.3           # cracked ledge: holds you, falls once you leave
const FALL_TIME := 1.6
const RESPAWN_TIME := 8.0            # both grow back, since a fall can bring you back here
const ISLAND_BOB := 0.25

const WOOD := Color(0.42, 0.28, 0.18)
const ROOF := Color(0.32, 0.22, 0.3)

const PICKUP_RESPAWN := 25.0         # seeds and poison grow back; gold feathers don't
const POWER_RESPAWN := 45.0
const POWERS := ["sunseed", "spring", "cloud", "charm"]
const GLOWS := {"feather": Color(1.0, 0.82, 0.3), "sunseed": Color(1.0, 0.7, 0.2), "spring": Color(1.0, 0.4, 0.45),
	"cloud": Color(0.75, 0.9, 1.0), "charm": Color(0.75, 0.45, 1.0)}
static var _pickup_tex := {}

var plan: Dictionary
var surfaces: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var glass: Array[ShaderMaterial] = []
var drafts: Array[Dictionary] = []
var npcs: Array[Npc] = []
var wires: Array[Dictionary] = []
var streams: Array[Dictionary] = []    # wind streams (see ChunkPlanner._plan_streams)
var speakers: Array = []               # crows' speech bubbles (ticked here)
var built := false

# `collected` holds ids of gold feathers already taken this run (they don't return)
func setup(p: Dictionary, collected: Dictionary) -> void:
	plan = p
	surfaces = p.surfaces
	for s in surfaces:
		s.offset = 0.0
		s.broken = false
		s.crumble = -1.0
		s.node = null
	for pk in p.pickups:
		if collected.has(pk.id):
			continue
		var d: Dictionary = pk.duplicate()
		d.taken = -1.0                   # seconds since taken, -1 while available
		d.home = Vector3(d.theta, d.r, d.y)
		d.node = null
		pickups.append(d)
	drafts = p.drafts
	for w in p.wires:
		var d: Dictionary = w.duplicate()
		d.dip = 0.0                      # how far the wire is pushed down (bounce)
		d.dip_v = 0.0
		d.tb = 0.5                       # where along it the push is
		d.line = null
		d.perched = []                   # crows sitting on it
		d.flying = []                    # crows that took off
		wires.append(d)
	for sm in p.streams:
		var d: Dictionary = sm.duplicate()
		d.line = stream_line(sm.pts)
		d.cool = 0.0                     # seconds before it can catch the bird again
		d.ribbons = null
		d.hoops = []
		streams.append(d)
	name = "Chunk%d" % p.k

# --- collision queries -------------------------------------------------------

static func contains(s: Dictionary, theta: float, r: float, tol: float) -> bool:
	if s.kind == Kind.GROUND:
		return true
	if s.broken:
		return false
	var p := TowerShape.polar_point(theta - s.offset, r)
	# Cheap bounding-box reject before the polygon tests (these run a lot)
	if not s.has("bb"):
		var bb := Rect2(s.polys[0][0], Vector2.ZERO)
		for poly: PackedVector2Array in s.polys:
			for q in poly:
				bb = bb.expand(q)
		s.bb = bb
	if not (s.bb as Rect2).grow(tol).has_point(p):
		return false
	for poly: PackedVector2Array in s.polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	for poly: PackedVector2Array in s.polys:
		for i in poly.size():
			var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
			if q.distance_squared_to(p) < tol * tol:
				return true
	return false

# --- per-frame ---------------------------------------------------------------

func tick(time: float, delta: float) -> void:
	for s in surfaces:
		match s.kind:
			Kind.MOVER:
				s.offset = sin(time * s.speed + s.phase) * s.swing
				if s.node:
					s.node.rotation.y = s.offset
			Kind.ISLAND, Kind.PROP:
				s.top = s.base_top + sin(time * 0.8 + s.bob_phase) * ISLAND_BOB
				if s.has("lift"):
					s.top += sin(time * s.speed + s.phase) * s.lift
				if s.has("swing"):
					s.offset = sin(time * s.speed + s.phase) * s.swing
					if s.node:
						s.node.rotation.y = s.offset
				if s.node:
					s.node.position.y = s.top - s.base_top
					var blades: Node3D = s.node.get_node_or_null("Blades")
					if blades:
						blades.rotation.y += delta * 24.0
			Kind.ORBIT:
				# All the way round, forever
				s.offset = s.phase + time * s.speed
				if s.node:
					s.node.rotation.y = s.offset
			Kind.RETRACT:
				_tick_retract(s, time)
			_:
				# Crumbling ledges, and anything lightning has smashed
				if s.crumble >= 0.0:
					_tick_crumble(s, delta)
	for w in wires:
		_tick_wire(w, delta)
	for sp in speakers:
		if is_instance_valid(sp):
			sp.tick(delta, false)
	for sm in streams:
		sm.cool = max(sm.cool - delta, 0.0)
		_tick_stream(sm, time)
	for pk in pickups:
		if pk.taken >= 0.0 and pk.type != "feather":
			pk.taken += delta
			if pk.taken > (POWER_RESPAWN if pk.type in POWERS else PICKUP_RESPAWN):
				pk.taken = -1.0
				pk.theta = pk.home.x      # back where it grew (the charm may have moved it)
				pk.r = pk.home.y
				pk.y = pk.home.z
		if pk.node:
			pk.node.visible = pk.taken < 0.0
			pk.node.position = Vector3(sin(pk.theta) * pk.r, pk.y + sin(time * 2.5 + pk.theta * 3.0) * 0.15, cos(pk.theta) * pk.r)

func _tick_crumble(s: Dictionary, delta: float) -> void:
	s.crumble += delta
	var node: Node3D = s.node
	var delay: float = s.delay
	var t: float = s.crumble - delay
	if t < 0.0:
		# Shaking harder and harder as it's about to go
		var k: float = 0.02 + 0.08 * s.crumble / delay
		if node:
			node.position = Vector3(randf_range(-k, k), randf_range(-k, k) * 0.5, randf_range(-k, k))
	elif t < RESPAWN_TIME:
		if not s.broken:
			s.broken = true
			_dust(s)
		if node:
			node.visible = t < FALL_TIME
			node.position = Vector3(0, -t * t * 9.0, 0)
			node.rotation = Vector3(t * 0.6, 0, t * 0.9) * s.get("spin", 1.0)
	else:
		s.broken = false
		s.crumble = -1.0
		if node:
			node.position = Vector3.ZERO
			node.rotation = Vector3.ZERO
			node.visible = true
			node.scale = Vector3.ONE * 0.01
			create_tween().tween_property(node, "scale", Vector3.ONE, 0.4)

# Standing on it: crusty ledges start to go
func touch(s: Dictionary) -> void:
	if s.kind == Kind.CRUMBLE and s.crumble < 0.0:
		s.crumble = 0.0
		s.delay = CRUMBLE_DELAY
		s.spin = 1.0 if randf() < 0.5 else -1.0

# Hit by lightning: shatters straight away (and grows back like the others)
func smash(s: Dictionary) -> void:
	if s.kind in [Kind.GROUND, Kind.RING, Kind.MOVER, Kind.ISLAND, Kind.ORBIT, Kind.PROP, Kind.RETRACT] or s.crumble >= 0.0:
		return
	s.crumble = 0.0
	s.delay = 0.02
	s.spin = 1.0 if randf() < 0.5 else -1.0

# Stepping or jumping off: cracked ledges give way behind you
func leave(s: Dictionary) -> void:
	if s.kind == Kind.FRAGILE and s.crumble < 0.0:
		s.crumble = 0.0
		s.delay = FRAGILE_DELAY
		s.spin = 1.0 if randf() < 0.5 else -1.0

func _dust(s: Dictionary) -> void:
	var poly: PackedVector2Array = s.polys[0]
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 18
	p.lifetime = 1.1
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.8
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -12, 0)
	var q := BoxMesh.new()
	q.size = Vector3.ONE * 0.14
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.45, 0.38) if s.kind == Kind.CRUMBLE else Color(0.7, 0.72, 0.65)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	p.mesh = q
	p.position = Vector3(c.x, s.top - 0.2, c.y)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

# Returns the pickups the bird touched ({id, type}). Poison has a smaller
# reach than the goodies, so brushing past it is forgiven.
func collect(pos: Vector3) -> Array[Dictionary]:
	var got: Array[Dictionary] = []
	for pk in pickups:
		if pk.taken < 0.0:
			var p := Vector3(sin(pk.theta) * pk.r, pk.y, cos(pk.theta) * pk.r)
			var reach := 0.75 if pk.type == "poison" else 1.1
			if p.distance_to(pos + Vector3(0, 0.5, 0)) < reach:
				pk.taken = 0.0
				got.append({"id": pk.id, "type": pk.type})
	return got

func set_glow(g: float) -> void:
	for m in glass:
		m.set_shader_parameter("glow", g)

# --- building ----------------------------------------------------------------

func build() -> void:
	if built:
		return
	built = true
	var shape: int = plan.k
	var base: float = plan.base
	var tint := TowerShape.tint(shape)
	_build_walls(shape, base, tint)
	for s in surfaces:
		_build_surface(s, tint)
	for w in plan.windows:
		_build_window(shape, w)
	for pk in pickups:
		_build_pickup(pk)
	for d in drafts:
		_build_draft(d)
	for n in plan.npcs:
		_build_npc(n)
	for w in wires:
		_build_wire(w)
	for sm in streams:
		_build_stream(sm)

func _build_walls(shape: int, base: float, tint: Color) -> void:
	if plan.get("summit", false):
		return                       # the Summit crown stands here instead
	var st := MeshUtil.begin()
	var n := TowerShape.sides(shape)
	var half := TowerShape.face_step(shape) * 0.5
	var y0 := base - (2.0 if plan.ground else 0.0)
	var y1 := base + TowerShape.CHUNK_H
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.k, 3])
	for i in n:
		var c := TowerShape.face_center(shape, i)
		var p0 := TowerShape.ring_point(shape, c - half, 0.0)
		var p1 := TowerShape.ring_point(shape, c + half, 0.0)
		var shade := Color.WHITE.darkened(rng.randf_range(0.0, 0.12))
		MeshUtil.face(st, [Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y)],
			Vector3(sin(c), 0, cos(c)), shade)
	# A thin string course at the chunk's base marks height as you climb
	if not ChunkPlanner.is_band_start(plan.k) and not plan.ground:
		for half_ring in [[0.0, PI], [PI, TAU]]:
			MeshUtil.extrude(st, TowerShape.strip_polygon(shape, half_ring[0], half_ring[1], -0.02, 0.18), base - 0.12, base + 0.12, Color(0.75, 0.72, 0.7))
	# Where the thickness changes, a sloped cap (narrowing) or a corbelled
	# overhang (widening) joins this chunk to the one below
	if plan.k > 0 and not ChunkPlanner.is_band_start(plan.k):
		var step: float = TowerShape.apothem(plan.k - 1) - TowerShape.apothem(plan.k)
		if abs(step) > 0.04:
			for i in n:
				var c := TowerShape.face_center(shape, i)
				var out := Vector3(sin(c), 0, cos(c))
				var lo_d := step                # where the wall below meets this chunk
				var p0 := TowerShape.ring_point(shape, c - half, lo_d)
				var p1 := TowerShape.ring_point(shape, c + half, lo_d)
				var q0 := TowerShape.ring_point(shape, c - half, 0.0)
				var q1 := TowerShape.ring_point(shape, c + half, 0.0)
				if step > 0.0:
					# Narrowing: slope up from the wider wall below onto this one
					MeshUtil.face(st, [Vector3(p0.x, base, p0.y), Vector3(p1.x, base, p1.y), Vector3(q1.x, base + 0.7, q1.y), Vector3(q0.x, base + 0.7, q0.y)],
						out + Vector3.UP, Color(0.8, 0.77, 0.74))
				else:
					# Widening: slope out from the narrower wall below under this one
					MeshUtil.face(st, [Vector3(p0.x, base - 0.8, p0.y), Vector3(p1.x, base - 0.8, p1.y), Vector3(q1.x, base, q1.y), Vector3(q0.x, base, q0.y)],
						out + Vector3.DOWN, Color(0.62, 0.6, 0.58))
	# Where the side count changes, cap the old band's top so there's no gap
	if ChunkPlanner.is_band_start(plan.k):
		var prev: int = plan.k - 1
		var rad: float = max(TowerShape.apothem(prev) / cos(PI / TowerShape.sides(prev)), TowerShape.apothem(shape))
		var cap := PackedVector2Array()
		for i in 24:
			cap.append(TowerShape.polar_point(TAU * i / 24.0, rad + 0.05))
		MeshUtil.extrude(st, cap, base - 0.35, base - 0.1, Color(0.6, 0.58, 0.56))
	add_child(MeshUtil.commit(st, MeshUtil.stone_material(tint)))

func _build_surface(s: Dictionary, tint: Color) -> void:
	if s.kind == Kind.GROUND:
		return
	var holder := Node3D.new()
	add_child(holder)
	s.node = holder
	if s.kind == Kind.TURRET:
		_build_turret(holder, s, tint)
		return
	if s.kind == Kind.ISLAND:
		_build_island(holder, s)
		return
	if s.kind == Kind.PROP:
		_build_prop(holder, s)
		return
	if s.kind == Kind.ORBIT:
		_build_orbit(holder, s, tint)
		return
	if s.kind == Kind.CATWALK:
		_build_catwalk(holder, s)
		return
	var st := MeshUtil.begin()
	var top: float = s.top
	var mat := MeshUtil.stone_material(tint.lerp(Color(1.0, 0.93, 0.8), 0.5), "slab")
	var shape: int = s.k
	match s.kind:
		Kind.LEDGE:
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.45, top, Color(0.95, 0.92, 0.88))
			# Corbel underneath
			var inset: float = (s.a1 - s.a0) * 0.15
			MeshUtil.extrude(st, TowerShape.strip_polygon(shape, s.a0 + inset, s.a1 - inset, 0.0, s.d1 * 0.45), top - 1.0, top - 0.45, Color(0.7, 0.68, 0.66))
		Kind.BALCONY:
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.4, top, Color(1.0, 0.97, 0.9))
			_build_railing(st, s)
			var inset: float = (s.a1 - s.a0) * 0.1
			for a in [s.a0 + inset, s.a1 - inset * 2.0]:
				MeshUtil.extrude(st, TowerShape.strip_polygon(shape, a, a + inset, 0.0, s.d1 * 0.7), top - 1.2, top - 0.4, Color(0.7, 0.68, 0.66))
		Kind.PERCH:
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.3, top, Color(0.55, 0.42, 0.32))
			var tip := TowerShape.ring_point(shape, (s.a0 + s.a1) * 0.5, s.d1)
			MeshUtil.box(st, Vector3(tip.x, top - 0.15, tip.y), Vector3(0.5, 0.5, 0.5), (s.a0 + s.a1) * 0.5, Color(0.5, 0.48, 0.5))
		Kind.RING:
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.7, top, Color(1.0, 0.95, 0.85))
		Kind.CRUMBLE:
			# Old crusty ledge: packed dirt with loose clods on top
			mat = MeshUtil.stone_material(Color(0.95, 0.72, 0.55), "dirt")
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.35, top, Color.WHITE, 2.0)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(s.id)
			for i in 5:
				var a: float = lerp(s.a0, s.a1, rng.randf_range(0.1, 0.9))
				var p := TowerShape.ring_point(shape, a, rng.randf_range(0.3, s.d1 - 0.3))
				MeshUtil.box(st, Vector3(p.x, top + 0.06, p.y), Vector3(0.28, 0.14, 0.24) * rng.randf_range(0.7, 1.3), rng.randf() * TAU, Color(0.8, 0.62, 0.5))
			# Dangling roots / crumbs underneath
			for i in 3:
				var a: float = lerp(s.a0, s.a1, rng.randf_range(0.15, 0.85))
				var p := TowerShape.ring_point(shape, a, rng.randf_range(0.3, s.d1 - 0.3))
				MeshUtil.box(st, Vector3(p.x, top - 0.5, p.y), Vector3(0.18, 0.35, 0.18), rng.randf() * TAU, Color(0.6, 0.45, 0.35))
		Kind.FRAGILE:
			# Cracked old stone: holds while you stand, gives way once you leave
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.35, top, Color(0.78, 0.82, 0.7))
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(s.id)
			for i in 3:
				var a: float = lerp(s.a0, s.a1, rng.randf_range(0.2, 0.8))
				var p := TowerShape.ring_point(shape, a, s.d1 * 0.5)
				MeshUtil.box(st, Vector3(p.x, top + 0.01, p.y), Vector3(0.07, 0.03, s.d1 * rng.randf_range(0.5, 0.9)), a + rng.randf_range(-0.5, 0.5), Color(0.2, 0.2, 0.18))
			var tip := TowerShape.ring_point(shape, lerp(s.a0, s.a1, 0.7), s.d1 - 0.3)
			MeshUtil.box(st, Vector3(tip.x, top - 0.55, tip.y), Vector3(0.3, 0.4, 0.3), 0.4, Color(0.7, 0.74, 0.62))
		Kind.MOVER:
			mat = MeshUtil.stone_material(Color(0.75, 0.62, 1.0), "glow")
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.35, top, Color.WHITE)
		Kind.RETRACT:
			# Iron-bound slab that slides in and out of a slot in the wall
			for poly in s.polys:
				MeshUtil.extrude(st, poly, top - 0.3, top, Color(0.72, 0.7, 0.78))
			var edge := TowerShape.strip_polygon(shape, s.a0, s.a1, s.d1 - 0.18, s.d1)
			MeshUtil.extrude(st, edge, top - 0.34, top + 0.04, Color(0.35, 0.33, 0.4))
	holder.add_child(MeshUtil.commit(st, mat))

# A little room hung off the tower on beams, crenellated on top (a bartizan)
func _build_turret(holder: Node3D, s: Dictionary, tint: Color) -> void:
	var shape: int = s.k
	var top: float = s.top
	var R: float = s.radius
	var c := Vector2(s.cx, s.cz)
	var out := c.normalized()
	var poly: PackedVector2Array = s.polys[0]

	var slab := MeshUtil.begin()
	MeshUtil.extrude(slab, poly, top - 0.35, top, Color(1.0, 0.96, 0.9))
	# Merlons on every other edge, low enough not to hide the bird
	for i in range(0, poly.size(), 2):
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var mid := (p + q) * 0.5
		var n := (mid - c).normalized()
		var at := mid - n * 0.13
		MeshUtil.box(slab, Vector3(at.x, top + 0.2, at.y), Vector3(p.distance_to(q) * 0.6, 0.4, 0.22), atan2(n.x, n.y), Color(0.95, 0.92, 0.86))
	holder.add_child(MeshUtil.commit(slab, MeshUtil.stone_material(tint.lerp(Color(1.0, 0.93, 0.8), 0.5), "slab")))

	# The room itself, in the tower's own brick, with a pointed cap underneath
	var room := MeshUtil.begin()
	var inner := PackedVector2Array()
	for p in poly:
		inner.append(c + (p - c) * 0.86)
	MeshUtil.extrude(room, inner, top - 2.9, top - 0.35, Color.WHITE)
	holder.add_child(MeshUtil.commit(room, MeshUtil.stone_material(tint)))

	var wood := MeshUtil.begin()
	MeshUtil.cone(wood, Vector3(c.x, top - 2.9, c.y), R * 0.95, -1.4, 8, ROOF)
	if s.get("roof", false):
		# Roofed variant: four corner posts holding up a pitched roof
		for i in range(0, poly.size(), 2):
			var p := c + (poly[i] - c) * 0.88
			MeshUtil.beam(wood, Vector3(p.x, top, p.y), Vector3(p.x, top + 2.4, p.y), 0.16, WOOD)
		MeshUtil.cone(wood, Vector3(c.x, top + 2.35, c.y), R * 1.15, 1.5, 8, ROOF)
		MeshUtil.beam(wood, Vector3(c.x, top + 3.8, c.y), Vector3(c.x, top + 4.3, c.y), 0.08, Color(0.8, 0.65, 0.3))
	# Beam straight out from the wall, and a diagonal strut below it
	var a: float = atan2(c.x, c.y)
	var w := TowerShape.ring_point(shape, a, -0.1)
	var room_in := c - out * R * 0.8
	MeshUtil.beam(wood, Vector3(w.x, top - 0.75, w.y), Vector3(room_in.x, top - 0.75, room_in.y), 0.32, WOOD)
	MeshUtil.beam(wood, Vector3(w.x, top - 3.4, w.y), Vector3(room_in.x, top - 1.6, room_in.y), 0.26, WOOD.darkened(0.15))
	holder.add_child(MeshUtil.commit(wood, MeshUtil.flat_material(Color.WHITE)))

	# A small stained-glass window facing out
	var win := ShaderMaterial.new()
	win.shader = GLASS_SHADER
	win.set_shader_parameter("style", 0)
	win.set_shader_parameter("size", Vector2(0.5, 1.0))
	win.set_shader_parameter("seed", float(hash(s.id) % 1000))
	win.set_shader_parameter("hue", fposmod(float(hash(s.id)) * 0.001, 1.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 1.0)
	quad.material = win
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	var face_r := R * 0.86 * cos(PI / 8.0) + 0.02
	var wp := c + out * face_r
	mi.position = Vector3(wp.x, top - 1.8, wp.y)
	mi.rotation.y = a
	holder.add_child(mi)
	glass.append(win)

# A floating chunk of earth: grassy top, jagged rock underneath
func _build_island(holder: Node3D, s: Dictionary) -> void:
	var top: float = s.top
	var poly: PackedVector2Array = s.polys[0]
	var c := Vector2(s.cx, s.cz)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(s.id)
	var st := MeshUtil.begin()
	MeshUtil.extrude(st, poly, top - 0.3, top, Color(0.45, 0.7, 0.35), 1.0)
	var mid_y := top - 1.1
	var tip := Vector3(c.x + rng.randf_range(-0.3, 0.3), top - 2.7, c.y + rng.randf_range(-0.3, 0.3))
	var ring: Array[Vector3] = []
	for p in poly:
		var q := c + (p - c) * rng.randf_range(0.55, 0.75)
		ring.append(Vector3(q.x, mid_y + rng.randf_range(-0.2, 0.2), q.y))
	var rock := Color(0.5, 0.42, 0.36)
	for i in poly.size():
		var j := (i + 1) % poly.size()
		var a := Vector3(poly[i].x, top - 0.3, poly[i].y)
		var b := Vector3(poly[j].x, top - 0.3, poly[j].y)
		var out := ((a + b) * 0.5 - Vector3(c.x, top, c.y))
		out.y = 0.0
		MeshUtil.face(st, [a, b, ring[j]], out + Vector3.DOWN * 0.5, rock.lightened(0.08 * (i % 2)), 1.0)
		MeshUtil.face(st, [a, ring[j], ring[i]], out + Vector3.DOWN * 0.5, rock.lightened(0.08 * (i % 2)), 1.0)
		MeshUtil.face(st, [ring[i], ring[j], tip], out + Vector3.DOWN, rock.darkened(0.15), 1.0)
	# A shrub and a pebble or two drifting alongside
	var edge := c + (poly[rng.randi_range(0, poly.size() - 1)] - c) * 0.6
	MeshUtil.cone(st, Vector3(edge.x, top, edge.y), 0.35, 0.7, 5, Color(0.2, 0.45, 0.25))
	for i in 2:
		var off: Vector2 = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * (s.radius + 0.6)
		MeshUtil.box(st, Vector3(c.x + off.x, top - rng.randf_range(0.8, 2.0), c.y + off.y), Vector3.ONE * rng.randf_range(0.25, 0.45), rng.randf() * TAU, rock)
	holder.add_child(MeshUtil.commit(st, MeshUtil.flat_material(Color.WHITE)))

func _build_npc(d: Dictionary) -> void:
	# Stand on its ledge's own node, so it bobs / falls along with it
	var parent: Node3D = self
	var on: Dictionary = {}
	for s in surfaces:
		if s.get("id", "") == d.get("surface", "-") and s.node:
			parent = s.node
			on = s
	var npc := Npc.new()
	npc.setup(d, on)
	npc.position = Vector3(sin(d.theta) * d.r, d.y, cos(d.theta) * d.r)
	parent.add_child(npc)
	npcs.append(npc)

# A column of streaks: pale and rising for an updraft, dark and sinking for
# a downdraft
func _build_draft(d: Dictionary) -> void:
	var h: float = d.y1 - d.y0
	var speed := 7.0 if d.up else 6.0
	var p := CPUParticles3D.new()
	p.amount = Tuning.particles(int(h * 4.0))
	p.lifetime = h / speed
	p.preprocess = p.lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = d.radius
	p.emission_ring_inner_radius = 0.0
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP if d.up else Vector3.DOWN
	p.spread = 3.0
	p.initial_velocity_min = speed * 0.8
	p.initial_velocity_max = speed * 1.2
	p.gravity = Vector3.ZERO
	p.set_particle_flag(CPUParticles3D.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
	var ramp := Gradient.new()
	var c := Color(0.85, 0.97, 1.0, 0.45) if d.up else Color(0.3, 0.22, 0.4, 0.5)
	ramp.set_color(0, Color(c, 0.0))
	ramp.add_point(0.2, c)
	ramp.add_point(0.8, c)
	ramp.set_color(ramp.get_point_count() - 1, Color(c, 0.0))
	p.color_ramp = ramp
	var streak := BoxMesh.new()
	streak.size = Vector3(0.05, 0.9, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	streak.material = m
	p.mesh = streak
	p.position = Vector3(sin(d.theta) * d.r, d.y0 if d.up else d.y1, cos(d.theta) * d.r)
	add_child(p)

func _build_railing(st: SurfaceTool, s: Dictionary) -> void:
	var shape: int = s.k
	var top: float = s.top
	var d: float = s.d1 - 0.12
	MeshUtil.extrude(st, TowerShape.strip_polygon(shape, s.a0, s.a1, d - 0.08, d + 0.08), top + 0.55, top + 0.68, Color(0.9, 0.88, 0.85), 1.0)
	var angles: Array[float] = [s.a0]
	angles.append_array(TowerShape.corners_between(shape, s.a0, s.a1))
	angles.append(s.a1)
	for i in angles.size() - 1:
		var seg := TowerShape.perimeter_len(shape, angles[i], angles[i + 1], d)
		var count: int = max(1, roundi(seg / 0.7))
		for j in count + (1 if i == angles.size() - 2 else 0):
			var a: float = lerp(angles[i], angles[i + 1], float(j) / count)
			var p := TowerShape.ring_point(shape, a, d)
			MeshUtil.box(st, Vector3(p.x, top + 0.3, p.y), Vector3(0.12, 0.6, 0.12), a, Color(0.85, 0.83, 0.8))

func _build_window(shape: int, w: Dictionary) -> void:
	var c := TowerShape.face_center(shape, w.face)
	var r := TowerShape.apothem(shape) + 0.03
	var mat := ShaderMaterial.new()
	mat.shader = GLASS_SHADER
	mat.set_shader_parameter("style", w.style)
	mat.set_shader_parameter("size", Vector2(w.w, w.h))
	mat.set_shader_parameter("seed", w.seed)
	mat.set_shader_parameter("hue", w.hue)
	var quad := QuadMesh.new()
	quad.size = Vector2(w.w, w.h)
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(sin(c) * r, w.y + w.h * 0.5, cos(c) * r)
	mi.rotation.y = c
	add_child(mi)
	if w.style != 2:
		glass.append(mat)

static func _texture_for(type: String) -> Texture2D:
	if _pickup_tex.has(type):
		return _pickup_tex[type]
	var tex: Texture2D
	if type == "plume":
		tex = Feathers.pale_texture()
	elif type == "poison":
		tex = MeshUtil.pixel_texture([
			"..oooo..",
			".opwpppo",
			"opppppwo",
			"opwppppo",
			"oooooooo",
			"...os...",
			"...os...",
			"..ossso.",
		], {"o": Color(0.2, 0.05, 0.25), "p": Color(0.62, 0.2, 0.78), "w": Color(0.85, 1.0, 0.6), "s": Color(0.75, 0.88, 0.6)})
	elif type == "sunseed":
		tex = MeshUtil.pixel_texture([
			"....y....",
			".y..y..y.",
			"..yoooy..",
			"..oSSSo..",
			"yyoSWSoyy",
			"..oSSSo..",
			"..yoooy..",
			".y..y..y.",
			"....y....",
		], {"y": Color(1.0, 0.9, 0.35), "o": Color(0.6, 0.3, 0.05), "S": Color(1.0, 0.6, 0.15), "W": Color(1, 1, 0.9)})
	elif type == "spring":
		tex = MeshUtil.pixel_texture([
			"...gg....",
			"..gg.....",
			"...oo....",
			"..orro...",
			".orrwro..",
			".orrrro..",
			"..orro...",
			"...oo....",
			"..zzzz...",
		], {"g": Color(0.35, 0.75, 0.3), "o": Color(0.35, 0.05, 0.1), "r": Color(0.9, 0.2, 0.3), "w": Color(1, 0.8, 0.8), "z": Color(0.75, 0.75, 0.8)})
	elif type == "cloud":
		tex = MeshUtil.pixel_texture([
			".........",
			"...ww....",
			"..wwww.w.",
			".wwwwwwww",
			"wwwwwwwww",
			"wwbwwwbww",
			".bbbbbbb.",
			".........",
			".........",
		], {"w": Color(1, 1, 1), "b": Color(0.7, 0.82, 1.0)})
	elif type == "charm":
		tex = MeshUtil.pixel_texture([
			"...ggg...",
			"..g...g..",
			"...ggg...",
			"...gpg...",
			"..gpppg..",
			".gppwppg.",
			"..gpppg..",
			"...gpg...",
			"....g....",
		], {"g": Color(0.95, 0.75, 0.28), "p": Color(0.6, 0.25, 0.85), "w": Color(1, 0.9, 1)})
	else:
		# A proper feather: a pale quill, a lit and a shaded vane, a notch
		tex = MeshUtil.pixel_texture([
			".....o...",
			"....oho..",
			"...ohwyo.",
			"...ohwyo.",
			"..ohhwyyo",
			"..ohhwyyo",
			".ohhhwyyo",
			".ohhhwyyo",
			".ohh.wyyo",
			"..ohhwyyo",
			"..ohhwyo.",
			"..ohhwyo.",
			"...ohwo..",
			"...ohwo..",
			"....ow...",
			".....w...",
			".....w...",
			".....o...",
		], {"o": Color(0.5, 0.28, 0.05), "h": Color(1.0, 0.88, 0.4), "y": Color(0.95, 0.66, 0.15), "w": Color(1.0, 0.98, 0.85)})
	_pickup_tex[type] = tex
	return tex

func _build_pickup(pk: Dictionary) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(sin(pk.theta) * pk.r, pk.y, cos(pk.theta) * pk.r)
	add_child(holder)
	var sp := Sprite3D.new()
	sp.texture = _texture_for(pk.type)
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD    # solid, so depth decides who's in front
	sp.pixel_size = 0.075 if pk.type == "feather" else 0.09
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false
	holder.add_child(sp)
	if GLOWS.has(pk.type):
		_add_feather_glow(holder, GLOWS[pk.type])
	if pk.type in POWERS:
		sp.pixel_size = 0.1
	pk.node = holder

# Gold feathers glow softly and twinkle, so they read as treasure from afar
func _add_feather_glow(holder: Node3D, color: Color) -> void:
	var glow := Sprite3D.new()
	glow.texture = MeshUtil.blob_texture(16, color)
	glow.pixel_size = 0.14
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	glow.shaded = false
	glow.modulate = Color(1, 1, 1, 0.55)
	glow.position = Vector3(0, 0, -0.05)
	holder.add_child(glow)
	var pulse := glow.create_tween().set_loops()
	pulse.tween_property(glow, "modulate:a", 0.25, 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(glow, "modulate:a", 0.6, 0.7).set_trans(Tween.TRANS_SINE)
	var sparkle := CPUParticles3D.new()
	sparkle.amount = Tuning.particles(7)
	sparkle.lifetime = 1.1
	sparkle.local_coords = true
	sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparkle.emission_sphere_radius = 0.7
	sparkle.direction = Vector3.UP
	sparkle.spread = 30.0
	sparkle.initial_velocity_min = 0.1
	sparkle.initial_velocity_max = 0.4
	sparkle.gravity = Vector3.ZERO
	var twinkle := Curve.new()
	twinkle.add_point(Vector2(0, 0))
	twinkle.add_point(Vector2(0.5, 1))
	twinkle.add_point(Vector2(1, 0))
	sparkle.scale_amount_curve = twinkle
	var star := QuadMesh.new()
	star.size = Vector2(0.22, 0.22)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_texture = _star_texture()
	star.material = m
	sparkle.mesh = star
	holder.add_child(sparkle)

static var _star: Texture2D

static func _star_texture() -> Texture2D:
	if _star == null:
		_star = MeshUtil.pixel_texture([
			"...w...",
			"...w...",
			"..wyw..",
			"wwyyyww",
			"..wyw..",
			"...w...",
			"...w...",
		], {"w": Color(1.0, 0.95, 0.7), "y": Color(1, 1, 1)})
	return _star

# The meadow round the tower's foot. Built once by the generator, not per
# chunk, so it's still down there after the first chunks unload.
static func make_ground() -> Node3D:
	var st := MeshUtil.begin()
	var disk := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		# Far bigger than you can see: fog swallows the edge, so there's no disc
		disk.append(TowerShape.polar_point(a, 1500.0))
	# The grass: its own mesh, with a very subtle pixel texture (see _grass)
	var turf := MeshUtil.begin()
	MeshUtil.extrude(turf, disk, -3.0, 0.0, Color.WHITE, 4.0)
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = _grass()
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	gm.vertex_color_use_as_albedo = true
	gm.roughness = 1.0
	gm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var grass := MeshUtil.commit(turf, gm)
	# A cobbled apron around the tower's foot
	for half_ring in [[0.0, PI], [PI, TAU]]:
		MeshUtil.extrude(st, TowerShape.strip_polygon(0, half_ring[0], half_ring[1], -0.1, 2.6), -0.2, 0.02, Color(0.6, 0.58, 0.55))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# The wood round the hub, out to the horizon, in one smooth spread: over
	# the ground its density eases off gradually from a thick edge (no step
	# anywhere), and the far trees grow a little taller, so the canopy closes
	# up toward the horizon by itself. Fewer on phones. (The pictures and
	# shades are for the flat-sprite forest, PAPER_FOREST off.)
	# [position, height, texture, shade]
	var yard := HubStations.DREAM.x
	var trees: Array = []
	while trees.size() < Tuning.particles(900):
		var a := rng.randf() * TAU
		var r: float = sqrt(lerp(44.0 * 44.0, 340.0 * 340.0, rng.randf()))     # even over the ground...
		if rng.randf() > (1.0 + 1.5 * exp(-(r - 44.0) / 45.0)) / 2.5:
			continue                                # ...then thicker toward the edge, easing off
		var near := r < 70.0
		var tex: Texture2D = DEAD_TREES[rng.randi_range(0, 2)] if near and rng.randf() < 0.75 else TREES[rng.randi_range(0, TREES.size() - 1)]
		var h: float = rng.randf_range(14.0, 22.0) * lerp(1.0, 1.35, clamp((r - 150.0) / 190.0, 0.0, 1.0))
		trees.append([Vector3(sin(a) * r, 0.0, cos(a) * r), h, tex, rng.randf_range(0.62, 0.88)])
	# ...and a thick band hugging the wood's edge by the meadow, fading off
	# smoothly outward (a half-bell curve, so there's no step where it ends)
	for i in 240:
		var a := rng.randf() * TAU
		var r: float = 44.0 + abs(rng.randfn(0.0, 22.0))
		var tex: Texture2D = DEAD_TREES[rng.randi_range(0, 2)] if rng.randf() < 0.75 else TREES[rng.randi_range(0, TREES.size() - 1)]
		trees.append([Vector3(sin(a) * r, 0.0, cos(a) * r), rng.randf_range(14.0, 22.0), tex, rng.randf_range(0.62, 0.88)])
	# Boulders near the tower
	for i in 5:
		var a := rng.randf() * TAU
		var r := rng.randf_range(14.0, 20.0)
		MeshUtil.box(st, Vector3(sin(a) * r, 0.2, cos(a) * r), Vector3(1, 0.7, 0.8) * rng.randf_range(0.6, 1.3), rng.randf() * TAU, Color(0.5, 0.5, 0.52))
	# A broken ring of low standing stones round the tower's foot
	for i in 9:
		if i == 4:
			continue      # one fallen out of the circle
		var a := TAU * i / 9.0 + 0.2
		var r := rng.randf_range(9.5, 11.0)
		var h := rng.randf_range(0.9, 1.8)
		MeshUtil.box(st, Vector3(sin(a) * r, h * 0.5, cos(a) * r), Vector3(0.7, h, 0.4), a + rng.randf_range(-0.2, 0.2), Color(0.45, 0.46, 0.5))
	MeshUtil.box(st, Vector3(sin(1.6) * 10.3, 0.2, cos(1.6) * 10.3), Vector3(1.6, 0.4, 0.7), 1.1, Color(0.42, 0.43, 0.47))
	# Wildflowers in clumps, a few of them blood red
	for clump in 16:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.5, 30.0)
		var centre := Vector3(sin(a) * r, 0.0, cos(a) * r)
		var col: Color = [Color(0.8, 0.7, 0.95), Color(1.0, 0.97, 0.9), Color(1.0, 0.9, 0.5), Color(0.75, 0.1, 0.15)][rng.randi_range(0, 3)]
		for f in 8:
			var p := centre + Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2))
			MeshUtil.box(st, p + Vector3(0, 0.12, 0), Vector3(0.04, 0.24, 0.04), 0.0, Color(0.25, 0.45, 0.2))
			MeshUtil.box(st, p + Vector3(0, 0.27, 0), Vector3(0.14, 0.08, 0.14), rng.randf() * TAU, col)
	var ground := Node3D.new()
	ground.add_child(MeshUtil.commit(st, MeshUtil.flat_material(Color.WHITE)))
	ground.add_child(grass)
	# Fairy rings of pale mushrooms that glow faintly (unshaded, so they show at night)
	var glow := MeshUtil.begin()
	for ring in 1:
		var a := rng.randf() * TAU
		var c := Vector3(sin(a), 0, cos(a)) * rng.randf_range(12.0, 20.0)
		var rr := rng.randf_range(1.6, 2.4)
		for i in 11:
			var b := TAU * i / 11.0
			var p := c + Vector3(sin(b), 0, cos(b)) * rr * rng.randf_range(0.9, 1.1)
			var h := rng.randf_range(0.2, 0.45)
			MeshUtil.box(glow, p + Vector3(0, h * 0.5, 0), Vector3(0.07, h, 0.07), 0.0, Color(0.85, 0.9, 0.85))
			MeshUtil.cone(glow, p + Vector3(0, h, 0), rng.randf_range(0.14, 0.24), 0.14, 6, Color(0.55, 0.95, 0.85))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	ground.add_child(MeshUtil.commit(glow, m))
	_add_forest(ground, trees)
	_add_mountains(ground, rng)
	_add_props(ground, rng, yard)
	return ground

const FOREST_SHADER := preload("res://shaders/forest.gdshader")
const MOUNTAIN_SHADER := preload("res://shaders/mountains.gdshader")
# The forest: 3D Paper-Mario-style trees with Paradise Island leaves (see
# PaperTrees), or false for the flat 8 Bit Evil Returns tree sprites
const PAPER_FOREST := true
static var forest_materials: Array[ShaderMaterial] = []   # the meadow dims them at night
static var night_sprites: Array[Sprite3D] = []   # pixel-art props, dimmed together at night (the meadow does it)

# The meadow's grass texture: the base green with a light scatter of
# blades and specks a shade or two either side of it (a 32 px tile, laid 4 m
# wide), just enough to read as pixel-art grass
static func _grass() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var base := Color(0.36, 0.55, 0.3)
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for i in 70:
		var x := rng.randi_range(0, 31)
		var y := rng.randi_range(0, 31)
		var c := base.lightened(0.07) if rng.randf() < 0.55 else base.darkened(0.07)
		img.set_pixel(x, y, c)
		if rng.randf() < 0.6:
			img.set_pixel(x, posmod(y - 1, 32), c)        # a blade, two pixels tall
	return ImageTexture.create_from_image(img)

# The trees, one MultiMesh per picture (a single draw call each, however
# many trees). The owls blink, so they're sprites of their own.
# trees: [position, height, texture, shade]
static func _add_forest(ground: Node3D, trees: Array) -> void:
	var by_tex := {}
	var paper := []
	for t in trees:
		if t[2] == OWL_TREE:
			var owl := _prop(t[0], t[1], t[2], 5, 0.0)
			owl.modulate = Color(t[3], t[3] * 0.92, t[3] * 1.08)
			owl.set_meta("tint", owl.modulate)
			ground.add_child(owl)
		elif PAPER_FOREST:
			paper.append([t[0], t[1] * 0.8])
		else:
			if not by_tex.has(t[2]):
				by_tex[t[2]] = []
			by_tex[t[2]].append(t)
	for tex: Texture2D in by_tex:
		var list: Array = by_tex[tex]
		var h := float(tex.get_height())
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		# Its foot (the lowest opaque pixel, a touch sunk) sits at the origin
		quad.center_offset = Vector3(0, 0.5 - (_empty_rows_below(tex, 1) + 2) / h, 0)
		var mat := ShaderMaterial.new()
		mat.shader = FOREST_SHADER
		mat.set_shader_parameter("tex", tex)
		forest_materials.append(mat)
		quad.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = quad
		mm.instance_count = list.size()
		var aspect := tex.get_width() / h
		for i in list.size():
			var t: Array = list[i]
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(t[1] * aspect, t[1], 1.0)), t[0]))
			mm.set_instance_color(i, Color(t[3], t[3] * 0.92, t[3] * 1.08))    # dark, a little bruised
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Instances turn to face the camera, so give it room not to be culled
		mmi.custom_aabb = AABB(Vector3(-400, -10, -400), Vector3(800, 60, 800))
		ground.add_child(mmi)
	if not paper.is_empty():
		PaperTrees.add(ground, paper, forest_materials)

# Two rings of snow-capped mountains on the horizon, hazed toward the fog
# colour by their own shader (the engine fog would swallow them): the far
# ring paler, and all of them fading out in thick weather.
static func _add_mountains(ground: Node3D, rng: RandomNumberGenerator) -> void:
	var st := MeshUtil.begin()
	for layer in 2:
		var far := layer == 1
		var ring := 900.0 if far else 620.0
		var rock := Color(0.52, 0.55, 0.68) if far else Color(0.34, 0.33, 0.44)
		var count := 26 if far else 34
		for i in count:
			var a := TAU * (i + rng.randf_range(-0.35, 0.35)) / count + layer * 0.4
			var r := ring + rng.randf_range(-60.0, 60.0)
			var height := rng.randf_range(160.0, 330.0) if far else rng.randf_range(90.0, 210.0)
			var radius := height * rng.randf_range(0.9, 1.4)
			var base := Vector3(sin(a) * r, -2.0, cos(a) * r)
			MeshUtil.cone(st, base, radius, height, 7, rock.darkened(rng.randf_range(0.0, 0.12)))
			# A shoulder beside each peak breaks up the silhouette
			var side := Vector3(cos(a), 0, -sin(a)) * radius * rng.randf_range(-0.7, 0.7)
			MeshUtil.cone(st, base + side, radius * 0.7, height * rng.randf_range(0.45, 0.7), 6, rock.darkened(0.08))
			if height > (220.0 if far else 150.0):
				# Snow on the upper third
				var snow := Color(0.92, 0.93, 1.0) if far else Color(0.82, 0.83, 0.92)
				MeshUtil.cone(st, base + Vector3(0, height * 0.64, 0), radius * 0.37, height * 0.37, 7, snow)
	var m := ShaderMaterial.new()
	m.shader = MOUNTAIN_SHADER
	forest_materials.append(m)          # (so the game feeds it the fog colour and night light)
	var mi := MeshUtil.commit(st, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.add_child(mi)

# Pixel art from 8 Bit Evil Returns
const DEAD_TREES := [preload("res://images/trees/tree.png"), preload("res://images/trees/tree_5.png"), preload("res://images/trees/tree_6.png")]
const TREES := [preload("res://images/trees/tree_2.png"), preload("res://images/trees/tree_3.png"), preload("res://images/trees/tree_4.png"),
	preload("res://images/trees/tree.png"), preload("res://images/trees/tree_5.png"), preload("res://images/trees/tree_6.png")]
const OWL_TREE := preload("res://images/trees/tree_owl.png")      # 5 frames: the owl blinks
const GRAVES := [preload("res://images/ambient/grave_1_small.png"), preload("res://images/ambient/grave_2.png")]
const LAMP := preload("res://images/ambient/street_lamp.png")      # 4 frames: flickers
const SCARECROW := preload("res://images/ambient/scarecrow.png")   # 6 frames: sways
const PUMPKIN := preload("res://images/ambient/pumpkin.png")       # 6 frames: its candle gutters
const SKULL := preload("res://images/ambient/skull.png")

# The meadow's set dressing, outside the stone circle. Tall things stay near
# the hub's edge or beyond, so they rarely come between the camera and bird.
static func _add_props(ground: Node3D, rng: RandomNumberGenerator, yard: float) -> void:
	# A little graveyard behind the cauldrons
	for i in 6:
		var a := yard + (1.0 if i % 2 == 0 else -1.0) * rng.randf_range(0.13, 0.4)
		var r := rng.randf_range(18.5, 26.0)
		var lean := Vector3(rng.randf_range(-0.12, 0.12), a + rng.randf_range(-0.25, 0.25), rng.randf_range(-0.1, 0.1))
		ground.add_child(_grave(Vector3(sin(a) * r, 0, cos(a) * r), rng.randf_range(1.6, 2.2), GRAVES[i % 2], lean))
	# Street lamps ringing the hub, flickering
	for i in 5:
		var a := TAU * i / 5.0 + 0.45
		ground.add_child(_prop(Vector3(sin(a), 0, cos(a)) * 32.0, 4.2, LAMP, 4, 6.0 + rng.randf() * 3.0))
		var glow := Sprite3D.new()
		glow.texture = MeshUtil.blob_texture(16, Color(1.0, 0.8, 0.45))
		glow.pixel_size = 0.12
		glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		glow.shaded = false
		glow.modulate = Color(1, 1, 1, 0.5)
		glow.position = Vector3(sin(a), 0, cos(a)) * 32.0 + Vector3(0, 3.7, 0)
		ground.add_child(glow)
	# A scarecrow keeping watch over the meadow
	var sa := yard + PI * 0.7
	ground.add_child(_prop(Vector3(sin(sa), 0, cos(sa)) * 25.0, 3.0, SCARECROW, 6, 5.0))
	# Pumpkin patches, and a few skulls in the grass
	for patch in 2:
		var a := rng.randf() * TAU
		var c := Vector3(sin(a), 0, cos(a)) * rng.randf_range(15.0, 28.0)
		for i in 3:
			var p := c + Vector3(rng.randf_range(-2.0, 2.0), 0, rng.randf_range(-2.0, 2.0))
			ground.add_child(_prop(p, 0.8, PUMPKIN, 6, rng.randf_range(4.0, 7.0), false))
	for i in 3:
		var a := rng.randf() * TAU
		var r := rng.randf_range(13.0, 30.0)
		ground.add_child(_prop(Vector3(sin(a) * r, 0, cos(a) * r), 0.45, SKULL))

# A gravestone from its pixel art, made solid: the picture stacked in cut-out
# layers a few pixels deep (lit on the faces, darker between), so it has the
# art's exact outline from the front and real thickness from the side.
# `turn` is its (x, y, z) rotation: facing out, leaning a little.
static func _grave(base: Vector3, height: float, tex: Texture2D, turn: Vector3) -> MeshInstance3D:
	var px := height / tex.get_height()
	var w := tex.get_width() * px
	var y0 := -(_empty_rows_below(tex, 1) + 1) * px
	var y1 := y0 + height
	var layers := 6
	var depth := px * 5.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in layers:
		var z: float = lerp(-depth * 0.5, depth * 0.5, float(i) / (layers - 1))
		var face := i == 0 or i == layers - 1
		st.set_color(Color.WHITE if face else Color(0.6, 0.6, 0.65))
		st.set_normal(Vector3(0, 0, 1.0 if i == layers - 1 else -1.0))
		for v in [[-0.5, 0.0, 0.0, 1.0], [0.5, 0.0, 1.0, 1.0], [0.5, 1.0, 1.0, 0.0], [-0.5, 0.0, 0.0, 1.0], [0.5, 1.0, 1.0, 0.0], [-0.5, 1.0, 0.0, 0.0]]:
			st.set_uv(Vector2(v[2], v[3]))
			st.add_vertex(Vector3(v[0] * w, lerp(y0, y1, v[1]), z))
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.metallic_specular = 0.0
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = base
	mi.rotation = turn
	return mi

static var _foot_rows := {}

# Transparent rows under the art in the first frame of `tex`
static func _empty_rows_below(tex: Texture2D, frames: int) -> int:
	if _foot_rows.has(tex):
		return _foot_rows[tex]
	var img := tex.get_image()
	var rows := 0
	if img:
		if img.is_compressed():
			img.decompress()
		var w := img.get_width() / frames
		rows = img.get_height()
		for y in range(img.get_height() - 1, -1, -1):
			var solid := false
			for x in w:
				if img.get_pixel(x, y).a > 0.5:
					solid = true
					break
			if solid:
				rows = img.get_height() - 1 - y
				break
	_foot_rows[tex] = rows
	return rows

# A pixel-art sprite standing on the ground at `base`, `height` metres tall,
# turning to face the camera. With `frames` > 1 it animates at `fps`
# (0 = sit on frame 0 and play the rest now and then, like a blink).
# `dims`: darkens at night (false for things that glow).
static func _prop(base: Vector3, height: float, tex: Texture2D, frames := 1, fps := -1.0, dims := true) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = frames
	var h := tex.get_height()
	s.pixel_size = height / h
	# Plant its lowest opaque pixel a little into the ground (the art has
	# empty rows under the trunk, which would leave it floating)
	s.offset = Vector2(0, h * 0.5 - _empty_rows_below(tex, frames) - 2)
	s.position = base
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	# Unshaded like the crows: lit, the flat sprites came out pale next to them.
	# Night dims them instead (unless they glow, like the pumpkins).
	s.shaded = false
	if dims:
		s.set_meta("tint", Color.WHITE)
		night_sprites.append(s)
	s.double_sided = true
	if frames > 1 and fps >= 0.0:
		s.frame = randi() % frames
		s.tree_entered.connect(func():
			var anim := s.create_tween().set_loops()
			if fps == 0.0:
				anim.tween_interval(randf_range(2.5, 5.0))
				for f in range(1, frames + 1):
					anim.tween_property(s, "frame", f % frames, 0.0)
					anim.tween_interval(0.08)
			else:
				for f in frames:
					anim.tween_property(s, "frame", (f + 1) % frames, 0.0)
					anim.tween_interval(1.0 / fps), CONNECT_ONE_SHOT)
	return s

# --- retracting ledges ----------------------------------------------------------

# Out for most of the cycle, a rattle of warning, then it slides into the
# wall for a moment and comes back out
func _tick_retract(s: Dictionary, time: float) -> void:
	var period: float = s.period
	var t := fposmod(time + s.phase, period)
	var out_until := period * 0.62
	var ext := 1.0
	var rattle := 0.0
	if t < out_until - 0.5:
		ext = 1.0
	elif t < out_until:
		rattle = 0.05
	elif t < out_until + 0.3:
		ext = 1.0 - (t - out_until) / 0.3
	elif t < period - 0.3:
		ext = 0.0
	else:
		ext = (t - (period - 0.3)) / 0.3
	s.broken = ext < 0.7
	if s.node:
		var c: float = (s.a0 + s.a1) * 0.5
		var out := Vector3(sin(c), 0, cos(c))
		s.node.position = -out * s.d1 * (1.0 - ext) + Vector3(randf_range(-rattle, rattle), 0, randf_range(-rattle, rattle))

# --- wires --------------------------------------------------------------------

const WIRE_SPRING := 70.0
const WIRE_DAMP := 5.0

# Height of wire `w` at t (0 = wall hook, 1 = post), including its sag and
# any bounce pushing it down around tb
static func wire_point(w: Dictionary, t: float) -> Vector3:
	var a: Vector3 = w.a
	var b: Vector3 = w.b
	var p := a.lerp(b, t)
	var tb: float = clamp(w.get("tb", 0.5), 0.05, 0.95)
	var shape := t / tb if t < tb else (1.0 - t) / (1.0 - tb)
	p.y -= w.sag * 4.0 * t * (1.0 - t) + w.get("dip", 0.0) * shape
	return p

func _tick_wire(w: Dictionary, delta: float) -> void:
	var was: float = w.dip
	w.dip_v += (-WIRE_SPRING * w.dip - WIRE_DAMP * w.dip_v) * delta
	w.dip += w.dip_v * delta
	if abs(w.dip) < 0.002 and abs(w.dip_v) < 0.01:
		w.dip = 0.0
		w.dip_v = 0.0
	if w.dip != was or w.line == null:
		_draw_wire(w)
		for b in w.perched:
			b.position = wire_point(w, b.get_meta("t"))
	# A crow on a low wire right up against the lens just fills the screen: hide it
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam:
		for b: Node3D in w.perched:
			b.visible = b.global_position.distance_to(cam.global_position) > 5.0
	for i in range(w.flying.size() - 1, -1, -1):
		var b: AnimatedSprite3D = w.flying[i]
		var v: Vector3 = b.get_meta("v")
		var age: float = b.get_meta("age") + delta
		b.set_meta("age", age)
		match b.get_meta("mood"):
			"fall":
				# Drops like a stone for a moment, then remembers it has wings
				v.y -= 14.0 * delta
				b.position += v * delta
				b.set_meta("v", v)
				if age > 0.7:
					b.set_meta("mood", "fly")
					b.sprite_frames = Npc.recoloured(Player.FLAP_FRAMES, b.get_meta("tint"))
					b.offset = Vector2(0, 16)
					b.play("default")
					b.set_meta("v", Vector3(v.x, 6.0, v.z))
			"land":
				# A hop through the air to the nearest ledge, then settles there
				var t: float = min(age / 1.3, 1.0)
				var from: Vector3 = b.get_meta("from")
				var to: Vector3 = b.get_meta("to")
				b.position = from.lerp(to, t) + Vector3(0, sin(t * PI) * 1.5, 0)
				b.flip_h = to.x < from.x
				if t >= 1.0:
					b.sprite_frames = Npc.recoloured(Npc.IDLE_FRAMES, b.get_meta("tint"))
					b.offset = Vector2(0, 7)
					b.play("default")
					b.speed_scale = 0.8
					w.flying.remove_at(i)
			_:
				b.position += v * delta
				b.set_meta("v", v + Vector3(0, 2.0, 0) * delta)
				if age > 3.2:
					speakers.erase(b.get_node_or_null("Bubble"))
					b.queue_free()
					w.flying.remove_at(i)

const WIRE_LINES := {
	"stay": ["Hey, this is my wire.", "Do you mind?", "Wobbly...", "I'm not moving.", "Rude."],
	"fly": ["Caw!", "Not again!", "Scram!", "Ugh, tourists."],
	"fall": ["Waaah!", "Whoa-", "My perch!"],
	"land": ["Fine. I'll sit over here.", "Some of us were napping.", "Tch."],
}

# The bird landed on this wire. Each crow on it reacts its own way: flies
# off, drops (then catches itself), stays put and grumbles, or hops over
# to the nearest ledge. Usually one of them says something about it.
func scare_wire(w: Dictionary) -> void:
	var spoke := false
	var shed := false
	for b: AnimatedSprite3D in w.perched.duplicate():
		var roll := randf()
		var mood := "fly" if roll < 0.4 else ("fall" if roll < 0.6 else ("stay" if roll < 0.85 else "land"))
		if not spoke and randf() < 0.6:
			spoke = true
			_crow_says(b, WIRE_LINES[mood].pick_random())
		if mood == "stay":
			continue
		w.perched.erase(b)
		b.set_meta("mood", mood)
		b.set_meta("age", 0.0)
		var away := Vector3(b.position.x, 0, b.position.z).normalized()
		if mood == "land":
			var spot := _nearest_perch(b.position)
			if spot == Vector3.INF:
				mood = "fly"
				b.set_meta("mood", mood)
			else:
				b.set_meta("from", b.position)
				b.set_meta("to", spot)
		if mood == "fall":
			b.sprite_frames = Npc.recoloured(Player.FALL_FRAMES, b.get_meta("tint"))
			b.set_meta("v", Vector3(0, -1.0, 0) + away * 0.5)
		else:
			if not shed and Feathers.the and randf() < 0.4:
				shed = true      # startled crows lose a feather
				Feathers.the.shed(b.global_position + Vector3(0, 0.5, 0))
			b.sprite_frames = Npc.recoloured(Player.FLAP_FRAMES, b.get_meta("tint"))
			b.set_meta("v", away * randf_range(2.0, 5.0) + Vector3(randf_range(-2, 2), randf_range(4.0, 7.0), randf_range(-2, 2)))
		b.offset = Vector2(0, b.sprite_frames.get_frame_texture("default", 0).get_height() * 0.5)
		b.play("default")
		b.speed_scale = 3.0
		w.flying.append(b)

# The top of the nearest standing ledge within reach of a crow, or INF
func _nearest_perch(from: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := 12.0
	for s in surfaces:
		if s.broken or s.kind in [Kind.GROUND, Kind.RING, Kind.MOVER, Kind.ORBIT, Kind.RETRACT, Kind.PROP, Kind.ISLAND]:
			continue
		var a: float = (s.a0 + s.a1) * 0.5
		var r: float = Vector2(s.cx, s.cz).length() if ChunkPlanner.is_outer(s) else TowerShape.wall_r(s.k, a, s.d1 * 0.6)
		var p := Vector3(sin(a) * r, s.top, cos(a) * r)
		var d := p.distance_to(from)
		if d < best_d and d > 2.0:
			best_d = d
			best = p
	return best

func _crow_says(b: Node3D, line: String) -> void:
	var bubble: SpeechBubble = b.get_node_or_null("Bubble")
	if bubble == null:
		bubble = SpeechBubble.new()
		bubble.name = "Bubble"
		bubble.position = Vector3(0, 1.4, 0)
		b.add_child(bubble)
		speakers.append(bubble)
	bubble.say(line, 2.6)

func _draw_wire(w: Dictionary) -> void:
	if w.line == null:
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.1, 0.08, 0.1)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		w.line = mi
	var im: ImmediateMesh = w.line.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 17:
		im.surface_add_vertex(wire_point(w, i / 16.0))
	im.surface_end()

func _build_wire(w: Dictionary) -> void:
	var st := MeshUtil.begin()
	var a: Vector3 = w.a
	var b: Vector3 = w.b
	if w.get("poles", false):
		# Telegraph poles from the ground, each with a crossbar and a glass insulator
		for end: Vector3 in [a, b]:
			var foot := Vector3(end.x, 0.0, end.z)
			var across := Vector3(end.z, 0, -end.x).normalized()
			MeshUtil.beam(st, foot, end + Vector3(0, 0.5, 0), 0.2, WOOD.darkened(0.15))
			MeshUtil.beam(st, end + Vector3(0, 0.15, 0) - across * 0.7, end + Vector3(0, 0.15, 0) + across * 0.7, 0.12, WOOD)
			MeshUtil.box(st, end + Vector3(0, 0.05, 0), Vector3(0.14, 0.18, 0.14), 0.0, Color(0.45, 0.7, 0.65))
	else:
		# An iron hook on the wall, and a post on the platform
		MeshUtil.box(st, a, Vector3(0.18, 0.18, 0.3), atan2(a.x, a.z), Color(0.25, 0.24, 0.27))
		MeshUtil.beam(st, b - Vector3(0, 1.45, 0), b + Vector3(0, 0.12, 0), 0.14, WOOD)
	add_child(MeshUtil.commit(st, MeshUtil.flat_material(Color.WHITE)))
	_draw_wire(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(w.id)
	for i in w.birds:
		var tint: Color = Npc.TINTS.values()[rng.randi_range(0, Npc.TINTS.size() - 1)]
		var bird := AnimatedSprite3D.new()
		bird.sprite_frames = Npc.recoloured(Npc.IDLE_FRAMES, tint)
		bird.pixel_size = 0.085
		bird.offset = Vector2(0, 7)
		bird.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		bird.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		bird.shaded = false
		bird.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		bird.flip_h = rng.randf() < 0.5
		var t: float = (i + 1.0) / (w.birds + 1.0) + rng.randf_range(-0.05, 0.05)
		bird.set_meta("t", t)
		bird.set_meta("tint", tint)
		bird.position = wire_point(w, t)
		bird.play("default")
		bird.speed_scale = rng.randf_range(0.5, 1.0)
		add_child(bird)
		w.perched.append(bird)

# --- wind streams -----------------------------------------------------------------

const STREAM_HOOP_EVERY := 7          # sampled points between wind hoops (3.5 m)
const STREAM_RIBBONS := 7
const WIND_WHITE := Color(0.92, 0.98, 1.0)

# A current's curve through its points (Catmull-Rom), resampled every
# STREAM_STEP metres so riding it is an even speed
static func stream_line(pts: Array) -> PackedVector3Array:
	var dense := PackedVector3Array()
	for i in pts.size() - 1:
		var p0: Vector3 = pts[max(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[min(i + 2, pts.size() - 1)]
		var n := maxi(2, int(p1.distance_to(p2) / 0.1))
		for j in n:
			var t := float(j) / n
			dense.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	dense.append(pts[-1])
	var out := PackedVector3Array([dense[0]])
	var carry := 0.0
	for i in range(1, dense.size()):
		var a := dense[i - 1]
		var b := dense[i]
		var seg := a.distance_to(b)
		var d := Tuning.STREAM_STEP - carry
		while d <= seg:
			out.append(a.lerp(b, d / seg))
			d += Tuning.STREAM_STEP
		carry = seg - (d - Tuning.STREAM_STEP)
	return out

# The point `f` samples along a current (f can fall between samples)
static func stream_point(line: PackedVector3Array, f: float) -> Vector3:
	var i := clampi(int(f), 0, line.size() - 2)
	return line[i].lerp(line[i + 1], clamp(f - i, 0.0, 1.0))

static func stream_tangent(line: PackedVector3Array, f: float) -> Vector3:
	var i := clampi(int(f), 1, line.size() - 2)
	return (line[i + 1] - line[i - 1]).normalized()

# Two directions square to the current at a point, for things to circle it
static func _stream_frame(t: Vector3) -> Array[Vector3]:
	var side := t.cross(Vector3.UP)
	side = Vector3.RIGHT if side.length() < 0.01 else side.normalized()
	return [side, side.cross(t)]

# Hoops of wind along the current, as big as the space that catches you,
# and a bundle of ribbons spiralling along it (both animated in _tick_stream)
func _build_stream(sm: Dictionary) -> void:
	var line: PackedVector3Array = sm.line
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(WIND_WHITE, 0.45)
	for i in range(3, line.size() - 3, STREAM_HOOP_EVERY):
		var torus := TorusMesh.new()
		torus.inner_radius = Tuning.STREAM_CATCH - 0.12
		torus.outer_radius = Tuning.STREAM_CATCH
		torus.rings = 20
		torus.ring_segments = 3
		torus.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = torus
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var t := stream_tangent(line, i)
		var f := _stream_frame(t)
		mi.basis = Basis(f[0], t, f[0].cross(t))    # the hole faces along the flow
		mi.position = line[i]
		add_child(mi)
		sm.hoops.append(mi)
	var rib := MeshInstance3D.new()
	rib.mesh = ImmediateMesh.new()
	rib.top_level = true
	rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.vertex_color_use_as_albedo = true
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rib.material_override = rm
	add_child(rib)
	sm.ribbons = rib

func _tick_stream(sm: Dictionary, time: float) -> void:
	# The hoops swell one after another down the flow, showing which way it goes
	for i in sm.hoops.size():
		var s := 1.0 + 0.14 * sin(time * 6.0 - i * 1.1)
		sm.hoops[i].scale = Vector3(s, 1.0, s)
	if sm.ribbons == null:
		return
	var cam := get_viewport().get_camera_3d()
	var im: ImmediateMesh = sm.ribbons.mesh
	im.clear_surfaces()
	if cam == null or global_position.y != 0.0:
		return                           # (not while the tower's growing)
	var line: PackedVector3Array = sm.line
	var n := line.size()
	var run := float(n + 20)
	for k in STREAM_RIBBONS:
		var head := fposmod(time * Tuning.STREAM_SPEED / Tuning.STREAM_STEP * 1.2 + k * run / STREAM_RIBBONS, run)
		var pts: Array[Vector3] = []
		var fade: Array[float] = []
		for j in 16:
			var f := head - j * 0.9
			if f < 0.0 or f > n - 1:
				continue
			var p := stream_point(line, f)
			var fr := _stream_frame(stream_tangent(line, f))
			var spin := f * 0.22 + k * TAU / STREAM_RIBBONS
			var wobble := 0.7 + 0.45 * sin(f * 0.13 + k)
			pts.append(p + (fr[0] * cos(spin) + fr[1] * sin(spin)) * wobble)
			fade.append(sin(PI * j / 15.0) * min(f / 6.0, 1.0) * min((n - 1 - f) / 6.0, 1.0))
		if pts.size() < 3:
			continue
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for j in pts.size():
			var along := (pts[max(j - 1, 0)] - pts[min(j + 1, pts.size() - 1)]).normalized()
			var side := along.cross(cam.global_position - pts[j]).normalized() * 0.045
			var c := Color(WIND_WHITE, 0.8 * fade[j])
			im.surface_set_color(c)
			im.surface_add_vertex(pts[j] + side)
			im.surface_set_color(c)
			im.surface_add_vertex(pts[j] - side)
		im.surface_end()

# A current close enough to catch the bird at `pos`: {stream, i} or {}
func stream_near(pos: Vector3) -> Dictionary:
	var reach := Tuning.STREAM_CATCH * Tuning.STREAM_CATCH
	for sm in streams:
		if sm.cool > 0.0:
			continue
		var line: PackedVector3Array = sm.line
		for i in range(0, line.size() - 6):
			if line[i].distance_squared_to(pos) < reach:
				return {"stream": sm, "i": float(i)}
	return {}

# Where a falling bird crossed a wire this frame (or {}): {wire, t}
func wire_crossed(prev: Vector3, now: Vector3) -> Dictionary:
	for w in wires:
		var a2 := Vector2(w.a.x, w.a.z)
		var b2 := Vector2(w.b.x, w.b.z)
		var p2 := Vector2(now.x, now.z)
		var q := Geometry2D.get_closest_point_to_segment(p2, a2, b2)
		if q.distance_to(p2) > 0.45:
			continue
		var t: float = clamp(a2.distance_to(q) / max(a2.distance_to(b2), 0.01), 0.0, 1.0)
		var wy := wire_point(w, t).y
		if prev.y >= wy - 0.05 and now.y <= wy:
			return {"wire": w, "t": t}
	return {}

# A wooden deck held up by a propeller underneath (the blades spin in tick)
func _build_prop(holder: Node3D, s: Dictionary) -> void:
	var top: float = s.top
	var c := Vector2(s.cx, s.cz)
	var st := MeshUtil.begin()
	MeshUtil.extrude(st, s.polys[0], top - 0.22, top, Color(0.62, 0.44, 0.28), 1.0)
	# Plank lines and a rim
	var poly: PackedVector2Array = s.polys[0]
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		MeshUtil.beam(st, Vector3(p.x, top + 0.02, p.y), Vector3(q.x, top + 0.02, q.y), 0.1, WOOD)
	# Motor housing under the deck, with a brass cap
	MeshUtil.box(st, Vector3(c.x, top - 0.55, c.y), Vector3(0.6, 0.6, 0.6), 0.0, Color(0.35, 0.33, 0.38))
	MeshUtil.cone(st, Vector3(c.x, top - 0.85, c.y), 0.3, -0.35, 6, Color(0.8, 0.62, 0.25))
	holder.add_child(MeshUtil.commit(st, MeshUtil.flat_material(Color.WHITE)))
	var blades := Node3D.new()
	blades.name = "Blades"
	blades.position = Vector3(c.x, top - 1.0, c.y)
	var bt := MeshUtil.begin()
	MeshUtil.box(bt, Vector3.ZERO, Vector3(3.2, 0.06, 0.3), 0.0, Color(0.55, 0.4, 0.28))
	MeshUtil.box(bt, Vector3.ZERO, Vector3(0.3, 0.06, 3.2), 0.0, Color(0.5, 0.36, 0.25))
	blades.add_child(MeshUtil.commit(bt, MeshUtil.flat_material(Color.WHITE)))
	holder.add_child(blades)

# A brass-edged platform riding a rail round the whole tower. The rail stays
# put; the platform's holder is rotated by tick.
func _build_orbit(holder: Node3D, s: Dictionary, tint: Color) -> void:
	var top: float = s.top
	var st := MeshUtil.begin()
	for poly in s.polys:
		MeshUtil.extrude(st, poly, top - 0.3, top, Color(0.95, 0.85, 0.6))
	holder.add_child(MeshUtil.commit(st, MeshUtil.stone_material(tint.lerp(Color(1.0, 0.93, 0.8), 0.5), "slab")))
	var rail := MeshUtil.begin()
	var n := 40
	var rr: float = s.rail_r
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		MeshUtil.beam(rail, Vector3(sin(a0) * rr, top - 0.5, cos(a0) * rr), Vector3(sin(a1) * rr, top - 0.5, cos(a1) * rr), 0.12, Color(0.55, 0.45, 0.3))
	add_child(MeshUtil.commit(rail, MeshUtil.flat_material(Color.WHITE)))

# A long plank catwalk straight out from the wall: railings along both
# sides, struts underneath, cables from high on the wall to the far end, and
# a lantern on the lookout pad
func _build_catwalk(holder: Node3D, s: Dictionary) -> void:
	var top: float = s.top
	var st := MeshUtil.begin()
	var walk: PackedVector2Array = s.polys[0]
	var pad: PackedVector2Array = s.polys[1]
	MeshUtil.extrude(st, walk, top - 0.16, top, Color(0.58, 0.42, 0.28), 1.0)
	MeshUtil.extrude(st, pad, top - 0.25, top, Color(0.55, 0.4, 0.27), 1.0)
	var base := (walk[0] + walk[1]) * 0.5
	var end := Vector2(s.end_x, s.end_z)
	var out := (end - base).normalized()
	var side := Vector2(out.y, -out.x)
	var length: float = s.length
	# Railings
	for sgn in [-1.0, 1.0]:
		var n := int(length / 1.2)
		for i in range(1, n + 1):
			var p: Vector2 = base + out * (i * 1.2) + side * (0.5 * sgn)
			MeshUtil.box(st, Vector3(p.x, top + 0.45, p.y), Vector3(0.08, 0.9, 0.08), 0.0, WOOD)
		var a: Vector2 = base + out * 1.2 + side * (0.5 * sgn)
		var b: Vector2 = base + out * length + side * (0.5 * sgn)
		MeshUtil.beam(st, Vector3(a.x, top + 0.9, a.y), Vector3(b.x, top + 0.9, b.y), 0.07, WOOD)
	# Struts from the wall below, and cables from the wall above to the far end
	var mid: Vector2 = base + out * (length * 0.5)
	MeshUtil.beam(st, Vector3(base.x, top - 2.6, base.y), Vector3(mid.x, top - 0.16, mid.y), 0.18, WOOD.darkened(0.2))
	for sgn in [-1.0, 1.0]:
		var hook: Vector2 = base + side * (0.5 * sgn)
		var tip: Vector2 = end - out * 1.1 + side * (0.5 * sgn)
		MeshUtil.beam(st, Vector3(hook.x, top + 3.6, hook.y), Vector3(tip.x, top + 0.95, tip.y), 0.04, Color(0.15, 0.14, 0.16))
	# Lantern post at the end
	var lp: Vector2 = end + out * 0.9
	MeshUtil.beam(st, Vector3(lp.x, top, lp.y), Vector3(lp.x, top + 1.5, lp.y), 0.1, WOOD)
	MeshUtil.box(st, Vector3(lp.x, top + 1.6, lp.y), Vector3(0.3, 0.35, 0.3), 0.0, Color(0.95, 0.65, 0.25))
	holder.add_child(MeshUtil.commit(st, MeshUtil.flat_material(Color.WHITE)))
	var lamp := Sprite3D.new()
	lamp.texture = MeshUtil.blob_texture(16, Color(1.0, 0.7, 0.3))
	lamp.pixel_size = 0.09
	lamp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lamp.shaded = false
	lamp.modulate.a = 0.6
	lamp.position = Vector3(lp.x, top + 1.6, lp.y)
	holder.add_child(lamp)
