extends Control

signal back_to_menu

const HUMAN := 0
const BOT := 1
const DuelScript = preload("res://rules/duel.gd")
const BotScript = preload("res://rules/bot.gd")
const FlashScript = preload("res://vfx/flashes.gd")
const KeywordScript = preload("res://rules/keywords.gd")
const CardWidgetScript = preload("res://scripts/card_widget.gd")
const ClothScript = preload("res://scripts/table_cloth.gd")
const AshTheme = preload("res://scripts/ash_theme.gd")

var duel = null
var db: Dictionary = {}
var deck_you: Dictionary = {}
var deck_rook: Dictionary = {}
var seed_value: int = 1
var seen: int = 0
var legal: Array = []
var mode: String = ""
var chosen_iid: int = -1
var lane_pick: int = -1
var targets: Array = []
var tributes: Array = []
var discards: Array = []
var picks: Array = []
var target_kind: String = ""
var target_iid: int = -1
var shed_needed: int = 0
var anchors: Dictionary = {}
var lane_anchor: Dictionary = {}
var warden_anchor: Dictionary = {}
var resolving: bool = false

var status_label: Label
var chain_label: Label
var hint_label: Label
var log_label: Label
var you_bar: Button
var rook_bar: Button
var opp_hand: HBoxContainer
var you_hand: HBoxContainer
var opp_lanes: HBoxContainer
var you_lanes: HBoxContainer
var veil_row: HBoxContainer
var choice_box: VBoxContainer
var fx: Node2D
var motes: CPUParticles2D
var over_panel: PanelContainer
var over_label: Label
var confirm_button: Button
var pass_button: Button
var end_button: Button
var tick: Timer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	tick = Timer.new()
	tick.wait_time = 0.28
	tick.timeout.connect(_on_tick)
	add_child(tick)
	tick.start()


func start_match(card_db: Dictionary, you_deck: Dictionary, rook_deck: Dictionary, seed_no: int) -> void:
	db = card_db
	deck_you = you_deck
	deck_rook = rook_deck
	seed_value = seed_no
	duel = DuelScript.new(db, you_deck.get("cards", []), rook_deck.get("cards", []), seed_no)
	seen = 0
	_clear_selection()
	_refresh()
	call_deferred("_flash_new")


