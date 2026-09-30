class_name HubStations
extends Node3D
# The meadow is the hub: places to go, each doing something.
#  - Two witches' cauldrons, bubbling on their fires. Jump in:
#     - the blue stew takes you to the start of any section you've reached,
#     - the green stew dreams you an Endless tower (and in Endless, jumping
#       back in wakes you up).
#    Say "not yet" and the cauldron spits you back out.
#  - Hemlock's plinth: the clockwork owl, rebuilt a part per section
#    cleared. Once whole, walking up to him offers to wind his key (the boss).
# The tower itself is the Ascent: just climb.

signal entered(station: String)

# (theta, r): side by side round the back of the tower, opposite its door
const TRAVEL := Vector2(PI - 0.2, 15.0)
const DREAM := Vector2(PI + 0.2, 15.0)
const POT_R := 1.6                    # the cauldron's belly
const RIM := 1.75                     # height of its rim
const STEWS := {
	"travel": {"name": "THE WANDERING STEW", "brew": Color(0.3, 0.6, 1.0), "deep": Color(0.06, 0.12, 0.35)},
	"dream": {"name": "THE DREAMING STEW", "brew": Color(0.4, 0.95, 0.35), "deep": Color(0.07, 0.3, 0.1)},
}
const BREW_SHADER := preload("res://shaders/brew.gdshader")
const IRON := Color(0.2, 0.19, 0.22)
const HEMLOCK := Vector2(5.35, 13.0)
const HEMLOCK_REACH := 2.6
const PLINTH := 0.9

var active := true                   # off while not in the meadow's own run
var inside := ""                     # the station the bird is in
var labels := {}
var time := 0.0
var flames: Array[Node3D] = []
var owl: HemlockOwl
var owl_parts := 0
var owl_beaten := false

static func spot(p: Vector2, out := 0.0) -> Vector3:
	return Vector3(sin(p.x) * (p.y + out), 0.0, cos(p.x) * (p.y + out))

static func where(id: String) -> Vector2:
	return TRAVEL if id == "travel" else DREAM

func _ready() -> void:
	_build_cauldron("travel")
	_build_cauldron("dream")
	_build_plinth()

# A round-bellied iron pot on three stubby legs over a log fire, full to the
# brim with bubbling stew, steaming
func _build_cauldron(id: String) -> void:
	var at := spot(where(id))
	var stew: Dictionary = STEWS[id]
	var st := MeshUtil.begin()
	# The belly, as stacked bands: narrow foot, wide middle, drawn-in neck
	var bands := [[0.35, 0.6, 1.1], [0.6, 0.95, 1.45], [0.95, 1.3, POT_R], [1.3, 1.55, 1.45]]
	for b in bands:
		MeshUtil.extrude(st, HemlockOwl._ring(b[2], 1.0, 1.0), b[0], b[1], IRON)
	# A thick lip round the rim, and the legs
	for i in 16:
		var a := TAU * i / 16.0
		MeshUtil.box(st, at * 0.0 + Vector3(sin(a), 0, cos(a)) * 1.42 + Vector3(0, 1.62, 0), Vector3(0.62, 0.26, 0.3), a, IRON.lightened(0.08))
	for i in 3:
		var a := TAU * i / 3.0 + 0.3
		MeshUtil.beam(st, Vector3(sin(a), 0, cos(a)) * 1.0 + Vector3(0, 0.45, 0), Vector3(sin(a), 0, cos(a)) * 1.25, 0.22, IRON)
	# Logs under it
	var wood := Color(0.36, 0.22, 0.12)
	for i in 3:
		var a := TAU * i / 3.0
		MeshUtil.beam(st, Vector3(sin(a), 0.12, cos(a)) * 0.9, Vector3(sin(a + PI), 0.12, cos(a + PI)) * 0.9 + Vector3(0, 0.12, 0), 0.24, wood)
	var pot := MeshUtil.commit(st, MeshUtil.flat_material(Color.WHITE))
	pot.position = at
	add_child(pot)
	# The stew, filling it to just under the lip
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.35
	cyl.bottom_radius = 1.35
	cyl.height = 0.05
	cyl.radial_segments = 16
	var m := ShaderMaterial.new()
	m.shader = BREW_SHADER
	m.set_shader_parameter("brew", stew.brew)
	m.set_shader_parameter("deep", stew.deep)
	cyl.material = m
	disc.mesh = cyl
	disc.position = at + Vector3(0, 1.56, 0)
	add_child(disc)
	# Flames licking up round the belly (they flicker in update)
	for i in 5:
		var a := TAU * i / 5.0
		var f := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.22
		cone.height = 0.7
		cone.radial_segments = 5
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.albedo_color = Color(1.0, 0.55, 0.15) if i % 2 == 0 else Color(1.0, 0.85, 0.3)
		cone.material = fm
		f.mesh = cone
		f.position = at + Vector3(sin(a), 0, cos(a)) * 0.55 + Vector3(0, 0.35, 0)
		f.set_meta("phase", randf() * TAU)
		add_child(f)
		flames.append(f)
	# Bubbles and steam rising off the brew
	var bubbles := CPUParticles3D.new()
	bubbles.amount = Tuning.particles(16)
	bubbles.lifetime = 1.6
	bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	bubbles.emission_sphere_radius = 1.0
	bubbles.direction = Vector3.UP
	bubbles.spread = 15.0
	bubbles.initial_velocity_min = 0.6
	bubbles.initial_velocity_max = 1.4
	bubbles.gravity = Vector3.ZERO
	bubbles.color_ramp = Player._fade_ramp(1.0)
	bubbles.color = (stew.brew as Color).lightened(0.3)
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	bm.vertex_color_use_as_albedo = true
	bm.albedo_texture = MeshUtil.blob_texture(8, Color.WHITE)
	q.material = bm
	bubbles.mesh = q
	bubbles.position = at + Vector3(0, 1.7, 0)
	add_child(bubbles)
	var light := OmniLight3D.new()
	light.light_color = stew.brew
	light.omni_range = 6.0
	light.light_energy = 1.3
	light.position = at + Vector3(0, 2.4, 0)
	light.visible = not Tuning.low_quality     # (phones: the glowing stew alone)
	add_child(light)
	labels[id] = _label(stew.name, at + Vector3(0, 4.0, 0))

