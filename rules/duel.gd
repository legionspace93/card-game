class_name Duel
extends RefCounted

## Ashrift rules. View code may read this object and may change it only through apply().
##
## Turn: draw (first warden skips the first turn draw), main, combat, end.
## Each phase opens a priority gate. A declared play, attack, trap, or trigger
## goes on a chain. The opponent gets priority first. Two passes in a row
## resolve the chain from the top. Negate marks a lower link so it fizzles.
## Death, on-play, on-spell, and end listeners queue a new chain after the
## current one settles, so a death can chain into another effect.
##
## Spark is the growing resource (max 10). Some cards also ask for life
## (cannot pay below 1), tribute (destroy your units), or a chosen discard.
## Deck-out on a draw is a loss. Life at 0 or below is a loss. Max life is 30.

const LANES = 5
const START_LIFE = 30
const MAX_LIFE = 30
const MAX_ENERGY = 10
const HAND_LIMIT = 7
const HAND_CAP = 10
const VEIL_MAX = 3
const OPENING = 4

var db: Dictionary = {}
var players: Array = []
var rng = RandomNumberGenerator.new()
var active: int = 0
var turn_number: int = 1
var player_turn_index: int = 0
var phase: String = "main"
var window: String = "priority" # focus, priority, closed, over
var gate: String = "phase" # phase, advance, chain, ""
var priority_player: int = 1
var consecutive_passes: int = 0
var proposed_advance: bool = false
var after_chain: String = ""
var chain: Array = []
var trigger_queue: Array = []
var trigger_rounds: int = 0
var limbo: Dictionary = {}
var winner: int = -1
var win_reason: String = ""
var events: Array = []
var revision: int = 0
var next_iid: int = 1
var next_link: int = 1

func _init(card_db: Dictionary, list0: Array, list1: Array, seed_value: int = 1) -> void:
	db = card_db
	rng.seed = seed_value if seed_value != 0 else 1
	players = [_blank(), _blank()]
	for def_id in list0:
		_add_deck(0, str(def_id))
	for def_id in list1:
		_add_deck(1, str(def_id))
	_shuffle(players[0].deck)
	_shuffle(players[1].deck)
	for _i in OPENING:
		if winner >= 0:
			return
		_draw_one(0)
		if winner >= 0:
			return
		_draw_one(1)
	if winner < 0:
		_start_turn()


func actor() -> int:
	if winner >= 0:
		return -1
	if window == "priority":
		return priority_player
	if window == "focus":
		return active
	return -1


func apply(pid: int, action: Dictionary) -> Dictionary:
	var reason = validate(pid, action)
	if reason != "":
		return {"ok": false, "reason": reason}
	_commit(pid, action)
	revision += 1
	return {"ok": true}


func validate(pid: int, action: Dictionary) -> String:
	if winner >= 0:
		return "game over"
	var kind = str(action.get("type", ""))
	match kind:
		"pass":
			if window != "priority" or pid != priority_player:
				return "cannot pass"
			return ""
		"end_phase":
			if window != "focus" or pid != active:
				return "cannot end"
			if phase == "end" and players[pid].hand.size() > HAND_LIMIT:
				return "discard first"
			return ""
		"discard_down":
			return _validate_discard_down(pid, action)
		"play":
			return _validate_play(pid, action)
		"set_trap":
			return _validate_set(pid, action)
		"activate":
			return _validate_activate(pid, action)
		"attack":
			return _validate_attack(pid, action)
		_:
			return "unknown action"


func legal_actions(pid: int) -> Array:
	var raw: Array = []
	if winner >= 0:
		return raw
	raw.append({"type": "pass"})
	raw.append({"type": "end_phase"})
	_collect_discards(pid, raw)
	_collect_from_hand(pid, raw)
	_collect_activates(pid, raw)
	_collect_attacks(pid, raw)
	var out: Array = []
	for action in raw:
		if validate(pid, action) == "":
			out.append(action)
	return out


func attack_value(unit) -> int:
	if typeof(unit) == TYPE_INT or typeof(unit) == TYPE_FLOAT:
		unit = _live_unit(int(unit))
	if unit == null:
		return 0
	var total: int = int(unit.atk)
	for other in _each_board(false):
		if other.iid == unit.iid or other.silenced:
			continue
		for hook in other.hooks.get("while_board", []):
			if hook.get("op") == "aura_atk" and hook.get("who") == "other_friendly" and other.owner == unit.owner:
				total += int(hook.get("amount", 0))
	return maxi(0, total)


func link_kind(link: Dictionary) -> String:
	match str(link.get("kind", "")):
		"play_unit":
			return "summon"
		"cast_spell":
			return "spell"
		"set_trap":
			return "set"
		"activate_trap":
			return "trap"
		"attack":
			return "attack"
		"trigger":
			return "trigger"
		_:
			return ""


func top_match(kind: String):
	for i in range(chain.size() - 1, -1, -1):
		var link: Dictionary = chain[i]
		if link.get("negated", false):
			continue
		var have = link_kind(link)
		if kind == "any" or kind == have:
			return link
	return null


func debug_begin(phase_name: String) -> void:
	phase = phase_name
	window = "focus"
	gate = ""
	proposed_advance = false
	after_chain = ""
	consecutive_passes = 0
	priority_player = active
	chain.clear()
	trigger_queue.clear()
	limbo.clear()


func debug_hand(pid: int, def_id: String) -> int:
	var card = _make_card(def_id, pid)
	card.zone = "hand"
	players[pid].hand.append(card)
	return card.iid


func debug_deck(pid: int, def_id: String) -> int:
	return _add_deck(pid, def_id)


func debug_place(pid: int, def_id: String, lane: int, ready: bool = false) -> int:
	if lane < 0 or lane >= LANES or players[pid].board[lane] != null:
		return -1
	var card = _make_card(def_id, pid)
	_enter(card, pid, lane)
	if ready:
		card.sick = false
		card.attacks_left = _strikes(card)
	else:
		card.sick = true
		card.attacks_left = 0
	return card.iid


func debug_veil(pid: int, def_id: String, stamp: int = 0) -> int:
	var card = _make_card(def_id, pid)
	card.zone = "veil"
	card.set_stamp = stamp
	players[pid].veil.append(card)
	return card.iid


func debug_life(pid: int, value: int) -> void:
	players[pid].life = value


func debug_energy(pid: int, value: int) -> void:
	players[pid].energy = value
	players[pid].max_energy = maxi(int(players[pid].max_energy), value)


func _blank() -> Dictionary:
	return {
		"life": START_LIFE,
		"energy": 0,
		"max_energy": 0,
		"life_paid": false,
		"deck": [],
		"hand": [],
		"board": [null, null, null, null, null],
		"grave": [],
		"veil": [],
	}


func _add_deck(pid: int, def_id: String) -> int:
	if not db.has(def_id):
		push_error("Unknown card %s" % def_id)
		return -1
	var card = _make_card(def_id, pid)
	card.zone = "deck"
	players[pid].deck.append(card)
	return card.iid


func _make_card(def_id: String, owner: int) -> Dictionary:
	var defn: Dictionary = db[def_id]
	var card = {
		"iid": next_iid,
		"def_id": def_id,
		"owner": owner,
		"zone": "deck",
		"lane": -1,
		"set_stamp": -1,
		"silenced": false,
		"sick": true,
		"doomed": false,
		"attacks_left": 0,
	}
	next_iid += 1
	_reset_card(card)
	card.zone = "deck"
	return card