func _build() -> void:
	var bg = ClothScript.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	motes = CPUParticles2D.new()
	motes.amount = 26
	motes.lifetime = 5.5
	motes.preprocess = 2.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(460, 14)
	motes.direction = Vector2(0, -1)
	motes.spread = 24
	motes.gravity = Vector2(0, -6)
	motes.initial_velocity_min = 6
	motes.initial_velocity_max = 18
	motes.scale_amount_min = 1.4
	motes.scale_amount_max = 3.2
	motes.color = Color(1.0, 0.55, 0.22, 0.4)
	add_child(motes)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(columns)

	var board := VBoxContainer.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.add_theme_constant_override("separation", 4)
	columns.add_child(board)

	rook_bar = Button.new()
	rook_bar.alignment = HORIZONTAL_ALIGNMENT_LEFT
	rook_bar.custom_minimum_size = Vector2(0, 52)
	rook_bar.pressed.connect(_click_face)
	_paint_button(rook_bar)
	board.add_child(rook_bar)

	opp_hand = HBoxContainer.new()
	opp_hand.add_theme_constant_override("separation", 4)
	board.add_child(opp_hand)

	opp_lanes = HBoxContainer.new()
	opp_lanes.add_theme_constant_override("separation", 8)
	opp_lanes.alignment = BoxContainer.ALIGNMENT_CENTER
	board.add_child(opp_lanes)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 20)
	status_label.add_theme_color_override("font_color", AshTheme.ink())
	board.add_child(status_label)
	chain_label = Label.new()
	chain_label.add_theme_color_override("font_color", Color("9ad7ff"))
	chain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board.add_child(chain_label)

	you_lanes = HBoxContainer.new()
	you_lanes.add_theme_constant_override("separation", 8)
	you_lanes.alignment = BoxContainer.ALIGNMENT_CENTER
	board.add_child(you_lanes)

	veil_row = HBoxContainer.new()
	veil_row.add_theme_constant_override("separation", 6)
	board.add_child(veil_row)

	you_hand = HBoxContainer.new()
	you_hand.add_theme_constant_override("separation", 6)
	you_hand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	you_hand.alignment = BoxContainer.ALIGNMENT_CENTER
	board.add_child(you_hand)

	you_bar = Button.new()
	you_bar.alignment = HORIZONTAL_ALIGNMENT_LEFT
	you_bar.disabled = true
	you_bar.custom_minimum_size = Vector2(0, 52)
	_paint_button(you_bar)
	you_bar.add_theme_color_override("font_disabled_color", AshTheme.ink())
	board.add_child(you_bar)

	hint_label = Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size = Vector2(0, 28)
	hint_label.add_theme_color_override("font_color", Color("efe4d4"))
	board.add_child(hint_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	board.add_child(buttons)
	pass_button = _button("Pass", _press_pass)
	end_button = _button("End phase", _press_end)
	confirm_button = _button("Confirm", _press_confirm)
	var cancel := _button("Cancel", _press_cancel)
	var skip := _button("Skip flashes", _press_skip)
	var faster := _button("Faster", _press_faster)
	var menu := _button("Menu", func() -> void: back_to_menu.emit())
	for btn in [pass_button, end_button, confirm_button, cancel, skip, faster, menu]:
		buttons.add_child(btn)

	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(280, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	AshTheme.plate(side, Color("8a5a32"), Color(0.09, 0.05, 0.05, 0.78))
	columns.add_child(side)
	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 8)
	side.add_child(side_box)
	var side_title := Label.new()
	side_title.text = "Chain"
	side_title.add_theme_font_size_override("font_size", 18)
	side_title.add_theme_color_override("font_color", AshTheme.gold())
	side_box.add_child(side_title)
	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_color_override("font_color", Color("efe4d4"))
	side_box.add_child(log_label)
	choice_box = VBoxContainer.new()
	side_box.add_child(choice_box)

	fx = FlashScript.new()
	fx.z_index = 20
	add_child(fx)

	over_panel = PanelContainer.new()
	over_panel.visible = false
	over_panel.set_anchors_preset(Control.PRESET_CENTER)
	over_panel.position = Vector2(470, 320)
	over_panel.custom_minimum_size = Vector2(520, 180)
	AshTheme.plate(over_panel, AshTheme.gold(), Color("1a1216"))
	add_child(over_panel)
	var over_box := VBoxContainer.new()
	over_panel.add_child(over_box)
	over_label = Label.new()
	over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_label.add_theme_font_size_override("font_size", 22)
	over_box.add_child(over_label)
	var over_buttons := HBoxContainer.new()
	over_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	over_box.add_child(over_buttons)
	over_buttons.add_child(_button("Same seed", func() -> void: start_match(db, deck_you, deck_rook, seed_value)))
	over_buttons.add_child(_button("New seed", func() -> void: start_match(db, deck_you, deck_rook, seed_value + 1)))
	over_buttons.add_child(_button("Menu", func() -> void: back_to_menu.emit()))


func _button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	_paint_button(btn)
	btn.pressed.connect(callback)
	return btn


func _paint_button(btn: Button) -> void:
	AshTheme.paint_button(btn)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and motes != null:
		motes.position = size * Vector2(0.38, 0.46)


func _on_tick() -> void:
	if duel == null or int(duel.winner) >= 0 or resolving:
		return
	var pid := int(duel.actor())
	if pid == BOT:
		_act(BOT, BotScript.choose(duel, BOT))
		return
	if pid == HUMAN and mode == "" and _only_pass():
		_act(HUMAN, {"type": "pass"})


func _act(pid: int, action: Dictionary) -> void:
	if duel == null or resolving:
		return
	resolving = true
	var res: Dictionary = duel.apply(pid, action)
	resolving = false
	if not res.get("ok", false):
		hint_label.text = "Illegal: %s" % str(res.get("reason", ""))
		return
	_clear_selection()
	_refresh()
	call_deferred("_flash_new")


func _refresh() -> void:
	if duel == null:
		return
	legal = duel.legal_actions(HUMAN) if int(duel.actor()) == HUMAN else []
	if mode == "" and _must_shed():
		mode = "shed"
		shed_needed = int(legal[0].discards.size()) if not legal.is_empty() else 0
	_fill_bars()
	_fill_row(opp_hand, BOT, "hand", true)
	_fill_lanes(opp_lanes, BOT)
	_fill_lanes(you_lanes, HUMAN)
	_fill_veil()
	_fill_row(you_hand, HUMAN, "hand", false)
	status_label.text = _status_text()
	chain_label.text = _chain_text()
	log_label.text = _log_text()
	hint_label.text = _prompt_text()
	pass_button.disabled = not _has_type("pass")
	end_button.disabled = not _has_type("end_phase")
	var ready: bool = _need() == "confirm" and _matching().size() == 1
	confirm_button.disabled = not ready
	_fill_choices()
	var over: bool = int(duel.winner) >= 0
	over_panel.visible = over
	if over:
		var who := "You" if int(duel.winner) == HUMAN else "Rook"
		var how := "life" if str(duel.win_reason) == "life" else "an empty deck"
		over_label.text = "%s win.\nThe duel ended by %s." % [who, how]
	call_deferred("_capture_anchors")


func _fill_bars() -> void:
	_fill_plate(you_bar, "You", HUMAN, deck_you)
	_fill_plate(rook_bar, "Rook", BOT, deck_rook)


func _fill_plate(btn: Button, title: String, pid: int, deck: Dictionary) -> void:
	btn.text = ""
	_wipe(btn)
	var who: Dictionary = duel.players[pid]
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_top = 4
	row.offset_right = -10
	row.offset_bottom = -4
	btn.add_child(row)

	var name := Label.new()
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name.text = title
	name.custom_minimum_size = Vector2(52, 0)
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.add_theme_font_size_override("font_size", 18)
	name.add_theme_color_override("font_color", AshTheme.gold() if pid == HUMAN else Color("f0a070"))
	row.add_child(name)

	var life_col := VBoxContainer.new()
	life_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	life_col.custom_minimum_size = Vector2(150, 0)
	row.add_child(life_col)
	var life_label := Label.new()
	life_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	life_label.text = "Life %d" % int(who.life)
	life_label.add_theme_font_size_override("font_size", 12)
	life_label.add_theme_color_override("font_color", AshTheme.ink())
	life_col.add_child(life_label)
	var track := Control.new()
	track.custom_minimum_size = Vector2(140, 8)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	life_col.add_child(track)
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color("2a1818")
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(back)
	var ratio := clampf(float(who.life) / 30.0, 0.0, 1.0)
	var fill := ColorRect.new()
	fill.anchor_right = ratio
	fill.anchor_bottom = 1.0
	fill.color = Color("e15b5b") if int(who.life) <= 10 else Color("e07a3d")
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)

	var spark_col := VBoxContainer.new()
	spark_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spark_col)
	var spark_label := Label.new()
	spark_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spark_label.text = "Spark %d / %d" % [int(who.energy), int(who.max_energy)]
	spark_label.add_theme_font_size_override("font_size", 12)
	spark_label.add_theme_color_override("font_color", AshTheme.gold())
	spark_col.add_child(spark_label)
	var pips := HBoxContainer.new()
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.add_theme_constant_override("separation", 3)
	spark_col.add_child(pips)
	var cap := maxi(int(who.max_energy), 1)
	for i in cap:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(9, 9)
		pip.color = AshTheme.gold() if i < int(who.energy) else Color("3a2e28")
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)

	var piles := Label.new()
	piles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	piles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	piles.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	piles.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	piles.text = "%s\nDeck %d   Grave %d   Veil %d" % [
		str(deck.get("name", "")), who.deck.size(), who.grave.size(), who.veil.size(),
	]
	piles.add_theme_font_size_override("font_size", 12)
	piles.add_theme_color_override("font_color", AshTheme.muted())
	row.add_child(piles)


