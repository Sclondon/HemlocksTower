class_name TowerShape
# Pure geometry for the tower: which n-gon lives at which height, and helpers
# for building footprints that hug its flat faces. No nodes, so the headless
# reachability test can use it too.
#
# Shape functions take a chunk index `k`: the side count, rotation and tint
# come from the chunk's band, while the thickness varies chunk by chunk.
#
# Angle convention: a point at angle theta and radius r sits at
# (sin(theta) * r, y, cos(theta) * r). Theta grows to the camera's right.

const CHUNK_H := 12.0
const CHUNKS_PER_BAND := 10          # 120 m per band
const BAND_H := CHUNK_H * CHUNKS_PER_BAND

# Each band picks its side count / size from these (cycled)
const BAND_SIDES := [8, 7, 6, 8, 5, 9, 6, 10]
const BAND_APOTHEM := [4.0, 3.8, 3.6, 4.2, 3.5, 4.3, 3.7, 4.4]
const BAND_TINT := [
	Color(0.95, 0.9, 0.85), Color(0.8, 0.85, 0.95), Color(0.75, 0.8, 0.9),
	Color(0.7, 0.72, 0.85), Color(0.9, 0.95, 1.0), Color(1.0, 0.95, 0.85),
	Color(0.85, 0.75, 0.95), Color(0.95, 0.85, 0.8),
]

# Endless mode only builds from the sections the player has unlocked: band b
# then looks like section b % style_count (0 = every band is its own section)
static var style_count := 0

static func style(b: int) -> int:
	return posmod(b, style_count) if style_count > 0 else b

static func chunk_at(y: float) -> int:
	return floori(max(y, 0.0) / CHUNK_H)

static func band_of_chunk(k: int) -> int:
	return floori(float(max(k, 0)) / CHUNKS_PER_BAND)

static func band_at(y: float) -> int:
	return band_of_chunk(chunk_at(y))

static func sides(k: int) -> int:
	return BAND_SIDES[style(band_of_chunk(k)) % BAND_SIDES.size()]

# The tower swells and narrows from chunk to chunk (the opening chunks and
# each band's first chunk keep the band's standard size)
static func thickness(k: int) -> float:
	if k < 2 or k % CHUNKS_PER_BAND == 0:
		return 1.0
	return 1.0 + 0.16 * sin(k * 0.87 + band_of_chunk(k) * 1.7) + 0.07 * sin(k * 2.3)

static func apothem(k: int) -> float:
	return BAND_APOTHEM[style(band_of_chunk(k)) % BAND_APOTHEM.size()] * thickness(k)

static func tint(k: int) -> Color:
	return BAND_TINT[style(band_of_chunk(k)) % BAND_TINT.size()]

static func face_offset(k: int) -> float:
	# Band 0 has a face centred on theta = 0, where the climb starts
	return band_of_chunk(k) * 0.37

static func difficulty(band: int) -> float:
	return clamp(band / 6.0, 0.0, 1.0)

static func face_step(k: int) -> float:
	return TAU / sides(k)

static func face_center(k: int, i: int) -> float:
	return face_offset(k) + i * face_step(k)

static func face_width(k: int) -> float:
	return 2.0 * apothem(k) * tan(PI / sides(k))

# Angle relative to the centre of the nearest face, in [-step/2, step/2)
static func rel_angle(k: int, theta: float) -> float:
	var step := face_step(k)
	return fposmod(theta - face_offset(k) + step * 0.5, step) - step * 0.5

static func nearest_face(k: int, theta: float) -> int:
	var step := face_step(k)
	return posmod(roundi((theta - face_offset(k)) / step), sides(k))

# Radius of the n-gon (offset outward by d) along the ray at theta
static func wall_r(k: int, theta: float, d := 0.0) -> float:
	return (apothem(k) + d) / cos(rel_angle(k, theta))

static func ring_point(k: int, theta: float, d: float) -> Vector2:
	var r := wall_r(k, theta, d)
	return Vector2(sin(theta) * r, cos(theta) * r)

static func polar_point(theta: float, r: float) -> Vector2:
	return Vector2(sin(theta) * r, cos(theta) * r)

# Corner angles strictly between a0 and a1 (a0 < a1)
static func corners_between(k: int, a0: float, a1: float) -> Array[float]:
	var step := face_step(k)
	var first := face_offset(k) + step * 0.5
	var out: Array[float] = []
	var j := ceili((a0 - first) / step)
	var c := first + j * step
	while c < a1:
		if c > a0 + 0.0001:
			out.append(c)
		c += step
	return out

# A simple polygon (XZ plane) covering angles a0..a1 between offsets d0 and d1
# from the wall, following the n-gon's flat faces and corners.
static func strip_polygon(k: int, a0: float, a1: float, d0: float, d1: float) -> PackedVector2Array:
	var angles: Array[float] = [a0]
	angles.append_array(corners_between(k, a0, a1))
	angles.append(a1)
	var pts := PackedVector2Array()
	for a in angles:
		pts.append(ring_point(k, a, d0))
	for i in range(angles.size() - 1, -1, -1):
		pts.append(ring_point(k, angles[i], d1))
	return pts

# An arc-shaped polygon on true circles (used for things that move around the tower)
static func arc_polygon(a0: float, a1: float, r0: float, r1: float, segments := 4) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments + 1:
		pts.append(polar_point(lerp(a0, a1, float(i) / segments), r0))
	for i in range(segments, -1, -1):
		pts.append(polar_point(lerp(a0, a1, float(i) / segments), r1))
	return pts

# Walking distance along the wall (at offset d) from a0 to a1 (a0 <= a1)
static func perimeter_len(k: int, a0: float, a1: float, d := 0.5) -> float:
	if a1 <= a0:
		return 0.0
	var prev := ring_point(k, a0, d)
	var total := 0.0
	for c in corners_between(k, a0, a1):
		var p := ring_point(k, c, d)
		total += prev.distance_to(p)
		prev = p
	return total + prev.distance_to(ring_point(k, a1, d))

# Rough metres -> radians along the wall, good enough for placing things
static func angle_for_len(k: int, length: float, d := 0.5) -> float:
	return length / (apothem(k) * 1.04 + d)
