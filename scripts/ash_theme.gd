extends RefCounted

## Shared colors and control skins for Ashrift. Original palette, no imported art.

static func palette(faction: String) -> Dictionary:
	match faction:
		"emberline":
			return {
				"accent": Color("e07a3d"),
				"deep": Color("2a100c"),
				"mid": Color("6a2c16"),
				"ink": Color("ffd8b8"),
				"title": "Emberline",
			}
		"mirevault":
			return {
				"accent": Color("7dba6a"),
				"deep": Color("101c12"),
				"mid": Color("24502c"),
				"ink": Color("d7f0c8"),
				"title": "Mirevault",
			}
		"glassward":
			return {
				"accent": Color("7fd0c8"),
				"deep": Color("0d1c22"),
				"mid": Color("1d4c58"),
				"ink": Color("dff7f4"),
				"title": "Glassward",
			}
		_:
			return {
				"accent": Color("e6d3a3"),
				"deep": Color("241c12"),
				"mid": Color("5c4a2e"),
				"ink": Color("f6edd8"),
				"title": "Wayline",
			}


static func ink() -> Color:
	return Color("f4efe6")


static func muted() -> Color:
	return Color("b7aa9c")


static func gold() -> Color:
	return Color("f2c14e")


static func ash() -> Color:
	return Color("140e12")


static func plate(panel: Control, accent: Color, fill: Color = Color("1a1216")) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = accent
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", box)


static func paint_button(btn: Button, accent: Color = Color("8a6a45")) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("241820")
	normal.border_color = accent.darkened(0.15)
	normal.set_border_width_all(1)
	normal.border_width_bottom = 3
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("342430")
	hover.border_color = gold()
	var down := hover.duplicate() as StyleBoxFlat
	down.bg_color = Color("1a1218")
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", down)
	btn.add_theme_stylebox_override("disabled", normal)
	btn.add_theme_color_override("font_color", ink())
	btn.add_theme_color_override("font_hover_color", gold())
	btn.add_theme_color_override("font_disabled_color", muted())
	btn.add_theme_font_size_override("font_size", 15)
