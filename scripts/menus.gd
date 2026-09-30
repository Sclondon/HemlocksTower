class_name Menus
extends Control
# Every full-screen menu: the title, section select, how to play, pause and
# the results after a climb, plus big captions for the summit cinematic.
# One screen shows at a time; buttons work with mouse, touch, keys and pads.

signal continue_pressed
signal section_chosen(index: int)
signal play_pressed
signal sections_closed               # the blue cauldron's list was backed out of
signal prompt_answered(yes: bool)
signal title_pressed
signal resume_pressed
signal end_pressed
signal primary_pressed               # results: "Climb On" / "Climb Again" ...
signal menu_pressed                  # results: back to the meadow

const VIGNETTE := preload("res://shaders/vignette.gdshader")
const CINZEL := preload("res://fonts/Cinzel.ttf")
const BODY := preload("res://fonts/AlegreyaSans-Regular.ttf")
const BODY_BOLD := preload("res://fonts/AlegreyaSans-Bold.ttf")

const PARCHMENT := Color(0.93, 0.87, 0.77)
const GOLD := Color(1.0, 0.8, 0.44)
const DIM := Color(0.75, 0.72, 0.85, 0.8)
const INK := Color(0.07, 0.03, 0.1)
const NUMERALS := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

var screens := {}                    # name -> Control
var current := ""
var shade: ColorRect
var caption: VBoxContainer
var caption_title: Label
var caption_sub: Label
var continue_button: Button
var section_box: VBoxContainer
var footer: Label
var pause_line: Label
var results: Dictionary = {}         # the results screen's parts
var back_to := "title"               # where "Back" goes from how-to-play

static func display_font(weight := 600, spacing := 0) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = CINZEL
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	f.spacing_glyph = spacing
	return f

static func body_font(bold := false, spacing := 0) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = BODY_BOLD if bold else BODY
	f.spacing_glyph = spacing
	return f

# The look shared by the menus and the HUD
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 20
	t.set_font("font", "Button", display_font(600, 2))
	t.set_font_size("font_size", "Button", 25)
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_focus_color", "Button", GOLD)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.5, 0.6, 0.6))
	t.set_color("font_outline_color", "Button", INK)
	t.set_constant("outline_size", "Button", 6)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.03, 0.09, 0.0)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var lit := normal.duplicate() as StyleBoxFlat
	lit.bg_color = Color(0.1, 0.05, 0.13, 0.62)
	lit.border_color = Color(GOLD, 0.75)
	lit.border_width_top = 1
	lit.border_width_bottom = 1
	lit.corner_radius_top_left = 2
	lit.corner_radius_top_right = 2
	lit.corner_radius_bottom_left = 2
	lit.corner_radius_bottom_right = 2
	var pressed := lit.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.2, 0.1, 0.12, 0.75)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("disabled", "Button", normal)
	t.set_stylebox("hover", "Button", lit)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	var card := StyleBoxFlat.new()
	card.bg_color = Color(0.06, 0.03, 0.09, 0.78)
	card.border_color = Color(GOLD, 0.3)
	card.set_border_width_all(1)
	card.set_corner_radius_all(6)
	card.set_content_margin_all(26)
	t.set_stylebox("panel", "PanelContainer", card)
	return t

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = make_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = VIGNETTE
	shade.material = m
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.visible = false
	add_child(shade)

	_build_title()
	_build_sections()
	_build_howto()
	_build_pause()
	_build_results()
	_build_prompt()
	_build_caption()

# --- building blocks ------------------------------------------------------------

func _screen(key: String) -> VBoxContainer:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	screens[key] = root
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	return col

