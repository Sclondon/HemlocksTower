class_name Player
extends Node3D
# The bird. Lives in cylindrical coordinates around the tower axis:
# left/right changes theta (at a constant speed on screen), up/down moves in
# toward the wall or out from it. Surfaces are one-way: you land on them
# from above and pass through them going up.

signal landed(fall_height: float)
signal flapped
signal jumped
signal boosted
signal powered(kind: String)
signal flap_denied
signal picked_up(kind: String)

const IDLE_FRAMES := preload("res://animations/player_idle_SF.tres")
const FLAP_FRAMES := preload("res://animations/player_jump_SF.tres")
const FALL_FRAMES := preload("res://animations/player_fall.tres")

var tower: TowerGenerator
var weather_wind := 0.0              # m/s pushed around the tower while airborne
var active := false

var theta := 0.0
var r := 5.5
var y := 0.0
var vt := 0.0                        # tangential speed (m/s)
var vr := 0.0
var vy := 0.0
var stamina := Tuning.BASE_STAMINA
var max_stamina := Tuning.BASE_STAMINA  # grows with gold feathers
var max_y := 0.0
var grounded := true
var ground: Dictionary = {}
var coyote := 0.0
var jump_buffer := 0.0
var regen_wait := 0.0
var fall_from := 0.0
var stun := 0.0
var facing := 1.0
var squash := 0.0
var knock := Vector2.ZERO             # shove from a bump (around, in/out) m/s, fades
var is_npc := false                    # rival climbers: no silhouette, no pickups
var regen_rate := Tuning.REGEN_RATE
var speed_mult := 1.0
var hidden_for := 0.0                  # how long something has blocked the view of the bird
var _hidden := false
var frames_idle: SpriteFrames = IDLE_FRAMES
var frames_flap: SpriteFrames = FLAP_FRAMES
var frames_fall: SpriteFrames = FALL_FRAMES
var flap_anim := 0.0
var gliding := false
var wire: Dictionary = {}               # the tightrope we're riding, if any
var powers := {}                       # active power-ups: name -> seconds left
var wire_chunk: TowerChunk
var sick := 0.0                      # poisoned: no stamina recovery for a moment

var sprite: AnimatedSprite3D
var ghost: AnimatedSprite3D           # silhouette shown only where the bird is hidden
var feathers: CPUParticles3D           # black feathers shed while flapping / gliding
var trails: WingTrails                 # wing-tip lines while gliding fast
var flap_hold := 0.0                   # keeps the flap animation going briefly
var hop_phase := 0.0                   # walking is a run of little hops: how far through them

const FLAP_UNTIL_FALLING := -9.0       # flap animation until falling faster than this
const GHOST_COLOR := Color(0.6, 0.5, 0.95, 0.5)
static var _derived := {}
var shadow: Sprite3D

func _ready() -> void:
	sprite = AnimatedSprite3D.new()
	sprite.sprite_frames = frames_idle
	sprite.pixel_size = 0.085
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.shaded = false
	# Normal depth sorting (a high priority here drew the bird over pickups and
	# ledges it was actually behind); the silhouette just goes first
	sprite.render_priority = 1
	add_child(sprite)
	sprite.play("default")

	# Depth-tested bird, so ledges in front really do hide it. Underneath, a dim
	# silhouette drawn through everything shows where it is when hidden; the
	# real sprite (drawn later) covers it wherever the bird is visible.
	ghost = AnimatedSprite3D.new()
	ghost.sprite_frames = IDLE_FRAMES
	ghost.pixel_size = sprite.pixel_size
	ghost.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ghost.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	ghost.shaded = false
	ghost.no_depth_test = true
	ghost.render_priority = 0
	add_child(ghost)
	ghost.visible = false
	ghost.modulate.a = 0.0
	# Keep the silhouette on exactly the same frame (it would otherwise lag a
	# frame behind and show its wings beside the bird while flapping fast)
	sprite.frame_changed.connect(func(): ghost.frame = sprite.frame)

	feathers = _make_feathers()
	add_child(feathers)
	trails = WingTrails.new()
	add_child(trails)

	shadow = Sprite3D.new()
	shadow.texture = MeshUtil.blob_texture()
	shadow.pixel_size = 0.11
	shadow.modulate = Color(0.12, 0.05, 0.2)
	shadow.axis = Vector3.AXIS_Y     # lies flat on the ledge
	shadow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shadow.shaded = false
	shadow.render_priority = 0
	shadow.top_level = true
	add_child(shadow)