func _reset_card(card: Dictionary) -> void:
	var defn: Dictionary = db[card.def_id]
	var hp = int(defn.get("hp", 0))
	var atk = int(defn.get("atk", 0))
	card.atk = atk
	card.hp = hp
	card.max_hp = hp
	card.base_atk = atk
	card.base_hp = hp
	card.keywords = (defn.get("keywords", []) as Array).duplicate()
	card.hooks = (defn.get("hooks", {}) as Dictionary).duplicate(true)
	card.silenced = false
	card.sick = true
	card.attacks_left = 0
	card.doomed = false
	card.lane = -1


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _start_turn() -> void:
	if winner >= 0:
		return
	player_turn_index += 1
	trigger_rounds = 0
	var who: Dictionary = players[active]
	who.life_paid = false
	if int(who.max_energy) < MAX_ENERGY:
		who.max_energy = int(who.max_energy) + 1
	who.energy = int(who.max_energy)
	for unit in _each_board(false):
		if unit.owner != active:
			continue
		unit.sick = false
		unit.attacks_left = _strikes(unit)
	phase = "draw"
	_emit({"type": "phase", "phase": "draw", "player": active})
	if player_turn_index != 1:
		_draw_one(active)
		if winner >= 0:
			return
	phase = "main"
	_emit({"type": "phase", "phase": "main", "player": active})
	_open_phase_gate()


func _switch_turn() -> void:
	if winner >= 0:
		return
	if active == 1:
		turn_number += 1
	active = 1 - active
	_start_turn()


func _draw_one(pid: int) -> void:
	var who: Dictionary = players[pid]
	if who.deck.is_empty():
		_set_winner(1 - pid, "deck")
		return
	var card: Dictionary = who.deck.pop_front()
	if who.hand.size() >= HAND_CAP:
		_add_grave(card)
		_emit({"type": "mill", "player": pid, "iid": card.iid, "def_id": card.def_id, "via": "cap"})
		return
	card.zone = "hand"
	who.hand.append(card)
	_emit({"type": "draw", "player": pid, "iid": card.iid, "def_id": card.def_id})


func _commit(pid: int, action: Dictionary) -> void:
	match str(action.get("type", "")):
		"pass":
			_commit_pass()
		"end_phase":
			_commit_end()
		"discard_down":
			_commit_discard_down(pid, action)
		"play":
			_commit_play(pid, action)
		"set_trap":
			_commit_set(pid, action)
		"activate":
			_commit_activate(pid, action)
		"attack":
			_commit_attack(pid, action)


func _commit_pass() -> void:
	consecutive_passes += 1
	if consecutive_passes < 2:
		priority_player = 1 - priority_player
		_emit({"type": "priority", "player": priority_player, "gate": gate})
		return
	consecutive_passes = 0
	if gate == "phase":
		_enter_focus()
	elif gate == "advance":
		proposed_advance = false
		gate = ""
		_advance_phase()
	elif gate == "chain":
		_resolve_all()
	else:
		_enter_focus()


func _commit_end() -> void:
	proposed_advance = true
	gate = "advance"
	window = "priority"
	priority_player = 1 - active
	consecutive_passes = 0
	_emit({"type": "priority", "player": priority_player, "gate": gate})


func _commit_discard_down(pid: int, action: Dictionary) -> void:
	for iid in action.get("discards", []):
		var card = _hand_card(pid, int(iid))
		if card == null:
			continue
		_remove_zone(card)
		_add_grave(card)
		_emit({"type": "discard", "player": pid, "iid": card.iid, "def_id": card.def_id, "via": "hand"})


func _commit_play(pid: int, action: Dictionary) -> void:
	var card = _hand_card(pid, int(action.get("iid", -1)))
	var defn: Dictionary = db[card.def_id]
	_pay(pid, card, action, defn)
	_remove_zone(card)
	card.zone = "limbo"
	limbo[card.iid] = card
	var kind = "cast_spell" if str(defn.get("type")) == "spell" else "play_unit"
	var link = _make_link(kind, pid, card, action, (defn.get("effects", []) as Array).duplicate(true), str(defn.get("answers", "")))
	chain.append(link)
	_emit({
		"type": "play",
		"player": pid,
		"iid": card.iid,
		"def_id": card.def_id,
		"lane": int(action.get("lane", -1)),
		"kind": kind,
	})
	_open_chain_priority()


func _commit_set(pid: int, action: Dictionary) -> void:
	var card = _hand_card(pid, int(action.get("iid", -1)))
	var defn: Dictionary = db[card.def_id]
	_pay(pid, card, action, defn)
	_remove_zone(card)
	card.zone = "limbo"
	limbo[card.iid] = card
	var link = _make_link("set_trap", pid, card, action, [], "")
	chain.append(link)
	_emit({"type": "play", "player": pid, "iid": card.iid, "def_id": card.def_id, "kind": "set_trap"})
	_open_chain_priority()


func _commit_activate(pid: int, action: Dictionary) -> void:
	var card = _veil_card(pid, int(action.get("iid", -1)))
	var defn: Dictionary = db[card.def_id]
	var trigger = str(defn.get("trigger", ""))
	var matched = top_match(trigger)
	var ctx = {}
	if matched != null:
		ctx = (matched.get("context", {}) as Dictionary).duplicate(true)
	_remove_zone(card)
	card.zone = "limbo"
	limbo[card.iid] = card
	var link = _make_link("activate_trap", pid, card, action, (defn.get("effects", []) as Array).duplicate(true), trigger)
	link.context = ctx
	chain.append(link)
	_emit({"type": "play", "player": pid, "iid": card.iid, "def_id": card.def_id, "kind": "activate_trap"})
	_emit({"type": "trap_reveal", "player": pid, "iid": card.iid, "def_id": card.def_id})
	_open_chain_priority()


func _commit_attack(pid: int, action: Dictionary) -> void:
	var unit = _live_unit(int(action.get("iid", -1)))
	unit.attacks_left = int(unit.attacks_left) - 1
	var target_kind = str(action.get("target_kind", ""))
	var target_iid = int(action.get("target_iid", -1))
	var target_player = 1 - pid
	var target_lane = -1
	if target_kind == "unit":
		var tgt = _live_unit(target_iid)
		target_player = int(tgt.owner)
		target_lane = int(tgt.lane)
	var link = {
		"id": next_link,
		"kind": "attack",
		"controller": pid,
		"iid": unit.iid,
		"def_id": unit.def_id,
		"lane": int(unit.lane),
		"targets": [],
		"picks": [],
		"effects": [],
		"answers": "",
		"negated": false,
		"context": {
			"attacker_iid": unit.iid,
			"target_kind": target_kind,
			"target_iid": target_iid,
			"target_player": target_player,
			"target_lane": target_lane,
		},
	}
	next_link += 1
	chain.append(link)
	_emit({
		"type": "attack",
		"player": pid,
		"iid": unit.iid,
		"def_id": unit.def_id,
		"lane": int(unit.lane),
		"target_kind": target_kind,
		"target_iid": target_iid,
		"target_player": target_player,
		"target_lane": target_lane,
	})
	_open_chain_priority()


