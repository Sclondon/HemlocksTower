class_name PaperTrees
# The meadow's forest, after the trees in Paradise Island. Each tree is
# grown procedurally: a leaning, tapering trunk flared at the foot, branches,
# all in chunky pixel bark, and round clumps of leaves at the top and the
# branch ends, made from the pixel-art leaf sprite: fixed cards set round a
# ball, each facing outward (a bushy 3D crown from any side, not a
# billboard). Three kinds:
#  - broad trees: a short thick brown trunk, long branches reaching out
#    nearly level, big flattened clumps of big leaves (the teal fronds),
#  - aspens: tall and skinny, a long thin pale trunk, short branches angled
#    steeply up and a narrow column of stretched clumps (the round green
#    leaves),
#  - dead trees: bare, grey, gnarled branches that fork again. No leaves.
# A few shapes of each are grown, then scattered with their own turn and
# size as MultiMeshes: a handful of draw calls for the whole wood. A soft
# shadow sits under each, and a few owls perch in the crowns nearest the
# meadow.

enum Kind { BROAD, ASPEN, DEAD }
const CANOPIES := {Kind.BROAD: preload("res://images/paradise/canopy_teal.png"), Kind.ASPEN: preload("res://images/paradise/canopy_leafy.png")}
const TRUNK_SHADER := preload("res://shaders/paper_trunk.gdshader")
const LEAF_SHADER := preload("res://shaders/paper_leaves.gdshader")
const NOMINAL_H := 16.0              # trees are grown this tall, then scaled
const SIDES := 7
const SHAPES := 4                    # shapes grown per kind
const OWLS := 4
const MIX := {Kind.BROAD: 0.4, Kind.ASPEN: 0.3, Kind.DEAD: 0.3}
const HEIGHT := {Kind.BROAD: 1.2, Kind.ASPEN: 1.3, Kind.DEAD: 1.0}   # of the height asked for
const BROAD_SETBACK := 16.0         # metres further out the broad trees stand