func place(t: float, radius: float, height: float) -> void:
	wire = {}
	powers.clear()
	theta = t
	r = radius
	y = height
	vt = 0.0
	vr = 0.0
	vy = 0.0
	stun = 0.0
	stamina = max_stamina
	max_y = max(max_y, height)
	fall_from = height
	grounded = false
	ground = {}
	var s := tower.find_landing(height + 0.5, height - 0.5, theta, r)
	if not s.is_empty():
		_land(s, false)

func world_position() -> Vector3:
	return Vector3(sin(theta) * r, y, cos(theta) * r)

func _physics_process(delta: float) -> void:
	if tower == null:
		return
	var shape := TowerShape.chunk_at(y + 0.05)

	var ax := 0.0
	var ar := 0.0
	var jump_pressed := false
	var jump_held := false
	if active and stun <= 0.0:
		var input := read_input()
		ax = input.ax
		ar = input.ar
		jump_pressed = input.jump_pressed
		jump_held = input.jump_held
	stun = max(stun - delta, 0.0)

	# Around / in-out, with snappier control on the ground
	var accel := Tuning.GROUND_ACCEL if grounded else Tuning.AIR_ACCEL
	vt = move_toward(vt, ax * Tuning.RUN_SPEED * speed_mult, accel * delta)
	vr = move_toward(vr, ar * Tuning.RADIAL_SPEED * speed_mult, accel * delta)
	if abs(ax) > 0.1:
		facing = sign(ax)
	var push := 0.0 if grounded else weather_wind
	theta += (vt + push + knock.x) / r * delta
	r += (vr + knock.y) * delta
	knock = knock.move_toward(Vector2.ZERO, 12.0 * delta)
	var r_min := TowerShape.wall_r(shape, theta, Tuning.WALL_MARGIN)
	var r_max := TowerShape.wall_r(shape, theta, Tuning.OUTER_REACH)
	if y < Tuning.HUB_TOP:
		r_max = max(r_max, Tuning.HUB_RADIUS)      # the meadow round the base: the hub
	r = max(r, r_min)
	if r > r_max:
		if y < Tuning.HUB_TOP + TowerShape.CHUNK_H:
			# Flown up out of the hub from far out: drift back in rather than snap
			r = move_toward(r, r_max, Tuning.RADIAL_SPEED * 2.0 * delta) if r - r_max > 0.3 else r_max
			vr = min(vr, 0.0)
		else:
			r = r_max

	# On a tightrope: slide along it, bounce with it, launch off it
	if not wire.is_empty():
		_ride_wire(delta, jump_pressed or jump_buffer > 0.0)
		# (this frame ends here, even after a launch, so the same press
		# doesn't also count as a flap)
		_collect(delta)
		return

	# Jumping: the ground jump costs a little stamina (but you can always jump
	# off the ground, even with an empty bar), each air flap more
	if jump_pressed:
		jump_buffer = Tuning.JUMP_BUFFER
	if jump_buffer > 0.0:
		if grounded or coyote > 0.0:
			vy = Tuning.JUMP_SPEED * _spring()
			stamina = max(stamina - Tuning.JUMP_COST, 0.0)
			_leave_ground()
			jumped.emit()
			_puff()
			coyote = 0.0
			jump_buffer = 0.0
			squash = -0.6
		elif not grounded and coyote <= 0.0 and stamina >= Tuning.FLAP_COST - 0.001:
			vy = Tuning.FLAP_SPEED * _spring()
			stamina -= Tuning.FLAP_COST
			jump_buffer = 0.0
			flap_anim = 0.35
			fall_from = y
			flapped.emit()
		elif jump_pressed:
			flap_denied.emit()
	jump_buffer = max(jump_buffer - delta, 0.0)
	coyote = max(coyote - delta, 0.0)

	if grounded:
		# Ride moving ledges, and step off edges (or fall with a crumbling one)
		if ground.kind in [ChunkPlanner.Kind.MOVER, ChunkPlanner.Kind.ORBIT, ChunkPlanner.Kind.PROP]:
			theta += ground.offset - ground.get("_last_offset", ground.offset)
		ground._last_offset = ground.offset
		if not tower.supports(ground, theta, r):
			_leave_ground()
			coyote = Tuning.COYOTE_TIME
			vy = 0.0
		else:
			y = ground.top
			regen_wait -= delta
			if regen_wait <= 0.0 and sick <= 0.0:
				stamina = min(stamina + regen_rate * delta, max_stamina)
			tower.touch(ground)
	if not grounded:
		# Holding jump on the way down glides, for as long as stamina lasts:
		# gravity still pulls, just gently, and a fast fall is braked
		gliding = jump_held and vy <= 0.0 and stamina > 0.0
		var g := Tuning.GRAVITY
		if gliding:
			g *= Tuning.GLIDE_GRAVITY
		elif vy > 0.0 and jump_held:
			g *= Tuning.RISE_GRAVITY_HELD
		elif vy < 0.0:
			g *= Tuning.CLOUD_GRAVITY if powers.has("cloud") else Tuning.FALL_GRAVITY
		vy = max(vy - g * delta, Tuning.TERMINAL_VY)
		if gliding:
			if vy < -Tuning.GLIDE_MAX_SINK:
				vy = move_toward(vy, -Tuning.GLIDE_MAX_SINK, Tuning.GLIDE_BRAKE * delta)
			stamina = max(stamina - Tuning.GLIDE_COST * delta, 0.0)
			fall_from = y            # a glide lands softly
		# Updrafts lift, downdrafts press you down
		var lift := tower.draft_at(world_position())
		if lift != 0.0:
			vy += lift * delta
			if lift > 0.0:
				vy = min(vy, Tuning.DRAFT_MAX_RISE)
				fall_from = y
		var prev_y := y
		var prev_pos := world_position()
		y += vy * delta
		if not is_npc:
			var rg := tower.ring_hit(world_position())
			if not rg.is_empty():
				_boost(rg)
		if vy <= 0.0:
			var s := tower.find_landing(prev_y, y, theta, r)
			if not s.is_empty():
				_land(s, true)
			elif not is_npc and _try_wire(prev_pos):
				pass
			elif y <= 0.0:
				_land(tower.chunk(0).surfaces[0], true)   # the ground

	_collect(delta)