func _fill_row(row: HBoxContainer, pid: int, zone: String, hidden: bool) -> void:
	_wipe(row)
	var marks := _marks()
	for card in duel.players[pid][zone]:
		var widget := CardWidgetScript.new()
		widget.zone_name = zone
		if hidden:
			widget.custom_minimum_size = Vector2(40, 52)
			widget.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		else:
			widget.custom_minimum_size = Vector2(150, 198)
			widget.size_flags_vertical = Control.SIZE_SHRINK_END
		if hidden:
			widget.present_back()
		else:
			var defn: Dictionary = db[str(card.def_id)]
			var atk := int(duel.attack_value(card)) if zone == "board" else -1
			widget.present(defn, card, false, atk)
			widget.set_marked(_marked(marks, int(card.iid), zone))
		widget.clicked.connect(_click_card.bind(zone, pid))
		widget.hovered.connect(_on_hover)
		row.add_child(widget)


func _fill_lanes(row: HBoxContainer, pid: int) -> void:
	_wipe(row)
	var marks := _marks()
	for lane_i in DuelScript.LANES:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(148, 128)
		panel.set_meta("who", pid)
		panel.set_meta("lane", lane_i)
		var box := StyleBoxFlat.new()
		var empty: bool = duel.players[pid].board[lane_i] == null
		box.bg_color = Color(0.09, 0.05, 0.04, 0.55) if empty else Color(0.1, 0.06, 0.05, 0.88)
		box.border_color = Color("6a3e28")
		box.set_border_width_all(2)
		box.set_corner_radius_all(12)
		box.shadow_color = Color(0, 0, 0, 0.45)
		box.shadow_size = 4
		if pid == HUMAN and bool(marks.lanes.get(lane_i, false)):
			box.border_color = Color("f2c14e")
		panel.add_theme_stylebox_override("panel", box)
		panel.gui_input.connect(_on_lane_input.bind(pid, lane_i))
		var unit = duel.players[pid].board[lane_i]
		if unit != null:
			var widget := CardWidgetScript.new()
			widget.zone_name = "board"
			widget.set_anchors_preset(Control.PRESET_FULL_RECT)
			widget.offset_left = 4
			widget.offset_top = 4
			widget.offset_right = -4
			widget.offset_bottom = -4
			var defn: Dictionary = db[str(unit.def_id)]
			widget.present(defn, unit, true, int(duel.attack_value(unit)))
			widget.set_marked(_marked(marks, int(unit.iid), "board"))
			widget.clicked.connect(_click_card.bind("board", pid))
			widget.hovered.connect(_on_hover)
			panel.add_child(widget)
		else:
			var label := Label.new()
			label.text = "Lane %d" % (lane_i + 1)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_size_override("font_size", 13)
			label.add_theme_color_override("font_color", Color("8a6248"))
			panel.add_child(label)
		row.add_child(panel)


