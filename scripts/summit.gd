class_name Summit
extends Node3D
# The crown on top of a section in section mode: a battlemented roof with a
# spire and a beacon burning at its tip. The ring ledge round its foot is the
# summit the bird lands on. When a section is cleared the crown rides up as the
# tower grows beneath it.

const PARAPET := 1.6                 # roof height above the summit ledge
const BEACON := Color(1.0, 0.72, 0.3)

var k := -1                          # the chunk whose shape the crown takes
var beacon: Node3D
var light: OmniLight3D
var time := 0.0

func build(chunk_k: int) -> void:
	for c in get_children():
		c.queue_free()
	k = chunk_k
	position = Vector3(0, k * TowerShape.CHUNK_H, 0)
	var n := TowerShape.sides(k)
	var step := TowerShape.face_step(k)
	var tint := TowerShape.tint(k)
	var corners := PackedVector2Array()
	for i in n:
		corners.append(TowerShape.ring_point(k, TowerShape.face_offset(k) + (i + 0.5) * step, 0.0))

	# The roof block, then merlons round its rim (two per face)
	var stone := MeshUtil.begin()
	MeshUtil.extrude(stone, corners, -0.2, PARAPET, Color(1.0, 0.97, 0.92))
	for i in n:
		var p := corners[i]
		var q := corners[(i + 1) % n]
		var out := ((p + q) * 0.5).normalized()
		var yaw := atan2(out.x, out.y)
		for t in [0.25, 0.75]:
			var at: Vector2 = p.lerp(q, t) - out * 0.2
			MeshUtil.box(stone, Vector3(at.x, PARAPET + 0.3, at.y), Vector3(p.distance_to(q) * 0.28, 0.6, 0.35), yaw, Color(0.95, 0.92, 0.86))
	# A drum in the middle holding up the spire
	var drum := PackedVector2Array()
	for p in corners:
		drum.append(p * 0.5)
	MeshUtil.extrude(stone, drum, PARAPET, PARAPET + 1.8, Color.WHITE)
	add_child(MeshUtil.commit(stone, MeshUtil.stone_material(tint)))

	var roof := MeshUtil.begin()
	var spire_r := TowerShape.apothem(k) * 0.62
	MeshUtil.cone(roof, Vector3(0, PARAPET + 1.8, 0), spire_r, 5.5, n, TowerChunk.ROOF)
	MeshUtil.beam(roof, Vector3(0, PARAPET + 7.2, 0), Vector3(0, PARAPET + 8.4, 0), 0.12, Color(0.8, 0.65, 0.3))
	add_child(MeshUtil.commit(roof, MeshUtil.flat_material(Color.WHITE)))

	# The beacon: a warm glow, a light and a stream of embers
	beacon = Node3D.new()
	beacon.position = Vector3(0, PARAPET + 8.8, 0)
	add_child(beacon)
	var glow := Sprite3D.new()
	glow.texture = MeshUtil.blob_texture(16, BEACON)
	glow.pixel_size = 0.13
	glow.modulate = Color(1, 1, 1, 0.8)
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	glow.shaded = false
	beacon.add_child(glow)
	light = OmniLight3D.new()
	light.light_color = BEACON
	light.omni_range = 16.0
	light.light_energy = 2.0
	beacon.add_child(light)
	var embers := CPUParticles3D.new()
	embers.amount = Tuning.particles(24)
	embers.lifetime = 2.2
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.5
	embers.direction = Vector3.UP
	embers.spread = 25.0
	embers.initial_velocity_min = 1.0
	embers.initial_velocity_max = 2.5
	embers.gravity = Vector3(0, 0.4, 0)
	embers.scale_amount_min = 0.5
	embers.color_ramp = Player._fade_ramp(1.0)
	embers.color = BEACON
	var spark := QuadMesh.new()
	spark.size = Vector2(0.18, 0.18)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	spark.material = m
	embers.mesh = spark
	beacon.add_child(embers)

func _process(delta: float) -> void:
	time += delta
	if light:
		light.light_energy = 2.0 + 0.5 * sin(time * 5.0) + 0.3 * sin(time * 13.0)
		beacon.scale = Vector3.ONE * (1.0 + 0.08 * sin(time * 3.0))