func _collect(delta: float) -> void:
	max_y = max(max_y, y)
	sick = max(sick - delta, 0.0)
	for p in powers.keys():
		powers[p] -= delta
		if powers[p] <= 0.0:
			powers.erase(p)
	if powers.has("sunseed"):
		stamina = max_stamina             # endless, while it lasts
	if powers.has("charm"):
		tower.magnet(world_position(), delta)
	for kind in ([] if is_npc else tower.collect_pickups(world_position())):
		match kind:
			"feather":   # bigger bucket for good, plus a flap's worth
				max_stamina = min(max_stamina + Tuning.FEATHER_BONUS, Tuning.STAMINA_CAP)
				stamina = min(stamina + Tuning.FEATHER_REFILL, max_stamina)
			"seed":      # just a top-up
				stamina = min(stamina + Tuning.SEED_STAMINA, max_stamina)
			"poison":
				stamina = max(stamina - Tuning.POISON_DRAIN, 0.0)
				sick = Tuning.POISON_SICK
			_:
				if Tuning.POWER_TIME.has(kind):
					powers[kind] = Tuning.POWER_TIME[kind]
					powered.emit(kind)
		picked_up.emit(kind)

# Struck by lightning: stunned, blasted outward and up, and it stings
func zap() -> void:
	stun = 0.9
	knock.y += 8.0
	vy = max(vy, 7.0)
	_leave_ground()
	stamina = max(stamina - 25.0, 0.0)
	squash = 1.0

func _spring() -> float:
	return Tuning.SPRING_MULT if powers.has("spring") else 1.0

