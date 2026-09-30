class_name HemlockOwl
extends Node3D
# Hemlock, the clockwork owl: brass plates, iron ribs, a ticking heart and
# lantern eyes. Built from seven parts, one recovered at each section's
# summit; any subset can be shown. About 3.6 m tall at scale 1, standing on
# the origin and facing +Z.

const PARTS := ["Talons", "Tail Fan", "Left Wing", "Right Wing", "Clockwork Heart", "Head", "Lantern Eyes"]
const BRASS := Color(0.82, 0.62, 0.3)
const COPPER := Color(0.72, 0.42, 0.26)
const IRON := Color(0.28, 0.24, 0.24)
const GLOW := Color(1.0, 0.72, 0.3)

var parts := {}                      # index -> Node3D
var gear: Node3D                     # the heart's cog (turns)
var key: Node3D                      # the wind-up key on his head (turns)
var eye_light: OmniLight3D
var wing_l: Node3D
var wing_r: Node3D
var flap := 0.0                      # 0 = folded, 1 = beating
var awake := 1.0                     # eye glow
var time := 0.0

static func part_name(i: int) -> String:
	return "Hemlock's " + PARTS[i]

func _init() -> void:
	var metal := StandardMaterial3D.new()
	metal.vertex_color_use_as_albedo = true
	metal.metallic = 0.55
	metal.roughness = 0.45
	# A faint warm glow, so he reads against a night sky
	metal.emission_enabled = true
	metal.emission = Color(0.22, 0.13, 0.04)
	var lit := StandardMaterial3D.new()
	lit.vertex_color_use_as_albedo = true
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# 0 Talons: two feet of three claws forward and one back
	var st := MeshUtil.begin()
	for s in [-1.0, 1.0]:
		var foot := Vector3(0.36 * s, 0.1, 0.05)
		MeshUtil.box(st, foot, Vector3(0.34, 0.2, 0.36), 0.0, IRON)
		MeshUtil.beam(st, foot + Vector3(0, 0.05, 0), Vector3(0.32 * s, 0.5, 0.0), 0.14, IRON)
		for c in [-0.13, 0.0, 0.13]:
			MeshUtil.beam(st, foot + Vector3(c, 0.0, 0.15), foot + Vector3(c * 1.5, -0.08, 0.42), 0.07, BRASS)
		MeshUtil.beam(st, foot + Vector3(0, 0.0, -0.15), foot + Vector3(0, -0.08, -0.36), 0.07, BRASS)
	_part(0, st, metal)

	# 1 Tail Fan: slats fanned out behind and below
	st = MeshUtil.begin()
	for i in 5:
		var a: float = lerp(-0.5, 0.5, i / 4.0)
		MeshUtil.beam(st, Vector3(0, 0.75, -0.55), Vector3(sin(a) * 0.7, 0.15, -1.15), 0.1, BRASS if i % 2 == 0 else COPPER)
	_part(1, st, metal)

	# 2, 3 Wings: feather slats on an iron rib, hinged at the shoulder
	for side in [2, 3]:
		var s := -1.0 if side == 2 else 1.0
		var wing := Node3D.new()
		wing.position = Vector3(0.78 * s, 1.95, -0.05)
		st = MeshUtil.begin()
		MeshUtil.beam(st, Vector3.ZERO, Vector3(0.35 * s, -1.25, -0.1), 0.14, IRON)
		for i in 5:
			var top := Vector3(0.05 * s, -0.12 - i * 0.26, -0.02 - i * 0.03)
			var tip := top + Vector3((0.3 + i * 0.05) * s, -0.55 - i * 0.12, -0.05)
			MeshUtil.beam(st, top, tip, 0.11, BRASS if i % 2 == 0 else COPPER)
		var mi := MeshUtil.commit(st, metal)
		wing.add_child(mi)
		add_child(wing)
		parts[side] = wing
		if side == 2:
			wing_l = wing
		else:
			wing_r = wing

	# 4 Clockwork Heart: the barrel of the body, with a cog behind glass
	st = MeshUtil.begin()
	var bands := [[0.35, 0.6, 0.5], [0.6, 1.0, 0.78], [1.0, 1.7, 0.86], [1.7, 2.1, 0.76], [2.1, 2.38, 0.56]]
	for i in bands.size():
		var b: Array = bands[i]
		MeshUtil.extrude(st, _ring(b[2], 1.0, 0.85), b[0], b[1], BRASS if i % 2 == 1 else COPPER)
	MeshUtil.box(st, Vector3(0, 1.35, 0.72), Vector3(0.8, 0.8, 0.12), 0.0, IRON)
	for r in 3:
		MeshUtil.box(st, Vector3(0, 0.75 + r * 0.45, -0.72), Vector3(0.9, 0.08, 0.1), 0.0, IRON)
	_part(4, st, metal)
	gear = Node3D.new()
	gear.position = Vector3(0, 1.35, 0.8)
	st = MeshUtil.begin()
	MeshUtil.box(st, Vector3.ZERO, Vector3(0.36, 0.36, 0.05), 0.0, GLOW)
	for t in 8:
		var a := TAU * t / 8.0
		MeshUtil.box(st, Vector3(sin(a), cos(a), 0) * 0.25, Vector3(0.1, 0.1, 0.05), 0.0, GLOW)
	gear.add_child(MeshUtil.commit(st, lit))
	parts[4].add_child(gear)

	# 5 Head: a round brass head, facial disc, ear tufts, beak, and the key
	st = MeshUtil.begin()
	MeshUtil.extrude(st, _ring(0.74, 1.12, 0.9), 2.35, 3.3, BRASS)
	MeshUtil.box(st, Vector3(0, 2.85, 0.62), Vector3(1.25, 0.8, 0.1), 0.0, COPPER)
	for s in [-1.0, 1.0]:
		MeshUtil.beam(st, Vector3(0.45 * s, 3.2, 0.0), Vector3(0.7 * s, 3.8, -0.1), 0.16, BRASS)
		MeshUtil.box(st, Vector3(0.3 * s, 2.9, 0.68), Vector3(0.44, 0.44, 0.06), 0.0, IRON)   # sockets
	MeshUtil.cone(st, Vector3(0, 2.72, 0.68), 0.14, -0.34, 4, COPPER)
	_part(5, st, metal)
	key = Node3D.new()
	key.position = Vector3(0, 3.3, -0.1)
	st = MeshUtil.begin()
	MeshUtil.beam(st, Vector3.ZERO, Vector3(0, 0.45, 0), 0.1, BRASS)
	MeshUtil.box(st, Vector3(0, 0.62, 0), Vector3(0.5, 0.26, 0.08), 0.0, BRASS)
	MeshUtil.box(st, Vector3(0, 0.62, 0), Vector3(0.08, 0.5, 0.08), 0.0, BRASS)
	key.add_child(MeshUtil.commit(st, metal))
	parts[5].add_child(key)

	# 6 Lantern Eyes
	st = MeshUtil.begin()
	for s in [-1.0, 1.0]:
		MeshUtil.box(st, Vector3(0.3 * s, 2.9, 0.72), Vector3(0.34, 0.34, 0.06), 0.0, GLOW)
		MeshUtil.box(st, Vector3(0.3 * s, 2.9, 0.75), Vector3(0.12, 0.12, 0.04), 0.0, Color(0.25, 0.1, 0.05))
	_part(6, st, lit)
	eye_light = OmniLight3D.new()
	eye_light.light_color = GLOW
	eye_light.omni_range = 7.0
	eye_light.light_energy = 1.3
	eye_light.position = Vector3(0, 2.9, 1.2)
	parts[6].add_child(eye_light)

func _part(i: int, st: SurfaceTool, mat: Material) -> void:
	var n := Node3D.new()
	n.add_child(MeshUtil.commit(st, mat))
	add_child(n)
	parts[i] = n

# An octagon, squashed to `sx` wide and `sz` deep
static func _ring(r: float, sx: float, sz: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		pts.append(Vector2(sin(a) * r * sx, cos(a) * r * sz))
	return pts

# Show the first `n` parts (the order they're recovered in)
func show_parts(n: int) -> void:
	for i in parts:
		parts[i].visible = i < n

func _process(delta: float) -> void:
	time += delta
	if gear and parts[4].visible:
		gear.rotation.z += delta * 1.5
	if key:
		key.rotation.y += delta * 0.8 * awake
	var beat: float = sin(time * 9.0) * 0.75 * flap
	if wing_l:
		wing_l.rotation.z = -beat - 0.1 * flap
		wing_r.rotation.z = beat + 0.1 * flap
	eye_light.light_energy = 1.3 * awake