# The bird said "not yet": the cauldron spits it back out, away from the tower
func spit_out(bird: Player) -> void:
	var at := where(inside)
	bird.place(at.x + randf_range(-0.05, 0.05), at.y + POT_R + 1.4, 0.0)
	bird.vy = 9.0
	bird.grounded = false
	bird.fall_from = bird.y
	if Feathers.the:
		Feathers.the.burst(bird.world_position() + Vector3(0, 0.6, 0), 3)

func _build_plinth() -> void:
	var at := spot(HEMLOCK)
	var st := MeshUtil.begin()
	MeshUtil.extrude(st, HemlockOwl._ring(1.5, 1.0, 1.0), 0.0, PLINTH, Color(0.62, 0.6, 0.66))
	MeshUtil.extrude(st, HemlockOwl._ring(1.7, 1.0, 1.0), 0.0, 0.25, Color(0.5, 0.5, 0.55))
	st.set_color(Color.WHITE)
	var mi := MeshUtil.commit(st, MeshUtil.stone_material(Color(0.85, 0.83, 0.9)))
	mi.position = at
	add_child(mi)
	owl = HemlockOwl.new()
	owl.position = at + Vector3(0, PLINTH, 0)
	owl.rotation.y = HEMLOCK.x          # facing out, toward the camera
	owl.scale = Vector3.ONE * 0.9
	add_child(owl)
	labels.hemlock = _label("HEMLOCK", at + Vector3(0, PLINTH + 4.3, 0))
	set_parts(0, false)

# How much of Hemlock the player has recovered
func set_parts(n: int, beaten: bool) -> void:
	owl_parts = n
	owl_beaten = beaten
	owl.show_parts(n)
	owl.awake = 0.35 if beaten else (1.0 if n >= HemlockOwl.PARTS.size() else 0.0)
	labels.hemlock.text = "HEMLOCK  ·  AT REST" if beaten else "HEMLOCK  ·  %d / %d" % [n, HemlockOwl.PARTS.size()]

func _label(text: String, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Menus.display_font(800, 2)
	l.font_size = 64
	l.outline_size = 16
	l.outline_modulate = Menus.INK
	l.modulate = Menus.GOLD
	l.pixel_size = 0.008
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false          # (the tower hides it, rather than it showing through)
	l.fixed_size = false
	l.position = at
	add_child(l)
	return l

# Checks where the bird is; fires `entered` once each time it gets in.
# Cauldrons are solid (walk into one and you're nudged round it): you have
# to jump up over the rim and drop into the stew. `endless` changes what
# the green one does; `can_enter` is false outside play.
func update(delta: float, bird: Player, endless: bool, can_enter: bool) -> void:
	time += delta
	var pos := bird.world_position()
	# Only the nearest station's name shows (the cauldrons sit close together)
	var nearest := ""
	var nearest_d := INF
	for key in labels:
		var d := Vector2(pos.x, pos.z).distance_to(Vector2(labels[key].position.x, labels[key].position.z))
		if labels[key].visible and d < nearest_d:
			nearest_d = d
			nearest = key
	for key in labels:
		var near: float = clamp(1.0 - (nearest_d - 6.0) / 6.0, 0.0, 1.0) if key == nearest else 0.0
		var a: float = near if active and pos.y < 12.0 else 0.0
		labels[key].modulate.a = a
		labels[key].outline_modulate = Color(Menus.INK, a)     # (the outline has its own colour)
	labels.dream.text = "WAKE UP" if endless else STEWS.dream.name
	labels.travel.visible = not endless
	labels.hemlock.visible = not endless
	for f in flames:
		var ph: float = f.get_meta("phase")
		f.scale = Vector3(1.0, 0.75 + 0.35 * sin(time * 11.0 + ph) + 0.15 * sin(time * 23.0 + ph * 2.0), 1.0)
	var now := ""
	if active:
		for id in ["travel", "dream"]:
			if id == "travel" and endless:
				continue
			var c := spot(where(id))
			var flat := Vector2(pos.x - c.x, pos.z - c.z)
			if pos.y < RIM - 0.1 and flat.length() < POT_R + 0.35:
				# Bumped into the pot: round it, not through it
				var out := c + Vector3(flat.x, 0, flat.y).normalized() * (POT_R + 0.35)
				bird.theta = atan2(out.x, out.z)
				bird.r = Vector2(out.x, out.z).length()
			elif can_enter and flat.length() < 1.3 and pos.y < RIM + 1.5 and bird.vy < 0.0 and not bird.grounded:
				now = id                  # dropped in from above
		var by_owl := Vector2(pos.x, pos.z).distance_to(Vector2(spot(HEMLOCK).x, spot(HEMLOCK).z)) < HEMLOCK_REACH
		if can_enter and not endless and bird.grounded and pos.y < 1.0 and owl_parts >= HemlockOwl.PARTS.size() and by_owl:
			now = "hemlock"
	if now != inside:
		inside = now
		if now != "":
			entered.emit(now)
