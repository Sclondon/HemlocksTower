class_name Hud
extends Control
# Height, best height, band banner, lightning flash and the stamina border.

signal pause_pressed

const BORDER := 12.0                 # stamina runs round the screen edge, this thick

var height_label: Label
var best_label: Label
var banner: Label
var flash_rect: ColorRect
var meter: Control
var pause_button: Button

var stamina := Tuning.BASE_STAMINA
var max_stamina := Tuning.BASE_STAMINA
var deny_time := 0.0
var pulse_time := 0.0                # border flash after a pickup
var powers := {}
var power_row: Control

const POWER_NAMES := {
	"sunseed": "Sun Seed: endless stamina!", "spring": "Spring Berry: super jumps!",
	"cloud": "Cloud Puff: feather-light falls!", "charm": "Crow's Charm: treasure comes to you!",
}
var pulse_color := Color.WHITE
var banner_time := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	flash_rect = ColorRect.new()
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_rect)

	height_label = make_label(48, Color(1, 0.88, 0.6))
	height_label.add_theme_font_override("font", Menus.display_font(800))
	_anchor(height_label, Vector4(0, 0, 1, 0), Vector4(0, 14, 0, 74))
	add_child(height_label)

	best_label = make_label(20, Color(0.85, 0.78, 0.98))
	_anchor(best_label, Vector4(0, 0, 1, 0), Vector4(0, 72, 0, 100))
	add_child(best_label)

	banner = make_label(30, Color(1, 1, 1))
	_anchor(banner, Vector4(0, 0.3, 1, 0.3), Vector4(0, -25, 0, 25))
	banner.modulate.a = 0.0
	add_child(banner)

	meter = Control.new()
	_anchor(meter, Vector4(0, 0, 1, 1), Vector4.ZERO)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.draw.connect(_draw_meter)
	meter.resized.connect(meter.queue_redraw)
	add_child(meter)

	# Active power-ups: an icon each, with a draining bar under it
	power_row = Control.new()
	power_row.position = Vector2(24, 24)
	power_row.size = Vector2(240, 60)
	power_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_row.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	power_row.draw.connect(_draw_powers)
	add_child(power_row)

	pause_button = Button.new()
	pause_button.text = "II"
	pause_button.add_theme_font_size_override("font_size", 26)
	_anchor(pause_button, Vector4(1, 0, 1, 0), Vector4(-72, 16, -16, 72))
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.pressed.connect(func(): pause_pressed.emit())
	add_child(pause_button)

# anchors / offsets as (left, top, right, bottom)
static func _anchor(c: Control, anchors: Vector4, offsets: Vector4) -> void:
	c.anchor_left = anchors.x
	c.anchor_top = anchors.y
	c.anchor_right = anchors.z
	c.anchor_bottom = anchors.w
	c.offset_left = offsets.x
	c.offset_top = offsets.y
	c.offset_right = offsets.z
	c.offset_bottom = offsets.w