func _fill_veil() -> void:
	_wipe(veil_row)
	var title := Label.new()
	title.text = "Veil"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("e7c6ff"))
	veil_row.add_child(title)
	var marks := _marks()
	if duel.players[HUMAN].veil.is_empty():
		var none := Label.new()
		none.text = "nothing set"
		none.add_theme_color_override("font_color", Color("8d7a90"))
		veil_row.add_child(none)
		return
	for card in duel.players[HUMAN].veil:
		var widget := CardWidgetScript.new()
		widget.zone_name = "veil"
		widget.custom_minimum_size = Vector2(168, 70)
		widget.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		widget.present(db[str(card.def_id)], card, true)
		widget.set_marked(_marked(marks, int(card.iid), "veil"))
		widget.clicked.connect(_click_card.bind("veil", HUMAN))
		widget.hovered.connect(_on_hover)
		veil_row.add_child(widget)


func _fill_choices() -> void:
	_wipe(choice_box)
	var need := _need()
	if need != "pick" and need != "target":
		return
	var key := "picks" if need == "pick" else "targets"
	var have: Array = picks if need == "pick" else targets
	var ids := {}
	for action in _matching():
		var arr: Array = action.get(key, [])
		if have.size() < arr.size():
			ids[int(arr[have.size()])] = true
	if ids.is_empty():
		return
	var caption := Label.new()
	caption.text = "Choose a card" if need == "pick" else "Choose a target"
	caption.add_theme_color_override("font_color", Color("f2c14e"))
	choice_box.add_child(caption)
	for iid in ids.keys():
		var btn := Button.new()
		btn.text = _choice_name(int(iid))
		_paint_button(btn)
		btn.pressed.connect(_append_choice.bind(key, int(iid)))
		choice_box.add_child(btn)


