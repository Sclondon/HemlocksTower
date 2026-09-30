class_name CloudLayers
extends Node3D
# A deck of stepped-alpha clouds just under each band's ring, so every new
# band starts by bursting up through the clouds, and puffy clouds (spheres
# with scrolling noise) billowing round each deck and drifting higher up.
# Decks near the focus exist; the rest are freed.

const CLOUD_SHADER := preload("res://shaders/clouds.gdshader")
const PUFF_SHADER := preload("res://shaders/cloud_puff.gdshader")
const PUFF_MIN_R := 34.0             # clear of the climb and the camera
const DECK_SIZE := 2600.0           # follows the camera; the shader fades it out
const CLOUD_SCALE := 380.0           # metres across the cloud pattern: big, sweeping banks
const KEEP_BANDS := 2

var noise_tex: NoiseTexture2D
var decks := {}                      # band index -> Node3D
var puffs := {}                      # band index -> MultiMeshInstance3D (world-anchored, circling slowly)
var last_tint := Color.WHITE

static func deck_height(b: int) -> float:
	return b * TowerShape.BAND_H - 5.0

func _ready() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	noise_tex = NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.noise = noise

func update(focus_y: float, tint: Color, cam_pos: Vector3) -> void:
	var c := roundi(focus_y / TowerShape.BAND_H)
	for b in range(max(1, c - KEEP_BANDS), c + KEEP_BANDS + 1):
		if not decks.has(b):
			decks[b] = _make_deck(b)
	# The meadow has no deck, just puffs high overhead
	if c <= KEEP_BANDS and not puffs.has(0):
		puffs[0] = _make_puffs(0, Weather.weather_of(0))
	for b in puffs.keys():
		puffs[b].rotation.y = Time.get_ticks_msec() * 0.001 * (0.006 if b % 2 == 0 else -0.006)
		if tint != last_tint or puffs[b].get_meta("fresh", true):
			puffs[b].set_meta("fresh", false)
			puffs[b].multimesh.mesh.material.set_shader_parameter("tint", tint)
		if abs(b - c) > KEEP_BANDS + 1:
			puffs[b].queue_free()
			puffs.erase(b)
	for b in decks.keys():
		# Noise is sampled in world space, so sliding the plane along is invisible
		decks[b].position.x = cam_pos.x
		decks[b].position.z = cam_pos.z
		if tint != last_tint or decks[b].get_meta("fresh", true):
			decks[b].set_meta("fresh", false)
			for mi in decks[b].get_children():
				mi.mesh.material.set_shader_parameter("tint", tint)
		if abs(b - c) > KEEP_BANDS + 1:
			decks[b].queue_free()
			decks.erase(b)
	last_tint = tint

func clear() -> void:
	for d in decks.values():
		d.queue_free()
	decks.clear()
	for p in puffs.values():
		p.queue_free()
	puffs.clear()

func _make_deck(b: int) -> Node3D:
	var below := Weather.weather_of(b - 1)
	var deck := Node3D.new()
	deck.position.y = deck_height(b)
	add_child(deck)
	# Two thin, broken layers: a light scatter of cloud to fly up through,
	# not a wall of it
	for i in (1 if Tuning.low_quality else 2):
		var m := ShaderMaterial.new()
		m.shader = CLOUD_SHADER
		m.set_shader_parameter("noise_tex", noise_tex)
		m.set_shader_parameter("color", below.cloud)
		m.set_shader_parameter("shade", (below.cloud as Color).darkened(0.25))
		m.set_shader_parameter("coverage", below.cover * 0.45 - i * 0.06)
		m.set_shader_parameter("scale", CLOUD_SCALE)
		m.set_shader_parameter("fade_near", 450.0)
		m.set_shader_parameter("fade_far", 1150.0)
		m.set_shader_parameter("offset", b * 0.37 + i * 0.21)
		m.set_shader_parameter("wind", Vector2(0.006, 0.002) * (1.0 + i * 0.4))
		m.render_priority = i
		var plane := PlaneMesh.new()
		plane.size = Vector2(DECK_SIZE, DECK_SIZE)
		plane.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = (i - 1) * 1.6
		deck.add_child(mi)
	puffs[b] = _make_puffs(b, below)
	return deck

# Billows of 3-6 spheres: some sitting in the deck, some drifting higher up
func _make_puffs(b: int, look: Dictionary) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([b, 77])
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var m := ShaderMaterial.new()
	m.shader = PUFF_SHADER
	m.set_shader_parameter("noise_tex", noise_tex)
	m.set_shader_parameter("color", look.cloud)
	m.set_shader_parameter("shade", (look.cloud as Color).darkened(0.3))
	sphere.material = m
	var xforms: Array[Transform3D] = []
	for cluster in (6 if Tuning.low_quality else 12):
		var a := rng.randf() * TAU
		var r := PUFF_MIN_R + pow(rng.randf(), 1.3) * 160.0
		# Half sit in the deck, half drift up through the band
		var y := rng.randf_range(-3.0, 5.0) if cluster % 2 == 0 and b > 0 else rng.randf_range(35.0, 95.0)
		var centre := Vector3(sin(a) * r, y, cos(a) * r)
		var size := rng.randf_range(5.0, 11.0)
		for i in rng.randi_range(3, 6):
			var off := Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.2, 0.7), rng.randf_range(-1.2, 1.2)) * size
			var s := size * rng.randf_range(0.55, 1.0)
			xforms.append(Transform3D(Basis.from_scale(Vector3(s * 1.25, s * 0.8, s)), centre + off))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.position.y = deck_height(b)
	add_child(mmi)
	return mmi