func _pay(pid: int, card: Dictionary, action: Dictionary, defn: Dictionary) -> void:
	var who: Dictionary = players[pid]
	var tax = _spell_tax(pid, defn)
	who.energy = int(who.energy) - int(defn.get("cost", 0)) - tax
	var alt = defn.get("alt", null)
	if typeof(alt) != TYPE_DICTIONARY:
		return
	if str(alt.get("type", "")) == "life":
		var amount = int(alt.get("amount", 0))
		who.life = int(who.life) - amount
		who.life_paid = true
		_emit({"type": "damage", "amount": amount, "player": pid, "target": "warden", "via": "life"})
	elif str(alt.get("type", "")) == "discard":
		for iid in action.get("discards", []):
			var shed = _hand_card(pid, int(iid))
			if shed == null:
				continue
			_remove_zone(shed)
			_add_grave(shed)
			_emit({"type": "discard", "player": pid, "iid": shed.iid, "def_id": shed.def_id, "via": "cost"})
	elif str(alt.get("type", "")) == "tribute":
		for iid in action.get("tributes", []):
			var unit = _live_unit(int(iid))
			if unit != null:
				_kill_unit(unit)


func _open_chain_priority() -> void:
	proposed_advance = false
	gate = "chain"
	window = "priority"
	consecutive_passes = 0
	var top: Dictionary = chain[chain.size() - 1]
	priority_player = 1 - int(top.get("controller", active))
	_emit({"type": "priority", "player": priority_player, "gate": "chain"})


func _open_phase_gate() -> void:
	if winner >= 0:
		return
	gate = "phase"
	window = "priority"
	priority_player = 1 - active
	consecutive_passes = 0
	_emit({"type": "priority", "player": priority_player, "gate": "phase"})


func _enter_focus() -> void:
	if winner >= 0:
		window = "over"
		return
	gate = ""
	window = "focus"
	priority_player = active
	consecutive_passes = 0
	_emit({"type": "priority", "player": active, "gate": "focus"})


func _advance_phase() -> void:
	if phase == "main":
		phase = "combat"
		_emit({"type": "phase", "phase": "combat", "player": active})
		_open_phase_gate()
	elif phase == "combat":
		phase = "end"
		_emit({"type": "phase", "phase": "end", "player": active})
		_open_phase_gate()
	elif phase == "end":
		_begin_finish_turn()


func _begin_finish_turn() -> void:
	for unit in _each_board(false):
		if unit.owner != active or unit.silenced:
			continue
		for hook in unit.hooks.get("while_board", []):
			if hook.get("op") == "listen" and hook.get("event") == "your_end":
				_queue_trigger(unit.owner, unit.iid, hook.get("effects", []), "while_board", [], [], {})
	if trigger_queue.is_empty():
		_switch_turn()
	else:
		after_chain = "finish_turn"
		_present_triggers()


func _resolve_all() -> void:
	window = "closed"
	while not chain.is_empty() and winner < 0:
		var link: Dictionary = chain.pop_back()
		_resolve_link(link)
		if winner < 0:
			_sweep_deaths()
	if winner >= 0:
		return
	if _present_triggers():
		return
	_after_chains_settled()


func _present_triggers() -> bool:
	if trigger_queue.is_empty() or winner >= 0:
		return false
	trigger_rounds += 1
	if trigger_rounds > 80:
		trigger_queue.clear()
		push_error("Trigger chain cap hit")
		return false
	var items = trigger_queue.duplicate()
	trigger_queue.clear()
	for i in range(items.size() - 1, -1, -1):
		chain.append(items[i])
	_open_chain_priority()
	return true


func _after_chains_settled() -> void:
	if after_chain == "finish_turn":
		after_chain = ""
		_switch_turn()
		return
	_enter_focus()


func _resolve_link(link: Dictionary) -> void:
	_emit({
		"type": "chain_resolve",
		"kind": str(link.get("kind", "")),
		"player": int(link.get("controller", 0)),
		"iid": int(link.get("iid", -1)),
		"def_id": str(link.get("def_id", "")),
		"negated": bool(link.get("negated", false)),
		"hook": str(link.get("hook", "")),
	})
	match str(link.get("kind", "")):
		"play_unit":
			_resolve_unit(link)
		"cast_spell":
			_resolve_spell(link)
		"set_trap":
			_resolve_set(link)
		"activate_trap":
			_resolve_trap(link)
		"attack":
			_resolve_attack(link)
		"trigger":
			_resolve_trigger(link)


func _take_limbo(link: Dictionary):
	var iid = int(link.get("iid", -1))
	if not limbo.has(iid):
		return null
	var card: Dictionary = limbo[iid]
	limbo.erase(iid)
	return card


func _resolve_unit(link: Dictionary) -> void:
	var card = _take_limbo(link)
	if card == null:
		return
	if link.get("negated", false) or winner >= 0:
		_add_grave(card)
		_emit({"type": "negate", "player": int(link.controller), "iid": card.iid, "def_id": card.def_id, "what": "summon"})
		return
	var lane = int(link.get("lane", -1))
	var pid = int(link.controller)
	if lane < 0 or lane >= LANES or players[pid].board[lane] != null:
		_add_grave(card)
		return
	_enter(card, pid, lane)
	_emit({"type": "summon", "player": pid, "iid": card.iid, "def_id": card.def_id, "lane": lane})
	var hooks: Array = card.hooks.get("on_play", [])
	if hooks.size() > 0 and not card.silenced:
		_queue_trigger(pid, card.iid, hooks, "on_play", link.get("targets", []), link.get("picks", []), link.get("context", {}))


func _resolve_spell(link: Dictionary) -> void:
	var card = _take_limbo(link)
	if card != null:
		_add_grave(card)
	if link.get("negated", false) or winner >= 0:
		_emit({"type": "negate", "player": int(link.controller), "iid": int(link.get("iid", -1)), "def_id": str(link.get("def_id", "")), "what": "spell"})
		return
	_run_effects(link.get("effects", []), int(link.controller), null, link)
	if winner >= 0:
		return
	for unit in _each_board(false):
		if unit.owner != int(link.controller) or unit.silenced:
			continue
		var hooks: Array = unit.hooks.get("on_spell", [])
		if hooks.size() > 0:
			_queue_trigger(unit.owner, unit.iid, hooks, "on_spell", [], [], {})


func _resolve_set(link: Dictionary) -> void:
	var card = _take_limbo(link)
	if card == null:
		return
	if link.get("negated", false) or winner >= 0:
		_add_grave(card)
		return
	if players[int(card.owner)].veil.size() >= VEIL_MAX:
		_add_grave(card)
		return
	card.zone = "veil"
	card.set_stamp = player_turn_index
	players[int(card.owner)].veil.append(card)


func _resolve_trap(link: Dictionary) -> void:
	var card = _take_limbo(link)
	if not link.get("negated", false) and winner < 0:
		_run_effects(link.get("effects", []), int(link.controller), null, link)
	if card != null:
		_add_grave(card)


func _resolve_trigger(link: Dictionary) -> void:
	if link.get("negated", false) or winner >= 0:
		return
	var source = _live_unit(int(link.get("source_iid", -1)))
	_run_effects(link.get("effects", []), int(link.controller), source, link)


