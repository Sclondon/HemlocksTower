class_name OrbitCamera
extends Camera3D
# Orbits the tower to stay behind the bird's angle, looking in at the tower.
# The tower itself never moves, so light and weather stay put in the world.

const DISTANCE := 12.5               # from the bird's radius out to the lens
const HEIGHT := 2.2
const MIN_VIEW_WIDTH := 11.0
const MIN_VIEW_HEIGHT := 18.0         # bigger jumps need a taller view
const IDLE_DISTANCE := 19.0
const CINE_DISTANCE := 30.0

var player: Player
var cam_theta := 0.0
var cam_y := 0.0
var cam_r := 5.8                     # follows the bird in/out, so turrets frame the same
var distance := DISTANCE
var orbit_idle := false              # title screen: drift slowly round and up the tower
var idle_time := 0.0
var cine := false                    # cutscene: pulled well back, watching cine_y
var cine_y := 0.0
var shake := 0.0                     # 0..1, decays
var watch: Node3D                    # the boss: framed along with the bird
var tilt := 0.0                       # metres the look point rides above / below: up while climbing, down while dropping
const TILT_MAX := 3.5

func _ready() -> void:
	# A nearer near plane than the default: the depth buffer then has the
	# precision to keep far, closely layered things (tree crowns) apart
	near = 0.25

func snap() -> void:
	cam_theta = player.theta
	cam_y = player.y + 1.5
	cam_r = max(player.r, 5.0)
	distance = DISTANCE
	_apply()

func _process(delta: float) -> void:
	if player == null:
		return
	var want := DISTANCE
	if cine:
		cam_theta += delta * 0.22
		cam_y = lerp(cam_y, cine_y, 1.0 - exp(-3.0 * delta))
		cam_r = lerp(cam_r, 5.0, 1.0 - exp(-2.0 * delta))
		want = CINE_DISTANCE
	elif orbit_idle:
		# A slow crane shot: round the tower, rising and sinking again
		idle_time += delta
		cam_theta += delta * 0.09
		var rise := 16.0 * (0.5 - 0.5 * cos(idle_time * 0.06))
		cam_y = lerp(cam_y, player.y + 3.0 + rise, 1.0 - exp(-1.5 * delta))
		want = IDLE_DISTANCE
	else:
		var goal := player.theta
		var target := player.y + (1.5 if player.vy > -10.0 else -2.5)   # further ahead down in a long fall
		if watch and watch.is_visible_in_tree():
			# Turn part way toward the boss and pull back, so both are in shot
			var w := watch.global_position
			goal += wrapf(atan2(w.x, w.z) - player.theta, -PI, PI) * 0.5
			target = lerp(target, w.y + 3.0, 0.3)
			want = DISTANCE * 1.6
		cam_theta += wrapf(goal - cam_theta, -PI, PI) * (1.0 - exp(-5.0 * delta))
		var rate := 4.0 if target > cam_y else 7.0
		cam_y = lerp(cam_y, target, 1.0 - exp(-rate * delta))
		cam_r = lerp(cam_r, max(player.r, 5.0), 1.0 - exp(-3.0 * delta))
	# Tip the view a little the way the bird is heading (not in cutscenes / menus)
	var lean: float = 0.0 if cine or orbit_idle else clamp(player.vy / 12.0, -1.0, 1.0) * TILT_MAX
	tilt = lerp(tilt, lean, 1.0 - exp(-2.5 * delta))
	distance = lerp(distance, want, 1.0 - exp(-1.5 * delta))
	shake = max(shake - delta * 0.6, 0.0)
	_apply()

func _apply() -> void:
	var size := get_viewport().get_visible_rect().size
	var aspect: float = size.x / max(size.y, 1.0)
	var needed_h: float = max(MIN_VIEW_HEIGHT, MIN_VIEW_WIDTH / aspect)
	fov = clamp(rad_to_deg(2.0 * atan(needed_h * 0.5 / DISTANCE)), 40.0, 100.0)
	var radius := cam_r + distance
	var dir := Vector3(sin(cam_theta), 0, cos(cam_theta))
	position = dir * radius + Vector3(0, cam_y + HEIGHT, 0)
	look_at(Vector3(0, cam_y + 0.8 + tilt, 0) + dir * 1.5, Vector3.UP)
	if shake > 0.0:
		var s := shake * shake * 0.5
		position += Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))
