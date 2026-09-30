class_name Weather
extends Node3D
# Sky, fog, light, particles and wind, built from three layers:
#  - each height band's character: its daytime colours and its "climate",
#    the odds of each kind of weather there (some bands are nearly always
#    raining, some nearly always clear),
#  - the weather itself: sunny, cloudy, foggy, rainy (snowy up high),
#    thunderstorm or windy. States come and go, blending into each other;
#    wind and fog get stronger the harder the band,
#  - a day / night clock: dusk, stars and a moon, windows lit at night.

signal lightning
signal changed(line: String)         # "A fog rolls in." etc, for the HUD

const SKY_SHADER := preload("res://shaders/sky.gdshader")
const BLEND_HEIGHT := 25.0
const DAY_LENGTH := 300.0            # seconds for a full day and night
const STATE_BLEND := 8.0             # seconds for one weather to turn into another

# Bands: name, daytime sky, base fog, cloud-deck colour, and climate (the
# relative odds of each weather there)
const TYPES := [
	{"name": "The Hemlock Grounds", "top": Color(0.3, 0.45, 0.8), "horizon": Color(0.95, 0.75, 0.55), "bottom": Color(0.3, 0.35, 0.3),
	 "fog": 0.004, "cloud": Color(1.0, 0.92, 0.88), "cover": 0.5, "aurora": 0.0,
	 "climate": {"sunny": 3, "cloudy": 2, "foggy": 2, "rainy": 1, "windy": 1}},
	{"name": "The Misty Spires", "top": Color(0.45, 0.52, 0.65), "horizon": Color(0.78, 0.8, 0.84), "bottom": Color(0.5, 0.52, 0.56),
	 "fog": 0.01, "cloud": Color(0.9, 0.92, 0.95), "cover": 0.6, "aurora": 0.0,
	 "climate": {"foggy": 5, "cloudy": 3, "rainy": 1, "sunny": 1}},
	{"name": "The Weeping Walls", "top": Color(0.3, 0.36, 0.46), "horizon": Color(0.55, 0.6, 0.66), "bottom": Color(0.2, 0.22, 0.28),
	 "fog": 0.008, "cloud": Color(0.6, 0.63, 0.7), "cover": 0.65, "aurora": 0.0,
	 "climate": {"rainy": 6, "storm": 2, "cloudy": 2}},
	{"name": "The Stormcrown", "top": Color(0.2, 0.2, 0.3), "horizon": Color(0.4, 0.38, 0.48), "bottom": Color(0.1, 0.1, 0.15),
	 "fog": 0.008, "cloud": Color(0.35, 0.35, 0.45), "cover": 0.7, "aurora": 0.0,
	 "climate": {"storm": 6, "rainy": 2, "windy": 2}},
	{"name": "The Frost Gallery", "top": Color(0.4, 0.55, 0.8), "horizon": Color(0.88, 0.92, 0.98), "bottom": Color(0.6, 0.65, 0.75),
	 "fog": 0.006, "cloud": Color(0.95, 0.97, 1.0), "cover": 0.6, "aurora": 0.0, "cold": true,
	 "climate": {"rainy": 4, "windy": 3, "sunny": 2, "foggy": 1}},
	{"name": "Above the Clouds", "top": Color(0.12, 0.32, 0.78), "horizon": Color(0.62, 0.8, 1.0), "bottom": Color(0.9, 0.92, 1.0),
	 "fog": 0.002, "cloud": Color(1.0, 1.0, 1.0), "cover": 0.8, "aurora": 0.0,
	 "climate": {"sunny": 6, "windy": 3, "cloudy": 1}},
	{"name": "The Aurora Vault", "top": Color(0.1, 0.12, 0.3), "horizon": Color(0.3, 0.32, 0.5), "bottom": Color(0.08, 0.1, 0.18),
	 "fog": 0.004, "cloud": Color(0.4, 0.45, 0.65), "cover": 0.5, "aurora": 1.0, "night_bias": 0.6,
	 "climate": {"sunny": 4, "windy": 2, "foggy": 1}},
]