func _card_widgets() -> Array:
	var out: Array = []
	_walk_cards(self, out)
	return out


func _walk_cards(node: Node, out: Array) -> void:
	if node.get_script() == CardWidgetScript:
		out.append(node)
	for child in node.get_children():
		_walk_cards(child, out)


func _wipe(node: Node) -> void:
	for child in node.get_children().duplicate():
		node.remove_child(child)
		child.free()


func _capture_anchors() -> void:
	anchors.clear()
	lane_anchor.clear()
	for widget in _card_widgets():
		if int(widget.iid) >= 0:
			anchors[int(widget.iid)] = widget.get_global_rect().get_center()
	for panel in you_lanes.get_children():
		lane_anchor["%s:%s" % [panel.get_meta("who"), panel.get_meta("lane")]] = panel.get_global_rect().get_center()
	for panel in opp_lanes.get_children():
		lane_anchor["%s:%s" % [panel.get_meta("who"), panel.get_meta("lane")]] = panel.get_global_rect().get_center()
	warden_anchor[HUMAN] = you_bar.get_global_rect().get_center()
	warden_anchor[BOT] = rook_bar.get_global_rect().get_center()


func _flash_new() -> void:
	if duel == null:
		return
	_capture_anchors()
	while seen < duel.events.size():
		var ev: Dictionary = duel.events[seen]
		seen += 1
		var style := FlashScript.style_for(str(ev.get("type", "")))
		if style == "":
			continue
		fx.burst(_pos_for(ev, style), style, _flash_text(ev, style))


func _pos_for(ev: Dictionary, style: String) -> Vector2:
	if style == "chain_resolve" or style == "phase" or style == "win":
		return size * 0.5
	var iid := int(ev.get("iid", -1))
	if anchors.has(iid):
		return anchors[iid]
	if ev.has("player") and ev.has("lane") and int(ev.get("lane", -1)) >= 0:
		var key := "%s:%s" % [ev.get("player"), ev.get("lane")]
		if lane_anchor.has(key):
			return lane_anchor[key]
	if str(ev.get("target", "")) == "warden":
		return warden_anchor.get(int(ev.get("player", 0)), size * 0.5)
	return size * 0.5


func _flash_text(ev: Dictionary, style: String) -> String:
	match style:
		"damage":
			return "-%s" % str(ev.get("amount", ""))
		"heal":
			return "+%s" % str(ev.get("amount", ""))
		"destroy":
			return "Destroy"
		"buff":
			return "Buff"
		"trap_reveal":
			return "Trap"
		"chain_resolve":
			return "Resolve"
		"silence":
			return "Silence"
		"negate":
			return "Negate"
		"attack":
			return "Attack"
		"ward":
			return "Ward"
		"bounce":
			return "Bounce"
		"phase":
			return str(ev.get("phase", "")).capitalize()
		"win":
			return "Win"
		_:
			return _cname(str(ev.get("def_id", "")))


func _click_card(iid: int, zone: String, _pid: int) -> void:
	if iid < 0 or duel == null or int(duel.winner) >= 0 or int(duel.actor()) != HUMAN:
		return
	if mode == "":
		if zone == "hand":
			_begin("card", iid)
		elif zone == "board" and _can_attack(iid):
			_begin("attack", iid)
		elif zone == "veil":
			_begin("card", iid)
		return
	if mode == "shed":
		_toggle(discards, iid)
		_refresh()
		return
	var need := _need()
	if need == "tribute" and _next_is("tributes", iid):
		tributes.append(iid)
	elif need == "discard" and _next_is("discards", iid):
		discards.append(iid)
	elif need == "target" and _next_is("targets", iid):
		targets.append(iid)
	elif need == "attack_target" and _attack_has_unit(iid):
		target_kind = "unit"
		target_iid = iid
	else:
		_on_hover(iid)
		return
	_refresh()