func _resolve_attack(link: Dictionary) -> void:
	if link.get("negated", false) or winner >= 0:
		return
	var ctx: Dictionary = link.get("context", {})
	var attacker = _live_unit(int(ctx.get("attacker_iid", -1)))
	if attacker == null:
		return
	if not attacker.silenced:
		var hooks: Array = attacker.hooks.get("on_attack", [])
		if hooks.size() > 0:
			_run_effects(hooks, int(attacker.owner), attacker, link)
	if winner >= 0:
		return
	attacker = _live_unit(int(ctx.get("attacker_iid", -1)))
	if attacker == null:
		return
	if str(ctx.get("target_kind", "")) == "warden":
		if _enemy_has_guard(int(attacker.owner)) and not attacker.keywords.has("breach"):
			return
		_damage_warden(int(ctx.get("target_player", 0)), attack_value(attacker), "combat")
		return
	var defender = _live_unit(int(ctx.get("target_iid", -1)))
	if defender == null:
		return
	if _enemy_has_guard(int(attacker.owner)) and not defender.keywords.has("guard") and not attacker.keywords.has("breach"):
		return
	var strike = attack_value(attacker)
	var reply = attack_value(defender)
	var defender_hp = int(defender.hp)
	var dealt = _damage_unit(defender, strike, "combat")
	var back = 0
	if _live_unit(int(attacker.iid)) != null:
		back = _damage_unit(attacker, reply, "combat")
	if dealt > 0 and attacker.keywords.has("pierce"):
		var excess = strike - defender_hp
		if excess > 0:
			_damage_warden(int(defender.owner), excess, "pierce")
	if dealt > 0 and attacker.keywords.has("venom") and defender.zone == "board":
		defender.doomed = true
		defender.hp = 0
	if back > 0 and defender.keywords.has("venom") and attacker.zone == "board":
		attacker.doomed = true
		attacker.hp = 0
	if dealt > 0 and attacker.keywords.has("siphon"):
		_heal_warden(int(attacker.owner), dealt)
	if back > 0 and defender.keywords.has("siphon"):
		_heal_warden(int(defender.owner), back)


func _run_effects(effects: Array, actor_id: int, source, link: Dictionary) -> void:
	for effect in effects:
		if winner >= 0:
			return
		if not _cond_ok(effect.get("if", null), actor_id, link):
			continue
		_run_one(effect, actor_id, source, link)
		if winner >= 0:
			return
		_sweep_deaths()


func _run_one(effect: Dictionary, actor_id: int, source, link: Dictionary) -> void:
	var op = str(effect.get("op", ""))
	var targets = _collect(effect.get("target", {}), actor_id, source, link)
	match op:
		"damage":
			for tgt in targets:
				_damage_target(tgt, int(effect.get("amount", 0)), "effect")
		"heal":
			for tgt in targets:
				_heal_target(tgt, int(effect.get("amount", 0)))
		"buff":
			for tgt in targets:
				_buff_unit(tgt, int(effect.get("atk", 0)), int(effect.get("hp", 0)))
		"silence":
			for tgt in targets:
				_silence_unit(tgt)
		"destroy":
			for tgt in targets:
				_mark_destroy(tgt)
		"bounce":
			for tgt in targets:
				_bounce_unit(tgt)
		"draw":
			if _is_player_scope(effect):
				for _n in int(effect.get("amount", 0)):
					if winner >= 0:
						return
					_draw_one(_scope_player(effect, actor_id))
		"mill":
			if _is_player_scope(effect):
				_mill(_scope_player(effect, actor_id), int(effect.get("amount", 0)))
		"shed":
			if _is_player_scope(effect):
				_shed(_scope_player(effect, actor_id), int(effect.get("amount", 0)))
		"ramp":
			_ramp(actor_id, int(effect.get("amount", 0)))
		"summon":
			_summon_token(actor_id, str(effect.get("card", "")))
		"fetch":
			_fetch(actor_id, str(effect.get("type", "any")))
		"take_pick":
			_take_pick(actor_id, link, int(effect.get("index", 0)), str(effect.get("dest", "hand")))
		"grant_keyword":
			for tgt in targets:
				_grant(tgt, str(effect.get("keyword", "")))
		"ready":
			for tgt in targets:
				_ready_unit(tgt)
		"set_stats":
			for tgt in targets:
				_set_stats(tgt, int(effect.get("atk", 0)), int(effect.get("hp", 0)))
		"negate":
			_apply_negate(link)


func _cond_ok(cond, actor_id: int, link: Dictionary) -> bool:
	if typeof(cond) != TYPE_DICTIONARY:
		return true
	var kind = str(cond.get("kind", ""))
	var who: Dictionary = players[actor_id]
	match kind:
		"life_paid_this_turn":
			return bool(who.life_paid)
		"your_grave_at_least":
			return who.grave.size() >= int(cond.get("n", 0))
		"you_control_keyword":
			return _controls_keyword(actor_id, str(cond.get("keyword", "")))
		"your_hand_at_most":
			return who.hand.size() <= int(cond.get("n", 0))
		"self_life_below":
			return int(who.life) < int(cond.get("n", 0))
		"event_attacker_atk_at_most":
			var atk_unit = _live_unit(int(link.get("context", {}).get("attacker_iid", -1)))
			return atk_unit != null and attack_value(atk_unit) <= int(cond.get("n", 0))
		"event_attacker_has_keyword":
			var kw_unit = _live_unit(int(link.get("context", {}).get("attacker_iid", -1)))
			return kw_unit != null and kw_unit.keywords.has(str(cond.get("keyword", "")))
		_:
			return false


func _is_player_scope(effect: Dictionary) -> bool:
	var tgt = effect.get("target", {})
	if typeof(tgt) != TYPE_DICTIONARY:
		return false
	var scope = str(tgt.get("scope", ""))
	return scope == "you" or scope == "opponent"


func _scope_player(effect: Dictionary, actor_id: int) -> int:
	if str(effect.get("target", {}).get("scope", "")) == "opponent":
		return 1 - actor_id
	return actor_id


func _collect(spec, actor_id: int, source, link: Dictionary) -> Array:
	var out: Array = []
	if typeof(spec) != TYPE_DICTIONARY:
		return out
	if spec.has("ref"):
		var idx = int(spec.get("ref", 0))
		var targets: Array = link.get("targets", [])
		if idx < 0 or idx >= targets.size():
			return out
		var iid = int(targets[idx])
		var live = _live_unit(iid)
		if live != null:
			out.append(live)
			return out
		var card = _find(iid)
		if card != null and str(card.zone) == "veil":
			out.append(card)
		return out
	var scope = str(spec.get("scope", ""))
	match scope:
		"your_warden":
			out.append({"warden": actor_id})
		"opponent_warden":
			out.append({"warden": 1 - actor_id})
		"self":
			if source != null and _live_unit(int(source.iid)) != null:
				out.append(source)
		"all_enemy_units":
			for unit in _each_board(false):
				if unit.owner != actor_id:
					out.append(unit)
		"all_friendly_units":
			for unit in _each_board(false):
				if unit.owner == actor_id:
					out.append(unit)
		"all_units":
			for unit in _each_board(false):
				out.append(unit)
		"other_friendly":
			for unit in _each_board(false):
				if unit.owner == actor_id and (source == null or unit.iid != source.iid):
					out.append(unit)
		"all_units_except_self":
			for unit in _each_board(false):
				if source == null or unit.iid != source.iid:
					out.append(unit)
		"event_attacker":
			var attacker = _live_unit(int(link.get("context", {}).get("attacker_iid", -1)))
			if attacker != null:
				out.append(attacker)
		"event_defender":
			var ctx: Dictionary = link.get("context", {})
			if str(ctx.get("target_kind", "")) == "unit":
				var defender = _live_unit(int(ctx.get("target_iid", -1)))
				if defender != null:
					out.append(defender)
	return out


func _damage_target(tgt, amount: int, via: String) -> void:
	if typeof(tgt) != TYPE_DICTIONARY or amount <= 0:
		return
	if tgt.has("warden"):
		_damage_warden(int(tgt.warden), amount, via)
	else:
		_damage_unit(tgt, amount, via)


