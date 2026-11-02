class_name CardWidget
extends Panel

signal clicked(iid: int)
signal hovered(iid: int)

const AshTheme = preload("res://scripts/ash_theme.gd")
const SigilScript = preload("res://scripts/sigil.gd")

var iid: int = -1
var zone_name: String = ""

var _accent: Color = Color("e6d3a3")
var _deep: Color = Color("241c12")
var _marked: bool = false
var _face_down: bool = false
var _kind: String = ""
var _show_stats: bool = false
var _atk: int = 0
var _hp: int = 0
var _hurt: bool = false
var _keywords: Array = []
var _silenced: bool = false
var _compact: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func present(defn: Dictionary, inst: Dictionary, compact: bool, attack: int = -1) -> void:
	iid = int(inst.get("iid", -1))
	_face_down = false
	_compact = compact
	_kind = str(defn.get("type", ""))
	_silenced = bool(inst.get("silenced", false))
	var faction := str(defn.get("faction", "wayline"))
	var pal: Dictionary = AshTheme.palette(faction)
	_accent = pal.accent
	_deep = pal.deep
	_show_stats = _kind == "unit"
	_atk = int(inst.get("atk", defn.get("atk", 0)))
	if attack >= 0:
		_atk = attack
	_hp = int(inst.get("hp", defn.get("hp", 0)))
	_hurt = _hp < int(inst.get("max_hp", _hp))
	_keywords = []
	if not _silenced:
		for kw in inst.get("keywords", []):
			_keywords.append(str(kw))
	for child in get_children():
		child.queue_free()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_border_width_all(0)
	add_theme_stylebox_override("panel", box)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 8
	column.offset_top = 8
	column.offset_right = -8
	column.offset_bottom = -44 if _show_stats else -8
	add_child(column)

	var sigil = SigilScript.new()
	sigil.seed_key = str(defn.get("id", defn.get("name", "")))
	sigil.faction = faction
	sigil.kind = _kind
	sigil.portrait = _load_portrait(str(defn.get("art", "")))
	sigil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sigil.custom_minimum_size = Vector2(0, 44 if compact else 52)
	sigil.size_flags_vertical = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_SHRINK_CENTER
	if _silenced:
		sigil.modulate = Color(0.62, 0.62, 0.66)
	column.add_child(sigil)

	var name := Label.new()
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name.text = str(defn.get("name", ""))
	name.clip_text = true
	name.add_theme_font_size_override("font_size", 12 if compact else 15)
	name.add_theme_color_override("font_color", AshTheme.ink())
	column.add_child(name)

	var line := Label.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.text = _type_line(defn)
	if defn.has("alt"):
		var alt: Dictionary = defn.alt
		line.text += "   ·   " + _alt_text(alt)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.clip_text = true
	line.add_theme_font_size_override("font_size", 11)
	line.add_theme_color_override("font_color", _accent.lightened(0.15))
	column.add_child(line)

	if not compact:
		var body := Label.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.text = str(defn.get("text", ""))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.clip_text = true
		body.add_theme_font_size_override("font_size", 11)
		body.add_theme_color_override("font_color", Color("efe4d4"))
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(body)

	if _show_stats:
		_stat_label(str(_atk), false)
		_stat_label(str(_hp), true)
	var cost := Label.new()
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.text = str(int(defn.get("cost", 0)))
	cost.position = Vector2(6, 6)
	cost.size = Vector2(28, 26)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.add_theme_font_size_override("font_size", 14)
	cost.add_theme_color_override("font_color", AshTheme.gold())
	cost.z_index = 2
	add_child(cost)
	queue_redraw()


func _load_portrait(path: String) -> Texture2D:
	if path == "":
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)


func present_back(_count_label: String = "") -> void:
	iid = -1
	_face_down = true
	_show_stats = false
	_marked = false
	_keywords = []
	for child in get_children():
		child.queue_free()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("panel", box)
	queue_redraw()


func set_marked(marked: bool, _color: Color = Color("f2c14e")) -> void:
	_marked = marked
	queue_redraw()


func _stat_label(text: String, right: bool) -> void:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.z_index = 2
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("1a100c"))
	if right:
		label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		label.offset_left = -34
		label.offset_right = -6
		label.add_theme_color_override("font_color", Color("2a100c") if not _hurt else Color("fff4f0"))
	else:
		label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		label.offset_left = 6
		label.offset_right = 34
	label.offset_top = -30
	label.offset_bottom = -4
	add_child(label)


func _type_line(defn: Dictionary) -> String:
	if _silenced:
		return "Silenced"
	if _kind == "unit":
		if _keywords.is_empty():
			return "Unit"
		var parts: PackedStringArray = []
		for kw in _keywords:
			parts.append(str(kw).capitalize())
		return " ".join(parts)
	var line := _kind.capitalize()
	if defn.has("trigger"):
		line += "  ·  " + str(defn.trigger)
	return line


func _alt_text(alt: Dictionary) -> String:
	var kind := str(alt.get("type", ""))
	var amount := str(alt.get("amount", ""))
	match kind:
		"life":
			return "Also costs %s life" % amount
		"tribute":
			return "Tribute %s" % amount
		"discard":
			return "Shed %s" % amount
		_:
			return "%s %s" % [kind.capitalize(), amount]