# trees: [position, height] each. Materials that should follow the night go
# into `lit_materials`.
static func add(ground: Node3D, trees: Array, lit_materials: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var bark_mats := {}
	var leaf_mats := {}
	for kind in Kind.values():
		var b := ShaderMaterial.new()
		b.shader = TRUNK_SHADER
		b.set_shader_parameter("tex", _bark(kind))
		bark_mats[kind] = b
		lit_materials.append(b)
		if CANOPIES.has(kind):
			var l := ShaderMaterial.new()
			l.shader = LEAF_SHADER
			l.set_shader_parameter("tex", _calm(CANOPIES[kind], 0.35) if kind == Kind.ASPEN else CANOPIES[kind])
			leaf_mats[kind] = l
			lit_materials.append(l)
	var shapes := {}                     # kind -> [grown trees]
	for kind in Kind.values():
		shapes[kind] = []
		for i in SHAPES:
			shapes[kind].append(_grow(rng, kind))
	var placed := {}                     # Vector2i(kind, shape) -> [Transform3D]
	var shadow_xf: Array[Transform3D] = []
	var crowns := []                     # [top clump in the world, its radius] (leafy trees)
	for t in trees:
		var base: Vector3 = t[0]
		var roll := rng.randf()
		var kind := Kind.BROAD if roll < MIX[Kind.BROAD] else (Kind.ASPEN if roll < MIX[Kind.BROAD] + MIX[Kind.ASPEN] else Kind.DEAD)
		if kind == Kind.BROAD:
			# Their crowns spread far: plant them further back, so the canopy
			# ends about where the wood's edge is rather than over the meadow
			base += Vector3(base.x, 0, base.z).normalized() * BROAD_SETBACK
		var h: float = t[1] * HEIGHT[kind]
		var s := h / NOMINAL_H
		var shape := rng.randi_range(0, SHAPES - 1)
		var key := Vector2i(kind, shape)
		if not placed.has(key):
			placed[key] = []
		var turn := Basis(Vector3.UP, rng.randf() * TAU)
		placed[key].append(Transform3D(turn.scaled(Vector3.ONE * s), base))
		var grown: Dictionary = shapes[kind][shape]
		var top: Vector3 = base + turn * grown.top * s
		var spread: float = grown.spread * s
		if kind != Kind.DEAD:
			crowns.append([top, grown.top_r * s])
		shadow_xf.append(Transform3D(Basis.from_scale(Vector3(spread, 1.0, spread)), Vector3(top.x, 0.04, top.z)))
	for key: Vector2i in placed:
		var grown: Dictionary = shapes[key.x][key.y]
		_multimesh(ground, grown.wood, bark_mats[key.x], placed[key])
		if grown.leaves:
			_multimesh(ground, grown.leaves, leaf_mats[key.x], placed[key])
	# Soft round shadows on the grass
	var plane := QuadMesh.new()
	plane.size = Vector2.ONE
	plane.orientation = PlaneMesh.FACE_Y
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = MeshUtil.blob_texture(32, Color(0.05, 0.08, 0.05))
	sm.albedo_color = Color(1, 1, 1, 0.45)
	_multimesh(ground, plane, sm, shadow_xf)
	_perch_owls(ground, crowns)
	_treeline(ground, leaf_mats)

# One tree: {wood, leaves (meshes; no leaves on a dead one), top (its top
# clump's centre), top_r, spread (how wide its shadow is)}
static func _grow(rng: RandomNumberGenerator, kind: int) -> Dictionary:
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var H := NOMINAL_H
	# [trunk top, trunk thickness, lean, branch count, branch start, branch
	#  rise (radians), branch length, clump radius, clump stretch (tall/flat)]
	var p: Dictionary
	match kind:
		Kind.BROAD:
			p = {"top": 0.5, "thick": 1.25, "lean": rng.randf_range(0.2, 0.8), "n": rng.randi_range(5, 7), "from": Vector2(0.45, 0.88),
				"rise": Vector2(0.1, 0.4), "len": Vector2(0.38, 0.55), "clump": Vector2(0.2, 0.26), "stretch": 0.75}
		Kind.ASPEN:
			p = {"top": 0.82, "thick": 0.28, "lean": rng.randf_range(0.05, 0.3), "n": rng.randi_range(4, 5), "from": Vector2(0.4, 0.92),
				"rise": Vector2(0.95, 1.3), "len": Vector2(0.08, 0.13), "clump": Vector2(0.095, 0.12), "stretch": 1.5}
		_:
			p = {"top": 0.6, "thick": 0.9, "lean": rng.randf_range(0.4, 1.2), "n": rng.randi_range(4, 6), "from": Vector2(0.4, 0.9),
				"rise": Vector2(0.2, 0.9), "len": Vector2(0.18, 0.32), "clump": Vector2.ZERO, "stretch": 1.0}
	var top_h: float = H * p.top
	var thick: float = p.thick
	var lean: float = p.lean
	# Some broad trees have a second storey: the trunk carries on up through
	# the first canopy and spreads a smaller one above it
	var tiered := kind == Kind.BROAD and rng.randf() < 0.5
	var trunk_h := top_h * (1.6 if tiered else 1.0)
	# The trunk
	var pts: Array[Vector3] = []
	var radii: Array[float] = []
	for j in 7:
		var t := j / 6.0
		pts.append(Vector3(_bend(t, lean), t * trunk_h, 0))
		radii.append(lerp(0.85, 0.42 if kind != Kind.DEAD else 0.2, t) * thick * (1.0 + 0.55 * pow(1.0 - t, 6.0)))
	_tube(wood, pts, radii)
	# Branches, curving upward toward their ends
	var tips := []                       # [where, clump radius]
	var spin := rng.randf() * TAU
	var reach := 0.0
	for b in p.n:
		var y0: float = rng.randf_range(p.from.x, p.from.y) * top_h
		var t0 := y0 / trunk_h
		var start := Vector3(_bend(t0, lean), y0, 0)
		var yaw: float = spin + TAU * b / p.n + rng.randf_range(-0.35, 0.35)
		var rise: float = rng.randf_range(p.rise.x, p.rise.y)
		var length: float = H * rng.randf_range(p.len.x, p.len.y)
		var r0: float = lerp(0.85, 0.42, t0) * thick * 0.5
		var end := _branch(wood, start, yaw, rise, length, r0)
		reach = max(reach, Vector2(end.x, end.z).length())
		if kind == Kind.DEAD:
			# Gnarled: each branch forks again, twice, into thinner crooked twigs
			for f in 2:
				var at: Vector3 = start.lerp(end, rng.randf_range(0.55, 0.9))
				_branch(wood, at, yaw + rng.randf_range(-1.1, 1.1), rise + rng.randf_range(-0.3, 0.5), length * rng.randf_range(0.35, 0.55), r0 * 0.35)
		else:
			tips.append([end, H * rng.randf_range(p.clump.x, p.clump.y)])
	if tiered:
		# The upper storey: fewer, shorter branches, a little steeper
		var m := rng.randi_range(3, 4)
		for b in m:
			var y0 := trunk_h * rng.randf_range(0.78, 0.93)
			var t0 := y0 / trunk_h
			var yaw: float = spin + PI / m + TAU * b / m + rng.randf_range(-0.3, 0.3)
			var end := _branch(wood, Vector3(_bend(t0, lean), y0, 0), yaw, rng.randf_range(0.3, 0.6), H * rng.randf_range(0.2, 0.3), lerp(0.85, 0.42, t0) * thick * 0.4)
			tips.append([end, H * rng.randf_range(0.15, 0.19)])
	var top := Vector3(_bend(1.0, lean), trunk_h + H * 0.04, 0)
	var top_r: float = H * p.clump.y * 1.1
	var leaves: ArrayMesh = null
	if kind != Kind.DEAD:
		tips.append([top, top_r])
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var tex: Texture2D = CANOPIES[kind]
		var aspect := float(tex.get_height()) / tex.get_width()
		for tip in tips:
			_clump(st, rng, tip[0], tip[1], p.stretch, aspect)
			reach = max(reach, Vector2(tip[0].x, tip[0].z).length() + tip[1])
		leaves = st.commit()
	return {"wood": wood.commit(), "leaves": leaves, "top": top, "top_r": top_r, "spread": max(reach * 2.0, 3.0)}

# A branch from `start`, heading `yaw` round and `rise` up, `length` long,
# curving upward toward its end; returns where it ends
static func _branch(st: SurfaceTool, start: Vector3, yaw: float, rise: float, length: float, r0: float) -> Vector3:
	var dir := Vector3(cos(rise) * cos(yaw), sin(rise), cos(rise) * sin(yaw))
	var mid := start + dir * length * 0.5 + Vector3(0, length * 0.08, 0)
	var end := start + dir * length + Vector3(0, length * 0.2, 0)
	_tube(st, [start - dir * 0.25, mid, end], [r0, r0 * 0.6, r0 * 0.25])
	return end

# A round tube through `pts`, `radii` thick at each, with tiling bark UVs
static func _tube(st: SurfaceTool, pts: Array, radii: Array) -> void:
	var rings := []
	var along := 0.0
	for i in pts.size():
		var p: Vector3 = pts[i]
		var d: Vector3 = (pts[min(i + 1, pts.size() - 1)] - pts[max(i - 1, 0)]).normalized()
		var side := d.cross(Vector3.UP)
		side = Vector3.RIGHT if side.length() < 0.01 else side.normalized()
		var up := side.cross(d)
		if i > 0:
			along += p.distance_to(pts[i - 1])
		var ring := []
		for k in SIDES + 1:
			var a := TAU * k / SIDES
			var out := side * cos(a) + up * sin(a)
			ring.append([p + out * radii[i], out, Vector2(float(k) / SIDES, -along / 5.0)])
		rings.append(ring)
	for i in rings.size() - 1:
		for k in SIDES:
			var q := [rings[i][k], rings[i + 1][k], rings[i + 1][k + 1], rings[i][k], rings[i + 1][k + 1], rings[i][k + 1]]
			for v in q:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])