# What each kind of weather does
const STATES := {
	"sunny": {"fog": 0.0, "cloud": 0.0, "light": 1.0, "sun": 1.0, "particles": "", "wind": 0.4, "lightning": 0.0},
	"cloudy": {"fog": 0.004, "cloud": 0.55, "light": 0.65, "sun": 0.2, "particles": "", "wind": 0.9, "lightning": 0.0},
	"foggy": {"fog": 0.028, "cloud": 0.4, "light": 0.6, "sun": 0.1, "particles": "mist", "wind": 0.2, "lightning": 0.0},
	"rainy": {"fog": 0.012, "cloud": 0.7, "light": 0.5, "sun": 0.0, "particles": "rain", "wind": 1.6, "lightning": 0.0},
	"storm": {"fog": 0.014, "cloud": 0.9, "light": 0.35, "sun": 0.0, "particles": "rain", "wind": 2.8, "lightning": 1.0},
	"windy": {"fog": 0.002, "cloud": 0.25, "light": 0.9, "sun": 0.7, "particles": "", "wind": 3.2, "lightning": 0.0},
}
const LINES := {
	"sunny": "The skies clear.", "cloudy": "Clouds gather.", "foggy": "A fog rolls in.",
	"rainy": "It begins to rain.", "snowy": "Snow begins to fall.", "storm": "A storm is coming.",
	"windy": "The wind picks up.",
}

const NIGHT_TOP := Color(0.02, 0.03, 0.09)
const NIGHT_HORIZON := Color(0.1, 0.1, 0.22)
const NIGHT_BOTTOM := Color(0.04, 0.05, 0.1)
const DUSK := Color(1.0, 0.5, 0.32)
const MOON := Color(0.6, 0.7, 0.95)
const DAY_AMBIENT := Color(0.62, 0.6, 0.68)
const NIGHT_AMBIENT := Color(0.32, 0.33, 0.5)

var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var emitters := {}
var gusts: WindGusts                 # ribbons showing which way the wind blows
var current: Dictionary = {}          # the composed result (glow, lightning, ...)
var band := -1
var wind := 0.0                      # tangential m/s, sampled by the player
var cloud_tint := Color.WHITE
var flash := 0.0
var time := 0.0
var lightning_timer := 5.0
var day_time := 0.985                # 0..1 round the clock (sunrise at 0); starts at dawn
var dayness := 1.0                   # 1 = broad day, 0 = deep night
var was_night := false

# The weather state machine
var state_name := ""
var state_from: Dictionary = STATES.sunny
var state_to: Dictionary = STATES.sunny
var state_blend := 1.0
var state_timer := 0.0
var locked := ""                     # when set, the only weather there is (the boss fight's storm)

static func weather_of(b: int) -> Dictionary:
	return TYPES[TowerShape.style(b) % TYPES.size()]

static func band_name(b: int) -> String:
	var cycle := b / (TowerShape.style_count if TowerShape.style_count > 0 else TYPES.size())
	var numerals := ["", " II", " III", " IV", " V", " VI", " VII", " VIII", " IX", " X"]
	return weather_of(b).name + (numerals[cycle] if cycle < numerals.size() else " %d" % (cycle + 1))

# How much harder the weather hits in a band (wind and fog)
static func intensity(b: int) -> float:
	return lerp(0.7, 1.3, TowerShape.difficulty(b))

# The strongest wind a band's climate can throw at you (for the level
# generator, which keeps route jumps makeable against it)
static func band_max_wind(b: int) -> float:
	var worst := 0.0
	for name in weather_of(b).climate:
		worst = max(worst, STATES[name].wind)
	return worst * intensity(b)

func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# Ambient comes from a colour and nothing is reflective, so the sky never
	# needs baking into a radiance map (costly on phones every time it changes)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = true
	env.fog_sky_affect = 0.25
	# Depth fog: clear round the camera, thickening past a start distance.
	# (Exponential fog put a milky film on everything a few metres away.)
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 0.95
	env.fog_depth_curve = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.shadow_enabled = false       # the blob shadow does the job, and it's cheap on phones
	add_child(sun)

	emitters.rain = _emitter(Tuning.particles(1300), 1.5, Vector3(0.025, 0.55, 1), Color(0.7, 0.8, 1.0, 0.55), Vector3(24, 0.5, 24), 20.0, 5.0, true)
	emitters.snow = _emitter(Tuning.particles(700), 9.0, Vector3(0.09, 0.09, 1), Color(1, 1, 1, 0.9), Vector3(24, 0.5, 24), 1.2, 35.0, false)
	emitters.mist = _emitter(Tuning.particles(36), 7.0, Vector3(3.0, 1.6, 1), Color(1, 1, 1, 0.13), Vector3(9, 6, 9), 0.25, 180.0, false)
	emitters.sparkle = _emitter(Tuning.particles(70), 3.0, Vector3(0.07, 0.07, 1), Color(0.6, 1.0, 0.8, 1.0), Vector3(9, 6, 9), 0.3, 180.0, false)

	gusts = WindGusts.new()
	add_child(gusts)