func _draw() -> void:
	var s := size
	if s.x < 4.0 or s.y < 4.0:
		return
	var rect := Rect2(Vector2.ZERO, s)
	if _face_down:
		_draw_back(rect)
		return
	draw_rect(rect, Color("120c10"))
	var edge := AshTheme.gold() if _marked else _accent
	draw_rect(rect, edge, false, 3.0 if _marked else 2.0)
	draw_rect(rect.grow(-4), _accent.darkened(0.35), false, 1.0)
	_corners(rect, edge)
	draw_circle(Vector2(20, 19), 12, Color("1a100c"))
	draw_arc(Vector2(20, 19), 12, 0, TAU, 20, AshTheme.gold(), 2.0)
	if _show_stats:
		draw_circle(Vector2(20, s.y - 17), 13, Color("f0b429"))
		var hp_col := Color("e15b5b") if _hurt else Color("8fd18a")
		draw_circle(Vector2(s.x - 20, s.y - 17), 13, hp_col)
	_draw_keywords(s)
	if _silenced:
		draw_rect(rect, Color(0.7, 0.75, 0.85, 0.16))


func _draw_back(rect: Rect2) -> void:
	draw_rect(rect, Color("1c1418"))
	draw_rect(rect, Color("c47a3a"), false, 2.0)
	var c := rect.size * 0.5
	var d: float = minf(rect.size.x, rect.size.y) * 0.28
	var gem := PackedVector2Array([
		c + Vector2(0, -d),
		c + Vector2(d * 0.72, 0),
		c + Vector2(0, d),
		c + Vector2(-d * 0.72, 0),
	])
	draw_colored_polygon(gem, Color("e07a3d"))
	draw_polyline(gem + PackedVector2Array([gem[0]]), Color("ffd8b0"), 1.4)
	var font := get_theme_default_font()
	if font != null and rect.size.y > 48:
		draw_string(font, Vector2(0, c.y + d + 16), "Rift", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 11, Color("ffd8b0"))


func _corners(rect: Rect2, edge: Color) -> void:
	var a := 8.0
	var b := 16.0
	draw_line(Vector2(a, a), Vector2(b, a), edge, 2.0)
	draw_line(Vector2(a, a), Vector2(a, b), edge, 2.0)
	draw_line(Vector2(rect.size.x - a, a), Vector2(rect.size.x - b, a), edge, 2.0)
	draw_line(Vector2(rect.size.x - a, a), Vector2(rect.size.x - a, b), edge, 2.0)
	draw_line(Vector2(a, rect.size.y - a), Vector2(b, rect.size.y - a), edge, 2.0)
	draw_line(Vector2(a, rect.size.y - a), Vector2(a, rect.size.y - b), edge, 2.0)
	draw_line(Vector2(rect.size.x - a, rect.size.y - a), Vector2(rect.size.x - b, rect.size.y - a), edge, 2.0)
	draw_line(Vector2(rect.size.x - a, rect.size.y - a), Vector2(rect.size.x - a, rect.size.y - b), edge, 2.0)


func _draw_keywords(s: Vector2) -> void:
	if _keywords.is_empty() or _silenced:
		return
	var x := 38.0
	var y := 20.0
	for kw in _keywords:
		_draw_mark(Vector2(x, y), str(kw))
		x += 14.0
		if x > s.x - 18:
			break


func _draw_mark(at: Vector2, kw: String) -> void:
	var col := _accent.lightened(0.2)
	match kw:
		"rush":
			draw_colored_polygon(PackedVector2Array([
				at + Vector2(-5, -4), at + Vector2(5, 0), at + Vector2(-5, 4),
			]), col)
		"guard":
			draw_colored_polygon(PackedVector2Array([
				at + Vector2(0, -6), at + Vector2(5, -2), at + Vector2(4, 4), at + Vector2(0, 6), at + Vector2(-4, 4), at + Vector2(-5, -2),
			]), col)
		"ward":
			draw_arc(at, 5, 0, TAU, 16, col, 1.6)
		"venom":
			draw_circle(at + Vector2(0, 1), 4, col)
		"pierce":
			draw_line(at + Vector2(0, 5), at + Vector2(0, -4), col, 1.6)
			draw_colored_polygon(PackedVector2Array([
				at + Vector2(0, -6), at + Vector2(4, -1), at + Vector2(-4, -1),
			]), col)
		"siphon":
			draw_arc(at, 5, PI, TAU, 12, col, 1.6)
		"breach":
			draw_line(at + Vector2(-5, 0), at + Vector2(-1, 0), col, 2.0)
			draw_line(at + Vector2(1, 0), at + Vector2(5, 0), col, 2.0)
		"twinstrike":
			draw_colored_polygon(PackedVector2Array([
				at + Vector2(-5, -3), at + Vector2(-1, 0), at + Vector2(-5, 3),
			]), col)
			draw_colored_polygon(PackedVector2Array([
				at + Vector2(-1, -3), at + Vector2(4, 0), at + Vector2(-1, 3),
			]), col)
		_:
			draw_circle(at, 3, col)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(iid)
			accept_event()
	elif event is InputEventMouseMotion:
		hovered.emit(iid)