func _heal_target(tgt, amount: int) -> void:
	if typeof(tgt) != TYPE_DICTIONARY or amount <= 0:
		return
	if tgt.has("warden"):
		_heal_warden(int(tgt.warden), amount)
	else:
		_heal_unit(tgt, amount)


func _damage_unit(unit: Dictionary, amount: int, via: String) -> int:
	if amount <= 0 or unit.zone != "board":
		return 0
	if unit.keywords.has("ward"):
		unit.keywords.erase("ward")
		_emit({"type": "ward", "player": int(unit.owner), "iid": unit.iid, "def_id": unit.def_id, "lane": int(unit.lane)})
		return 0
	unit.hp = int(unit.hp) - amount
	_emit({
		"type": "damage",
		"amount": amount,
		"player": int(unit.owner),
		"iid": unit.iid,
		"def_id": unit.def_id,
		"lane": int(unit.lane),
		"target": "unit",
		"via": via,
	})
	return amount


func _damage_warden(pid: int, amount: int, via: String) -> void:
	if amount <= 0 or winner >= 0:
		return
	players[pid].life = int(players[pid].life) - amount
	_emit({"type": "damage", "amount": amount, "player": pid, "target": "warden", "via": via})
	if int(players[pid].life) <= 0:
		_set_winner(1 - pid, "life")


func _heal_unit(unit: Dictionary, amount: int) -> void:
	if unit.zone != "board" or unit.doomed or int(unit.hp) <= 0:
		return
	var before = int(unit.hp)
	unit.hp = mini(int(unit.max_hp), before + amount)
	var gained = int(unit.hp) - before
	if gained > 0:
		_emit({"type": "heal", "amount": gained, "player": int(unit.owner), "iid": unit.iid, "def_id": unit.def_id, "lane": int(unit.lane), "target": "unit"})


func _heal_warden(pid: int, amount: int) -> void:
	if amount <= 0 or winner >= 0:
		return
	var before = int(players[pid].life)
	players[pid].life = mini(MAX_LIFE, before + amount)
	var gained = int(players[pid].life) - before
	if gained > 0:
		_emit({"type": "heal", "amount": gained, "player": pid, "target": "warden"})


func _buff_unit(unit: Dictionary, atk: int, hp: int) -> void:
	if unit.zone != "board" or (atk == 0 and hp == 0):
		return
	unit.atk = int(unit.atk) + atk
	unit.max_hp = int(unit.max_hp) + hp
	unit.hp = int(unit.hp) + hp
	_emit({"type": "buff", "player": int(unit.owner), "iid": unit.iid, "def_id": unit.def_id, "lane": int(unit.lane), "atk": atk, "hp": hp})


func _silence_unit(unit: Dictionary) -> void:
	if unit.zone != "board" or unit.silenced:
		return
	var missing = maxi(0, int(unit.max_hp) - int(unit.hp))
	unit.silenced = true
	unit.keywords = []
	unit.hooks = {}
	unit.atk = int(unit.base_atk)
	unit.max_hp = int(unit.base_hp)
	unit.hp = int(unit.max_hp) - missing
	_emit({"type": "silence", "player": int(unit.owner), "iid": unit.iid, "def_id": unit.def_id, "lane": int(unit.lane)})


func _mark_destroy(card: Dictionary) -> void:
	if card.has("warden"):
		return
	if str(card.zone) == "board":
		card.doomed = true
		card.hp = 0
		return
	if str(card.zone) == "veil":
		var owner = int(card.owner)
		var iid = int(card.iid)
		var def_id = str(card.def_id)
		_remove_zone(card)
		_add_grave(card)
		_emit({"type": "destroy", "player": owner, "iid": iid, "def_id": def_id, "zone": "veil"})


func _bounce_unit(unit: Dictionary) -> void:
	if unit.zone != "board":
		return
	var owner = int(unit.owner)
	var lane = int(unit.lane)
	_remove_board(unit)
	_reset_card(unit)
	if players[owner].hand.size() >= HAND_CAP:
		_add_grave(unit)
		_emit({"type": "mill", "player": owner, "iid": unit.iid, "def_id": unit.def_id, "via": "bounce"})
		return
	unit.zone = "hand"
	players[owner].hand.append(unit)
	_emit({"type": "bounce", "player": owner, "iid": unit.iid, "def_id": unit.def_id, "lane": lane})


func _mill(pid: int, amount: int) -> void:
	for _n in amount:
		if players[pid].deck.is_empty():
			return
		var card: Dictionary = players[pid].deck.pop_front()
		_add_grave(card)
		_emit({"type": "mill", "player": pid, "iid": card.iid, "def_id": card.def_id})


func _shed(pid: int, amount: int) -> void:
	for _n in amount:
		var card = _cheapest_hand(pid)
		if card == null:
			return
		_remove_zone(card)
		_add_grave(card)
		_emit({"type": "discard", "player": pid, "iid": card.iid, "def_id": card.def_id, "via": "shed"})


func _cheapest_hand(pid: int):
	var best = null
	for card in players[pid].hand:
		if best == null or _cheaper(card, best):
			best = card
	return best


func _cheaper(a: Dictionary, b: Dictionary) -> bool:
	var ca = int(db[a.def_id].get("cost", 0))
	var cb = int(db[b.def_id].get("cost", 0))
	if ca != cb:
		return ca < cb
	if str(a.def_id) != str(b.def_id):
		return str(a.def_id) < str(b.def_id)
	return int(a.iid) < int(b.iid)


func _ramp(pid: int, amount: int) -> void:
	if amount <= 0:
		return
	var who: Dictionary = players[pid]
	who.max_energy = mini(MAX_ENERGY, int(who.max_energy) + amount)
	who.energy = mini(MAX_ENERGY, int(who.energy) + amount)
	_emit({"type": "ramp", "player": pid, "amount": amount})


func _summon_token(actor_id: int, def_id: String) -> void:
	if not db.has(def_id):
		return
	var lane = _first_empty(actor_id)
	if lane < 0:
		return
	var card = _make_card(def_id, actor_id)
	_enter(card, actor_id, lane)
	_emit({"type": "summon", "player": actor_id, "iid": card.iid, "def_id": def_id, "lane": lane, "token": true})
	var hooks: Array = card.hooks.get("on_play", [])
	if hooks.size() > 0:
		_queue_trigger(actor_id, card.iid, hooks, "on_play", [], [], {})


func _fetch(actor_id: int, type_name: String) -> void:
	var best = null
	for card in players[actor_id].deck:
		if type_name != "any" and str(db[card.def_id].get("type", "")) != type_name:
			continue
		if best == null or _cheaper(card, best):
			best = card
	if best == null:
		return
	_remove_zone(best)
	_reset_card(best)
	_to_hand_or_grave(best, "fetch")


func _take_pick(actor_id: int, link: Dictionary, index: int, dest: String) -> void:
	var picks: Array = link.get("picks", [])
	if index < 0 or index >= picks.size():
		return
	var card = _find(int(picks[index]))
	if card == null or int(card.owner) != actor_id:
		return
	if str(card.zone) != "deck" and str(card.zone) != "grave":
		return
	_remove_zone(card)
	_reset_card(card)
	if dest == "board":
		var lane = _first_empty(actor_id)
		if lane >= 0:
			_enter(card, actor_id, lane)
			_emit({"type": "summon", "player": actor_id, "iid": card.iid, "def_id": card.def_id, "lane": lane})
			return
	_to_hand_or_grave(card, "tutor")


