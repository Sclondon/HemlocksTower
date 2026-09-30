class_name ChunkPlanner
# Deterministic layout for one 12 m chunk of tower: surfaces to land on,
# stained-glass windows and stamina pickups. Pure data (no nodes), seeded by
# (run seed, chunk index), so a chunk rebuilds the same after a long fall.
#
# Each chunk starts with an "anchor" surface at its base. A guaranteed path of
# jumps leads from this chunk's anchor to the next chunk's anchor, then extras
# (optional ledges, traps, movers) are scattered around it.

enum Kind { GROUND, LEDGE, BALCONY, PERCH, RING, CRUMBLE, MOVER, TURRET, ISLAND, FRAGILE, ORBIT, RETRACT, PROP, CATWALK }

const ANCHOR_LIFT := 0.3
const MIN_DY := 1.6
const REACH_MARGIN := 0.75           # path gaps use at most 75% of the real reach
const TURRET_RADIUS := 1.4
const CLEARANCE := 2.6               # min height between overlapping surfaces
const FAR_OUT := Vector2(6.0, 11.0)  # how far out (from the wall) far treasures float

# The first chunks are the same every run: a spiral of ledges round the tower
const START_CHUNKS := 2
const START_SEED := 20241031
const SPIRAL_RATE := 0.36            # radians of turn per metre climbed
const SPIRAL_STEP := 2.0             # metres between spiral ledges

