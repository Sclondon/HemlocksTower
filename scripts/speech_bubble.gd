class_name SpeechBubble
extends Node3D
# A speech bubble for a crow. Where it hangs is 3D (this node sits above the
# crow's head), but it's drawn flat on the UI overlay at full resolution: the
# 3D view renders at half size, and text written into it came out soft,
# see-through and hard to read. The balloon tracks its crow on screen, pops
# open / shut, and keeps inside the screen edges.

static var overlay: Control          # the UI layer bubbles draw on (set by the game)
static var view_scale := 1.0         # overlay pixels per 3D-view pixel

const FONT_SIZE := 22
const MAX_WIDTH := 320.0             # wrap width, in overlay pixels
const TAIL := 12.0
const MARGIN := 8.0                  # kept this far inside the screen edges
const PAPER := Color(1.0, 0.97, 0.9)
const EDGE := Color(0.15, 0.08, 0.2)
const INK := Color(0.12, 0.06, 0.16)

var box: Control                     # the balloon and its tail, on the overlay
var panel: PanelContainer
var label: Label
var openness := 0.0
var want := false
var hold := 0.0                      # seconds left on a timed line (say)
var ticked_at := -10                 # frame of the last tick: an untended bubble hides

# The balloon's tail, drawn under its middle and pointing down at the crow
class Tail extends Control:
	func _draw() -> void:
		var w := size.x
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w * 0.5, size.y)]), PAPER)
		draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.5, size.y), Vector2(w, 0)]), EDGE, 3.0)

# Show `text` for `seconds` (for crows that pipe up now and then)
func say(text: String, seconds := 3.0) -> void:
	setup(text)
	hold = seconds

func setup(text: String) -> void:
	if box == null:
		_build()
	label.text = text
	# Size it by hand: an autowrapping label only learns its height after a
	# layout pass, and until then the balloon comes out tall and narrow
	var font: Font = label.get_theme_font("font")
	var one_line := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var width: float = ceil(min(one_line + 4.0, MAX_WIDTH))
	var height := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width, FONT_SIZE, -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND).y
	label.custom_minimum_size = Vector2(width, ceil(height))
	label.size = label.custom_minimum_size
	var style := panel.get_theme_stylebox("panel")
	panel.size = label.custom_minimum_size + style.get_minimum_size()
	label.position = Vector2(style.content_margin_left, style.content_margin_top)

func _build() -> void:
	box = Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = EDGE
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	box.add_child(panel)
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	var tail := Tail.new()
	tail.name = "Tail"
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.size = Vector2(TAIL * 1.6, TAIL)
	box.add_child(tail)
	if overlay:
		overlay.add_child(box)

func _exit_tree() -> void:
	if box:
		box.queue_free()
		box = null

func tick(delta: float, want_open: bool) -> void:
	ticked_at = Engine.get_process_frames()
	hold = max(hold - delta, 0.0)
	want = want_open or hold > 0.0
	openness = move_toward(openness, 1.0 if want else 0.0, delta * 6.0)

func _process(_delta: float) -> void:
	if box == null:
		return
	if box.get_parent() == null and overlay:
		overlay.add_child(box)          # (built before the overlay existed)
	var cam := get_viewport().get_camera_3d()
	var shown := openness > 0.01 and cam != null and is_visible_in_tree() \
		and Engine.get_process_frames() - ticked_at <= 2 and not cam.is_position_behind(global_position)
	box.visible = shown
	if not shown:
		return
	panel.reset_size()                # (shrinks back to fit, if it grew while laying out)
	var size := panel.size
	var tail: Control = box.get_node("Tail")
	tail.position = Vector2(size.x * 0.5 - tail.size.x * 0.5, size.y - 3.0)
	# Tail tip on the spot above the crow's head, the balloon kept on screen
	var tip := cam.unproject_position(global_position) * view_scale
	var screen := overlay.size if overlay else Vector2(1e6, 1e6)
	var left: float = clamp(tip.x - size.x * 0.5, MARGIN, max(MARGIN, screen.x - size.x - MARGIN))
	box.position = Vector2(left, tip.y - size.y - TAIL + 3.0)
	tail.position.x = clamp(tip.x - left - tail.size.x * 0.5, 8.0, size.x - tail.size.x - 8.0)
	# A little overshoot as it pops open, from the tail's tip
	var s: float = ease(openness, 0.4) * (1.0 + 0.12 * sin(openness * PI))
	box.pivot_offset = Vector2(tail.position.x + tail.size.x * 0.5, size.y + TAIL - 3.0)
	box.scale = Vector2.ONE * max(s, 0.01)
	box.modulate.a = clamp(openness * 2.0, 0.0, 1.0)
