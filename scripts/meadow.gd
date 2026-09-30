class_name Meadow
extends Node3D
# The living part of the meadow at the tower's foot: fireflies, will-o'-wisps
# drifting between the trees, a low ground mist, and - after dusk - pairs of
# eyes blinking in the treeline. Only runs while the bird is near the ground.

const VISIBLE_BELOW := 50.0          # metres; above this the meadow sleeps
const CLOUD_SHADER := preload("res://shaders/clouds.gdshader")
const MIST_SHADER := preload("res://shaders/mist.gdshader")
const WISP := preload("res://images/ambient/willOWisp.png")

var fireflies: CPUParticles3D
var wisps: Array[Sprite3D] = []
var eyes: Array[Node3D] = []
var mist: MeshInstance3D
var time := 0.0

func _ready() -> void:
	# Fireflies: slow-drifting warm specks near the grass
	fireflies = CPUParticles3D.new()
	fireflies.amount = Tuning.particles(70)
	fireflies.lifetime = 4.0
	fireflies.preprocess = 4.0
	fireflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fireflies.emission_box_extents = Vector3(26, 1.4, 26)
	fireflies.position = Vector3(0, 1.4, 0)
	fireflies.direction = Vector3.UP
	fireflies.spread = 180.0
	fireflies.initial_velocity_min = 0.1
	fireflies.initial_velocity_max = 0.5
	fireflies.gravity = Vector3.ZERO
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.5, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	fireflies.color_ramp = ramp
	fireflies.mesh = _glow_quad(Color(0.85, 1.0, 0.45), 0.16)
	add_child(fireflies)

	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	# Will-o'-wisps: pale lights wandering slow loops between the trees
	for i in 4:
		var w := Sprite3D.new()
		w.texture = WISP        # 6 frames, from 8 Bit Evil Returns
		w.hframes = 6
		w.pixel_size = 0.045
		w.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		w.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		w.shaded = false
		w.set_meta("r", rng.randf_range(12.0, 26.0))
		w.set_meta("phase", rng.randf() * TAU)
		w.set_meta("speed", rng.randf_range(0.05, 0.12))
		add_child(w)
		wisps.append(w)

	# Eyes in the treeline: a pair of dots that blinks, and now and then moves
	for i in 12:
		var pair := Node3D.new()
		var col := Color(1.0, 0.85, 0.3) if rng.randf() < 0.6 else Color(1.0, 0.25, 0.2)
		for side in [-1.0, 1.0]:
			var e := Sprite3D.new()
			e.texture = MeshUtil.pixel_texture(["x"], {"x": col})
			e.pixel_size = 0.22
			e.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			e.shaded = false
			e.position = Vector3(side * 0.22, 0, 0)
			pair.add_child(e)
		_place_eyes(pair, rng)
		add_child(pair)
		eyes.append(pair)

	# A thin mist lying on the grass
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.noise = noise
	var m := ShaderMaterial.new()
	# (phones: the plain cloud shader: reading the depth buffer for the
	# meeting line is costly on phone GPUs)
	m.shader = CLOUD_SHADER if Tuning.low_quality else MIST_SHADER
	m.set_shader_parameter("noise_tex", tex)
	m.set_shader_parameter("color", Color(0.85, 0.9, 0.95, 0.45))
	m.set_shader_parameter("shade", Color(0.7, 0.75, 0.85, 0.45))
	# Big, loose drifts rather than a fine even film
	m.set_shader_parameter("coverage", 0.36)
	m.set_shader_parameter("scale", 75.0)
	m.set_shader_parameter("fade_near", 45.0)
	m.set_shader_parameter("fade_far", 140.0)
	# (a soft rim round each drift, and a bright line where the mist meets
	# anything standing in it: see mist.gdshader)
	var plane := PlaneMesh.new()
	plane.size = Vector2(320, 320)
	plane.material = m
	mist = MeshInstance3D.new()
	mist.mesh = plane
	mist.position.y = 1.2
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mist)

func _place_eyes(pair: Node3D, rng: RandomNumberGenerator) -> void:
	var a := rng.randf() * TAU
	var r := rng.randf_range(50.0, 62.0)
	pair.position = Vector3(sin(a) * r, rng.randf_range(0.8, 3.0), cos(a) * r)
	pair.set_meta("blink", rng.randf_range(1.0, 5.0))

static func _glow_quad(color: Color, size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = MeshUtil.blob_texture(8, Color.WHITE)
	q.material = m
	return q

# `night` is 0 by day, 1 at deep night
func update(delta: float, focus_y: float, night: float, cam_pos: Vector3) -> void:
	# The forest is seen from high up too, so dim it whatever the height
	for m in TowerChunk.forest_materials:
		m.set_shader_parameter("light", lerp(1.0, 0.38, night))
	for s in TowerChunk.night_sprites:
		var lit: Color = (s.get_meta("tint") as Color) * lerp(1.0, 0.38, night)
		lit.a = 1.0
		s.modulate = lit
	visible = focus_y < VISIBLE_BELOW
	fireflies.emitting = visible
	if not visible:
		return
	time += delta
	(fireflies.mesh.material as StandardMaterial3D).albedo_color.a = lerp(0.25, 1.0, night)
	mist.position.x = cam_pos.x
	mist.position.z = cam_pos.z
	for w in wisps:
		var t: float = time * w.get_meta("speed") + w.get_meta("phase")
		var r: float = w.get_meta("r") + sin(t * 2.3) * 3.0
		w.position = Vector3(sin(t) * r, 1.3 + sin(t * 3.1) * 0.6, cos(t * 1.3) * r)
		w.modulate.a = lerp(0.3, 0.9, night) * (0.7 + 0.3 * sin(time * 2.0 + t * 7.0))
		w.frame = int(time * 8.0 + w.get_meta("phase") * 3.0) % 6
	# Eyes only open after dusk, blink, and sometimes aren't where they were
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for pair in eyes:
		var blink: float = pair.get_meta("blink") - delta
		if blink <= 0.0:
			if rng.randf() < 0.15:
				_place_eyes(pair, rng)
			else:
				pair.set_meta("blink", rng.randf_range(2.0, 6.0))
			blink = pair.get_meta("blink")
		pair.set_meta("blink", blink)
		pair.visible = night > 0.45 and blink > 0.15