static func _rng(run_seed: int, k: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([START_SEED if k < START_CHUNKS else run_seed, k, salt])
	return rng

static func is_band_start(k: int) -> bool:
	return k > 0 and k % TowerShape.CHUNKS_PER_BAND == 0

static func max_dy(band: int) -> float:
	return lerp(0.45, 0.72, TowerShape.difficulty(band)) * Tuning.max_jump_height(Tuning.PATH_FLAPS)

static func gap_cap(band: int) -> float:
	return lerp(2.0, 5.0, TowerShape.difficulty(band))

static func snap_to_corner(k: int, a: float) -> float:
	var step := TowerShape.face_step(k)
	var first := TowerShape.face_offset(k) + step * 0.5
	return first + roundf((a - first) / step) * step

# Centre of the nearest face (balconies sit square on a face, with a door)
static func snap_to_face(k: int, a: float) -> float:
	var step := TowerShape.face_step(k)
	var first := TowerShape.face_offset(k)
	return first + roundf((a - first) / step) * step

static func spiral_angle(y: float) -> float:
	return y * SPIRAL_RATE

# The worst wind a band's weather can bring (either side of its start).
# Path jumps are shortened by it, since it might be blowing against you.
static func headwind(band: int) -> float:
	return max(Weather.band_max_wind(band), Weather.band_max_wind(max(band - 1, 0))) * 1.2

static func is_outer(s: Dictionary) -> bool:
	return s.kind == Kind.TURRET or s.kind == Kind.ISLAND or s.kind == Kind.PROP

# How far a surface's structure hangs below its top (to keep things apart)
static func hangs_below(s: Dictionary) -> float:
	match s.kind:
		Kind.TURRET:
			return 4.2
		Kind.ISLAND:
			return 2.8
		Kind.PROP:
			return 1.8 + s.get("lift", 0.0)
	return 1.2

# How far a surface's structure rises above its top (roofed turrets)
static func rises_above(s: Dictionary) -> float:
	return (3.2 if s.get("roof", false) else 0.0) + s.get("lift", 0.0)

# --- anchors ------------------------------------------------------------------

static func anchor_angle(run_seed: int, k: int) -> float:
	if k <= START_CHUNKS:
		return spiral_angle(k * TowerShape.CHUNK_H + ANCHOR_LIFT)
	var band := TowerShape.band_of_chunk(k)
	var start := k - k % TowerShape.CHUNKS_PER_BAND
	var a := _rng(run_seed, start, 7).randf() * TAU
	if start < START_CHUNKS:
		start = START_CHUNKS
		a = spiral_angle(start * TowerShape.CHUNK_H + ANCHOR_LIFT)
	for j in range(start + 1, k + 1):
		a += _rng(run_seed, j, 7).randf_range(-1.1, 1.1)
		if j % 2 == 1:
			a = snap_to_face(k, a)
	return a

static func anchor(run_seed: int, k: int) -> Dictionary:
	var band := TowerShape.band_of_chunk(k)
	var base := k * TowerShape.CHUNK_H
	if k == 0:
		return {"kind": Kind.GROUND, "top": 0.0, "band": 0, "k": 0, "a0": 0.0, "a1": TAU, "d0": 0.0, "d1": 99.0, "polys": []}
	if is_band_start(k):
		return ring_surface(k, base)
	var a := anchor_angle(run_seed, k)
	if k % 2 == 1:
		return balcony_surface(k, base + ANCHOR_LIFT, a)
	return wall_surface(k, Kind.LEDGE, base + ANCHOR_LIFT, a, ledge_width(band, 0.5), ledge_depth(band))

# --- surface builders ---------------------------------------------------------

static func ledge_width(band: int, roll: float) -> float:
	var d := TowerShape.difficulty(band)
	return lerp(lerp(2.8, 1.8, d), lerp(3.4, 2.4, d), roll)

static func ledge_depth(band: int) -> float:
	return lerp(2.2, 1.6, TowerShape.difficulty(band))

static func wall_surface(k: int, kind: int, top: float, center: float, width: float, depth: float, d0 := 0.0) -> Dictionary:
	var half := TowerShape.angle_for_len(k, width * 0.5, (d0 + depth) * 0.5)
	return _strip(k, kind, top, center - half, center + half, d0, depth)

static func _strip(k: int, kind: int, top: float, a0: float, a1: float, d0: float, d1: float) -> Dictionary:
	return {
		"kind": kind, "top": top, "band": TowerShape.band_of_chunk(k), "k": k, "a0": a0, "a1": a1, "d0": d0, "d1": d1,
		"polys": [TowerShape.strip_polygon(k, a0, a1, d0, d1)],
	}

# A balcony sits square on a face (with a doorway behind it, see the
# windows), a little narrower than the face
static func balcony_surface(k: int, top: float, near: float) -> Dictionary:
	var width: float = clamp(TowerShape.face_width(k) * 0.92, 2.6, 3.8)
	return wall_surface(k, Kind.BALCONY, top, snap_to_face(k, near), width, 2.5)

static func ring_surface(k: int, top: float) -> Dictionary:
	var s := {
		"kind": Kind.RING, "top": top, "band": TowerShape.band_of_chunk(k), "k": k, "a0": 0.0, "a1": TAU, "d0": -0.1, "d1": 2.0,
		"polys": [
			TowerShape.strip_polygon(k, 0.0, PI, -0.1, 2.0),
			TowerShape.strip_polygon(k, PI, TAU, -0.1, 2.0),
		],
	}
	return s

static func mover_surface(k: int, top: float, center: float, rng: RandomNumberGenerator) -> Dictionary:
	# Floats on a true circle just clear of the tower's corners
	var r0 := TowerShape.apothem(k) / cos(PI / TowerShape.sides(k)) + 0.35
	var half := 0.9 / (r0 + 0.8)
	var s := {
		"kind": Kind.MOVER, "top": top, "band": TowerShape.band_of_chunk(k), "k": k, "a0": center - half, "a1": center + half,
		"d0": r0 - TowerShape.apothem(k), "d1": r0 + 1.6 - TowerShape.apothem(k),
		"polys": [TowerShape.arc_polygon(center - half, center + half, r0, r0 + 1.6)],
		"swing": rng.randf_range(0.5, 0.9), "speed": rng.randf_range(0.7, 1.3), "phase": rng.randf() * TAU,
	}
	return s

# A platform well out from the wall: a turret room hung off a beam, or a
# floating island. `dist` is how far its centre sits out from the wall.
static func outer_surface(k: int, kind: int, top: float, center: float, dist: float, rng: RandomNumberGenerator) -> Dictionary:
	var c := TowerShape.ring_point(k, center, dist)
	var radius := TURRET_RADIUS if kind == Kind.TURRET else (1.45 if kind == Kind.PROP else rng.randf_range(1.3, 1.7))
	var sides := 8 if kind == Kind.TURRET else (4 if kind == Kind.PROP else 7)
	# (a propeller deck is a square, turned to face the tower)
	var spin := PI / 8.0 if kind == Kind.TURRET else (PI / 4.0 - atan2(c.x, c.y) if kind == Kind.PROP else rng.randf() * TAU)
	var poly := PackedVector2Array()
	for i in sides:
		var a := spin + TAU * i / sides
		var rr := radius if kind != Kind.ISLAND else radius * rng.randf_range(0.82, 1.1)
		poly.append(c + Vector2(cos(a), sin(a)) * rr)
	var half := radius / c.length()
	var s := {
		"kind": kind, "top": top, "band": TowerShape.band_of_chunk(k), "k": k, "a0": center - half, "a1": center + half,
		"d0": dist - radius, "d1": dist + radius, "polys": [poly],
		"cx": c.x, "cz": c.y, "radius": radius,
	}
	if kind == Kind.ISLAND or kind == Kind.PROP:
		s.base_top = top
		s.bob_phase = rng.randf() * TAU
	if kind == Kind.PROP:
		# Some propeller decks swing round the tower, some rise and sink
		var move := rng.randf()
		if move < 0.2:
			s.swing = rng.randf_range(0.4, 0.9)
		elif move < 0.4:
			s.lift = rng.randf_range(1.5, 3.0)
		s.speed = rng.randf_range(0.3, 0.6)
		s.phase = rng.randf() * TAU
	if kind == Kind.TURRET:
		s.roof = rng.randf() < 0.45       # some have a pitched roof on posts
	return s

# A platform that rides a rail all the way round the tower, out past the
# ledges so it never runs through them
static func orbit_surface(k: int, top: float, center: float, rng: RandomNumberGenerator) -> Dictionary:
	var r0 := TowerShape.apothem(k) / cos(PI / TowerShape.sides(k)) + 2.4
	var half := 1.0 / (r0 + 0.8)
	var speed := rng.randf_range(0.18, 0.4) * (1.0 if rng.randf() < 0.5 else -1.0)
	return {
		"kind": Kind.ORBIT, "top": top, "band": TowerShape.band_of_chunk(k), "k": k,
		"a0": center - half, "a1": center + half, "swing": PI,
		"d0": r0 - TowerShape.apothem(k), "d1": r0 + 1.6 - TowerShape.apothem(k),
		"polys": [TowerShape.arc_polygon(center - half, center + half, r0, r0 + 1.6)],
		"rail_r": r0 + 0.8, "speed": speed, "phase": rng.randf() * TAU,
	}

# A long catwalk straight out from the wall to a lookout pad at the end
static func catwalk_surface(k: int, top: float, center: float, length: float) -> Dictionary:
	var base := TowerShape.ring_point(k, center, -0.05)
	var out := Vector2(sin(center), cos(center))
	var side := Vector2(cos(center), -sin(center))
	var tip := base + out * length
	var walk := PackedVector2Array([base - side * 0.55, base + side * 0.55, tip + side * 0.55, tip - side * 0.55])
	var end := tip + out * 1.1
	var pad := PackedVector2Array([end - side * 1.2 - out * 1.2, end + side * 1.2 - out * 1.2, end + side * 1.2 + out * 1.2, end - side * 1.2 + out * 1.2])
	var half: float = max(0.15, 1.3 / end.length())
	return {
		"kind": Kind.CATWALK, "top": top, "band": TowerShape.band_of_chunk(k), "k": k,
		"a0": center - half, "a1": center + half, "d0": 0.0, "d1": length + 2.3,
		"polys": [walk, pad], "end_x": end.x, "end_z": end.y, "length": length,
	}

# A ledge that slides back into the wall every few seconds
static func retract_surface(k: int, top: float, center: float, width: float, depth: float, rng: RandomNumberGenerator) -> Dictionary:
	var s := wall_surface(k, Kind.RETRACT, top, center, width, depth)
	s.period = rng.randf_range(4.0, 6.5)
	s.phase = rng.randf() * s.period
	return s

# --- reachability -------------------------------------------------------------

static func angular_overlap(a: Dictionary, b: Dictionary, pad := 0.0) -> bool:
	var a0: float = a.a0 - pad - a.get("swing", 0.0)
	var a1: float = a.a1 + pad + a.get("swing", 0.0)
	var b0: float = b.a0 - b.get("swing", 0.0)
	var b1: float = b.a1 + b.get("swing", 0.0)
	return fposmod(b0 - a0, TAU) <= a1 - a0 or fposmod(a0 - b0, TAU) <= b1 - b0

# Would these two surfaces' structures (slab, beam, hanging room) collide?
static func conflicts(a: Dictionary, b: Dictionary) -> bool:
	if not angular_overlap(a, b, 0.15):
		return false
	# Turret beams run from the wall, so they claim the whole radial range
	var a_in: float = 0.0 if a.kind == Kind.TURRET else a.d0
	var b_in: float = 0.0 if b.kind == Kind.TURRET else b.d0
	if a_in > b.d1 + 0.3 or b_in > a.d1 + 0.3:
		return false
	return a.top - hangs_below(a) < b.top + max(CLEARANCE, rises_above(b) + 0.6) \
		and b.top - hangs_below(b) < a.top + max(CLEARANCE, rises_above(a) + 0.6)

# Closest-point distance between two polygons, split into around / in-out
static func _polygon_hop(pa: PackedVector2Array, pb: PackedVector2Array) -> float:
	for p in pa:
		if Geometry2D.is_point_in_polygon(p, pb):
			return 0.0
	for p in pb:
		if Geometry2D.is_point_in_polygon(p, pa):
			return 0.0
	var best := INF
	var best_pair := [Vector2.ZERO, Vector2.ZERO]
	for pass_i in 2:
		var src := pa if pass_i == 0 else pb
		var dst := pb if pass_i == 0 else pa
		for p in src:
			for i in dst.size():
				var q := Geometry2D.get_closest_point_to_segment(p, dst[i], dst[(i + 1) % dst.size()])
				var d := p.distance_to(q)
				if d < best:
					best = d
					best_pair = [p, q]
	var p: Vector2 = best_pair[0]
	var q: Vector2 = best_pair[1]
	var tangential: float = abs(wrapf(atan2(q.x, q.y) - atan2(p.x, p.y), -PI, PI)) * (p.length() + q.length()) * 0.5
	return Tuning.hop_length(tangential, abs(q.length() - p.length()))

# How far you have to travel between two surfaces' nearest edges
static func gap_between(a: Dictionary, b: Dictionary) -> float:
	if a.kind == Kind.GROUND or b.kind == Kind.GROUND:
		return 0.0
	if a.kind == Kind.RING or b.kind == Kind.RING:
		var other := b if a.kind == Kind.RING else a
		return Tuning.hop_length(0.0, max(0.0, other.d0 - 2.0)) if is_outer(other) else 0.0
	if is_outer(a) or is_outer(b):
		return _polygon_hop(a.polys[0], b.polys[0])
	if angular_overlap(a, b):
		return 0.0
	var shape: int = a.k
	var fwd := fposmod(b.a0 - a.a1, TAU)
	var back := fposmod(a.a0 - b.a1, TAU)
	return min(TowerShape.perimeter_len(shape, a.a1, a.a1 + fwd), TowerShape.perimeter_len(shape, b.a1, b.a1 + back))

static func reach_for(dy: float, band: int) -> float:
	var dist := Tuning.air_distance(dy, Tuning.PATH_FLAPS)
	if dist < 0.0:
		return -1.0
	var wind_factor: float = max(0.35, 1.0 - headwind(band) / Tuning.RUN_SPEED)
	return min(dist * REACH_MARGIN * wind_factor, gap_cap(band))

static func reachable(a: Dictionary, b: Dictionary) -> bool:
	if b.top - a.top > max_dy(a.band) + 0.01:
		return false
	var reach := reach_for(b.top - a.top, a.band)
	return reach >= 0.0 and gap_between(a, b) <= reach

# --- the plan -----------------------------------------------------------------

static func plan(run_seed: int, k: int) -> Dictionary:
	var band := TowerShape.band_of_chunk(k)
	var d := TowerShape.difficulty(band)
	var base := k * TowerShape.CHUNK_H
	var rng := _rng(run_seed, k, 1)
	var surfaces: Array[Dictionary] = []

	var start := anchor(run_seed, k)
	start.path = true
	if start.kind == Kind.RING:
		start._c = rng.randf() * TAU
	surfaces.append(start)
	var target := anchor(run_seed, k + 1)
	# Keep headroom under a full ring so nothing is squashed beneath it
	var top_limit := base + TowerShape.CHUNK_H - (2.2 if is_band_start(k + 1) else 0.6)

	var cur := start
	if k < START_CHUNKS:
		# The fixed opening: a gentle spiral of ledges climbing round the tower
		var sy: float = start.top + SPIRAL_STEP
		while sy < target.top - SPIRAL_STEP * 0.5:
			var s := wall_surface(k, Kind.LEDGE, sy, spiral_angle(sy), 2.8, 2.2)
			s.path = true
			surfaces.append(s)
			cur = s
			sy += SPIRAL_STEP
	for step in 20:
		if k < START_CHUNKS:
			break
		if reachable(cur, target):
			break
		var remaining: float = target.top - cur.top
		var dy := rng.randf_range(MIN_DY, max_dy(band))
		dy = min(dy, remaining - MIN_DY, top_limit - cur.top)
		dy = max(dy, 0.0)
		var reach := reach_for(dy, band)

		# Mostly ledges; sometimes a turret or island that pulls you away
		# from the wall, or an old ledge that gives way once you leave it
		var kind := Kind.LEDGE
		var width := ledge_width(band, rng.randf())
		var depth := ledge_depth(band)
		var roll := rng.randf()
		if roll < 0.14 and k > 0:
			kind = Kind.TURRET
		elif roll < 0.26 and band > 0:
			kind = Kind.ISLAND
		elif roll < 0.33 and k > 1:
			kind = Kind.PROP
		elif roll < 0.33 + lerp(0.05, 0.15, d) and band > 0:
			kind = Kind.FRAGILE
		elif roll < 0.33 + lerp(0.05, 0.15, d) + lerp(0.02, 0.2, d) and band > 0:
			kind = Kind.RETRACT
		elif roll < 0.6 and band > 0 and rng.randf() < d:
			kind = Kind.PERCH
			width = 0.9
			depth = 2.3
		if kind == Kind.TURRET or kind == Kind.ISLAND or kind == Kind.PROP:
			width = TURRET_RADIUS * 2.0

		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		var gap := rng.randf_range(-width * 0.4, reach)
		if target.kind != Kind.RING:
			var diff := wrapf((target.a0 + target.a1) * 0.5 - (cur.a0 + cur.a1) * 0.5, -PI, PI)
			dir = 1.0 if diff >= 0.0 else -1.0
			var hops: float = max(1.0, ceil((remaining - dy) / max_dy(band)))
			if gap_between(cur, target) > reach * hops * 0.5:
				gap = reach

		var dist := rng.randf_range(3.6, 5.6)
		var next := _place_beside(cur, kind, k, cur.top + dy, dir, gap, width, depth, dist, rng)
		# Placement is approximate: pull it in (around and in/out) if too far
		for i in 5:
			var over := gap_between(cur, next) - reach
			if over <= 0.0:
				break
			gap -= over + 0.1
			dist = max(3.4, dist - over)
			next = _place_beside(cur, kind, k, cur.top + dy, dir, gap, width, depth, dist, rng)
		# Turrets and islands hang a long way down: if one would run into
		# something (or still can't be reached), make it a plain ledge instead
		if is_outer(next):
			var fits := gap_between(cur, next) <= reach
			# ...and only if you could get back to a wall ledge from it afterwards
			var back := Tuning.hop_length(0.0, max(0.0, next.d0 - ledge_depth(band)))
			if back > reach_for(max_dy(band), band):
				fits = false
			for other in surfaces:
				if fits and conflicts(other, next):
					fits = false
			if not fits:
				kind = Kind.LEDGE
				width = ledge_width(band, 0.5)
				gap = min(gap, reach * 0.5)
				next = _place_beside(cur, kind, k, cur.top + dy, dir, gap, width, depth, dist, rng)
				for i in 4:
					var over := gap_between(cur, next) - reach
					if over <= 0.0:
						break
					gap -= over + 0.1
					next = _place_beside(cur, kind, k, cur.top + dy, dir, gap, width, depth, dist, rng)
		# Don't stack a step right on top of something: sidestep instead, as
		# long as that's still in reach
		if _crowded(next, surfaces):
			for i in 3:
				var side_gap: float = max(gap, 0.0) + 1.0 + 0.6 * i
				var cand := _place_beside(cur, kind, k, cur.top + dy, dir, side_gap, width, depth, dist, rng)
				if gap_between(cur, cand) <= reach and not _crowded(cand, surfaces):
					next = cand
					break
		next.path = true
		surfaces.append(next)
		cur = next

	# Extras: rest spots, detours, traps and movers
	var extra_count := rng.randi_range(2, 4)
	var extras: Array[Dictionary] = []
	for attempt in 14:
		if extras.size() >= extra_count:
			break
		var top := rng.randf_range(base + 1.0, top_limit - 0.4)
		var center := rng.randf() * TAU
		var roll := rng.randf()
		var s: Dictionary
		# (balconies only come as the regular anchors, so they stay orderly)
		if roll < 0.22:
			s = wall_surface(k, Kind.LEDGE, top, center, ledge_width(band, rng.randf()), ledge_depth(band))
		elif roll < 0.3:
			s = wall_surface(k, Kind.PERCH, top, center, 0.9, 2.3)
		elif roll < 0.43:
			s = outer_surface(k, Kind.TURRET, top, center, rng.randf_range(3.8, 8.5), rng)
		elif roll < 0.52 and band > 0:
			s = outer_surface(k, Kind.ISLAND, top, center, rng.randf_range(4.0, 9.5), rng)
		elif roll < 0.62:
			s = outer_surface(k, Kind.PROP, top, center, rng.randf_range(6.0, 10.5), rng)
		elif roll < 0.69:
			s = wall_surface(k, Kind.CRUMBLE, top, center, 2.2, 1.8)
		elif roll < 0.75:
			s = wall_surface(k, Kind.FRAGILE, top, center, 2.4, 1.9)
		elif roll < 0.75 + lerp(0.04, 0.16, d):
			s = retract_surface(k, top, center, ledge_width(band, rng.randf()), ledge_depth(band), rng)
		elif roll < 0.93 and band > 0:
			s = orbit_surface(k, top, center, rng)
		elif band >= 2:
			s = mover_surface(k, top, center, rng)
		else:
			s = wall_surface(k, Kind.LEDGE, top, center, ledge_width(band, rng.randf()), ledge_depth(band))
		var clear: bool = s.top - hangs_below(s) > 0.5
		for other in surfaces:
			if conflicts(other, s):
				clear = false
				break
		if clear:
			s.path = false
			surfaces.append(s)
			extras.append(s)

	# Now and then a long catwalk reaching far out, with something at the end
	var catwalk: Dictionary = {}
	if k >= START_CHUNKS and rng.randf() < 0.3:
		for attempt in 4:
			var cw := catwalk_surface(k, rng.randf_range(base + 1.5, top_limit - 0.5), rng.randf() * TAU, rng.randf_range(7.0, 9.5))
			var clear := true
			for other in surfaces:
				if conflicts(other, cw):
					clear = false
					break
			if clear:
				cw.path = false
				surfaces.append(cw)
				catwalk = cw
				break

	# Pickups. Gold feathers (bigger bucket, gone once taken) float above
	# detours; seeds (a top-up, they grow back) sit over some route ledges;
	# poison hovers just off the route, where a careless flight drifts into it.
	var pickups: Array[Dictionary] = []
	for s in extras:
		if s.kind in [Kind.MOVER, Kind.CRUMBLE, Kind.FRAGILE, Kind.ORBIT, Kind.RETRACT] or s.has("swing") or s.has("lift") or rng.randf() > 0.55:
			continue
		pickups.append(_pickup_over(k, "feather", pickups.size(), s, 1.3))
	var path: Array[Dictionary] = []
	for s in surfaces:
		if s.path:
			path.append(s)
	for i in range(1, path.size()):
		if rng.randf() < 0.3:
			pickups.append(_pickup_over(k, "plume", pickups.size(), path[i], 1.1))
	if band > 0:
		for i in path.size() - 1:
			var a: Dictionary = path[i]
			var b: Dictionary = path[i + 1]
			if is_outer(a) or is_outer(b) or a.kind == Kind.RING or rng.randf() > lerp(0.12, 0.3, d):
				continue
			var mid: float = (a.a0 + a.a1 + b.a0 + b.a1) * 0.25
			pickups.append({"id": "%d:p%d" % [k, pickups.size()], "type": "poison", "theta": mid,
				"r": TowerShape.wall_r(k, mid, 3.4), "y": (a.top + b.top) * 0.5 + 1.2})

	# Far out from the wall: a trail of seeds leading outward from a route
	# ledge, or a gold feather hanging in open air. Worth the trip out.
	if k >= START_CHUNKS:
		for n in rng.randi_range(1, 2):
			var s: Dictionary = path[rng.randi_range(0, path.size() - 1)]
			if s.kind == Kind.RING or s.kind == Kind.GROUND or is_outer(s):
				continue
			var a: float = (s.a0 + s.a1) * 0.5 + rng.randf_range(-0.25, 0.25)
			if rng.randf() < 0.35:
				pickups.append({"id": "%d:p%d" % [k, pickups.size()], "type": "feather", "theta": a,
					"r": TowerShape.wall_r(k, a, rng.randf_range(FAR_OUT.x, FAR_OUT.y)), "y": s.top + rng.randf_range(1.5, 3.0)})
			else:
				for j in 3:
					var t := j / 2.0
					pickups.append({"id": "%d:p%d" % [k, pickups.size()], "type": "plume", "theta": a,
						"r": TowerShape.wall_r(k, a, lerp(3.2, FAR_OUT.y, t)), "y": s.top + 1.0 + t * 1.6})

	# Power-ups: at the end of a catwalk, or out in open air now and then
	if not catwalk.is_empty():
		var e := Vector2(catwalk.end_x, catwalk.end_z)
		pickups.append({"id": "%d:p%d" % [k, pickups.size()], "type": _power(rng) if rng.randf() < 0.7 else "feather",
			"theta": atan2(e.x, e.y), "r": e.length(), "y": catwalk.top + 1.2})
	elif k >= START_CHUNKS and rng.randf() < 0.15:
		var a := rng.randf() * TAU
		pickups.append({"id": "%d:p%d" % [k, pickups.size()], "type": _power(rng), "theta": a,
			"r": TowerShape.wall_r(k, a, rng.randf_range(FAR_OUT.x, FAR_OUT.y)), "y": rng.randf_range(base + 2.0, base + TowerShape.CHUNK_H - 2.0)})

	for i in surfaces.size():
		surfaces[i].id = "%d:%d" % [k, i]

	return {
		"k": k, "band": band, "base": base, "surfaces": surfaces,
		"windows": _plan_windows(rng, k, base, surfaces, is_band_start(k), k == 0),
		"pickups": pickups, "ground": k == 0,
		"drafts": _plan_drafts(rng, k, band, base, path),
		"npcs": _plan_npcs(rng, k, surfaces),
		"wires": _plan_wires(rng, k, surfaces),
		"streams": _plan_streams(rng, k, path),
	}

# Columns of rising or sinking air. Updrafts sit beside the route as a
# helping hand (glide into one and it carries you up); downdrafts keep clear
# of every route ledge, so the guaranteed path never needs to cross one.
static func _plan_drafts(rng: RandomNumberGenerator, k: int, band: int, base: float, path: Array[Dictionary]) -> Array[Dictionary]:
	var drafts: Array[Dictionary] = []
	if k < START_CHUNKS:
		return drafts
	var d := TowerShape.difficulty(band)
	if rng.randf() < 0.35 and path.size() > 1:
		var s: Dictionary = path[rng.randi_range(1, path.size() - 1)]
		var a: float = (s.a1 if rng.randf() < 0.5 else s.a0) + rng.randf_range(-0.2, 0.2)
		var r := TowerShape.wall_r(k, a, rng.randf_range(3.0, 4.5))
		drafts.append({"up": true, "theta": a, "r": r, "radius": rng.randf_range(1.4, 2.0),
			"y0": s.top - 3.0, "y1": s.top + rng.randf_range(6.0, 10.0)})
	if band > 0 and rng.randf() < lerp(0.15, 0.35, d):
		for attempt in 8:
			var a := rng.randf() * TAU
			var radius := rng.randf_range(1.3, 1.8)
			var r := TowerShape.wall_r(k, a, rng.randf_range(1.5, 3.5))
			var y0 := rng.randf_range(base, base + TowerShape.CHUNK_H - 4.0)
			var y1 := y0 + rng.randf_range(5.0, 8.0)
			var clear := true
			for s in path:
				var pad := (radius + 1.5) / r
				if s.top > y0 - 2.0 and s.top < y1 + 4.0 and angular_overlap(s, {"a0": a - pad, "a1": a + pad}):
					clear = false
					break
			if clear:
				drafts.append({"up": false, "theta": a, "r": r, "radius": radius, "y0": y0, "y1": y1})
				break
	return drafts

# Tightropes: a wire from a hook on the wall out to a post on a turret,
# island or propeller platform. Land on one and it bounces you; jump at the
# bottom of the bounce for a big launch. Crows like to sit on them.
static func _plan_wires(rng: RandomNumberGenerator, k: int, surfaces: Array[Dictionary]) -> Array[Dictionary]:
	var wires: Array[Dictionary] = []
	if k == 0:
		return _hub_wires(rng)
	if k < START_CHUNKS:
		return wires
	for s in surfaces:
		if not is_outer(s) or s.get("roof", false) or s.has("swing") or s.has("lift") or rng.randf() > 0.55:
			continue
		var a := atan2(s.cx, s.cz) + rng.randf_range(-0.35, 0.35)
		var hook := TowerShape.ring_point(k, a, 0.05)
		var post_y: float = s.get("base_top", s.top) + 1.4
		wires.append({
			"id": "%d:w%d" % [k, wires.size()],
			"a": Vector3(hook.x, post_y + rng.randf_range(0.5, 3.0), hook.y),
			"b": Vector3(s.cx, post_y, s.cz),
			"sag": rng.randf_range(0.3, 0.6),
			"birds": rng.randi_range(2, 5) if rng.randf() < 0.55 else 0,
			"surface": s.id,
		})
	return wires

# The hub's telegraph line: poles in a ring round the meadow, wires slung
# between them, crows lined up along most of it. One span is missing, where a
# pole came down.
const HUB_POLES := 9
const HUB_POLE_R := 23.0
const HUB_POLE_TOP := 5.4

static func _hub_wires(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var wires: Array[Dictionary] = []
	for i in HUB_POLES - 1:
		var a0 := 0.35 + TAU * i / HUB_POLES
		var a1 := 0.35 + TAU * (i + 1) / HUB_POLES
		wires.append({
			"id": "0:w%d" % i,
			"a": Vector3(sin(a0) * HUB_POLE_R, HUB_POLE_TOP, cos(a0) * HUB_POLE_R),
			"b": Vector3(sin(a1) * HUB_POLE_R, HUB_POLE_TOP, cos(a1) * HUB_POLE_R),
			"sag": rng.randf_range(0.6, 0.9),
			"birds": rng.randi_range(3, 7) if rng.randf() < 0.8 else 0,
			"poles": true,
		})
	return wires

# Where the hub's talking crows sit (angle round the tower, distance from its
# axis) and what each of them says
const HUB_CROWS := [
	[Vector2(1.3, 9.5), "Everyone starts down here. Most of them end down here too."],
	[Vector2(2.4, 15.0), "The wires hum at night. Land on them anyway. It's fun."],
	[Vector2(3.3, 11.0), "I used to climb. Now I just watch the ones who do."],
	[Vector2(4.1, 20.0), "Those stones were a tower once. A short one."],
	[Vector2(4.9, 13.0), "Don't go past the hemlocks. Nothing comes back from past the hemlocks."],
	[Vector2(5.6, 18.5), "The mushrooms glow when somebody falls. Look. They're glowing."],
	[Vector2(0.9, 25.0), "Every morning there's one more crow on the wire. Count them."],
	[Vector2(3.9, 6.5), "Out of breath? You can always hop. Hopping is free."],
]

# Chains of boost rings out in open air, curving round and up from a route
# ledge: glide through them for a lift
# Wind streams: a current of strong wind along a curve round the tower,
# starting just off a route ledge. Jump into it and it carries you along
# like a slide. Most climb, some sweep level, a few swoop down. They're
# extras: the route never needs one.
static func _plan_streams(rng: RandomNumberGenerator, k: int, path: Array[Dictionary]) -> Array[Dictionary]:
	var streams: Array[Dictionary] = []
	if k < START_CHUNKS or rng.randf() > 0.5 or path.size() < 2:
		return streams
	var s: Dictionary = path[rng.randi_range(0, path.size() - 2)]
	var dir := 1.0 if rng.randf() < 0.5 else -1.0
	var roll := rng.randf()
	var steps := rng.randi_range(5, 8)
	var climb := rng.randf_range(2.0, 3.2) if roll < 0.65 else (rng.randf_range(-0.3, 0.3) if roll < 0.85 else -rng.randf_range(1.2, 1.8))
	var a: float = (s.a0 + s.a1) * 0.5
	var out := rng.randf_range(2.8, 4.5)
	# (a falling one starts high, so it ends about where it began)
	var y: float = s.top + 1.4 + (-climb * (steps - 1) if climb < 0.0 else 0.0)
	var pts: Array[Vector3] = []
	for i in steps:
		var r := TowerShape.wall_r(TowerShape.chunk_at(y), a, out)
		pts.append(Vector3(sin(a) * r, y, cos(a) * r))
		a += dir * 5.0 / r               # about 5 m round the tower each step
		out = clamp(out + rng.randf_range(-1.2, 1.2), 2.5, 7.0)
		y += climb + rng.randf_range(-0.4, 0.4)
	streams.append({"id": "%d:s0" % k, "pts": pts, "dir": dir})
	return streams

# Crows sitting on ledges, some with something odd to say. The first one is
# always the crow by the door.
static func _plan_npcs(rng: RandomNumberGenerator, k: int, surfaces: Array[Dictionary]) -> Array[Dictionary]:
	var npcs: Array[Dictionary] = []
	if k == 0:
		var a := 0.42
		npcs.append({"id": "0:n0", "kind": "crow_grey", "theta": a, "r": TowerShape.wall_r(0, a, 1.2), "y": 0.0, "line": -1, "talks": true})
		# The hub: crows loafing about the meadow, each with something to say,
		# and a few more pecking about in the grass
		var kinds := ["crow_grey", "crow_blue", "crow_brown"]
		for i in HUB_CROWS.size():
			var spot: Vector2 = HUB_CROWS[i][0]
			npcs.append({"id": "0:h%d" % i, "kind": kinds[i % kinds.size()], "theta": spot.x, "r": spot.y, "y": 0.0,
				"line": 0, "text": HUB_CROWS[i][1], "talks": true})
		var hub_rng := _rng(0, 0, 9)
		for i in 7:
			var ha := hub_rng.randf() * TAU
			npcs.append({"id": "0:g%d" % i, "kind": kinds[hub_rng.randi_range(0, 2)], "theta": ha,
				"r": hub_rng.randf_range(8.0, Tuning.HUB_RADIUS - 3.0), "y": 0.0, "line": 0, "talks": false, "roam": 2.5})
		return npcs
	if rng.randf() > 0.35:
		return npcs
	var spots: Array[Dictionary] = []
	for s in surfaces:
		if s.kind in [Kind.LEDGE, Kind.BALCONY, Kind.TURRET, Kind.ISLAND]:
			spots.append(s)
	if spots.is_empty():
		return npcs
	var s: Dictionary = spots[rng.randi_range(0, spots.size() - 1)]
	var a: float = lerp(s.a0, s.a1, rng.randf_range(0.25, 0.75))
	var r: float = Vector2(s.cx, s.cz).length() if is_outer(s) else TowerShape.wall_r(s.k, a, s.d1 * 0.55)
	var kinds := ["crow_grey", "crow_blue", "crow_brown"]
	npcs.append({"id": "%d:n0" % k, "kind": kinds[rng.randi_range(0, kinds.size() - 1)], "theta": a, "r": r,
		"y": s.get("base_top", s.top), "line": rng.randi(), "surface": s.id if s.has("id") else "",
		"talks": rng.randf() < 0.5})
	return npcs

static func _crowded(s: Dictionary, others: Array[Dictionary]) -> bool:
	for o in others:
		if o.kind != Kind.GROUND and o.kind != Kind.RING and conflicts(o, s):
			return true
	return false

# Which power-up: endless stamina, super jumps, feather-light falls, or a
# charm that pulls treasure to you
static func _power(rng: RandomNumberGenerator) -> String:
	return ["sunseed", "sunseed", "spring", "spring", "cloud", "charm"][rng.randi_range(0, 5)]

static func _pickup_over(k: int, type: String, n: int, s: Dictionary, lift: float) -> Dictionary:
	var a: float = (s.a0 + s.a1) * 0.5
	var r: float = Vector2(s.cx, s.cz).length() if is_outer(s) else TowerShape.wall_r(s.k, a, min(1.0, s.d1 * 0.5))
	return {"id": "%d:p%d" % [k, n], "type": type, "theta": a, "r": r, "y": s.top + lift}

static func _place_beside(cur: Dictionary, kind: int, k: int, top: float, dir: float, gap: float, width: float, depth: float, dist: float, rng: RandomNumberGenerator) -> Dictionary:
	var ang_gap := TowerShape.angle_for_len(k, gap)
	var ang_w := TowerShape.angle_for_len(k, width, depth * 0.5)
	var a0: float
	var a1: float
	if cur.kind == Kind.GROUND or cur.kind == Kind.RING:
		# Any angle works from a ring: wander from the camera-side start
		var c := 0.0 if cur.kind == Kind.GROUND else (cur.get("_c", 0.0) as float)
		a0 = c + dir * ang_gap - ang_w * 0.5
		a1 = a0 + ang_w
	elif dir > 0.0:
		a0 = cur.a1 + ang_gap
		a1 = a0 + ang_w
	else:
		a1 = cur.a0 - ang_gap
		a0 = a1 - ang_w
	if kind == Kind.TURRET or kind == Kind.ISLAND or kind == Kind.PROP:
		# Same rng draws every retry, so a pulled-in retry keeps its shape
		var state := rng.state
		var s := outer_surface(k, kind, top, (a0 + a1) * 0.5, dist, rng)
		rng.state = state
		return s
	var s := _strip(k, kind, top, a0, a1, 0.0, depth)
	if kind == Kind.RETRACT:
		s.period = 5.0
		s.phase = fposmod(a0 * 7.3, 5.0)
	return s

static func _plan_windows(rng: RandomNumberGenerator, k: int, base: float, surfaces: Array[Dictionary], rose: bool, ground: bool) -> Array[Dictionary]:
	var n := TowerShape.sides(k)
	var fw := TowerShape.face_width(k)
	var half_face := PI / n
	var windows: Array[Dictionary] = []
	var hue := rng.randf()

	if ground:
		windows.append({"face": 0, "y": 0.0, "w": min(fw * 0.5, 1.8), "h": 2.8, "style": 2, "seed": 0.0, "hue": hue})
	# A doorway behind every balcony
	for s in surfaces:
		if s.kind == Kind.BALCONY:
			var face := TowerShape.nearest_face(k, (s.a0 + s.a1) * 0.5)
			windows.append({"face": face, "y": s.top, "w": min(fw * 0.42, 1.4), "h": 2.4, "style": 2, "seed": 0.0, "hue": hue})
	if rose:
		for f in range(0, n, 2):
			var size: float = min(2.2, fw * 0.62)
			windows.append({"face": f, "y": base + 3.0, "w": size, "h": size, "style": 1, "seed": rng.randf() * 100.0, "hue": hue})

	var wanted := rng.randi_range(3, 6)
	for attempt in 14:
		if windows.size() >= wanted + (n / 2 if rose else 0) + (1 if ground else 0):
			break
		var face := rng.randi_range(0, n - 1)
		var h := rng.randf_range(1.8, 2.8)
		var w: float = clamp(fw * 0.32, 0.7, 1.3)
		var y := rng.randf_range(base + 1.0, base + TowerShape.CHUNK_H - h - 0.6)
		var c := TowerShape.face_center(k, face)
		var span := {"a0": c - half_face * 0.6, "a1": c + half_face * 0.6}
		var ok := true
		for s in surfaces:
			if s.kind != Kind.GROUND and s.top > y - 0.3 and s.top - hangs_below(s) < y + h + 0.3 and angular_overlap(s, span):
				ok = false
				break
		for other in windows:
			if other.face == face and abs(other.y - y) < max(other.h, h) + 0.6:
				ok = false
				break
		if ok:
			# Mostly stained glass; some lamplit, some dark and barred
			var roll := rng.randf()
			var style := 0 if roll < 0.55 else (3 if roll < 0.8 else 4)
			windows.append({"face": face, "y": y, "w": w, "h": h, "style": style, "seed": rng.randf() * 100.0, "hue": hue})
	return windows