# Bounced off something's head (another bird): a free hop up
func bounce(speed: float) -> void:
	vy = speed
	_leave_ground()
	squash = -0.5
	flap_anim = 0.3

# Overridden by the climb-bot test
func read_input() -> Dictionary:
	return {
		"ax": Input.get_axis("move_left", "move_right"),
		"ar": Input.get_axis("move_in", "move_out"),
		"jump_pressed": Input.is_action_just_pressed("jump"),
		"jump_held": Input.is_action_pressed("jump"),
	}

func _leave_ground() -> void:
	wire = {}
	if not ground.is_empty():
		tower.leave(ground)
	grounded = false
	ground = {}
	fall_from = y

func _land(s: Dictionary, emit: bool) -> void:
	var fall: float = fall_from - s.top
	grounded = true
	gliding = false
	ground = s
	ground._last_offset = s.get("offset", 0.0)
	y = s.top
	vy = 0.0
	regen_wait = Tuning.REGEN_DELAY
	if emit:
		squash = clamp(fall / 6.0, 0.25, 1.0)
		if fall > Tuning.STUN_FALL:
			stun = Tuning.STUN_TIME
		landed.emit(fall)

func _process(delta: float) -> void:
	position = world_position()
	flap_anim = max(flap_anim - delta, 0.0)
	var frames: SpriteFrames
	# Near the top of a jump the bird flaps frantically, struggling to stay up
	var apex: float = clamp(1.0 - abs(vy) / 4.0, 0.0, 1.0) if not grounded else 0.0
	# Keep flapping until genuinely dropping, and a moment after that
	if not grounded and (gliding or flap_anim > 0.0 or vy > FLAP_UNTIL_FALLING):
		flap_hold = 0.25
	flap_hold = max(flap_hold - delta, 0.0)
	var flapping := not grounded and flap_hold > 0.0
	if grounded:
		frames = frames_idle
	elif flapping:
		frames = frames_flap
	else:
		frames = frames_fall
	if sprite.sprite_frames != frames:
		sprite.sprite_frames = frames
		sprite.play("default")
	if gliding:
		sprite.speed_scale = 1.8          # slow, steady beats while gliding
	elif frames == frames_flap:
		sprite.speed_scale = lerp(3.0, 11.0, apex)
	else:
		sprite.speed_scale = 2.5 if abs(vt) > 0.5 else 1.5
	# Feet at the node origin whatever the frame size
	var tex := frames.get_frame_texture("default", 0)
	sprite.offset = Vector2(0, tex.get_height() * 0.5 - 1.0)
	sprite.flip_h = facing > 0.0     # the art faces left
	squash = move_toward(squash, 0.0, delta * 4.0)
	sprite.scale = Vector3(1.0 + squash * 0.3, 1.0 - squash * 0.3, 1.0)
	sprite.modulate = Color(1, 0.7, 0.7) if stun > 0.0 else Color.WHITE

	# Nudge the flat sprite toward the camera so it doesn't clip into the wall
	# at the tower's corners
	var cam := get_viewport().get_camera_3d()
	var nudge := Vector3.ZERO
	if cam:
		nudge = cam.global_position - global_position
		nudge.y = 0.0
		nudge = nudge.normalized() * 0.35
	sprite.position = nudge + Vector3(0, _hop(delta), 0)

	var derived := _derive(frames, GHOST_COLOR, 0)
	if ghost.sprite_frames != derived:
		ghost.sprite_frames = derived
	ghost.frame = sprite.frame
	ghost.offset = sprite.offset
	ghost.flip_h = sprite.flip_h
	ghost.scale = sprite.scale
	ghost.position = sprite.position
	# Only show the silhouette when something really is in the way (it used to
	# sit under the bird all the time, which some phones drew as a second bird)
	if not is_npc and cam and tower:
		# (a line-of-sight check; every third frame is plenty)
		if Engine.get_process_frames() % 3 == 0:
			_hidden = tower.blocked(global_position + Vector3(0, 0.7, 0), cam.global_position)
		var hidden := _hidden
		hidden_for = hidden_for + delta if hidden else 0.0
		var want := 1.0 if hidden_for > 0.08 else 0.0     # (the frames carry the tint and alpha)
		ghost.modulate.a = move_toward(ghost.modulate.a, want, delta * 4.0)
		ghost.visible = ghost.modulate.a > 0.01

	feathers.emitting = flapping
	feathers.position = nudge + Vector3(0, 0.6, 0)
	# Two clean lines off the wing tips, only while gliding at a good clip
	var speed := Vector3(vt, vy, vr).length()
	trails.active = gliding and speed > 5.0
	var right := cam.global_transform.basis.x if cam else Vector3.RIGHT
	var wings := global_position + nudge + Vector3(0, 1.3, 0)
	var tips: Array[Vector3] = [wings - right * 1.05, wings + right * 1.05]
	trails.update(delta, tips)
	if sick > 0.0:
		sprite.modulate = Color(0.75, 1.0, 0.6)   # a queasy green

	var floor_y := tower.ground_below(theta, r, y, 40.0) if tower else -INF
	shadow.visible = floor_y > -INF
	if shadow.visible:
		shadow.global_position = Vector3(sin(theta) * r, floor_y + 0.03, cos(theta) * r)
		var s: float = clamp(1.0 - (y - floor_y) / 16.0, 0.55, 1.0)
		shadow.scale = Vector3.ONE * s