# A clump of leaves round `c`, `r` in radius and `stretch` times as tall (a
# column above 1): the leaf sprite on upright cards in a ring, facing out
# like the sides of a hexagonal box (neighbours overlap, so the outline
# stays leafy), stacked two high for a tall clump with each ring turned half
# a step, plus a leafy lid on top and a shaded underside. Every card is
# upright and the right way up, so the pixel art reads cleanly.
const SIDES_PER_RING := 6

static func _clump(st: SurfaceTool, rng: RandomNumberGenerator, c: Vector3, r: float, stretch: float, aspect: float) -> void:
	var levels := maxi(1, roundi(stretch * 1.4))
	var w := 2.0 * r * tan(PI / SIDES_PER_RING) * 1.45
	var h := w * aspect
	var step := h * 0.75
	var total := h + step * (levels - 1)
	var twist := rng.randf() * TAU
	for level in levels:
		var y := c.y - total * 0.5 + h * 0.5 + level * step
		# Rings toward the ends of a stack sit a little tighter, rounding it off
		var mid := (levels - 1) * 0.5
		var ring_r: float = r * 0.75 * (1.0 - 0.18 * abs(level - mid) / max(mid, 1.0))
		for k in SIDES_PER_RING:
			var a := twist + TAU * k / SIDES_PER_RING + (level % 2) * PI / SIDES_PER_RING
			var out := Vector3(cos(a), 0, sin(a))
			_card(st, Vector3(c.x, y, c.z) + out * ring_r, out, w, aspect, 0.0, rng.randf_range(0.88, 1.0))
	# The lid: two flat cards across each other, and a darker underside
	var lid := Vector3(c.x, c.y + total * 0.5 - h * 0.2, c.z)
	_card(st, lid, Vector3.UP, r * 2.0, aspect, twist, 1.0)
	_card(st, lid + Vector3(0, 0.05, 0), Vector3.UP, r * 2.0, aspect, twist + PI * 0.5, 1.0)
	_card(st, Vector3(c.x, c.y - total * 0.5 + h * 0.25, c.z), Vector3.DOWN, r * 1.7, aspect, twist, 0.7)

