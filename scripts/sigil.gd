extends Control

const AshTheme = preload("res://scripts/ash_theme.gd")

## A generated emblem. The faction sets the motif; the card id only shifts the arrangement.

var seed_key: String = ""
var faction: String = "wayline"
var kind: String = "unit"
var portrait: Texture2D = null


func _draw() -> void:
	var s := size
	if s.x < 8.0 or s.y < 8.0:
		return
	if portrait != null:
		var src := portrait.get_size()
		var region := Rect2(0, 0, src.x, src.y * 0.66)
		draw_texture_rect_region(portrait, Rect2(Vector2.ZERO, s), region)
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.18), false, 1.0)
		return
	var pal: Dictionary = AshTheme.palette(faction)
	var accent: Color = pal.accent
	var deep: Color = pal.deep
	var ink: Color = pal.ink
	var n := _mix(seed_key if seed_key != "" else faction)
	var rect := Rect2(Vector2.ZERO, s)
	draw_rect(rect, deep)
	for i in 7:
		var t := float(i) / 6.0
		var band := Rect2(0, s.y * t / 1.15, s.x, s.y / 5.0)
		var col: Color = deep.lerp(pal.mid, t)
		draw_rect(band, col)
	draw_rect(Rect2(0, s.y * 0.62, s.x, s.y * 0.4), Color(0, 0, 0, 0.28))
	match faction:
		"emberline":
			_flames(s, accent, ink, n)
		"mirevault":
			_barrow(s, accent, ink, n)
		"glassward":
			_pane(s, accent, ink, n)
		_:
			_road(s, accent, ink, n)
	if kind == "spell":
		draw_arc(s * 0.5, min(s.x, s.y) * 0.28, 0, TAU, 28, ink.lerp(accent, 0.4), 2.0)
	elif kind == "trap":
		var eye := s * Vector2(0.5, 0.42)
		draw_arc(eye, 11, 0, TAU, 20, ink, 1.6)
		draw_line(eye + Vector2(-5, 0), eye + Vector2(5, 0), accent, 2.0)
	var marks := 2 + (n % 4)
	for i in marks:
		var px := s.x * (0.16 + 0.68 * _unit(n, 4 + i * 3))
		var py := s.y * (0.2 + 0.48 * _unit(n, 11 + i * 5))
		var r := 3.0 + 4.0 * _unit(n, 30 + i)
		if i % 2 == 0:
			draw_circle(Vector2(px, py), r, accent.lightened(0.3))
		else:
			draw_rect(Rect2(px - r, py - r, r * 2.0, r * 2.0), pal.ink)
	var slash := Vector2(s.x * _unit(n, 40), s.y * 0.15)
	draw_line(slash, slash + Vector2(s.x * 0.35, s.y * (0.25 + 0.35 * _unit(n, 41))), Color(1, 1, 1, 0.28), 2.0)
	var font := get_theme_default_font()
	if font != null and seed_key.length() > 0:
		var brand := seed_key.substr(0, 1).to_upper()
		draw_string(font, Vector2(0, s.y * 0.58), brand, HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, Color(1, 1, 1, 0.78))
	draw_rect(rect, accent.darkened(0.25), false, 1.5)


func _flames(s: Vector2, accent: Color, ink: Color, n: int) -> void:
	for i in 3:
		var cx := s.x * (0.28 + 0.22 * float(i) + 0.08 * _unit(n, i + 1))
		var tip := s.y * (0.16 + 0.08 * _unit(n, 20 + i))
		var pts := PackedVector2Array([
			Vector2(cx, tip),
			Vector2(cx + 16 + i * 3, s.y * 0.78),
			Vector2(cx - 14, s.y * 0.82),
		])
		var col: Color = accent.lightened(0.15 * float(i))
		col.a = 0.92
		draw_colored_polygon(pts, col)
	draw_circle(Vector2(s.x * 0.5, s.y * 0.7), 7, ink)


func _barrow(s: Vector2, accent: Color, ink: Color, n: int) -> void:
	var mound: PackedVector2Array = []
	for i in 9:
		var t := float(i) / 8.0
		var x := s.x * (0.12 + 0.76 * t)
		var y := s.y * (0.72 - sin(t * PI) * (0.28 + 0.08 * _unit(n, 2)))
		mound.append(Vector2(x, y))
	mound.append(Vector2(s.x * 0.88, s.y))
	mound.append(Vector2(s.x * 0.12, s.y))
	draw_colored_polygon(mound, accent.darkened(0.25))
	var root := Vector2(s.x * (0.3 + 0.4 * _unit(n, 6)), s.y * 0.55)
	draw_line(root, root + Vector2(-28, 36), ink.darkened(0.1), 2.0)
	draw_line(root, root + Vector2(22, 40), accent.lightened(0.2), 2.0)
	draw_line(root + Vector2(-10, 16), root + Vector2(-26, 28), accent, 1.5)
	draw_circle(Vector2(s.x * 0.62, s.y * 0.48), 5, ink)


func _pane(s: Vector2, accent: Color, ink: Color, n: int) -> void:
	var c := Vector2(s.x * 0.5, s.y * 0.46)
	var d: float = minf(s.x, s.y) * (0.22 + 0.08 * _unit(n, 3))
	var gem := PackedVector2Array([
		c + Vector2(0, -d),
		c + Vector2(d * 0.8, 0),
		c + Vector2(0, d),
		c + Vector2(-d * 0.8, 0),
	])
	draw_colored_polygon(gem, accent.lightened(0.12))
	draw_polyline(gem + PackedVector2Array([gem[0]]), ink, 1.6)
	var shift := 18.0 + 16.0 * _unit(n, 8)
	var shard := PackedVector2Array([
		c + Vector2(shift, -d * 0.2),
		c + Vector2(shift + 16, 8),
		c + Vector2(shift - 4, d * 0.45),
	])
	draw_colored_polygon(shard, ink.darkened(0.05))


func _road(s: Vector2, accent: Color, ink: Color, n: int) -> void:
	draw_line(Vector2(8, s.y * 0.62), Vector2(s.x - 8, s.y * 0.62), accent, 3.0)
	var apex := Vector2(s.x * (0.4 + 0.2 * _unit(n, 5)), s.y * 0.28)
	var road := PackedVector2Array([
		apex,
		Vector2(s.x * 0.78, s.y * 0.84),
		Vector2(s.x * 0.22, s.y * 0.84),
	])
	draw_colored_polygon(road, accent.darkened(0.2))
	draw_line(apex, Vector2(s.x * 0.5, s.y * 0.84), ink, 1.5)
	draw_circle(apex, 4, ink)


func _mix(key: String) -> int:
	var n := 2166136261
	for i in key.length():
		n = int((n ^ key.unicode_at(i)) * 16777619) & 0x7fffffff
	return n


func _unit(n: int, salt: int) -> float:
	var x := int(n / (salt * 17 + 3)) % 1000
	if x < 0:
		x = -x
	return float(x) / 1000.0