func _emitter(amount: int, life: float, quad_size: Vector3, color: Color, extents: Vector3, speed: float, spread: float, stretch: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.DOWN
	p.spread = spread
	p.initial_velocity_min = speed * 0.8
	p.initial_velocity_max = speed
	p.gravity = Vector3.ZERO
	var q := QuadMesh.new()
	q.size = Vector2(quad_size.x, quad_size.y)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if stretch else BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	q.material = m
	p.mesh = q
	add_child(p)
	return p

# Start again from a fresh evening (a new climb)
func reset_clock() -> void:
	day_time = 0.985
	state_name = ""
	state_timer = 0.0

# Pick the next weather from the band's climate
func _next_state(b: int) -> void:
	var climate: Dictionary = weather_of(b).climate
	var total := 0
	for n in climate:
		total += climate[n]
	var roll := randi_range(1, total)
	var pick := ""
	for n in climate:
		roll -= climate[n]
		if roll <= 0:
			pick = n
			break
	if locked != "":
		pick = locked
	state_timer = randf_range(25.0, 60.0)
	if pick == state_name:
		return
	var announce := state_name != ""
	state_from = _state_now()
	state_to = STATES[pick]
	state_blend = 0.0
	state_name = pick
	if announce:
		var cold: bool = weather_of(b).get("cold", false)
		changed.emit(LINES["snowy" if cold and pick == "rainy" else pick])

func _state_now() -> Dictionary:
	var t := smoothstep(0.0, 1.0, state_blend)
	var out := {}
	for key in state_to:
		var a = state_from[key]
		var b = state_to[key]
		out[key] = lerp(a, b, t) if b is float else (b if t > 0.5 else a)
	return out

# The band's own colours at height y, blended across a band change
func _band_at(y: float) -> Dictionary:
	var b := TowerShape.band_at(y)
	var cur := weather_of(b)
	if b == 0:
		return cur
	var t: float = clamp((y - b * TowerShape.BAND_H) / BLEND_HEIGHT, 0.0, 1.0)
	var prev := weather_of(b - 1)
	var out := cur.duplicate()
	for key in ["top", "horizon", "bottom", "fog", "aurora"]:
		out[key] = lerp(prev[key], cur[key], t)
	out.night_bias = lerp(prev.get("night_bias", 0.0), cur.get("night_bias", 0.0), t)
	return out

func update(delta: float, focus: Vector3, theta: float) -> void:
	time += delta
	day_time = fposmod(day_time + delta / DAY_LENGTH, 1.0)
	var b := TowerShape.band_at(focus.y)
	if b != band or state_timer <= 0.0:
		band = b
		_next_state(b)
	state_timer -= delta
	state_blend = min(state_blend + delta / STATE_BLEND, 1.0)
	var st := _state_now()
	var look := _band_at(focus.y)
	var mult := intensity(b)

	# Time of day
	var e := sin(TAU * day_time)                     # the sun's height, -1..1
	dayness = smoothstep(-0.2, 0.25, e) * (1.0 - look.get("night_bias", 0.0))
	var dusk: float = clamp(1.0 - abs(e) / 0.3, 0.0, 1.0)
	var c: float = st.cloud
	var night_now := dayness < 0.3
	if night_now != was_night:
		was_night = night_now
		changed.emit("Night falls." if night_now else "Dawn breaks.")

	# Sky: the band's day colours, toward night, warmed at dusk, greyed by cloud
	var grey: Color = Color(0.55, 0.57, 0.62) * lerp(0.3, 1.0, dayness)
	var top: Color = NIGHT_TOP.lerp(look.top, dayness).lerp(grey * 0.9, c * 0.75)
	var horizon: Color = NIGHT_HORIZON.lerp(look.horizon, dayness).lerp(DUSK, dusk * 0.5).lerp(grey, c * 0.65)
	var bottom: Color = NIGHT_BOTTOM.lerp(look.bottom, dayness).lerp(grey * 0.7, c * 0.6)
	_sky("top_color", top)
	_sky("horizon_color", horizon)
	_sky("bottom_color", bottom)
	_sky("stars", (1.0 - dayness) * (1.0 - c))
	_sky("aurora", look.aurora * (1.0 - dayness) * (1.0 - c * 0.8) + look.aurora * 0.12)
	# The sun by day, a pale moon by night (both hidden by cloud)
	_sky("sun_color", Color(1.0, 0.85, 0.6).lerp(MOON, 1.0 - dayness))
	_sky("sun_amount", st.sun * dayness + (1.0 - dayness) * (1.0 - c) * 0.6)
	sun.rotation_degrees = Vector3(-lerp(18.0, 55.0, abs(e)), 35.0 + day_time * 120.0, 0)

	# Fog thickens as you near a cloud deck
	var deck_band := roundi(focus.y / TowerShape.BAND_H)
	var near_deck := 0.0
	if deck_band >= 1:
		near_deck = 1.0 - clamp(abs(focus.y - CloudLayers.deck_height(deck_band)) / 10.0, 0.0, 1.0)
	env.fog_light_color = horizon.lerp(grey, 0.4).lerp(Color(0.8, 0.82, 1.0), flash * 0.75)
	# How thick the weather is sets how close the fog starts
	var thick: float = look.fog + st.fog * mult + near_deck * 0.012
	env.fog_depth_end = clamp(2.2 / max(thick, 0.0001), 45.0, 900.0)
	env.fog_depth_begin = env.fog_depth_end * 0.35
	env.ambient_light_color = NIGHT_AMBIENT.lerp(DAY_AMBIENT, dayness) * lerp(1.0, 0.85, c)

	# Lightning
	flash = max(flash - delta * 3.0, 0.0)
	var stormy: bool = st.lightning > 0.5
	if stormy:
		lightning_timer -= delta
		if lightning_timer <= 0.0:
			lightning_timer = randf_range(3.5, 9.0)
			flash = 1.0
			lightning.emit()
	_sky("flash", flash * 0.6)
	var light: Color = MOON.lerp(Color(1.0, 0.95, 0.85), dayness).lerp(Color(1.0, 0.6, 0.35), dusk * dayness * 0.6)
	var energy: float = lerp(0.3, 1.15, dayness) * st.light
	sun.light_color = light
	sun.light_energy = energy + flash * 2.0
	# How brightly lit unshaded things (clouds) should look right now
	var ambient := env.ambient_light_color
	var l: Color = light * (energy * 0.6) + ambient * 0.6
	cloud_tint = Color(min(l.r, 1.0), min(l.g, 1.0), min(l.b, 1.0)).lerp(Color.WHITE, flash * 0.5)

	# Particles: rain turns to snow up high; sparkles on clear aurora nights
	var particles: String = st.particles
	if particles == "rain" and look.get("cold", false):
		particles = "snow"
	if particles == "" and look.aurora > 0.5 and dayness < 0.5:
		particles = "sparkle"

	current = {
		"glow": lerp(0.6, 2.0, 1.0 - dayness) + c * 0.4,
		"lightning": stormy,
		"state": state_name,
	}

	# Wind: this weather's strength with gusts, direction alternating by band
	var dir := 1.0 if b % 2 == 0 else -1.0
	var gust: float = 0.6 + 0.4 * sin(time * 0.9) + (0.7 * max(sin(time * 2.3), 0.0) if stormy else 0.0)
	wind = st.wind * mult * gust * dir
	var tangent := Vector3(cos(theta), 0, -sin(theta)) * wind

	# Ribbons of wind flow past the bird the way it will be pushed
	gusts.update(delta, wind, focus, theta)

	for key in emitters:
		var em: CPUParticles3D = emitters[key]
		var on: bool = particles == key
		if em.emitting != on:
			em.emitting = on
		if on:
			em.global_position = focus + (Vector3(0, 15, 0) if key == "rain" or key == "snow" else Vector3(0, 1, 0))
			em.gravity = tangent * (3.0 if key == "rain" else 1.0)

var _sky_cache := {}

# Only pass sky values that actually changed (most frames, few do)
func _sky(param: String, value) -> void:
	if _sky_cache.get(param) != value:
		_sky_cache[param] = value
		sky_mat.set_shader_parameter(param, value)

# A lightning flash right now (for a strike on the tower)
func flash_now() -> void:
	flash = 1.0
	lightning.emit()