# One leaf card at `at`, facing `n`, `w` wide; `roll` turns it about its
# facing (0 = upright, the art the right way up)
static func _card(st: SurfaceTool, at: Vector3, n: Vector3, w: float, aspect: float, roll: float, shade: float) -> void:
	var u := n.cross(Vector3.UP)
	u = n.cross(Vector3.RIGHT) if u.length() < 0.01 else u
	u = u.normalized().rotated(n, roll)
	var v := u.cross(n).normalized()     # "up" on the card
	var hu := u * w * 0.5
	var hv := v * w * aspect * 0.5
	var corners := [[at - hu - hv, Vector2(0, 1)], [at + hu - hv, Vector2(1, 1)], [at + hu + hv, Vector2(1, 0)], [at - hu + hv, Vector2(0, 0)]]
	st.set_normal(n)
	st.set_color(Color(shade, shade, shade))
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(corners[i][1])
		st.add_vertex(corners[i][0])

# The far horizon's forest: rings of leaf cards facing the tower, filling in
# behind the last real trees so the wood reads as unbroken to the horizon
# (single trees out there are only a few pixels tall, with sky between).
# Made to blend: tree-sized cards, many of them, in seven staggered rings that
# start well in among the real trees, each at its own height (so the skyline is
# ragged, not a band), shaded like the real leaves. One mesh per leaf
# picture; the scene's fog softens it like the rest.
static func _treeline(ground: Node3D, leaf_mats: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	var sts := {}
	for kind in CANOPIES:
		sts[kind] = SurfaceTool.new()
		sts[kind].begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in [[125.0, 80], [150.0, 115], [190.0, 145], [235.0, 175], [280.0, 210], [330.0, 250], [380.0, 290]]:
		for i in ring[1]:
			var a: float = TAU * (i + rng.randf_range(-0.45, 0.45)) / ring[1]
			var r: float = ring[0] + rng.randf_range(-18.0, 18.0)
			var kind: int = Kind.BROAD if rng.randf() < 0.6 else Kind.ASPEN
			var tex: Texture2D = CANOPIES[kind]
			var aspect := float(tex.get_height()) / tex.get_width()
			var w: float = rng.randf_range(16.0, 26.0) * (1.25 if kind == Kind.BROAD else 0.9) * clamp(r / 300.0, 0.6, 1.3)     # (nearer ones tree-sized)
			var out := Vector3(sin(a), 0, cos(a))
			var lift := rng.randf_range(3.0, 16.0)          # ragged skyline: some low, some tall
			var at := out * r + Vector3(0, lift + w * aspect * 0.5 - 4.0, 0)
			_card(sts[kind], at, -out, w, aspect, rng.randf_range(-0.12, 0.12), rng.randf_range(0.85, 1.0))
	for kind in sts:
		var mi := MeshInstance3D.new()
		mi.mesh = sts[kind].commit()
		mi.material_override = leaf_mats[kind]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ground.add_child(mi)

# A calmer copy of some leaf art: every leaf pixel drawn `amount` of the way
# toward the art's average colour, so it reads as less speckled (the aspens)
static func _calm(tex: Texture2D, amount: float) -> Texture2D:
	var img := tex.get_image()
	img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var sum := Color(0, 0, 0, 0)
	var count := 0
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a > 0.5:
				sum += p
				count += 1
	var avg: Color = sum / max(count, 1)
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a > 0.5:
				var c := p.lerp(avg, amount)
				c.a = p.a
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# Owls (cut from the 8 Bit Evil Returns owl tree) perched in a few of the
# crowns nearest the meadow, spread round it, on the side facing in
static func _perch_owls(ground: Node3D, crowns: Array) -> void:
	var owl := owl_texture()
	for i in OWLS:
		var want := TAU * (i + 0.5) / OWLS
		var best: Array = []
		var best_score := INF
		for c in crowns:
			var p: Vector3 = c[0]
			var off: float = abs(wrapf(atan2(p.x, p.z) - want, -PI, PI))
			var score: float = Vector2(p.x, p.z).length() + off * 60.0
			if score < best_score:
				best_score = score
				best = c
		var top: Vector3 = best[0]
		var r: float = best[1]
		var inward := -Vector3(top.x, 0, top.z).normalized()
		var at: Vector3 = top + inward * (r + 0.3) - Vector3(0, r * 0.25, 0)
		ground.add_child(TowerChunk._prop(at, 1.8, owl, 5, 0.0))

static var _owl: Texture2D

# The owl from the owl tree's five frames (it blinks), with the bit of branch
# it sits on
static func owl_texture() -> Texture2D:
	if _owl == null:
		var src := TowerChunk.OWL_TREE.get_image()
		src.decompress()
		src.convert(Image.FORMAT_RGBA8)
		var box := Rect2i(47, 42, 9, 11)
		var img := Image.create(box.size.x * 5, box.size.y, false, Image.FORMAT_RGBA8)
		for f in 5:
			img.blit_rect(src, Rect2i(box.position + Vector2i(f * 128, 0), box.size), Vector2i(f * box.size.x, 0))
		_owl = ImageTexture.create_from_image(img)
	return _owl

static func _multimesh(ground: Node3D, mesh: Mesh, mat: Material, xfs: Array) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# On the instance, not the mesh: meshes can be shared between materials
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.add_child(mmi)

# How far the trunk has leaned over at height fraction t (0 foot, 1 top)
static func _bend(t: float, amount: float) -> float:
	return sin(t * PI * 0.5) * 1.6 * amount

# Chunky pixel bark, tiling: brown with big blotches (broad trees), pale
# with dark dashes (aspens), or weathered grey with cracks (dead trees)
static func _bark(kind: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + kind
	var w := 16
	var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
	match kind:
		Kind.ASPEN:
			img.fill(Color(0.84, 0.83, 0.78))
			for i in 12:
				var y := rng.randi_range(0, w - 1)
				var x := rng.randi_range(0, w - 1)
				var col := Color(0.3, 0.29, 0.3) if rng.randf() < 0.6 else Color(0.62, 0.6, 0.58)
				for d in rng.randi_range(2, 5):
					img.set_pixel(posmod(x + d, w), y, col)
			for y in w:
				img.set_pixel(0, y, img.get_pixel(0, y).darkened(0.12))     # a faint grain
		Kind.DEAD:
			img.fill(Color(0.36, 0.34, 0.34))
			# Long dark cracks running up it, and a few pale weathered patches
			for i in 5:
				var x := rng.randi_range(0, w - 1)
				var y := rng.randi_range(0, w - 1)
				for d in rng.randi_range(4, 9):
					img.set_pixel(posmod(x + (1 if rng.randf() < 0.25 else 0) * d / 4, w), posmod(y + d, w), Color(0.18, 0.16, 0.17))
			for i in 6:
				img.set_pixel(rng.randi_range(0, w - 1), rng.randi_range(0, w - 1), Color(0.5, 0.48, 0.46))
		_:
			img.fill(Color(0.42, 0.26, 0.15))
			var tones := [Color(0.3, 0.18, 0.1), Color(0.58, 0.37, 0.2), Color(0.5, 0.31, 0.17)]
			for i in 11:
				var c := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, w - 1))
				var r := rng.randf_range(1.2, 2.4)
				var col: Color = tones[i % tones.size()]
				for dy in range(-3, 4):
					for dx in range(-3, 4):
						if Vector2(dx, dy).length() <= r:
							img.set_pixel(posmod(c.x + dx, w), posmod(c.y + dy, w), col)
	return ImageTexture.create_from_image(img)