func _click_lane(pid: int, lane_i: int) -> void:
	if duel == null or int(duel.actor()) != HUMAN:
		return
	if pid == HUMAN and _need() == "lane" and _lane_open(lane_i):
		lane_pick = lane_i
		_refresh()
		return
	var unit = duel.players[pid].board[lane_i]
	if unit != null:
		_click_card(int(unit.iid), "board", pid)


func _click_face() -> void:
	if _need() == "attack_target" and _attack_has_face():
		target_kind = "warden"
		target_iid = -1
		_refresh()


func _on_lane_input(event: InputEvent, pid: int, lane_i: int) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_click_lane(pid, lane_i)


func _begin(next_mode: String, iid: int) -> void:
	mode = next_mode
	chosen_iid = iid
	lane_pick = -1
	targets = []
	tributes = []
	discards = []
	picks = []
	target_kind = ""
	target_iid = -1
	if _matching().is_empty():
		_clear_selection()
		hint_label.text = "That card has no legal play right now."
		return
	_refresh()


func _toggle(bucket: Array, iid: int) -> void:
	var next: Array = []
	var removed := false
	for have in bucket:
		if int(have) == iid and not removed:
			removed = true
		else:
			next.append(have)
	if not removed and bucket.size() < shed_needed:
		next.append(iid)
	discards = next


func _append_choice(key: String, iid: int) -> void:
	if key == "picks":
		picks.append(iid)
	elif key == "targets":
		targets.append(iid)
	_refresh()


func _press_pass() -> void:
	if _has_type("pass"):
		_act(HUMAN, {"type": "pass"})


func _press_end() -> void:
	if _has_type("end_phase"):
		_act(HUMAN, {"type": "end_phase"})


func _press_confirm() -> void:
	var acts := _matching()
	if acts.size() == 1:
		_act(HUMAN, acts[0])


func _press_cancel() -> void:
	_clear_selection()
	_refresh()


func _press_skip() -> void:
	fx.skip_all()


func _press_faster() -> void:
	tick.wait_time = 0.08 if tick.wait_time > 0.1 else 0.28


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_SPACE:
			_press_pass()
		elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			_press_confirm()
		elif key.keycode == KEY_ESCAPE:
			_press_cancel()


func _clear_selection() -> void:
	mode = ""
	chosen_iid = -1
	lane_pick = -1
	targets = []
	tributes = []
	discards = []
	picks = []
	target_kind = ""
	target_iid = -1
	shed_needed = 0


func _only_pass() -> bool:
	return legal.size() == 1 and str(legal[0].get("type", "")) == "pass"


func _must_shed() -> bool:
	if legal.is_empty():
		return false
	for action in legal:
		if str(action.get("type", "")) != "discard_down":
			return false
	return true


func _has_type(type_name: String) -> bool:
	for action in legal:
		if str(action.get("type", "")) == type_name:
			return true
	return false


func _can_attack(iid: int) -> bool:
	for action in legal:
		if str(action.get("type", "")) == "attack" and int(action.get("iid", -1)) == iid:
			return true
	return false


func _matching() -> Array:
	var out: Array = []
	for action in legal:
		var type_name := str(action.get("type", ""))
		if mode == "shed":
			if type_name != "discard_down":
				continue
			if not _subset(discards, action.get("discards", [])):
				continue
			out.append(action)
			continue
		if mode == "card" and not (type_name == "play" or type_name == "set_trap" or type_name == "activate"):
			continue
		if mode == "attack" and type_name != "attack":
			continue
		if chosen_iid >= 0 and int(action.get("iid", -2)) != chosen_iid:
			continue
		if lane_pick >= 0 and int(action.get("lane", -1)) != lane_pick:
			continue
		if not _prefix(action.get("targets", []), targets):
			continue
		if not _prefix(action.get("tributes", []), tributes):
			continue
		if not _prefix(action.get("discards", []), discards):
			continue
		if not _prefix(action.get("picks", []), picks):
			continue
		if target_kind != "":
			if str(action.get("target_kind", "")) != target_kind:
				continue
			if target_kind == "unit" and int(action.get("target_iid", -1)) != target_iid:
				continue
		out.append(action)
	return out