# Crows don't walk, they hop: while moving on the ground the sprite bounces
# along in little hops (just the picture: the bird's feet stay on the ledge).
# Stopping finishes the hop in the air. Returns the lift for this frame.
func _hop(delta: float) -> float:
	var walking := grounded and wire.is_empty() and Vector2(vt, vr).length() > 0.6
	if not grounded or not wire.is_empty():
		hop_phase = 0.0
		return 0.0
	if walking or hop_phase > 0.0:
		var before := floorf(hop_phase)
		hop_phase += delta * Tuning.HOP_RATE * clamp(Vector2(vt, vr).length() / Tuning.RUN_SPEED, 0.7, 1.3)
		if floorf(hop_phase) > before:
			if walking:
				squash = max(squash, 0.22)        # a little bump on each touchdown
			else:
				hop_phase = 0.0                   # stopped: settle on this landing
	return sin(fposmod(hop_phase, 1.0) * PI) * Tuning.HOP_HEIGHT

# A flat-colour copy of an animation (for the see-through silhouette),
# optionally grown by `grow` pixels all round. Cached: the bird's three
# animations are shared.
static func _derive(frames: SpriteFrames, color: Color, grow: int) -> SpriteFrames:
	var key := "%s|%s|%d" % [frames.resource_path, color.to_html(), grow]
	if _derived.has(key):
		return _derived[key]
	var out := SpriteFrames.new()
	out.set_animation_speed("default", frames.get_animation_speed("default"))
	out.set_animation_loop("default", frames.get_animation_loop("default"))
	for i in frames.get_frame_count("default"):
		var src := frames.get_frame_texture("default", i).get_image()
		src.decompress()
		src.convert(Image.FORMAT_RGBA8)
		var img := Image.create(src.get_width() + grow * 2, src.get_height() + grow * 2, false, Image.FORMAT_RGBA8)
		for y in src.get_height():
			for x in src.get_width():
				if src.get_pixel(x, y).a > 0.5:
					img.set_pixel(x + grow, y + grow, color)
					if grow > 0:
						for d in [Vector2i(-grow, 0), Vector2i(grow, 0), Vector2i(0, -grow), Vector2i(0, grow)]:
							img.set_pixel(x + grow + d.x, y + grow + d.y, color)
		out.add_frame("default", ImageTexture.create_from_image(img), frames.get_frame_duration("default", i))
	_derived[key] = out
	return out

static func _fade_ramp(alpha: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, alpha))
	g.set_color(1, Color(1, 1, 1, 0))
	return g