func _to_hand_or_grave(card: Dictionary, via: String) -> void:
	var pid = int(card.owner)
	if players[pid].hand.size() >= HAND_CAP:
		_add_grave(card)
		_emit({"type": "mill", "player": pid, "iid": card.iid, "def_id": card.def_id, "via": via})
		return
	card.zone = "hand"
	players[pid].hand.append(card)
	_emit({"type": "draw", "player": pid, "iid": card.iid, "def_id": card.def_id, "via": via})


func _grant(unit: Dictionary, keyword: String) -> void:
	if unit.zone != "board" or unit.silenced or keyword == "":
		return
	if unit.keywords.has(keyword):
		return
	unit.keywords.append(keyword)
	_emit({"type": "buff", "player": int(unit.owner), "iid": unit.iid, "def_id": unit.def_id, "lane": int(unit.lane), "keyword": keyword, "atk": 0, "hp": 0})


func _ready_unit(unit: Dictionary) -> void:
	if unit.zone != "board":
		return
	unit.sick = false
	unit.attacks_left = _strikes(unit)
	_emit({"type": "buff", "player": int(unit.owner), "iid": unit.iid, "def_id": unit.def_id, "lane": int(unit.lane), "ready": true, "atk": 0, "hp": 0})


func _set_stats(unit: Dictionary, atk: int, hp: int) -> void:
	if unit.zone != "board":
		return
	unit.base_atk = atk
	unit.base_hp = hp
	unit.atk = atk
	unit.max_hp = hp
	unit.hp = hp
	_emit({"type": "buff", "player": int(unit.owner), "iid": unit.iid, "def_id": unit.def_id, "lane": int(unit.lane), "atk": atk, "hp": hp, "set": true})


func _apply_negate(link: Dictionary) -> void:
	var want = str(link.get("answers", ""))
	if want == "":
		return
	for i in range(chain.size() - 1, -1, -1):
		var other: Dictionary = chain[i]
		if other.get("negated", false):
			continue
		if want == "any" or link_kind(other) == want:
			other.negated = true
			_emit({"type": "negate", "player": int(link.get("controller", 0)), "iid": int(other.get("iid", -1)), "def_id": str(other.get("def_id", "")), "what": link_kind(other)})
			return


func _queue_trigger(controller: int, source_iid: int, effects: Array, hook: String, targets: Array, picks: Array, context) -> void:
	trigger_queue.append({
		"id": next_link,
		"kind": "trigger",
		"controller": controller,
		"iid": source_iid,
		"source_iid": source_iid,
		"def_id": "",
		"hook": hook,
		"effects": effects.duplicate(true),
		"targets": _ints(targets),
		"picks": _ints(picks),
		"answers": "",
		"negated": false,
		"context": context.duplicate(true) if typeof(context) == TYPE_DICTIONARY else {},
	})
	var src = _find(source_iid)
	if src != null:
		trigger_queue[trigger_queue.size() - 1].def_id = src.def_id
	next_link += 1


func _sweep_deaths() -> void:
	if winner >= 0:
		return
	var dying: Array = []
	for unit in _each_board(true):
		if int(unit.hp) <= 0 or unit.doomed:
			dying.append(unit)
	_sort_dying(dying)
	for unit in dying:
		if str(unit.zone) != "board":
			continue
		_kill_unit(unit)


func _kill_unit(unit: Dictionary) -> void:
	var hooks: Array = []
	if not unit.silenced:
		hooks = (unit.hooks.get("on_death", []) as Array).duplicate(true)
	var owner = int(unit.owner)
	var iid = int(unit.iid)
	var def_id = str(unit.def_id)
	var lane = int(unit.lane)
	_remove_board(unit)
	unit.hp = 0
	unit.doomed = true
	_add_grave(unit)
	_emit({"type": "destroy", "player": owner, "iid": iid, "def_id": def_id, "lane": lane})
	if hooks.size() > 0:
		_queue_trigger(owner, iid, hooks, "on_death", [], [], {})
	for watcher in _each_board(false):
		if watcher.silenced:
			continue
		for hook in watcher.hooks.get("while_board", []):
			if hook.get("op") != "listen":
				continue
			var event_name = str(hook.get("event", ""))
			var hears = event_name == "any_death" or (event_name == "friendly_death" and watcher.owner == owner)
			if hears:
				_queue_trigger(watcher.owner, watcher.iid, hook.get("effects", []), "while_board", [], [], {})


func _enter(card: Dictionary, pid: int, lane: int) -> void:
	players[pid].board[lane] = card
	card.zone = "board"
	card.owner = pid
	card.lane = lane
	card.doomed = false
	card.sick = not card.keywords.has("rush")
	card.attacks_left = 0 if card.sick else _strikes(card)


func _strikes(unit: Dictionary) -> int:
	if unit.keywords.has("twinstrike"):
		return 2
	return 1


func _add_grave(card: Dictionary) -> void:
	card.zone = "grave"
	card.lane = -1
	card.sick = true
	card.attacks_left = 0
	players[int(card.owner)].grave.append(card)


func _remove_zone(card: Dictionary) -> void:
	var who: Dictionary = players[int(card.owner)]
	if str(card.zone) == "hand":
		_erase_iid(who.hand, card.iid)
	elif str(card.zone) == "deck":
		_erase_iid(who.deck, card.iid)
	elif str(card.zone) == "grave":
		_erase_iid(who.grave, card.iid)
	elif str(card.zone) == "veil":
		_erase_iid(who.veil, card.iid)
	elif str(card.zone) == "board":
		_remove_board(card)
	elif str(card.zone) == "limbo":
		limbo.erase(card.iid)
	card.zone = ""


func _remove_board(unit: Dictionary) -> void:
	var who: Dictionary = players[int(unit.owner)]
	for i in LANES:
		var there = who.board[i]
		if there != null and int(there.iid) == int(unit.iid):
			who.board[i] = null
	unit.lane = -1


func _erase_iid(arr: Array, iid: int) -> void:
	for i in range(arr.size()):
		if int(arr[i].iid) == int(iid):
			arr.remove_at(i)
			return


func _find(iid: int):
	if limbo.has(iid):
		return limbo[iid]
	for pid in [0, 1]:
		var who: Dictionary = players[pid]
		for zone_name in ["hand", "grave", "veil", "deck"]:
			for card in who[zone_name]:
				if int(card.iid) == int(iid):
					return card
		for card in who.board:
			if card != null and int(card.iid) == int(iid):
				return card
	return null


func _live_unit(iid: int):
	if iid < 0:
		return null
	for pid in [0, 1]:
		for lane in LANES:
			var card = players[pid].board[lane]
			if card != null and int(card.iid) == int(iid) and int(card.hp) > 0 and not card.doomed:
				return card
	return null


func _hand_card(pid: int, iid: int):
	for card in players[pid].hand:
		if int(card.iid) == int(iid):
			return card
	return null


func _veil_card(pid: int, iid: int):
	for card in players[pid].veil:
		if int(card.iid) == int(iid):
			return card
	return null


func _each_board(include_dying: bool) -> Array:
	var out: Array = []
	for pid in [0, 1]:
		for lane in LANES:
			var card = players[pid].board[lane]
			if card == null:
				continue
			if not include_dying and (int(card.hp) <= 0 or card.doomed):
				continue
			out.append(card)
	return out


func _first_empty(pid: int) -> int:
	for lane in LANES:
		if players[pid].board[lane] == null:
			return lane
	return -1