func _label(text: String, font: Font, size: int, color: Color, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _heading(col: Container, text: String, sub := "") -> void:
	col.add_child(_label(text, display_font(800, 4), 44, GOLD, 10))
	col.add_child(_ornament())
	if sub != "":
		var s := _label(sub, body_font(), 19, DIM, 4)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size.x = 420
		col.add_child(_centered(s))

func _button(col: Container, text: String, action: Callable, width := 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 58)
	b.pressed.connect(action)
	# Mouse and keys share one highlight: hovering moves the focus
	b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
	b.focus_entered.connect(func(): b.add_theme_stylebox_override("normal", theme.get_stylebox("hover", "Button")))
	b.focus_exited.connect(func(): b.remove_theme_stylebox_override("normal"))
	col.add_child(_centered(b))
	return b

func _centered(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.add_child(c)
	return cc

func _gap(col: Container, h: float) -> void:
	var g := Control.new()
	g.custom_minimum_size.y = h
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(g)

# A thin rule with a diamond in the middle
func _ornament(width := 260.0) -> Control:
	var o := Control.new()
	o.custom_minimum_size = Vector2(width, 18)
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	o.draw.connect(func():
		var mid := o.size * 0.5
		var c := Color(GOLD, 0.7)
		o.draw_line(Vector2(0, mid.y), Vector2(mid.x - 14, mid.y), c, 1.0)
		o.draw_line(Vector2(mid.x + 14, mid.y), Vector2(o.size.x, mid.y), c, 1.0)
		o.draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -6), mid + Vector2(6, 0), mid + Vector2(0, 6), mid + Vector2(-6, 0)]), GOLD)
		o.draw_circle(Vector2(0, mid.y), 2.0, c)
		o.draw_circle(Vector2(o.size.x, mid.y), 2.0, c))
	return o

# --- screens ----------------------------------------------------------------------

func _build_title() -> void:
	var col := _screen("title")
	var top := Control.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.size_flags_stretch_ratio = 0.6
	col.add_child(top)
	col.add_child(_label("HEMLOCK'S", display_font(700, 14), 34, PARCHMENT, 8))
	var logo := _label("TOWER", display_font(900, 6), 108, GOLD, 16)
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	logo.add_theme_constant_override("shadow_offset_y", 6)
	logo.add_theme_constant_override("shadow_offset_x", 0)
	col.add_child(logo)
	col.add_child(_ornament(300))
	col.add_child(_label("HOW HIGH CAN A SMALL BIRD CLIMB?", body_font(true, 4), 17, DIM, 4))
	_gap(col, 44)
	continue_button = _button(col, "Continue", func(): continue_pressed.emit(), 360)
	_button(col, "Play", func(): play_pressed.emit(), 360)
	_button(col, "How to Play", func(): back_to = "title"; show_screen("howto"), 360)
	var bottom := Control.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(bottom)
	footer = _label("", body_font(true, 3), 15, DIM, 4)
	col.add_child(footer)

func _build_sections() -> void:
	var col := _screen("sections")
	_heading(col, "THE WANDERING STEW", "Where shall the brew take you? The foot of any section you've reached. Each ends at a summit beacon; reach it and the tower grows.")
	_gap(col, 8)
	section_box = VBoxContainer.new()
	section_box.add_theme_constant_override("separation", 4)
	col.add_child(_centered(section_box))
	_gap(col, 8)
	_button(col, "Back", func(): sections_closed.emit())

func _build_howto() -> void:
	var col := _screen("howto")
	_heading(col, "HOW TO CLIMB")
	_gap(col, 6)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 10)
	var rows := [
		["A / D", "Around the tower"], ["W / S", "In toward the wall, and out"],
		["Space", "Jump, then press again to flap"], ["Hold Space", "Glide on the way down"],
		["Esc", "Pause"], ["Phone", "Left thumb steers, right thumb jumps"],
	]
	for row in rows:
		var k := _label(row[0], display_font(700, 1), 19, GOLD, 5)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(k)
		var v := _label(row[1], body_font(), 20, PARCHMENT, 5)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(v)
	col.add_child(_centered(grid))
	_gap(col, 10)
	var tips := _label("Flaps and glides spend stamina, the gold border round the screen. Stand on a ledge to get it back. "
		+ "Gold feathers make it bigger; loose feathers (crows drop them) top it up; purple berries are poison. "
		+ "Jump into a wind stream and it carries you.\n\n"
		+ "Climb each section to the beacon at its summit. In the meadow, jump into the blue stew to travel to any section "
		+ "you've reached, or the green stew for Endless: a fresh tower every time, where a fall of more than %d m ends the run."
		% int(Tuning.ENDLESS_FALL), body_font(), 18, DIM, 4)
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tips.custom_minimum_size.x = 440
	col.add_child(_centered(tips))
	_gap(col, 12)
	_button(col, "Back", func(): show_screen(back_to))