static func _particle_quad(tex: Texture2D, size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	q.material = m
	return q

# Little black feathers that tumble off and drift down while it flaps
func _make_feathers() -> CPUParticles3D:
	# A proper little feather, with a lighter quill so it shows on dark walls
	var tex := MeshUtil.pixel_texture([
		"....o",
		"...oo",
		"..ooq",
		"..oqo",
		".ooqo",
		".oqoo",
		"ooqo.",
		"oqoo.",
		"oqo..",
		"qo...",
	], {"o": Color(0.1, 0.07, 0.16), "q": Color(0.45, 0.4, 0.55)})
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.emitting = false
	p.amount = Tuning.particles(12)
	p.lifetime = 2.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.4
	# Gravity must beat the damping, or a feather that has slowed to a stop just
	# hangs in the air (it looked like one stuck under the bird after a landing)
	p.gravity = Vector3(0, -2.6, 0)
	p.damping_min = 0.4
	p.damping_max = 0.9
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -200.0
	p.angular_velocity_max = 200.0
	p.color_ramp = _fade_ramp(1.0)
	p.mesh = _particle_quad(tex, 0.5)
	return p

# A small puff of dust at the feet when leaving the ground
func _puff() -> void:
	if not is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 10
	p.lifetime = 0.55
	p.direction = Vector3.UP
	p.spread = 85.0
	p.flatness = 0.6
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.4
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.gravity = Vector3(0, 0.6, 0)
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 1.2))
	p.scale_amount_curve = grow
	p.color_ramp = _fade_ramp(0.35)
	p.mesh = _particle_quad(MeshUtil.blob_texture(8, Color.WHITE), 0.45)
	(p.mesh.material as StandardMaterial3D).albedo_color = Color(0.85, 0.82, 0.8)
	get_parent().add_child(p)
	p.global_position = global_position + Vector3(0, 0.1, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)

# --- tightropes and rings ---------------------------------------------------------

# Falling onto a wire: grab it, push it down, scare off any crows sitting on it
func _try_wire(prev_pos: Vector3) -> bool:
	var hit := tower.wire_crossed(prev_pos, world_position())
	if hit.is_empty():
		return false
	wire = hit.wire
	wire_chunk = hit.chunk
	wire.tb = hit.t
	wire.dip_v += abs(vy) * 0.45
	wire_chunk.scare_wire(wire)
	grounded = true
	ground = {}
	vy = 0.0
	gliding = false
	fall_from = y
	squash = 0.6
	return true

func _ride_wire(delta: float, jump: bool) -> void:
	# Keep the bird on the wire as it moves along it
	var a2 := Vector2(wire.a.x, wire.a.z)
	var b2 := Vector2(wire.b.x, wire.b.z)
	var here := Vector2(sin(theta) * r, cos(theta) * r)
	var q := Geometry2D.get_closest_point_to_segment(here, a2, b2)
	var t: float = a2.distance_to(q) / max(a2.distance_to(b2), 0.01)
	if t <= 0.01 or t >= 0.99:
		_leave_wire()         # walked off an end
		return
	wire.tb = t
	var p := TowerChunk.wire_point(wire, t)
	theta = atan2(p.x, p.z)
	r = Vector2(p.x, p.z).length()
	y = p.y
	stamina = min(stamina + regen_rate * delta, max_stamina)
	if jump:
		# Launch: always free, and much higher if timed at the bottom of a bounce
		vy = Tuning.JUMP_SPEED + Tuning.WIRE_LAUNCH + max(wire.dip, 0.0) * Tuning.WIRE_DIP_BOOST
		wire.dip_v -= 4.0
		jump_buffer = 0.0
		flap_anim = 0.3
		squash = -0.8
		_leave_wire()
		jumped.emit()

func _leave_wire() -> void:
	wire = {}
	wire_chunk = null
	grounded = false
	fall_from = y

# Flying through a boost ring: a lift, a shove the way you're going, a sip of
# stamina
func _boost(rg: Dictionary) -> void:
	vy = max(vy, Tuning.RING_LIFT)
	var dir: float = sign(vt) if abs(vt) > 0.5 else rg.dir
	knock.x += dir * Tuning.RING_PUSH
	stamina = min(stamina + Tuning.RING_STAMINA, max_stamina)
	flap_anim = 0.3
	fall_from = y
	boosted.emit()