static func make_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.03, 0.12))
	l.add_theme_constant_override("outline_size", max(6, font_size / 5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

var _shown := []

# (Only touch the labels when the numbers change: re-laying-out text every
# frame adds up on phones)
func set_heights(height: float, best: float, status := "") -> void:
	var now := [int(max(height, 0.0)), int(best), status]
	if now == _shown:
		return
	_shown = now
	height_label.text = "%d m" % now[0]
	if status != "":
		best_label.text = status
	else:
		best_label.text = "Best  %d m" % now[1] if best > 0.0 else ""

func set_stamina(value: float, bucket: float) -> void:
	if abs(value - stamina) > 0.001 or bucket != max_stamina:
		stamina = value
		max_stamina = bucket
		meter.queue_redraw()

func deny() -> void:
	deny_time = 0.35
	meter.queue_redraw()

# The border flashes: green for a seed, purple for poison, gold for a feather
func pickup(kind: String) -> void:
	pulse_time = 0.6
	pulse_color = {"plume": Color(0.85, 0.92, 1.0, 0.8), "poison": Color(0.7, 0.2, 0.9, 0.85)}.get(kind, Color(1, 0.9, 0.4, 0.8))
	meter.queue_redraw()

func set_powers(p: Dictionary) -> void:
	if p.is_empty() and powers.is_empty():
		return
	powers = p.duplicate()
	power_row.queue_redraw()
	meter.queue_redraw()

func _draw_powers() -> void:
	var x := 0.0
	for kind in powers:
		var tex := TowerChunk._texture_for(kind)
		power_row.draw_texture_rect(tex, Rect2(x, 0, 36, 36), false)
		var left: float = clamp(powers[kind] / Tuning.POWER_TIME[kind], 0.0, 1.0)
		power_row.draw_rect(Rect2(x, 40, 36, 6), Color(0.08, 0.04, 0.12, 0.7))
		power_row.draw_rect(Rect2(x, 40, 36 * left, 6), TowerChunk.GLOWS[kind])
		x += 46.0

func show_banner(text: String) -> void:
	banner.text = text
	banner_time = 3.0

func flash() -> void:
	flash_rect.color = Color(1, 1, 1, 0.45)

func _process(delta: float) -> void:
	flash_rect.color.a = max(flash_rect.color.a - delta * 1.8, 0.0)
	banner_time = max(banner_time - delta, 0.0)
	banner.modulate.a = clamp(banner_time, 0.0, 1.0) * clamp((3.0 - banner_time) * 3.0, 0.0, 1.0)
	if pulse_time > 0.0:
		pulse_time -= delta
		meter.queue_redraw()
	if deny_time > 0.0:
		deny_time -= delta
		meter.queue_redraw()

# The border fills from the bottom centre up both sides at once, meeting at
# the top centre when full. Notches mark each flap's worth; a bigger bucket
# (from gold feathers) just means more notches round the same border.
func _draw_meter() -> void:
	var s := meter.size
	var b := BORDER
	# Right-hand half of the loop; the left half is its mirror image
	var pts: Array[Vector2] = [Vector2(s.x * 0.5, s.y - b * 0.5), Vector2(s.x - b * 0.5, s.y - b * 0.5), Vector2(s.x - b * 0.5, b * 0.5), Vector2(s.x * 0.5, b * 0.5)]
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var frac: float = clamp(stamina / max_stamina, 0.0, 1.0)
	var deny := deny_time > 0.0 and int(deny_time * 20.0) % 2 == 0
	var empty := Color(0.08, 0.04, 0.12, 0.55)
	var fill_c := Color(1.0, 0.8, 0.25, 0.9) if stamina >= Tuning.FLAP_COST else Color(0.9, 0.4, 0.15, 0.9)
	if powers.has("sunseed"):
		# Endless stamina: the border shimmers white-gold
		fill_c = Color(1.0, 0.85, 0.4).lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
	if deny:
		empty = Color(0.8, 0.1, 0.1, 0.7)
	elif pulse_time > 0.0:
		empty = pulse_color
		empty.a *= clamp(pulse_time / 0.6, 0.0, 1.0)
	for mirror in [false, true]:
		_border_run(pts, 0.0, total, b, empty, mirror)
		_border_run(pts, 0.0, frac * total, b - 4.0, fill_c, mirror)
		var notch := Tuning.FLAP_COST
		while notch < max_stamina - 1.0:
			var at := notch / max_stamina * total
			_border_run(pts, at - 1.5, at + 1.5, b, Color(0.08, 0.04, 0.12, 0.9), mirror)
			notch += Tuning.FLAP_COST

# Draws the stretch [t0, t1] (in pixels along the half-loop) as a thick band
func _border_run(pts: Array[Vector2], t0: float, t1: float, thick: float, color: Color, mirror: bool) -> void:
	var w := meter.size.x
	var along := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var c := pts[i + 1]
		var seg := a.distance_to(c)
		var s0: float = clamp(t0 - along, 0.0, seg)
		var s1: float = clamp(t1 - along, 0.0, seg)
		along += seg
		if s1 <= s0:
			continue
		var p := a.lerp(c, s0 / seg)
		var q := a.lerp(c, s1 / seg)
		if mirror:
			p.x = w - p.x
			q.x = w - q.x
		var r := Rect2(p, Vector2.ZERO).expand(q).grow(thick * 0.5)
		meter.draw_rect(r, color)

# --- the boss fight: Hemlock's wind-down bar, and the bird's hearts ------------

var boss_view: Control
var boss_left := 1.0                 # fraction of Hemlock still wound
var hearts := 0
var hurt_time := 0.0

func set_boss(on: bool, left: float, heart_count: int) -> void:
	if boss_view == null:
		boss_view = Control.new()
		boss_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		boss_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		boss_view.draw.connect(_draw_boss)
		add_child(boss_view)
		var name_label := make_label(20, Color(1, 0.8, 0.44))
		name_label.add_theme_font_override("font", Menus.display_font(800, 4))
		name_label.text = "HEMLOCK"
		_anchor(name_label, Vector4(0, 0, 1, 0), Vector4(0, 18, 0, 44))
		boss_view.add_child(name_label)
	boss_view.visible = on
	height_label.visible = not on
	best_label.visible = not on
	if left != boss_left or heart_count != hearts:
		boss_left = left
		hearts = heart_count
		boss_view.queue_redraw()

func hurt() -> void:
	hurt_time = 0.5
	flash_rect.color = Color(1, 0.1, 0.1, 0.35)
	boss_view.queue_redraw()

func _draw_boss() -> void:
	var w := minf(320.0, boss_view.size.x - 140.0)
	var bar := Rect2((boss_view.size.x - w) * 0.5, 50, w, 12)
	boss_view.draw_rect(bar.grow(3), Color(0.08, 0.04, 0.12, 0.8))
	boss_view.draw_rect(Rect2(bar.position, Vector2(w * boss_left, bar.size.y)), Color(1.0, 0.7, 0.3))
	for i in range(1, 3):
		var x := bar.position.x + w * i / 3.0
		boss_view.draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0.08, 0.04, 0.12), 2.0)
	# Hearts, top left, drawn as chunky pixel hearts
	var shape := ["01100110", "11111111", "11111111", "01111110", "00111100", "00011000"]
	for h in BossFight.HEARTS:
		var col := Color(0.95, 0.25, 0.3) if h < hearts else Color(0.2, 0.12, 0.2, 0.7)
		for row in shape.size():
			for c in 8:
				if shape[row][c] == "1":
					boss_view.draw_rect(Rect2(24 + h * 40 + c * 4, 24 + row * 4, 4, 4), col)