func _build_pause() -> void:
	var col := _screen("pause")
	_heading(col, "PAUSED")
	pause_line = _label("", body_font(true, 3), 17, DIM, 4)
	col.add_child(pause_line)
	_gap(col, 20)
	_button(col, "Resume", func(): resume_pressed.emit())
	_button(col, "How to Play", func(): back_to = "pause"; show_screen("howto"))
	results.end_button = _button(col, "End Climb", func(): end_pressed.emit())
	_button(col, "Title Screen", func(): title_pressed.emit())

func _build_results() -> void:
	var col := _screen("results")
	results.title = _label("", display_font(800, 4), 44, GOLD, 10)
	results.title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(results.title)
	col.add_child(_ornament())
	results.sub = _label("", body_font(true, 3), 19, PARCHMENT, 5)
	col.add_child(results.sub)
	_gap(col, 12)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 380
	results.grid = GridContainer.new()
	results.grid.columns = 2
	results.grid.add_theme_constant_override("h_separation", 40)
	results.grid.add_theme_constant_override("v_separation", 12)
	card.add_child(results.grid)
	col.add_child(_centered(card))
	results.note = _label("", body_font(), 18, DIM, 4)
	results.note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	results.note.custom_minimum_size.x = 420
	col.add_child(_centered(results.note))
	_gap(col, 14)
	results.primary = _button(col, "", func(): primary_pressed.emit())
	_button(col, "Back to the Meadow", func(): menu_pressed.emit(), 360)

var prompt_title: Label
var prompt_body: Label
var prompt_yes: Button
var prompt_no: Button

# A yes / no question in a card (the cauldrons and Hemlock ask them)
func _build_prompt() -> void:
	var col := _screen("prompt")
	prompt_title = _label("", display_font(800, 4), 40, GOLD, 10)
	prompt_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(prompt_title)
	col.add_child(_ornament())
	_gap(col, 6)
	prompt_body = _label("", body_font(), 20, PARCHMENT, 5)
	prompt_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_body.custom_minimum_size.x = 420
	col.add_child(_centered(prompt_body))
	_gap(col, 18)
	prompt_yes = _button(col, "", func(): prompt_answered.emit(true))
	prompt_no = _button(col, "", func(): prompt_answered.emit(false))

func show_prompt(title: String, body: String, yes: String, no: String) -> void:
	prompt_title.text = title
	prompt_body.text = body
	prompt_yes.text = yes
	prompt_no.text = no
	show_screen("prompt")

func _build_caption() -> void:
	caption = VBoxContainer.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.alignment = BoxContainer.ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.modulate.a = 0.0
	add_child(caption)
	caption_title = _label("", display_font(900, 4), 52, GOLD, 12)
	caption_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_child(caption_title)
	caption_sub = _label("", body_font(true, 4), 20, PARCHMENT, 6)
	caption.add_child(caption_sub)

# --- showing things ---------------------------------------------------------------

func show_screen(key: String) -> void:
	for k in screens:
		screens[k].visible = k == key
	current = key
	shade.visible = key != ""
	var mat := shade.material as ShaderMaterial
	mat.set_shader_parameter("base", 0.15 if key == "title" else 0.5)
	if key == "":
		return
	var s: Control = screens[key]
	s.modulate.a = 0.0
	create_tween().tween_property(s, "modulate:a", 1.0, 0.35)
	# Focus the first button that can take it (for keys and pads)
	var first := _first_button(s)
	if first:
		first.grab_focus()