func _enemy_has_guard(pid: int) -> bool:
	for unit in _each_board(false):
		if unit.owner != pid and unit.keywords.has("guard"):
			return true
	return false


func _controls_keyword(pid: int, keyword: String) -> bool:
	for unit in _each_board(false):
		if unit.owner == pid and unit.keywords.has(keyword):
			return true
	return false


func _spell_tax(pid: int, defn: Dictionary) -> int:
	if str(defn.get("type", "")) != "spell":
		return 0
	var tax = 0
	for unit in _each_board(false):
		if unit.silenced or unit.owner == pid:
			continue
		for hook in unit.hooks.get("while_board", []):
			if hook.get("op") == "aura_tax":
				tax += int(hook.get("amount", 0))
	return tax


func _sort_dying(arr: Array) -> void:
	for i in range(1, arr.size()):
		var key = arr[i]
		var j = i - 1
		while j >= 0 and _death_before(key, arr[j]):
			arr[j + 1] = arr[j]
			j -= 1
		arr[j + 1] = key


func _death_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a.lane) != int(b.lane):
		return int(a.lane) < int(b.lane)
	if int(a.owner) != int(b.owner):
		return int(a.owner) == active
	return int(a.iid) < int(b.iid)


func _set_winner(pid: int, reason: String) -> void:
	if winner >= 0:
		return
	winner = pid
	win_reason = reason
	window = "over"
	gate = ""
	_emit({"type": "win", "player": pid, "reason": reason})


func _emit(ev: Dictionary) -> void:
	ev["i"] = events.size()
	events.append(ev)


func _make_link(kind: String, pid: int, card: Dictionary, action: Dictionary, effects: Array, answers: String) -> Dictionary:
	var link = {
		"id": next_link,
		"kind": kind,
		"controller": pid,
		"iid": card.iid,
		"def_id": card.def_id,
		"lane": int(action.get("lane", -1)),
		"targets": _ints(action.get("targets", [])),
		"picks": _ints(action.get("picks", [])),
		"effects": effects,
		"answers": answers,
		"negated": false,
		"context": {},
		"hook": "",
		"source_iid": card.iid,
	}
	next_link += 1
	return link


func _ints(value) -> Array:
	var out: Array = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for item in value:
		out.append(int(item))
	return out


func _validate_discard_down(pid: int, action: Dictionary) -> String:
	if window != "focus" or pid != active or phase != "end":
		return "not end"
	var extra = players[pid].hand.size() - HAND_LIMIT
	if extra <= 0:
		return "no discard"
	var ids: Array = action.get("discards", [])
	if not _unique_count(ids, extra):
		return "discard count"
	for iid in ids:
		if _hand_card(pid, int(iid)) == null:
			return "discard missing"
	return ""


func _validate_play(pid: int, action: Dictionary) -> String:
	var card = _hand_card(pid, int(action.get("iid", -1)))
	if card == null:
		return "not in hand"
	var defn: Dictionary = db[card.def_id]
	var typ = str(defn.get("type", ""))
	if typ == "trap":
		return "use set"
	var speed = str(defn.get("speed", ""))
	if window == "focus":
		if pid != active:
			return "not active"
		if phase == "end":
			return "wrong phase"
		if typ == "unit" and phase != "main":
			return "wrong phase"
		if typ == "spell" and speed == "sorcery" and phase != "main":
			return "sorcery"
		if typ == "spell" and speed != "instant" and speed != "sorcery":
			return "bad speed"
		if str(defn.get("answers", "")) != "":
			return "nothing to answer"
	elif window == "priority":
		if pid != priority_player:
			return "no priority"
		if not (typ == "spell" and speed == "instant"):
			return "not instant"
		var answers = str(defn.get("answers", ""))
		if answers != "" and top_match(answers) == null:
			return "no matching link"
	else:
		return "closed"
	return _validate_paid(pid, card, defn, action, typ == "unit")


func _validate_set(pid: int, action: Dictionary) -> String:
	if window != "focus" or pid != active or phase != "main":
		return "cannot set"
	var card = _hand_card(pid, int(action.get("iid", -1)))
	if card == null:
		return "not in hand"
	var defn: Dictionary = db[card.def_id]
	if str(defn.get("type", "")) != "trap":
		return "not trap"
	if players[pid].veil.size() >= VEIL_MAX:
		return "veil full"
	return _validate_paid(pid, card, defn, action, false)


func _validate_activate(pid: int, action: Dictionary) -> String:
	if window != "priority" or pid != priority_player:
		return "no priority"
	var card = _veil_card(pid, int(action.get("iid", -1)))
	if card == null:
		return "not in veil"
	if int(card.set_stamp) >= player_turn_index:
		return "same turn"
	var defn: Dictionary = db[card.def_id]
	if top_match(str(defn.get("trigger", ""))) == null:
		return "trigger"
	return _validate_schema(pid, defn, action, false)


func _validate_attack(pid: int, action: Dictionary) -> String:
	if window != "focus" or pid != active or phase != "combat":
		return "not combat"
	var unit = _live_unit(int(action.get("iid", -1)))
	if unit == null or int(unit.owner) != pid:
		return "no attacker"
	if unit.sick or int(unit.attacks_left) <= 0:
		return "exhausted"
	var target_kind = str(action.get("target_kind", ""))
	if target_kind == "warden":
		if _enemy_has_guard(pid) and not unit.keywords.has("breach"):
			return "guard"
		return ""
	if target_kind == "unit":
		var tgt = _live_unit(int(action.get("target_iid", -1)))
		if tgt == null or int(tgt.owner) == pid:
			return "bad target"
		if _enemy_has_guard(pid) and not tgt.keywords.has("guard") and not unit.keywords.has("breach"):
			return "guard"
		return ""
	return "bad target"


func _validate_paid(pid: int, card: Dictionary, defn: Dictionary, action: Dictionary, needs_lane: bool) -> String:
	var tax = _spell_tax(pid, defn)
	if int(players[pid].energy) < int(defn.get("cost", 0)) + tax:
		return "energy"
	var alt = defn.get("alt", null)
	if typeof(alt) == TYPE_DICTIONARY:
		var alt_type = str(alt.get("type", ""))
		if alt_type == "life":
			if int(players[pid].life) - int(alt.get("amount", 0)) < 1:
				return "life"
		elif alt_type == "discard":
			var discs: Array = action.get("discards", [])
			if not _unique_count(discs, int(alt.get("amount", 0))):
				return "discard"
			for iid in discs:
				if int(iid) == int(card.iid) or _hand_card(pid, int(iid)) == null:
					return "discard missing"
		elif alt_type == "tribute":
			var tribs: Array = action.get("tributes", [])
			if not _unique_count(tribs, int(alt.get("amount", 0))):
				return "tribute"
			for iid in tribs:
				var unit = _live_unit(int(iid))
				if unit == null or int(unit.owner) != pid:
					return "tribute missing"
				if action.get("targets", []).has(iid) or action.get("targets", []).has(int(iid)):
					return "tribute target"
		else:
			return "bad alt"
	return _validate_schema(pid, defn, action, needs_lane)


