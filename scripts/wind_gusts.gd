class_name WindGusts
extends MeshInstance3D
# Wind you can see, drawn the Wind Waker way: a few long white ribbons that
# flow round the tower with the wind, bobbing gently, and every so often
# curling up into a loop-de-loop. Each gust's head leaves a tapering tail
# behind it; when the gust dies its tail keeps drifting until it fades out.

const TAIL_LIFE := 0.75              # seconds a tail point lasts
const WIDTH := 0.035
const MIN_STEP := 0.12               # metres between recorded points
const LOOP_TIME := 0.85              # seconds for one full loop
const LOOP_CHANCE := 0.5             # odds a gust loops at some point

var gusts: Array = []                # {theta, r, y, a, speed, age, life, loop_at, loop_a, phase, pts}
var strength := 0.0                  # 0..1 how visible the wind is
var spawn_timer := 0.0
var _time := 0.0
var _mesh := ImmediateMesh.new()

func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m

# wind: tangential m/s (positive = theta grows); focus: what the camera
# watches; cam_theta: the camera's angle round the tower
func update(delta: float, wind: float, focus: Vector3, cam_theta: float) -> void:
	_time += delta
	var windy: bool = abs(wind) > 0.4
	strength = move_toward(strength, clamp(abs(wind) / 3.0, 0.35, 1.0) if windy else 0.0, delta)
	var dir := signf(wind) if windy else 1.0
	var wanted := Tuning.particles(13) if windy else 0
	spawn_timer -= delta
	var live := gusts.filter(func(g): return g.age < g.life).size()
	if live < wanted and spawn_timer <= 0.0:
		spawn_timer = randf_range(0.08, 0.3)
		_spawn(focus, cam_theta, dir)

	for g in gusts:
		g.age += delta
		if g.age < g.life:
			_steer(g, delta, dir)
			var p := _pos(g)
			var pts: Array = g.pts
			if pts.is_empty() or pts[-1].pos.distance_to(p) > MIN_STEP:
				pts.append({"pos": p, "t": _time})
		while not g.pts.is_empty() and _time - g.pts[0].t > TAIL_LIFE:
			g.pts.pop_front()
	gusts = gusts.filter(func(g): return g.age < g.life or not g.pts.is_empty())
	_rebuild()

func _spawn(focus: Vector3, cam_theta: float, dir: float) -> void:
	var focus_r := Vector2(focus.x, focus.z).length()
	# Upwind, anywhere in a big volume round the bird: from the tower's
	# face out past the lens, well above and below
	var r: float = max(focus_r, 4.0) + randf_range(-1.0, 16.0)
	gusts.append({
		"theta": cam_theta - dir * randf_range(0.2, 1.4), "r": r, "y": focus.y + randf_range(-9.0, 13.0),
		"a": 0.0, "speed": randf_range(9.0, 13.0), "age": 0.0, "life": randf_range(1.4, 2.4),
		"loop_at": randf_range(0.3, 1.0) if randf() < LOOP_CHANCE else INF, "loop_a": -1.0,
		"phase": randf() * TAU, "pts": [],
	})

# The head flies along the wind, its heading `a` (in the along / up plane)
# swaying gently, or spinning through a full turn while it loops
func _steer(g: Dictionary, delta: float, dir: float) -> void:
	if g.loop_a < 0.0 and g.age >= g.loop_at:
		g.loop_a = 0.0
	if g.loop_a >= 0.0 and g.loop_a < TAU:
		g.loop_a = min(g.loop_a + TAU * delta / LOOP_TIME, TAU)
		g.a = g.loop_a
	else:
		g.a = 0.22 * sin(g.age * 2.2 + g.phase)
	var along: float = g.speed * cos(g.a)
	g.theta += dir * along / g.r * delta
	g.y += g.speed * sin(g.a) * delta
	g.r += 0.6 * sin(g.age * 1.3 + g.phase * 2.0) * delta

func _pos(g: Dictionary) -> Vector3:
	return Vector3(sin(g.theta) * g.r, g.y, cos(g.theta) * g.r)

func _rebuild() -> void:
	if gusts.is_empty() and _mesh.get_surface_count() == 0:
		return
	_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for g in gusts:
		var pts: Array = g.pts
		if pts.size() < 3:
			continue
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var n := pts.size()
		for i in n:
			var p: Vector3 = pts[i].pos
			var along: Vector3 = (pts[min(i + 1, n - 1)].pos - pts[max(i - 1, 0)].pos).normalized()
			var side := along.cross(cam.global_position - p).normalized()
			# Thin at the tail, full through the body, pointed at the head
			var life: float = 1.0 - (_time - pts[i].t) / TAIL_LIFE
			var head: float = clamp(float(n - 1 - i) / 3.0, 0.0, 1.0)
			var w := WIDTH * sqrt(life) * (0.35 + 0.65 * head)
			var c := Color(1, 1, 1, 0.75 * strength * life)
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(p + side * w)
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(p - side * w)
		_mesh.surface_end()