func hide_all() -> void:
	show_screen("")

func _first_button(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and c.visible and not c.disabled and c.is_visible_in_tree():
			return c
		var b := _first_button(c)
		if b:
			return b
	return null

# info: continue_text ("" = no saved climb), cleared, sections, endless_best
func show_title(info: Dictionary) -> void:
	continue_button.get_parent().visible = info.continue_text != ""
	continue_button.text = info.continue_text
	var parts: Array[String] = ["SECTIONS  %d / %d" % [info.cleared, info.sections]]
	if info.endless_best > 0:
		parts.append("ENDLESS BEST  %d M" % info.endless_best)
	footer.text = "    ·    ".join(parts)
	show_screen("title")

# The list of sections: cleared ones show their best time, the next one is
# open, the rest are locked
func set_sections(names: Array, cleared: int, times: Dictionary) -> void:
	for c in section_box.get_children():
		c.queue_free()
	for i in names.size():
		var open := i <= cleared
		var b := Button.new()
		b.custom_minimum_size = Vector2(460, 62)
		b.disabled = not open
		b.pressed.connect(func(): section_chosen.emit(i))
		b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
		b.focus_entered.connect(func(): b.add_theme_stylebox_override("normal", theme.get_stylebox("hover", "Button")))
		b.focus_exited.connect(func(): b.remove_theme_stylebox_override("normal"))
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 18
		row.offset_right = -18
		row.add_theme_constant_override("separation", 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var num := _label(NUMERALS[i], display_font(800), 22, GOLD if open else DIM, 5)
		num.custom_minimum_size.x = 44
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(num)
		var text := VBoxContainer.new()
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		text.add_theme_constant_override("separation", -2)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(text)
		var name := _label(names[i] if open else "Locked", display_font(600, 1), 20, PARCHMENT if open else DIM, 5)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.add_child(name)
		var detail := "%d – %d m" % [i * TowerShape.BAND_H, (i + 1) * TowerShape.BAND_H]
		if not open:
			detail = "Reach the summit below to open it"
		elif times.has(str(i)):
			detail += "   ·   best " + clock(times[str(i)])
		var d := _label(detail, body_font(), 16, DIM, 4)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.add_child(d)
		var mark := _label("CLEARED" if times.has(str(i)) else "", body_font(true, 3), 13, Color(GOLD, 0.8), 4)
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(mark)
		section_box.add_child(b)

func show_pause(line: String, end_text := "") -> void:
	pause_line.text = line
	results.end_button.text = end_text
	results.end_button.get_parent().visible = end_text != ""
	show_screen("pause")

# data: title, sub, rows ([[label, value], ...]), note, primary ("" hides it)
func show_results(data: Dictionary) -> void:
	results.title.text = data.title
	results.sub.text = data.get("sub", "")
	for c in results.grid.get_children():
		c.queue_free()
	for row in data.rows:
		var k := _label(String(row[0]).to_upper(), body_font(true, 3), 16, DIM, 4)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		results.grid.add_child(k)
		var v := _label(row[1], display_font(700), 22, GOLD if row.size() > 2 and row[2] else PARCHMENT, 5)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		results.grid.add_child(v)
	results.note.text = data.get("note", "")
	results.note.visible = results.note.text != ""
	results.primary.text = data.get("primary", "")
	results.primary.get_parent().visible = results.primary.text != ""
	show_screen("results")

# Big words in the middle of the screen that fade in and out
func show_caption(title: String, sub := "", hold := 2.0) -> void:
	caption_title.text = title
	caption_sub.text = sub
	var t := create_tween()
	t.tween_property(caption, "modulate:a", 1.0, 0.4)
	t.tween_interval(hold)
	t.tween_property(caption, "modulate:a", 0.0, 0.6)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if current == "sections":
		sections_closed.emit()
	elif current == "prompt":
		prompt_answered.emit(false)
	elif current == "howto":
		show_screen(back_to)
	else:
		return
	get_viewport().set_input_as_handled()

static func clock(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
