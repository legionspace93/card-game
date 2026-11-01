class_name CardWidget
extends Panel

signal clicked(iid: int)
signal hovered(iid: int)

var iid: int = -1
var zone_name: String = ""
var _border: Color = Color("3a3348")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func present(defn: Dictionary, inst: Dictionary, compact: bool, attack: int = -1) -> void:
	iid = int(inst.get("iid", -1))
	for child in get_children():
		child.queue_free()
	var faction := str(defn.get("faction", "wayline"))
	var accent := _faction_color(faction)
	_border = accent.darkened(0.35)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("1c1726")
	box.border_color = _border
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	add_theme_stylebox_override("panel", box)

	var box_v := VBoxContainer.new()
	box_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box_v)
	box_v.set_anchors_preset(Control.PRESET_FULL_RECT)
	box_v.offset_left = 6
	box_v.offset_top = 4
	box_v.offset_right = -6
	box_v.offset_bottom = -4

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box_v.add_child(top)
	var cost := Label.new()
	cost.text = str(int(defn.get("cost", 0)))
	cost.add_theme_color_override("font_color", Color("f2c14e"))
	cost.add_theme_font_size_override("font_size", 16)
	top.add_child(cost)
	var name := Label.new()
	name.text = str(defn.get("name", ""))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.add_theme_font_size_override("font_size", 13 if compact else 14)
	name.add_theme_color_override("font_color", Color("f4efe6"))
	top.add_child(name)

	var kind := str(defn.get("type", ""))
	var line := Label.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if kind == "unit":
		var shown := int(inst.get("atk", defn.get("atk", 0)))
		if attack >= 0:
			shown = attack
		line.text = "%s   %d / %d" % [_keywords(inst), shown, int(inst.get("hp", 0))]
	else:
		line.text = kind.capitalize()
		if defn.has("trigger"):
			line.text += " · " + str(defn.trigger)
	line.add_theme_font_size_override("font_size", 11)
	line.add_theme_color_override("font_color", accent)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_v.add_child(line)

	if not compact:
		var body := Label.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.text = str(defn.get("text", ""))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_font_size_override("font_size", 11)
		body.add_theme_color_override("font_color", Color("d9d0c4"))
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box_v.add_child(body)
	if defn.has("alt"):
		var alt: Dictionary = defn.alt
		var badge := Label.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.text = "%s %s" % [str(alt.get("type", "")).capitalize(), str(alt.get("amount", ""))]
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", Color("e7a0a0"))
		box_v.add_child(badge)


func present_back(count_label: String = "") -> void:
	iid = -1
	var box := StyleBoxFlat.new()
	box.bg_color = Color("2a2340")
	box.border_color = Color("7c6aa5")
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = count_label if count_label != "" else "Rift"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color("c8bce0"))
	add_child(label)


func set_marked(marked: bool, color: Color = Color("f2c14e")) -> void:
	var box := get_theme_stylebox("panel")
	if box is StyleBoxFlat:
		(box as StyleBoxFlat).border_color = color if marked else _border


func _keywords(inst: Dictionary) -> String:
	var parts: PackedStringArray = []
	for kw in inst.get("keywords", []):
		parts.append(str(kw).capitalize())
	if bool(inst.get("silenced", false)):
		return "Silenced"
	if parts.is_empty():
		return "Unit"
	return " ".join(parts)


func _faction_color(faction: String) -> Color:
	match faction:
		"emberline":
			return Color("e07a3d")
		"mirevault":
			return Color("7dba6a")
		"glassward":
			return Color("7fd0c8")
		_:
			return Color("e6d3a3")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(iid)
			accept_event()
	elif event is InputEventMouseMotion:
		hovered.emit(iid)
