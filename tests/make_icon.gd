extends SceneTree
# Draws the game's icon (res://icon.png): Hemlock's Tower against a dawn sky,
# its crown's beacon lit, a moon, the bird on the wing, and the treetops.
# 32x32 pixel art, scaled up crisp to 128 and 512.
# Run: godot --headless --path . -s tests/make_icon.gd

const W := 32

func _init() -> void:
	var img := Image.create(W, W, false, Image.FORMAT_RGBA8)
	# Dawn sky in bands, deep violet to warm rose
	var bands := [Color(0.1, 0.08, 0.24), Color(0.16, 0.11, 0.33), Color(0.28, 0.16, 0.4),
		Color(0.48, 0.24, 0.45), Color(0.72, 0.36, 0.42), Color(0.93, 0.55, 0.42)]
	for y in W:
		var b: int = clampi(int(float(y) / 27.0 * bands.size()), 0, bands.size() - 1)
		for x in W:
			img.set_pixel(x, y, bands[b])
	# Stars and a crescent moon
	for s in [Vector2i(3, 3), Vector2i(8, 6), Vector2i(5, 11), Vector2i(27, 12), Vector2i(21, 3), Vector2i(29, 7)]:
		img.set_pixel(s.x, s.y, Color(1, 0.95, 0.85))
	for y in range(1, 10):
		for x in range(21, 31):
			var d := Vector2(x - 25.5, y - 5.0).length()
			var cut := Vector2(x - 27.5, y - 3.8).length()
			if d < 3.6 and cut > 3.0:
				img.set_pixel(x, y, Color(1.0, 0.93, 0.75))
	# The tower: lit left edge, shadowed right, brick courses, lit windows
	var stone := Color(0.33, 0.33, 0.4)
	for y in range(10, W):
		for x in range(12, 20):
			var c := stone
			if x == 12:
				c = stone.lightened(0.25)
			elif x >= 18:
				c = stone.darkened(0.3)
			if (y % 4 == 0) or ((y / 4) % 2 == 0 and x == 15) or ((y / 4) % 2 == 1 and x == 17):
				c = c.darkened(0.2)
			img.set_pixel(x, y, c)
	for w in [Vector2i(14, 15), Vector2i(16, 21), Vector2i(14, 26)]:
		img.set_pixel(w.x, w.y, Color(1.0, 0.78, 0.3))
		img.set_pixel(w.x, w.y + 1, Color(0.95, 0.6, 0.2))
	# Battlements, then the crown's pointed roof
	for x in range(11, 21):
		img.set_pixel(x, 9, stone.lightened(0.1))
		if x % 2 == 1:
			img.set_pixel(x, 8, stone.lightened(0.1))
	for y in range(2, 8):
		var half := int((y - 2) * 0.8)
		for x in range(15 - half, 17 + half):
			img.set_pixel(x, y, Color(0.45, 0.2, 0.32) if x < 16 else Color(0.32, 0.13, 0.24))
	# The beacon, glowing
	for g in [Vector2i(15, 0), Vector2i(16, 0), Vector2i(15, 1), Vector2i(16, 1)]:
		img.set_pixel(g.x, g.y, Color(1.0, 0.8, 0.35))
	for g in [Vector2i(14, 1), Vector2i(17, 1), Vector2i(15, 2), Vector2i(16, 2)]:
		img.set_pixel(g.x, g.y, Color(1.0, 0.6, 0.25))
	# The bird, wings up, with its red eye
	var bird := Color(0.1, 0.08, 0.16)
	for p in [Vector2i(23, 17), Vector2i(24, 17), Vector2i(25, 17), Vector2i(24, 16), Vector2i(25, 16),
			Vector2i(22, 16), Vector2i(21, 15), Vector2i(26, 15), Vector2i(27, 14), Vector2i(20, 14), Vector2i(26, 16), Vector2i(24, 18)]:
		img.set_pixel(p.x, p.y, bird)
	img.set_pixel(25, 16, Color(0.95, 0.2, 0.2))
	# Dark treetops along the bottom
	for x in W:
		var top := 27 + int(1.5 * sin(x * 1.3) + 1.0 * sin(x * 0.55 + 1.0))
		for y in range(top, W):
			if x < 11 or x > 20 or y > 29:
				img.set_pixel(x, y, Color(0.07, 0.14, 0.12) if (x + y) % 5 else Color(0.1, 0.2, 0.16))
	for size in [128, 512]:
		var big := img.duplicate()
		big.resize(size, size, Image.INTERPOLATE_NEAREST)
		big.save_png("res://icon.png" if size == 128 else "res://icon_512.png")
	print("icon written")
	quit()
