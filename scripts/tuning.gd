class_name Tuning
# Movement constants shared by the player and the level generator, so the
# generator only ever builds jumps the bird can actually make.

const GRAVITY := 22.0                 # gentle: a slow fall, plenty of hang time
const RISE_GRAVITY_HELD := 0.7       # holding jump while rising floats a little
const FALL_GRAVITY := 1.0            # (no extra pull on the way down)
const TERMINAL_VY := -19.0
const JUMP_SPEED := 11.6             # ground jump: ~3 m (v^2 / 2g)
const FLAP_SPEED := 9.4              # air flap: ~2 m more, costs stamina

# One stamina bucket. The starting one holds a jump and five flaps
# (20 + 5 x 33); gold feathers make it bigger (up to the cap).
const BASE_STAMINA := 185.0
const STAMINA_CAP := 320.0
const FLAP_COST := 33.0
const JUMP_COST := 20.0             # the jump off the ground costs a bit too
const REGEN_RATE := 55.0             # per second while standing
const REGEN_DELAY := 0.25
const FEATHER_BONUS := 5.0           # bucket growth per gold feather
const FEATHER_REFILL := 33.0         # and it tops you up by one flap

# Holding jump while falling glides: gravity barely pulls, drains stamina
const GLIDE_GRAVITY := 0.08          # fraction of normal gravity while gliding
const GLIDE_MAX_SINK := 4.0          # glide never falls faster than this (m/s)
const GLIDE_COST := 8.0              # stamina per second (a full starting bar glides ~23 s)
const GLIDE_BRAKE := 45.0            # how quickly a fast fall slows into a glide

# Air columns: push per second squared while inside (gravity is 22)
const UPDRAFT := 55.0
const DOWNDRAFT := 30.0
const DRAFT_MAX_RISE := 10.0         # updrafts lift you to at most this speed

# Loose plumes top stamina up (without growing the bucket); poison drains it and
# stops it recovering for a moment
const PLUME_STAMINA := 40.0
const POISON_DRAIN := 50.0
const POISON_SICK := 2.5             # seconds without regen after eating poison

const RUN_SPEED := 7.0               # around the tower, m/s at any radius
const RADIAL_SPEED := 5.0            # in / out from the tower
const GROUND_ACCEL := 60.0
const AIR_ACCEL := 40.0

const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12
const WALL_MARGIN := 0.35            # closest the bird gets to the wall
const OUTER_REACH := 12.0            # furthest out from the wall (turrets, props, rings live out here)
const FOOT_TOLERANCE := 0.2
const STUN_FALL := 14.0              # falls longer than this stun briefly
const STUN_TIME := 0.45

# The generator assumes a jump plus this many flaps for a path jump:
# 20 + 2 x 33 = 86 of the starting 185, so there's plenty to spare.
const PATH_FLAPS := 2

# Horizontal distance covered by a jump that lands dy above the take-off
# point, using `flaps` flaps at each apex. Conservative: ignores the
# hold-to-float bonus. Returns -1 if the height can't be reached.
static func air_distance(dy: float, flaps: int) -> float:
	var dt := 1.0 / 240.0
	var y := 0.0
	var vy := JUMP_SPEED
	var t := 0.0
	var reached := dy <= 0.0
	while t < 8.0:
		var g := GRAVITY * (FALL_GRAVITY if vy < 0.0 else 1.0)
		vy = max(vy - g * dt, TERMINAL_VY)
		y += vy * dt
		t += dt
		if vy <= 0.0 and flaps > 0:
			vy = FLAP_SPEED
			flaps -= 1
		if y >= dy:
			reached = true
		elif vy < 0.0:
			if reached:
				return RUN_SPEED * t
			if flaps == 0:
				return -1.0
	return RUN_SPEED * t

static func max_jump_height(flaps: int) -> float:
	var h := JUMP_SPEED * JUMP_SPEED / (2.0 * GRAVITY)
	return h + flaps * FLAP_SPEED * FLAP_SPEED / (2.0 * GRAVITY)

# Equivalent run distance for a hop that moves `tangential` metres around the
# tower and `radial` metres in/out: the two axes move independently, and
# in/out is slower, so the longer of the two (scaled) sets the time needed.
static func hop_length(tangential: float, radial: float) -> float:
	return max(tangential, radial * RUN_SPEED / RADIAL_SPEED)

# Phones get lighter effects (fewer particles and cloud layers). Set by the
# game at startup: on for touch devices, or with `-- --low`.
static var low_quality := false

# Scale a particle count for the current quality
static func particles(n: int) -> int:
	return maxi(1, int(n * (0.4 if low_quality else 1.0)))

# Tightropes and wind streams
const WIRE_LAUNCH := 3.5             # extra jump speed off a wire (and it's free)
const WIRE_DIP_BOOST := 11.0         # more still, per metre the wire is bent down
# Wind streams: currents along a curve that catch the bird and carry it
const STREAM_SPEED := 13.0           # m/s along the current
const STREAM_CATCH := 2.0            # how close to the current's middle catches you
const STREAM_STEP := 0.5             # metres between the sampled points of a current
const STREAM_STAMINA := 20.0         # a breather: stamina back when it lets you go

# Power-ups: how long each lasts (seconds)
const POWER_TIME := {"sunseed": 10.0, "spring": 12.0, "cloud": 12.0, "charm": 15.0}
const SPRING_MULT := 1.4             # jump / flap speed with a Spring Berry
const CLOUD_GRAVITY := 0.45          # falling gravity with a Cloud Puff

# The meadow round the tower's foot is the hub: down there the bird can wander
# much further out than the climb allows
const HUB_TOP := 10.0                # below this height...
const HUB_RADIUS := 30.0             # ...the bird can go this far from the tower's axis
const HOP_RATE := 5.0                # hops a second while walking
const HOP_HEIGHT := 0.32             # metres

# Endless mode: a single drop longer than this ends the run. Section mode:
# falling this far below the section's start carries you back to it.
const ENDLESS_FALL := 36.0
const SECTION_FALL_OUT := 18.0