func _need() -> String:
	if mode == "":
		return ""
	if mode == "shed":
		return "confirm" if discards.size() == shed_needed and _matching().size() >= 1 else "shed"
	var acts := _matching()
	if acts.is_empty():
		return "none"
	if _more(acts, "tributes", tributes):
		return "tribute"
	if _more(acts, "discards", discards):
		return "discard"
	if _more(acts, "targets", targets):
		return "target"
	if _more(acts, "picks", picks):
		return "pick"
	if mode == "attack" and target_kind == "":
		return "attack_target"
	if lane_pick < 0 and _any_lane(acts):
		return "lane"
	if _matching().size() == 1:
		return "confirm"
	return "choose"


func _more(acts: Array, key: String, have: Array) -> bool:
	for action in acts:
		if action.get(key, []).size() > have.size():
			return true
	return false


func _any_lane(acts: Array) -> bool:
	for action in acts:
		if action.has("lane"):
			return true
	return false


func _next_is(key: String, iid: int) -> bool:
	var have: Array = targets
	if key == "tributes":
		have = tributes
	elif key == "discards":
		have = discards
	elif key == "picks":
		have = picks
	for action in _matching():
		var arr: Array = action.get(key, [])
		if have.size() < arr.size() and int(arr[have.size()]) == iid:
			return true
	return false


func _lane_open(lane_i: int) -> bool:
	for action in _matching():
		if int(action.get("lane", -1)) == lane_i:
			return true
	return false


func _attack_has_unit(iid: int) -> bool:
	for action in _matching():
		if str(action.get("target_kind", "")) == "unit" and int(action.get("target_iid", -1)) == iid:
			return true
	return false


func _attack_has_face() -> bool:
	for action in _matching():
		if str(action.get("target_kind", "")) == "warden":
			return true
	return false


func _marks() -> Dictionary:
	var marks := {"lanes": {}, "iids": {}}
	var need := _need()
	if mode == "" and int(duel.actor()) == HUMAN:
		for action in legal:
			if action.has("iid"):
				marks.iids[int(action.iid)] = true
		return marks
	for action in _matching():
		if need == "lane" and action.has("lane"):
			marks.lanes[int(action.lane)] = true
		elif need == "tribute":
			_mark_next(marks, action.get("tributes", []), tributes)
		elif need == "discard" or need == "shed":
			_mark_next(marks, action.get("discards", []), discards)
		elif need == "target":
			_mark_next(marks, action.get("targets", []), targets)
		elif need == "attack_target" and str(action.get("target_kind", "")) == "unit":
			marks.iids[int(action.get("target_iid", -1))] = true
		elif need == "pick":
			_mark_next(marks, action.get("picks", []), picks)
	if chosen_iid >= 0:
		marks.iids[chosen_iid] = true
	for iid in discards:
		marks.iids[int(iid)] = true
	return marks


func _mark_next(marks: Dictionary, arr: Array, have: Array) -> void:
	if have.size() < arr.size():
		marks.iids[int(arr[have.size()])] = true


func _marked(marks: Dictionary, iid: int, _zone: String) -> bool:
	return bool(marks.iids.get(iid, false))


func _prompt_text() -> String:
	if duel == null:
		return ""
	if int(duel.winner) >= 0:
		return "The duel is over."
	if int(duel.actor()) == BOT:
		return "Rook is choosing a legal line."
	match _need():
		"tribute":
			return "Choose a friendly unit to tribute."
		"discard", "shed":
			return "Choose cards to shed. Confirm when the cost is paid."
		"target":
			return "Choose the target. Board units and the list on the right both work."
		"pick":
			return "Search and choose a card."
		"lane":
			return "Choose an empty lane."
		"attack_target":
			return "Choose a unit, or click Rook to attack the warden. Guard must be faced first."
		"confirm":
			return "Confirm the play, or cancel."
		"none":
			return "That selection is no longer legal."
		_:
			if str(duel.window) == "priority" and int(duel.priority_player) == HUMAN:
				return "Priority is yours. Play an instant, reveal a set trap, or pass."
			if str(duel.phase) == "combat":
				return "Combat. Choose a ready unit, then its target. End combat when you are done."
			if str(duel.phase) == "main":
				return "Main phase. Play a unit, a spell, or set a trap. Gold marks a legal card."
			return "End step. Shed to seven cards if you must, then end the turn."


