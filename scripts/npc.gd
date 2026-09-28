class_name Npc
extends Node3D
# A crow on a ledge. Talkers say something strange in a speech
# bubble when you come close; the quiet ones hop about their ledge instead.
# Either way they turn to look at you.

const IDLE_FRAMES := preload("res://animations/player_idle_SF.tres")
const TALK_RANGE := 6.5

const FIRST_LINE := "Up. It's always up."
const LINES := [
	"The top was here yesterday.",
	"I counted the steps once. There were more on the way down.",
	"Do the windows watch you, or look through you?",
	"Hemlock built this for someone who never came back down.",
	"Every feather you drop becomes a bird somewhere below.",
	"The tower grows when nobody is looking. Stop looking.",
	"Some rooms hang from nothing at all. Don't ask what holds them.",
	"The clouds remember everyone who passes through.",
	"Above the aurora there is a door. Behind it, more tower.",
	"Don't eat the purple ones. I did. I'm still here. Mostly.",
	"The wind speaks backwards up here.",
	"When the air rises, open your wings and let it carry you.",
	"The storm birds aren't birds.",
	"I was a pigeon once. Then I climbed.",
	"Have you seen my shadow? It left a few floors down.",
	"Seeds grow back. Feathers don't. Neither do crows.",
	"If you fall, fall toward something.",
	"The bells stopped ringing when the stairs came.",
	"Down is only a suggestion.",
	"The glass remembers colours the sun forgot.",
	"You're not the first crow to climb. You're the first to keep going.",
	"Listen, between the thunder. Something is knocking.",
	"Sinking air is heavy with old secrets. Fly around it.",
	"Hemlock is still up there. Somewhere. Waiting.",
]

# Other crows: black, just tinted a little (grey, blue or brown) so they
# don't look like you
const TINTS := {
	"crow_grey": Color(0.3, 0.3, 0.34),
	"crow_blue": Color(0.22, 0.25, 0.34),
	"crow_brown": Color(0.32, 0.27, 0.26),
}

static var _frames := {}

var data: Dictionary
var surface: Dictionary              # the ledge it stands on (for hopping about)
var line: String
var sprite: Node3D
var bubble: SpeechBubble
var hop_timer := 0.0
var hop_t := 1.0
var hop_from := Vector3.ZERO
var hop_to := Vector3.ZERO
var roam := 0.0                      # hops about within this far of home (crows on the open ground)
var home := Vector3.ZERO

func setup(d: Dictionary, on: Dictionary) -> void:
	data = d
	surface = on
	line = d.get("text", FIRST_LINE if d.line < 0 else LINES[d.line % LINES.size()])
	roam = d.get("roam", 0.0)
	hop_timer = randf_range(1.0, 4.0)
	name = "Npc_" + String(d.id).replace(":", "_")
	var s := AnimatedSprite3D.new()
	s.sprite_frames = recoloured(IDLE_FRAMES, TINTS.get(d.kind, TINTS.crow_grey))
	s.offset = Vector2(0, 7)
	s.play("default")
	s.speed_scale = randf_range(0.6, 1.0)
	sprite = s
	var base := sprite as SpriteBase3D
	base.pixel_size = 0.085
	base.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	base.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	base.shaded = false
	base.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	add_child(sprite)
	if d.get("talks", false):
		bubble = SpeechBubble.new()
		bubble.setup(line)
		bubble.position = Vector3(0, 1.5, 0)
		add_child(bubble)

func tick(delta: float, player_pos: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var right := cam.global_transform.basis.x
	# Out in the hub a crow can wander right in front of the lens: step out of shot
	sprite.visible = global_position.distance_to(cam.global_position) > 5.0
	if bubble:
		bubble.tick(delta, global_position.distance_to(player_pos) < TALK_RANGE)
	elif roam > 0.0 or (not surface.is_empty() and not surface.get("broken", false)):
		_wander(delta, right)
		if hop_t < 1.0:
			return
	# Turn toward the player as seen on screen (the art faces left)
	(sprite as SpriteBase3D).flip_h = (player_pos - global_position).dot(right) > 0.0

# Every few seconds, hop to another spot on the same ledge
func _wander(delta: float, right: Vector3) -> void:
	if hop_t < 1.0:
		hop_t = min(hop_t + delta / 0.35, 1.0)
		position = hop_from.lerp(hop_to, hop_t) + Vector3(0, sin(hop_t * PI) * 0.45, 0)
		return
	hop_timer -= delta
	if hop_timer > 0.0:
		return
	hop_timer = randf_range(1.5, 4.5)
	hop_from = position
	if home == Vector3.ZERO:
		home = position
	if roam > 0.0:
		# Pecking about in the grass: short hops, never far from home
		var target := home + Vector3(randf_range(-roam, roam), 0, randf_range(-roam, roam))
		hop_to = position + (target - position).limit_length(0.9)
		hop_timer = randf_range(0.4, 2.2)
	else:
		hop_to = _spot_on(surface)
	hop_t = 0.0
	(sprite as SpriteBase3D).flip_h = (hop_to - hop_from).dot(right) > 0.0

# A random standing spot on a surface, in the chunk's space
static func _spot_on(s: Dictionary) -> Vector3:
	var top: float = s.get("base_top", s.top)
	if ChunkPlanner.is_outer(s):
		var off: Vector2 = Vector2.from_angle(randf() * TAU) * randf() * s.radius * 0.55
		return Vector3(s.cx + off.x, top, s.cz + off.y)
	var a: float = lerp(s.a0, s.a1, randf_range(0.15, 0.85))
	var r := TowerShape.wall_r(s.k, a, randf_range(0.5, max(0.6, s.d1 - 0.4)))
	return Vector3(sin(a) * r, top, cos(a) * r)

# A crow animation recoloured: its dark body takes the tint, shaded by the
# original brightness; the red eye stays
static func recoloured(frames: SpriteFrames, tint: Color) -> SpriteFrames:
	var key := "%s|%s" % [frames.resource_path, tint.to_html()]
	if _frames.has(key):
		return _frames[key]
	var out := SpriteFrames.new()
	out.set_animation_speed("default", frames.get_animation_speed("default"))
	for i in frames.get_frame_count("default"):
		var img := frames.get_frame_texture("default", i).get_image()
		img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a < 0.5 or c.r > c.g + 0.3:
					continue
				var shade: float = clamp(0.55 + c.get_luminance() * 2.5, 0.4, 1.3)
				img.set_pixel(x, y, Color(tint.r * shade, tint.g * shade, tint.b * shade, c.a))
		out.add_frame("default", ImageTexture.create_from_image(img))
	_frames[key] = out
	return out
