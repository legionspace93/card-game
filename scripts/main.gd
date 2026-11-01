extends Control

const CardDBScript = preload("res://rules/card_db.gd")
const TableScene = preload("res://scenes/table.tscn")
const ClothScript = preload("res://scripts/table_cloth.gd")
const AshTheme = preload("res://scripts/ash_theme.gd")
const SigilScript = preload("res://scripts/sigil.gd")

var db: Dictionary = {}
var decks: Dictionary = {}
var seed_box: SpinBox
var menu: Control
var rules: Control
var table = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	db = CardDBScript.load_all()
	for faction in ["emberline", "mirevault", "glassward"]:
		decks[faction] = CardDBScript.load_deck("res://data/decks/%s.json" % faction)
	_build_menu()
	get_window().title = "Ashrift"


func start_faction(faction: String, seed_no: int) -> void:
	var counter := {"emberline": "glassward", "mirevault": "emberline", "glassward": "mirevault"}
	_open_table(decks[faction], decks[counter[faction]], seed_no)


func _build_menu() -> void:
	var cloth = ClothScript.new()
	cloth.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cloth)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	menu = VBoxContainer.new()
	menu.custom_minimum_size = Vector2(680, 0)
	menu.add_theme_constant_override("separation", 14)
	center.add_child(menu)

	var kicker := Label.new()
	kicker.text = "TWO WARDENS  ·  FIVE LANES  ·  ONE VEIL"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_font_size_override("font_size", 13)
	kicker.add_theme_color_override("font_color", AshTheme.gold())
	menu.add_child(kicker)
	var title := Label.new()
	title.text = "Ashrift"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", AshTheme.ink())
	menu.add_child(title)
	var sub := Label.new()
	sub.text = "Spark climbs each turn. The expensive plays also cost life, a tribute, or a card shed from hand."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(640, 0)
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color("efe4d4"))
	menu.add_child(sub)

	_faction_button("emberline", "Emberline Kindling", "Rush, burn, and paying life for reach.")
	_faction_button("mirevault", "Mirevault Barrow", "Tribute, graves, and death that chains.")
	_faction_button("glassward", "Glassward Pane", "Traps, silence, bounce, and tax.")

	var seed_row := HBoxContainer.new()
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seed_row.add_theme_constant_override("separation", 12)
	menu.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.add_theme_color_override("font_color", AshTheme.gold())
	seed_row.add_child(seed_label)
	seed_box = SpinBox.new()
	seed_box.min_value = 1
	seed_box.max_value = 9999
	seed_box.value = 1
	seed_row.add_child(seed_box)
	var rules_btn := Button.new()
	rules_btn.text = "Rules"
	AshTheme.paint_button(rules_btn)
	rules_btn.pressed.connect(_toggle_rules)
	seed_row.add_child(rules_btn)

	var note := Label.new()
	note.text = "Rook plays the opposing deck. A gold frame is a legal card. Space passes, Enter confirms, Esc cancels."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", AshTheme.muted())
	menu.add_child(note)
	_build_rules()


func _faction_button(faction: String, title: String, blurb: String) -> void:
	var pal: Dictionary = AshTheme.palette(faction)
	var btn := Button.new()
	btn.text = ""
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 92)
	AshTheme.paint_button(btn, pal.accent)
	btn.pressed.connect(_start_pressed.bind(faction))
	menu.add_child(btn)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_top = 10
	row.offset_right = -12
	row.offset_bottom = -10
	btn.add_child(row)
	var sigil = SigilScript.new()
	sigil.seed_key = faction
	sigil.faction = faction
	sigil.kind = "unit"
	sigil.custom_minimum_size = Vector2(72, 72)
	sigil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sigil)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(words)
	var heading := Label.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.text = title
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", pal.ink)
	words.add_child(heading)
	var detail := Label.new()
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.text = blurb
	detail.add_theme_font_size_override("font_size", 14)
	detail.add_theme_color_override("font_color", AshTheme.muted())
	words.add_child(detail)


func _start_pressed(faction: String) -> void:
	start_faction(faction, int(seed_box.value))


func _build_rules() -> void:
	rules = PanelContainer.new()
	rules.visible = false
	rules.set_anchors_preset(Control.PRESET_FULL_RECT)
	rules.offset_left = 160
	rules.offset_top = 70
	rules.offset_right = -160
	rules.offset_bottom = -70
	AshTheme.plate(rules, AshTheme.gold(), Color("161014"))
	add_child(rules)
	var wrap := VBoxContainer.new()
	rules.add_child(wrap)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = false
	body.text = """[b]How a duel works[/b]
Each warden starts at 30 life with 4 cards. Spark starts at 1 and the cap grows by 1 at the start of your turn, up to 10. You refill to that cap. The first warden does not draw on the first turn. After that, draw 1. If you must draw from an empty deck, you lose. Life at 0 also loses. Healing stops at 30. A life cost cannot be paid below 1.

[b]Turn[/b]
Draw, main, combat, end. Entering a phase and ending a phase both give the other warden priority. Two passes with nothing added resolve the chain from the top.

[b]Zones[/b]
Deck, hand (end the turn with at most 7, hard cap 10), five lanes, graveyard, and the veil. The veil holds up to 3 set traps. A trap cannot be revealed on the turn it was set. Traps answer a summon, a spell, an attack, or any chain link, as printed.

[b]Plays[/b]
Units and sorceries are main-phase plays. Instants and set traps can answer during priority. Declaring a play pays its spark, and its life, tribute, or shed cost, immediately. The card sits on the chain until both wardens pass. Negate sends a summon or spell to the grave without its on-play effect. Tribute deaths and on-play, on-spell, on-attack, and on-death hooks queue a new chain, so one death can cause another.

[b]Combat[/b]
A unit without Rush cannot attack the turn it is played. Guard must be attacked before the enemy warden unless the attacker has Breach. Ward prevents the next damage, then breaks. Venom destroys a unit that takes combat damage from the attacker. Pierce spills excess combat damage to the warden. Siphon heals you for combat damage dealt to units. Twinstrike attacks twice.

[b]Silence[/b]
Silence removes keywords, hooks, and bonus stats. Printed stats remain, and damage already taken stays. A silenced death does not chain.
"""
	body.scroll_active = true
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(640, 420)
	wrap.add_child(body)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_toggle_rules)
	wrap.add_child(close)


func _toggle_rules() -> void:
	rules.visible = not rules.visible


func _open_table(you_deck: Dictionary, rook_deck: Dictionary, seed_no: int) -> void:
	if table != null:
		table.queue_free()
	menu.visible = false
	rules.visible = false
	table = TableScene.instantiate()
	table.name = "Table"
	add_child(table)
	table.back_to_menu.connect(_close_table)
	table.start_match(db, you_deck, rook_deck, seed_no)


func _close_table() -> void:
	if table != null:
		table.queue_free()
		table = null
	menu.visible = true