func _status_text() -> String:
	if int(duel.winner) >= 0:
		return "Duel over"
	var phase_name := str(duel.phase).capitalize()
	var round_no := int(duel.turn_number)
	if str(duel.window) == "focus" and int(duel.active) == HUMAN:
		return "Round %d  ·  Your %s" % [round_no, phase_name]
	if str(duel.window) == "focus":
		return "Round %d  ·  Rook's %s" % [round_no, phase_name]
	if int(duel.priority_player) == HUMAN:
		return "Round %d  ·  Your priority" % round_no
	return "Round %d  ·  Rook's priority" % round_no


func _chain_text() -> String:
	if duel.chain.is_empty():
		return "No chain."
	var text := "Chain  "
	var first := true
	for i in range(duel.chain.size() - 1, -1, -1):
		var link: Dictionary = duel.chain[i]
		if not first:
			text += "  >  "
		first = false
		text += _cname(str(link.get("def_id", "")))
		if bool(link.get("negated", false)):
			text += " (negated)"
	return text


func _log_text() -> String:
	var lines: PackedStringArray = []
	var start := maxi(0, duel.events.size() - 14)
	for i in range(start, duel.events.size()):
		var line := _event_line(duel.events[i])
		if line != "":
			lines.append(line)
	return "\n".join(lines)


func _event_line(ev: Dictionary) -> String:
	var type_name := str(ev.get("type", ""))
	var who := "You" if int(ev.get("player", 0)) == HUMAN else "Rook"
	match type_name:
		"play":
			return "%s plays %s" % [who, _cname(str(ev.get("def_id", "")))]
		"summon":
			return "Summon %s" % _cname(str(ev.get("def_id", "")))
		"damage":
			return "%s takes %s" % [who, str(ev.get("amount", ""))]
		"heal":
			return "%s heals %s" % [who, str(ev.get("amount", ""))]
		"destroy":
			return "Destroyed %s" % _cname(str(ev.get("def_id", "")))
		"silence":
			return "Silenced %s" % _cname(str(ev.get("def_id", "")))
		"trap_reveal":
			return "Trap %s" % _cname(str(ev.get("def_id", "")))
		"negate":
			return "Negated %s" % _cname(str(ev.get("def_id", "")))
		"win":
			return "%s wins by %s" % [who, str(ev.get("reason", ""))]
		"phase":
			return "Phase %s" % str(ev.get("phase", ""))
		_:
			return ""


func _on_hover(iid: int) -> void:
	if iid < 0 or duel == null:
		return
	var card = _scan(iid)
	if card == null:
		return
	var defn: Dictionary = db[str(card.def_id)]
	var text := str(defn.get("text", ""))
	for kw in defn.get("keywords", []):
		var key := str(kw)
		if KeywordScript.TEXT.has(key):
			text += "  %s: %s" % [key.capitalize(), KeywordScript.TEXT[key]]
	hint_label.text = text


func _choice_name(iid: int) -> String:
	var card = _scan(iid)
	if card == null:
		return "Card"
	if str(card.zone) == "veil" and int(card.owner) != HUMAN:
		return "Facedown veil card"
	return _cname(str(card.def_id))


func _scan(iid: int):
	for pid in [HUMAN, BOT]:
		var who: Dictionary = duel.players[pid]
		for zone in ["hand", "deck", "grave", "veil"]:
			for card in who[zone]:
				if int(card.iid) == iid:
					return card
		for card in who.board:
			if card != null and int(card.iid) == iid:
				return card
	return null


func _cname(def_id: String) -> String:
	if def_id == "" or not db.has(def_id):
		return "Effect"
	return str(db[def_id].get("name", def_id))


func _prefix(full: Array, partial: Array) -> bool:
	if partial.size() > full.size():
		return false
	for i in partial.size():
		if int(full[i]) != int(partial[i]):
			return false
	return true


func _subset(partial: Array, full: Array) -> bool:
	var seen := {}
	for item in full:
		seen[int(item)] = int(seen.get(int(item), 0)) + 1
	for item in partial:
		var key := int(item)
		if int(seen.get(key, 0)) <= 0:
			return false
		seen[key] = int(seen[key]) - 1
	return true
