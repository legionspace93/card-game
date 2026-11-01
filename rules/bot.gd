class_name DuelBot
extends RefCounted

## Deterministic solo opponent. It only returns actions from Duel.legal_actions().

static func choose(duel, pid: int) -> Dictionary:
	var actions: Array = duel.legal_actions(pid)
	if actions.is_empty():
		return {"type": "pass"}
	var best: Dictionary = actions[0]
	var best_score := _score(duel, pid, best)
	for i in range(1, actions.size()):
		var action: Dictionary = actions[i]
		var score := _score(duel, pid, action)
		if score > best_score or (score == best_score and _prefer(action, best)):
			best = action
			best_score = score
	return best.duplicate(true)


static func _prefer(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("type", "")) == "pass" and str(b.get("type", "")) != "pass":
		return true
	if str(b.get("type", "")) == "pass":
		return false
	return _key(a) < _key(b)


static func _key(action: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%s" % [
		str(action.get("type", "")),
		str(action.get("iid", -1)),
		str(action.get("lane", -1)),
		str(action.get("targets", [])),
		str(action.get("tributes", [])),
		str(action.get("discards", [])),
		str(action.get("picks", [])),
	]


static func _score(duel, pid: int, action: Dictionary) -> int:
	match str(action.get("type", "")):
		"pass":
			return 0
		"end_phase":
			if str(duel.phase) == "end":
				return 60
			if str(duel.phase) == "combat":
				return 8
			return 4
		"discard_down":
			return 45 - _discard_cost(duel, action)
		"set_trap":
			return 11 - int(duel.db[duel._find(int(action.iid)).def_id].get("cost", 0))
		"attack":
			return _score_attack(duel, pid, action)
		"activate":
			return _score_activate(duel, pid, action)
		"play":
			return _score_play(duel, pid, action)
		_:
			return -100


static func _discard_cost(duel, action: Dictionary) -> int:
	var total := 0
	for iid in action.get("discards", []):
		var card = duel._find(int(iid))
		if card != null:
			total += int(duel.db[card.def_id].get("cost", 0))
	return total


static func _score_attack(duel, pid: int, action: Dictionary) -> int:
	var atk := int(duel.attack_value(int(action.get("iid", -1))))
	if str(action.get("target_kind", "")) == "warden":
		var life := int(duel.players[1 - pid].life)
		var score := atk * 5
		if atk >= life:
			score += 900
		return score
	var enemy = duel._live_unit(int(action.get("target_iid", -1)))
	var mine = duel._live_unit(int(action.get("iid", -1)))
	if enemy == null or mine == null:
		return -20
	var score := 0
	if atk >= int(enemy.hp) or mine.keywords.has("venom"):
		score += (int(enemy.atk) + int(enemy.hp)) * 3 + 6
	else:
		score += 1
	if int(enemy.atk) >= int(mine.hp):
		score -= (int(mine.atk) + int(mine.hp)) * 2
	if mine.keywords.has("siphon"):
		score += 4
	return score


static func _score_activate(duel, pid: int, action: Dictionary) -> int:
	var card = duel._find(int(action.get("iid", -1)))
	if card == null:
		return -10
	var defn: Dictionary = duel.db[card.def_id]
	var trigger := str(defn.get("trigger", ""))
	var link = duel.top_match(trigger)
	if link == null:
		return -10
	var answered = null
	if str(link.get("def_id", "")) != "" and duel.db.has(str(link.def_id)):
		answered = duel.db[str(link.def_id)]
	var threatens := false
	if answered != null:
		var body := int(answered.get("atk", 0)) + int(answered.get("hp", 0))
		threatens = int(answered.get("cost", 0)) >= 2 or body >= 4
	for effect in defn.get("effects", []):
		if str(effect.get("op", "")) == "negate":
			return 70 if threatens else -3
	if trigger == "attack":
		var attacker = duel._live_unit(int(link.get("context", {}).get("attacker_iid", -1)))
		if attacker == null:
			return -4
		return int(duel.attack_value(attacker)) * 8
	if trigger == "any":
		return 12
	return 6


static func _score_play(duel, pid: int, action: Dictionary) -> int:
	var card = duel._find(int(action.get("iid", -1)))
	if card == null:
		return -20
	var defn: Dictionary = duel.db[card.def_id]
	var score := 0
	var opp_life := int(duel.players[1 - pid].life)
	var my_life := int(duel.players[pid].life)
	if str(defn.get("type", "")) == "unit":
		score += (int(defn.get("atk", 0)) + int(defn.get("hp", 0))) * 2
		score += int(defn.get("keywords", []).size()) * 2
		score -= int(defn.get("cost", 0))
		if int(defn.get("cost", 0)) == int(duel.players[pid].energy):
			score += 3
	score += _effect_value(duel, pid, defn.get("effects", []), action, opp_life)
	for hook_name in defn.get("hooks", {}).keys():
		score += _effect_value(duel, pid, defn.hooks[hook_name], action, opp_life) / 2
	var alt = defn.get("alt", null)
	if typeof(alt) == TYPE_DICTIONARY:
		var amount := int(alt.get("amount", 0))
		match str(alt.get("type", "")):
			"life":
				score -= amount * 4
				if my_life - amount < 12 and _warden_damage(defn) < opp_life:
					score -= 70
			"tribute":
				score -= amount * 6
			"discard":
				score -= amount * 5
	if _warden_damage(defn) >= opp_life and opp_life > 0:
		score += 900
	return score


static func _effect_value(duel, pid: int, effects: Array, action: Dictionary, opp_life: int) -> int:
	var score := 0
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var op := str(effect.get("op", ""))
		var amount := int(effect.get("amount", 0))
		var scope := ""
		if typeof(effect.get("target", null)) == TYPE_DICTIONARY:
			scope = str(effect.target.get("scope", ""))
		match op:
			"damage":
				if scope == "opponent_warden":
					score += amount * 4
				elif effect.get("target", {}).has("ref"):
					score += amount * 2
				else:
					score += amount
			"heal":
				if int(duel.players[pid].life) < 30:
					score += amount
			"draw", "fetch", "take_pick":
				score += 7 * maxi(1, amount)
			"ramp":
				score += 8 * amount
			"destroy":
				score += _target_body(duel, action)
			"silence":
				score += 8 + _target_body(duel, action) / 2
			"bounce":
				score += 6 + _target_body(duel, action) / 2
			"summon":
				score += 5
			"buff":
				score += int(effect.get("atk", 0)) + int(effect.get("hp", 0))
			"listen", "aura_atk", "aura_tax":
				score += 4
			_:
				score += 1
	return score


static func _target_body(duel, action: Dictionary) -> int:
	var targets: Array = action.get("targets", [])
	if targets.is_empty():
		return 8
	var unit = duel._live_unit(int(targets[0]))
	if unit == null:
		return 4
	return int(unit.atk) + int(unit.hp)


static func _warden_damage(defn: Dictionary) -> int:
	var total := 0
	var pools: Array = [defn.get("effects", [])]
	for hook in defn.get("hooks", {}).values():
		pools.append(hook)
	for pool in pools:
		if typeof(pool) != TYPE_ARRAY:
			continue
		for effect in pool:
			if typeof(effect) != TYPE_DICTIONARY:
				continue
			if str(effect.get("op", "")) != "damage":
				continue
			var tgt = effect.get("target", {})
			if typeof(tgt) == TYPE_DICTIONARY and str(tgt.get("scope", "")) == "opponent_warden" and not effect.has("if"):
				total += int(effect.get("amount", 0))
	return total