func _validate_schema(pid: int, defn: Dictionary, action: Dictionary, needs_lane: bool) -> String:
	var targets: Array = action.get("targets", [])
	var schema: Array = defn.get("targets", [])
	if targets.size() != schema.size():
		return "targets"
	var seen = {}
	for i in schema.size():
		var iid = int(targets[i])
		if seen.has(iid):
			return "duplicate target"
		seen[iid] = true
		if not _target_ok(pid, schema[i], iid):
			return "illegal target"
	var picks: Array = action.get("picks", [])
	var pschema: Array = defn.get("picks", [])
	var need = 0
	for spec in pschema:
		need += int(spec.get("count", 1))
	if picks.size() != need:
		return "picks"
	var cursor = 0
	var pseen = {}
	for spec in pschema:
		for _n in int(spec.get("count", 1)):
			var iid = int(picks[cursor])
			cursor += 1
			if pseen.has(iid):
				return "duplicate pick"
			pseen[iid] = true
			if not _pick_ok(pid, spec, iid):
				return "bad pick"
	if needs_lane:
		var lane = int(action.get("lane", -1))
		if lane < 0 or lane >= LANES or players[pid].board[lane] != null:
			return "lane"
	return ""


func _target_ok(pid: int, spec: Dictionary, iid: int) -> bool:
	var accept = str(spec.get("accept", "unit"))
	var side = str(spec.get("side", "any"))
	if accept == "veil":
		var card = _find(iid)
		if card == null or str(card.zone) != "veil":
			return false
		if side == "enemy":
			return int(card.owner) != pid
		if side == "friendly":
			return int(card.owner) == pid
		return true
	var unit = _live_unit(iid)
	if unit == null:
		return false
	if side == "enemy" and int(unit.owner) == pid:
		return false
	if side == "friendly" and int(unit.owner) != pid:
		return false
	return true


func _pick_ok(pid: int, spec: Dictionary, iid: int) -> bool:
	var card = _find(iid)
	if card == null or int(card.owner) != pid:
		return false
	if str(card.zone) != str(spec.get("zone", "")):
		return false
	var typ = str(spec.get("type", "any"))
	if typ != "any" and str(db[card.def_id].get("type", "")) != typ:
		return false
	return true


func _unique_count(values: Array, count: int) -> bool:
	if values.size() != count:
		return false
	var seen = {}
	for value in values:
		var iid = int(value)
		if seen.has(iid):
			return false
		seen[iid] = true
	return true


func _collect_discards(pid: int, out: Array) -> void:
	var extra = players[pid].hand.size() - HAND_LIMIT
	if extra <= 0:
		return
	var ids: Array = []
	for card in players[pid].hand:
		ids.append(card.iid)
	for combo in _combos(ids, extra):
		out.append({"type": "discard_down", "discards": combo})


func _collect_from_hand(pid: int, out: Array) -> void:
	for card in players[pid].hand:
		var defn: Dictionary = db[card.def_id]
		if str(defn.get("type", "")) == "trap":
			_expand(pid, card, defn, "set_trap", false, out)
		else:
			_expand(pid, card, defn, "play", str(defn.get("type", "")) == "unit", out)


func _collect_activates(pid: int, out: Array) -> void:
	for card in players[pid].veil:
		var defn: Dictionary = db[card.def_id]
		_expand(pid, card, defn, "activate", false, out)


func _collect_attacks(pid: int, out: Array) -> void:
	for unit in _each_board(false):
		if unit.owner != pid:
			continue
		out.append({"type": "attack", "iid": unit.iid, "target_kind": "warden"})
		for enemy in _each_board(false):
			if enemy.owner == pid:
				continue
			out.append({"type": "attack", "iid": unit.iid, "target_kind": "unit", "target_iid": enemy.iid})


func _expand(pid: int, card: Dictionary, defn: Dictionary, kind: String, needs_lane: bool, out: Array) -> void:
	var alt = defn.get("alt", null)
	var trib_n = 0
	var disc_n = 0
	if typeof(alt) == TYPE_DICTIONARY:
		if str(alt.get("type", "")) == "tribute":
			trib_n = int(alt.get("amount", 0))
		elif str(alt.get("type", "")) == "discard":
			disc_n = int(alt.get("amount", 0))
	var board_ids: Array = []
	for unit in _each_board(false):
		if unit.owner == pid:
			board_ids.append(unit.iid)
	var hand_ids: Array = []
	for other in players[pid].hand:
		if int(other.iid) != int(card.iid):
			hand_ids.append(other.iid)
	var trib_sets: Array = _combos(board_ids, trib_n) if trib_n > 0 else [[]]
	var disc_sets: Array = _combos(hand_ids, disc_n) if disc_n > 0 else [[]]
	var target_lists: Array = []
	for spec in defn.get("targets", []):
		target_lists.append(_candidate_targets(pid, spec))
	var target_sets: Array = _product(target_lists) if target_lists.size() > 0 else [[]]
	var pick_lists: Array = []
	for spec in defn.get("picks", []):
		var opts = _candidate_picks(pid, spec)
		for _n in int(spec.get("count", 1)):
			pick_lists.append(opts)
	var pick_sets: Array = _product(pick_lists) if pick_lists.size() > 0 else [[]]
	var lanes: Array = []
	if needs_lane:
		for lane in LANES:
			if players[pid].board[lane] == null:
				lanes.append(lane)
		if lanes.is_empty():
			return
	else:
		lanes = [-1]
	for tribs in trib_sets:
		for discs in disc_sets:
			for tset in target_sets:
				for pset in pick_sets:
					if not _unique_count(pset, pset.size()) and pset.size() > 0:
						continue
					for lane in lanes:
						var action = {"type": kind, "iid": card.iid}
						if int(lane) >= 0:
							action["lane"] = lane
						if tribs.size() > 0:
							action["tributes"] = tribs.duplicate()
						if discs.size() > 0:
							action["discards"] = discs.duplicate()
						if tset.size() > 0:
							action["targets"] = tset.duplicate()
						if pset.size() > 0:
							action["picks"] = pset.duplicate()
						out.append(action)


func _candidate_targets(pid: int, spec: Dictionary) -> Array:
	var out: Array = []
	var accept = str(spec.get("accept", "unit"))
	var side = str(spec.get("side", "any"))
	if accept == "veil":
		for owner in [0, 1]:
			if side == "enemy" and owner == pid:
				continue
			if side == "friendly" and owner != pid:
				continue
			for card in players[owner].veil:
				out.append(card.iid)
		return out
	for unit in _each_board(false):
		if side == "enemy" and unit.owner == pid:
			continue
		if side == "friendly" and unit.owner != pid:
			continue
		out.append(unit.iid)
	return out


func _candidate_picks(pid: int, spec: Dictionary) -> Array:
	var out: Array = []
	var zone = str(spec.get("zone", ""))
	var typ = str(spec.get("type", "any"))
	var pile: Array = players[pid].get(zone, [])
	for card in pile:
		if typ != "any" and str(db[card.def_id].get("type", "")) != typ:
			continue
		out.append(card.iid)
	return out


func _combos(items: Array, n: int) -> Array:
	var out: Array = []
	if n <= 0:
		return [[]]
	if n > items.size():
		return out
	var acc: Array = []
	_combos_rec(items, n, 0, acc, out)
	return out


func _combos_rec(items: Array, n: int, start: int, acc: Array, out: Array) -> void:
	if acc.size() == n:
		out.append(acc.duplicate())
		return
	for i in range(start, items.size()):
		acc.append(items[i])
		_combos_rec(items, n, i + 1, acc, out)
		acc.pop_back()


func _product(lists: Array) -> Array:
	var out: Array = [[]]
	for list in lists:
		if list.is_empty():
			return []
		var nxt: Array = []
		for prefix in out:
			for item in list:
				var row: Array = prefix.duplicate()
				row.append(item)
				nxt.append(row)
		out = nxt
	return out
