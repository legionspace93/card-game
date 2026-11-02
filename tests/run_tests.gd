extends SceneTree

const CardDBScript = preload("res://rules/card_db.gd")
const DuelScript = preload("res://rules/duel.gd")
const BotScript = preload("res://rules/bot.gd")
const KeywordScript = preload("res://rules/keywords.gd")
const FlashScript = preload("res://vfx/flashes.gd")
const MainScene = preload("res://scenes/main.tscn")

var fails := 0
var passes := 0
var db: Dictionary = {}


func _init() -> void:
	db = CardDBScript.load_all()
	_test_pool()
	_test_turn_order_and_deckout()
	_test_life_loss_and_payment()
	_test_targeting_and_illegal_is_stable()
	_test_trap_answers_summon()
	_test_summon_resolves_when_passed()
	_test_silence_blanks_keyword_and_death()
	_test_death_trigger_chains()
	_test_combat_keywords()
	_test_aura_and_tax()
	_test_bot_game()
	_test_mirevault_art()
	call_deferred("_finish_view")


func _finish_view() -> void:
	_test_flashes_and_table()
	print("PASS %d  FAIL %d" % [passes, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("FAIL: ", msg)


func boot(seed: int = 1):
	var filler: Array = []
	for _i in 8:
		filler.append("peat_spore")
	return DuelScript.new(db, filler.duplicate(), filler.duplicate(), seed)


func pass_to_focus(duel, limit: int = 40) -> bool:
	var n := 0
	while str(duel.window) == "priority" and int(duel.winner) < 0 and n < limit:
		var res: Dictionary = duel.apply(int(duel.priority_player), {"type": "pass"})
		if not res.ok:
			print("  pass failed: ", res.get("reason", ""))
			return false
		n += 1
	return str(duel.window) == "focus" or int(duel.winner) >= 0


func drive(duel, limit: int = 100) -> bool:
	var n := 0
	while int(duel.winner) < 0 and n < limit:
		var res: Dictionary
		if str(duel.window) == "focus":
			res = duel.apply(int(duel.active), {"type": "end_phase"})
		elif str(duel.window) == "priority":
			res = duel.apply(int(duel.priority_player), {"type": "pass"})
		else:
			print("  stuck window ", duel.window)
			return false
		if not res.ok:
			print("  drive failed: ", res.get("reason", ""), " phase ", duel.phase, " window ", duel.window, " hand ", duel.players[duel.active].hand.size())
			return false
		n += 1
	return int(duel.winner) >= 0


func end_and_focus(duel) -> bool:
	if str(duel.window) != "focus":
		print("  expected focus, got ", duel.window, " ", duel.phase)
		return false
	var res: Dictionary = duel.apply(int(duel.active), {"type": "end_phase"})
	if not res.ok:
		print("  end failed ", res.get("reason", ""), " phase ", duel.phase)
		return false
	return pass_to_focus(duel)


func on_board(duel, iid: int) -> bool:
	return duel._live_unit(iid) != null


func _test_pool() -> void:
	check(db.size() >= 80 and db.size() <= 120, "card count %d" % db.size())
	check(db.size() == 100, "expected 100 cards, got %d" % db.size())
	var texts := {}
	var sigs := {}
	var runnable := {
		"damage": true, "heal": true, "buff": true, "summon": true, "draw": true,
		"destroy": true, "silence": true, "bounce": true, "mill": true, "ramp": true,
		"shed": true, "negate": true, "grant_keyword": true, "ready": true,
		"set_stats": true, "fetch": true, "take_pick": true,
	}
	var passive := {"aura_atk": true, "aura_tax": true, "listen": true}
	for id in db.keys():
		var card: Dictionary = db[id]
		check(str(card.get("text", "")).length() > 8, "text " + id)
		check(not texts.has(card.text), "dup text " + id)
		texts[card.text] = true
		var sig := JSON.stringify({
			"type": card.get("type"),
			"cost": card.get("cost"),
			"alt": card.get("alt"),
			"atk": card.get("atk"),
			"hp": card.get("hp"),
			"keywords": card.get("keywords"),
			"hooks": card.get("hooks"),
			"effects": card.get("effects"),
			"trigger": card.get("trigger"),
			"targets": card.get("targets"),
			"picks": card.get("picks"),
			"answers": card.get("answers"),
		})
		check(not sigs.has(sig), "dup mechanics " + id)
		sigs[sig] = true
		if str(card.get("type")) == "unit":
			check((card.get("keywords", []) as Array).size() > 0, "keywords " + id)
			check((card.get("hooks", {}) as Dictionary).size() > 0, "hooks " + id)
			for kw in card.get("keywords", []):
				check(KeywordScript.ALL.has(str(kw)), "unknown kw %s on %s" % [kw, id])
			for hook_name in card.hooks.keys():
				var ops: Array = card.hooks[hook_name]
				check(ops.size() > 0, "empty hook " + id)
				for effect in ops:
					var op := str(effect.get("op", ""))
					if str(hook_name) == "while_board":
						check(passive.has(op), "passive %s %s" % [op, id])
					else:
						check(runnable.has(op), "op %s %s" % [op, id])
		for ref_id in _summon_refs(card):
			check(db.has(ref_id), "summon %s from %s" % [ref_id, id])
	var covered := {}
	for faction in ["emberline", "mirevault", "glassward"]:
		var deck: Dictionary = CardDBScript.load_deck("res://data/decks/%s.json" % faction)
		var cards: Array = deck.cards
		check(cards.size() == 32, "%s deck size %d" % [faction, cards.size()])
		var seen := {}
		for cid in cards:
			check(db.has(str(cid)), "deck card " + str(cid))
			check(not bool(db[str(cid)].get("token", false)), "token in deck " + str(cid))
			check(not seen.has(cid), "dup deck " + str(cid))
			seen[cid] = true
			covered[str(cid)] = true
	for id in db.keys():
		if bool(db[id].get("token", false)):
			continue
		check(covered.has(str(id)), "uncovered " + str(id))


func _summon_refs(card: Dictionary) -> Array:
	var out: Array = []
	var pools: Array = []
	if card.has("effects"):
		pools.append(card.effects)
	for hook in card.get("hooks", {}).values():
		pools.append(hook)
	for pool in pools:
		if typeof(pool) != TYPE_ARRAY:
			continue
		for effect in pool:
			if typeof(effect) == TYPE_DICTIONARY and str(effect.get("op", "")) == "summon":
				out.append(str(effect.get("card", "")))
			if typeof(effect) == TYPE_DICTIONARY and effect.has("effects"):
				for inner in effect.effects:
					if str(inner.get("op", "")) == "summon":
						out.append(str(inner.get("card", "")))
	return out


func _test_turn_order_and_deckout() -> void:
	var filler: Array = []
	for _i in 8:
		filler.append("peat_spore")
	var duel = DuelScript.new(db, filler.duplicate(), filler.duplicate(), 2)
	check(duel.players[0].hand.size() == 4, "opening hand p0")
	check(duel.players[1].hand.size() == 4, "opening hand p1")
	check(duel.players[0].deck.size() == 4, "deck after open")
	check(int(duel.players[0].energy) == 1 and int(duel.players[0].max_energy) == 1, "turn 1 spark")
	check(int(duel.players[1].energy) == 0, "p1 has not started")
	check(str(duel.phase) == "main" and str(duel.window) == "priority", "opens on response gate")
	check(int(duel.actor()) == 1, "opponent priority first")
	check(pass_to_focus(duel), "enter first focus")
	check(end_and_focus(duel) and str(duel.phase) == "combat", "main to combat")
	check(end_and_focus(duel) and str(duel.phase) == "end", "combat to end")
	check(end_and_focus(duel), "end the first turn")
	check(int(duel.active) == 1 and str(duel.phase) == "main", "p1 turn")
	check(duel.players[1].hand.size() == 5, "p1 drew")
	check(duel.players[0].hand.size() == 4, "first warden skipped the extra draw")
	check(int(duel.players[1].max_energy) == 1, "p1 spark cap")
	check(end_and_focus(duel) and end_and_focus(duel) and end_and_focus(duel), "finish p1 turn")
	check(int(duel.active) == 0 and int(duel.turn_number) == 2, "round 2")
	check(int(duel.players[0].max_energy) == 2, "spark grows on your turn")
	check(duel.players[0].hand.size() == 5, "p0 draws on round 2")

	var short: Array = []
	for _i in 4:
		short.append("peat_spore")
	var doomed = DuelScript.new(db, short.duplicate(), short.duplicate(), 3)
	check(doomed.players[0].deck.is_empty(), "opening emptied a 4 card deck")
	check(drive(doomed), "play to deckout")
	check(int(doomed.winner) == 0 and str(doomed.win_reason) == "deck", "deckout loses for the player who must draw")


func _test_life_loss_and_payment() -> void:
	var duel = boot()
	duel.debug_begin("main")
	duel.debug_energy(0, 10)
	duel.debug_life(1, 2)
	var bolt := duel.debug_hand(0, "pyre_leap")
	var res: Dictionary = duel.apply(0, {"type": "play", "iid": bolt})
	check(res.ok, "pyre " + str(res.get("reason", "")))
	check(pass_to_focus(duel), "pyre resolves")
	check(int(duel.winner) == 0 and str(duel.win_reason) == "life", "life loss")

	var pay = boot()
	pay.debug_begin("main")
	pay.debug_energy(0, 5)
	pay.debug_life(0, 4)
	var rite := pay.debug_hand(0, "life_for_cinders")
	var blocked: Dictionary = pay.apply(0, {"type": "play", "iid": rite})
	check(not blocked.ok, "cannot pay life to 0")
	pay.debug_life(0, 5)
	var before := int(pay.revision)
	var ok_pay: Dictionary = pay.apply(0, {"type": "play", "iid": rite})
	check(ok_pay.ok, "life cost " + str(ok_pay.get("reason", "")))
	check(pass_to_focus(pay), "cinders resolve")
	check(int(pay.players[0].life) == 1, "life left at 1")
	check(int(pay.players[0].max_energy) == 7, "ramp from life cost")
	check(bool(pay.players[0].life_paid), "life paid flag")
	var leap := pay.debug_hand(0, "pyre_leap")
	check(pay.apply(0, {"type": "play", "iid": leap}).ok, "pyre after life")
	check(pass_to_focus(pay), "bonus pyre")
	check(int(pay.players[1].life) == 26, "life-paid bonus damage")
	check(int(pay.revision) > before, "revision moved")


func _test_targeting_and_illegal_is_stable() -> void:
	var duel = boot()
	duel.debug_begin("main")
	duel.debug_energy(0, 1)
	var skirm := duel.debug_hand(0, "cinder_skirmisher")
	duel.debug_place(0, "barrow_wall", 0, true)
	var rev := int(duel.revision)
	var events := int(duel.events.size())
	var life := int(duel.players[1].life)
	var occupied: Dictionary = duel.apply(0, {"type": "play", "iid": skirm, "lane": 0})
	check(not occupied.ok, "occupied lane rejected")
	var bad_lane: Dictionary = duel.apply(0, {"type": "play", "iid": skirm, "lane": 7})
	check(not bad_lane.ok, "bad lane rejected")
	var during: Dictionary = duel.apply(1, {"type": "pass"})
	check(not during.ok, "opponent cannot pass during your focus")
	check(int(duel.revision) == rev and duel.events.size() == events, "illegal apply does not emit")
	check(int(duel.players[1].life) == life, "life unchanged")

	duel.debug_energy(0, 10)
	var pact := duel.debug_hand(0, "molten_pact")
	var mine := duel.debug_place(0, "barrow_mite", 1, true)
	var theirs := duel.debug_place(1, "bog_warden", 0, true)
	var friendly: Dictionary = duel.apply(0, {"type": "play", "iid": pact, "targets": [mine]})
	check(not friendly.ok, "enemy-only removal rejects a friendly")
	var missing: Dictionary = duel.apply(0, {"type": "play", "iid": pact, "targets": []})
	check(not missing.ok, "missing target rejected")
	var aimed: Dictionary = duel.apply(0, {"type": "play", "iid": pact, "targets": [theirs]})
	check(aimed.ok, "legal enemy target " + str(aimed.get("reason", "")))
	check(str(duel.window) == "priority", "declared play opens priority")
	check(duel.apply(0, {"type": "play", "iid": skirm, "lane": 2}).ok == false, "cannot play a unit during priority")
	for action in duel.legal_actions(1):
		check(duel.validate(1, action) == "", "legal action failed validate")


func _test_trap_answers_summon() -> void:
	var duel = boot()
	duel.debug_begin("main")
	duel.debug_energy(0, 6)
	var trap := duel.debug_veil(1, "latch_of_glass", 0)
	var skirm := duel.debug_hand(0, "cinder_skirmisher")
	check(duel.apply(0, {"type": "play", "iid": skirm, "lane": 0}).ok, "declare summon")
	var answered := false
	for action in duel.legal_actions(1):
		if str(action.get("type")) == "activate" and int(action.get("iid", -1)) == trap:
			answered = true
			var fired: Dictionary = duel.apply(1, action)
			check(fired.ok, "activate latch " + str(fired.get("reason", "")))
			break
	check(answered, "trap is a legal answer to the summon")
	check(pass_to_focus(duel), "chain resolves")
	check(not on_board(duel, skirm), "negated summon never enters")
	check(int(duel.players[1].life) == 30, "on play did not resolve")
	check(_has_event(duel, "trap_reveal") and _has_event(duel, "chain_resolve") and _has_event(duel, "negate"), "trap events")

	var late = boot()
	late.debug_begin("main")
	late.debug_energy(0, 4)
	var fresh := late.debug_hand(0, "latch_of_glass")
	check(late.apply(0, {"type": "set_trap", "iid": fresh}).ok, "set trap")
	check(pass_to_focus(late), "set resolves")
	var veil_card = late._find(fresh)
	check(veil_card != null and str(veil_card.zone) == "veil", "trap is set")
	# A unit play now should not be answerable by a trap set this same turn.
	var bait := late.debug_hand(1, "cinder_skirmisher")
	# Give the opponent a turn fragment by ending ours.
	check(late.apply(0, {"type": "end_phase"}).ok, "leave main")
	check(pass_to_focus(late), "to combat")
	check(late.apply(0, {"type": "end_phase"}).ok, "leave combat")
	check(pass_to_focus(late), "to end")
	check(late.apply(0, {"type": "end_phase"}).ok, "leave end")
	check(pass_to_focus(late), "opponent focus or gate done")
	# Opponent may still be behind a phase gate; drive them nowhere, just ensure
	# the stamp blocks same-index activation. Re-set the window if we already moved on.
	if int(late.active) != 0:
		# Trap was set on p0's turn. p1's turn index is higher, so p0 CAN activate.
		# Same-turn block is tested by trying to activate before the turn flips.
		pass
	var same = boot()
	same.debug_begin("main")
	same.debug_energy(0, 8)
	var set_id := same.debug_hand(0, "latch_of_glass")
	check(same.apply(0, {"type": "set_trap", "iid": set_id}).ok, "set during main")
	# Still on the chain, opponent has priority. The trap is not in the veil yet.
	var early := false
	for action in same.legal_actions(0):
		if str(action.get("type")) == "activate":
			early = true
	check(not early, "cannot activate a trap that has not resolved")
	check(pass_to_focus(same), "set finished")
	var other := same.debug_hand(1, "fracture_bolt")
	var body := same.debug_place(0, "barrow_wall", 0, true)
	# Fracture from the opponent is illegal during our focus.
	check(not same.apply(1, {"type": "play", "iid": other, "targets": [body]}).ok, "no focus, no instant")
	# Open a chain with our own instant so priority exists, then the fresh trap must be illegal.
	same.debug_energy(0, 8)
	var our_bolt := same.debug_hand(0, "fracture_bolt")
	var foe := same.debug_place(1, "barrow_wall", 1, true)
	check(same.apply(0, {"type": "play", "iid": our_bolt, "targets": [foe]}).ok, "bolt to open chain")
	var sneaky := false
	for action in same.legal_actions(0):
		if str(action.get("type")) == "activate" and int(action.get("iid", -1)) == set_id:
			sneaky = true
	# Priority is with the opponent first, so p0 cannot activate yet.
	check(not sneaky, "setter does not have priority yet")
	check(same.apply(1, {"type": "pass"}).ok, "opponent passes")
	for action in same.legal_actions(0):
		if str(action.get("type")) == "activate" and int(action.get("iid", -1)) == set_id:
			sneaky = true
	check(not sneaky, "trap cannot answer on the turn it was set")


func _test_summon_resolves_when_passed() -> void:
	var duel = boot()
	duel.debug_begin("main")
	duel.debug_energy(0, 4)
	var skirm := duel.debug_hand(0, "cinder_skirmisher")
	check(duel.apply(0, {"type": "play", "iid": skirm, "lane": 2}).ok, "play rush unit")
	check(pass_to_focus(duel), "passes resolve the summon")
	check(on_board(duel, skirm), "unit entered")
	check(int(duel.players[1].life) == 29, "on play dealt 1")
	check(_has_event(duel, "play") and _has_event(duel, "summon") and _has_event(duel, "damage"), "play damage events")
	check(duel.apply(0, {"type": "end_phase"}).ok, "end main")
	check(pass_to_focus(duel), "enter combat")
	check(str(duel.phase) == "combat", "combat phase")
	var face := {"type": "attack", "iid": skirm, "target_kind": "warden"}
	check(duel.validate(0, face) == "", "rush can attack")
	check(duel.apply(0, face).ok, "declare rush attack")
	check(pass_to_focus(duel), "attack resolves")
	check(int(duel.players[1].life) == 27, "rush attack damage")

	var slow = boot()
	slow.debug_begin("main")
	slow.debug_energy(0, 4)
	var sentry := slow.debug_hand(0, "ember_sentry")
	check(slow.apply(0, {"type": "play", "iid": sentry, "lane": 0}).ok, "play sentry")
	check(pass_to_focus(slow), "sentry in")
	check(slow.apply(0, {"type": "end_phase"}).ok, "end")
	check(pass_to_focus(slow), "combat for sentry")
	check(slow.validate(0, {"type": "attack", "iid": sentry, "target_kind": "warden"}) != "", "summoning sickness")


func _test_silence_blanks_keyword_and_death() -> void:
	var ward = boot()
	ward.debug_begin("main")
	ward.debug_energy(0, 8)
	var beacon := ward.debug_place(1, "hush_beacon", 0, true)
	check(ward._live_unit(beacon).keywords.has("ward"), "starts with ward")
	var bolt := ward.debug_hand(0, "fracture_bolt")
	check(ward.apply(0, {"type": "play", "iid": bolt, "targets": [beacon]}).ok, "bolt ward")
	check(pass_to_focus(ward), "bolt1")
	var still = ward._live_unit(beacon)
	check(still != null and int(still.hp) == 5 and not still.keywords.has("ward"), "ward prevented the hit and was spent")
	var bolt2 := ward.debug_hand(0, "fracture_bolt")
	check(ward.apply(0, {"type": "play", "iid": bolt2, "targets": [beacon]}).ok, "bolt2")
	check(pass_to_focus(ward), "bolt2 resolve")
	check(int(ward._live_unit(beacon).hp) == 2, "second hit lands")

	var blank = boot()
	blank.debug_begin("main")
	blank.debug_energy(0, 8)
	var hush := blank.debug_place(1, "hush_beacon", 0, true)
	var deck_before := int(blank.players[1].deck.size())
	var seal := blank.debug_hand(0, "banishing_seal")
	check(blank.apply(0, {"type": "play", "iid": seal, "targets": [hush]}).ok, "banish")
	check(pass_to_focus(blank), "banish resolves")
	check(blank._live_unit(hush) == null, "destroyed")
	check(blank.players[1].deck.size() == deck_before, "silenced death hook did not draw")
	check(_has_event(blank, "silence") and _has_event(blank, "destroy"), "silence and destroy flashed")

	var live = boot()
	live.debug_begin("main")
	live.debug_energy(0, 8)
	var hush2 := live.debug_place(1, "hush_beacon", 0, true)
	var before := int(live.players[1].deck.size())
	var mulch := live.debug_hand(0, "mulch_the_line")
	check(live.apply(0, {"type": "play", "iid": mulch, "targets": [hush2]}).ok, "mulch")
	check(pass_to_focus(live), "mulch chain")
	check(live.players[1].deck.size() == before - 1, "death hook drew a card")


func _test_death_trigger_chains() -> void:
	var duel = boot()
	duel.debug_begin("main")
	duel.debug_energy(0, 8)
	var mite := duel.debug_place(0, "barrow_mite", 0, true)
	var ember := duel.debug_place(1, "grave_ember", 0, true)
	var deck_before := int(duel.players[0].deck.size())
	var mulch := duel.debug_hand(0, "mulch_the_line")
	check(duel.apply(0, {"type": "play", "iid": mulch, "targets": [ember]}).ok, "kill ember")
	check(pass_to_focus(duel), "death chain settles")
	check(not on_board(duel, ember) and not on_board(duel, mite), "both units died")
	check(duel.players[0].deck.size() == deck_before - 1, "mite death drew")
	check(int(duel.players[0].max_energy) > 1, "mulch ramped")

	var tribute = boot()
	tribute.debug_begin("main")
	tribute.debug_energy(0, 2)
	var mite2 := tribute.debug_place(0, "barrow_mite", 1, true)
	var roots := tribute.debug_hand(0, "tribute_of_roots")
	var hand_before := int(tribute.players[0].hand.size())
	check(tribute.apply(0, {"type": "play", "iid": roots, "tributes": [mite2]}).ok, "tribute")
	check(pass_to_focus(tribute), "tribute chain")
	check(not on_board(tribute, mite2), "tribute died")
	# Spell draws 1 and the death draws 1, and the spell left hand.
	check(tribute.players[0].hand.size() == hand_before - 1 + 2, "tribute death chained a draw plus the spell draw")


func _test_combat_keywords() -> void:
	var guard = boot()
	guard.debug_begin("combat")
	var rusher := guard.debug_place(0, "cinder_skirmisher", 0, true)
	var wall := guard.debug_place(1, "barrow_wall", 0, true)
	check(guard.validate(0, {"type": "attack", "iid": rusher, "target_kind": "warden"}) != "", "guard blocks the warden")
	check(guard.validate(0, {"type": "attack", "iid": rusher, "target_kind": "unit", "target_iid": wall}) == "", "guard itself is legal")
	var breacher := guard.debug_place(0, "breach_runner", 1, true)
	check(guard.validate(0, {"type": "attack", "iid": breacher, "target_kind": "warden"}) == "", "breach ignores guard")

	var venom = boot()
	venom.debug_begin("combat")
	var moss := venom.debug_place(0, "widow_moss", 0, true)
	var bog := venom.debug_place(1, "bog_warden", 0, true)
	check(venom.apply(0, {"type": "attack", "iid": moss, "target_kind": "unit", "target_iid": bog}).ok, "venom attack")
	check(pass_to_focus(venom), "venom resolves")
	check(not on_board(venom, bog), "venom destroyed a unit it did not reduce to 0")

	var quiet = boot()
	quiet.debug_begin("combat")
	var moss2 := quiet.debug_place(0, "widow_moss", 0, true)
	var bog2 := quiet.debug_place(1, "bog_warden", 0, true)
	var hall := quiet.debug_veil(1, "quiet_hall", 0)
	check(quiet.apply(0, {"type": "attack", "iid": moss2, "target_kind": "unit", "target_iid": bog2}).ok, "attack into silence trap")
	var used := false
	for action in quiet.legal_actions(1):
		if str(action.get("type")) == "activate" and int(action.get("iid", -1)) == hall:
			used = quiet.apply(1, action).ok
			break
	check(used, "quiet hall answered the attack")
	check(pass_to_focus(quiet), "silenced attack resolves")
	var bog_after = quiet._live_unit(bog2)
	check(bog_after != null and int(bog_after.hp) == 3, "silence blanked venom")
	check(_has_event(quiet, "silence"), "silence flash")

	var pierce = boot()
	pierce.debug_begin("combat")
	pierce.debug_life(1, 30)
	var maw := pierce.debug_place(0, "cindermaw", 0, true)
	var spore := pierce.debug_place(1, "peat_spore", 0, true)
	check(pierce.apply(0, {"type": "attack", "iid": maw, "target_kind": "unit", "target_iid": spore}).ok, "pierce attack")
	check(pass_to_focus(pierce), "pierce resolves")
	check(not on_board(pierce, spore), "small unit died")
	check(int(pierce.players[1].life) == 27, "excess 3 hit the warden")

	var siphon = boot()
	siphon.debug_begin("combat")
	siphon.debug_life(0, 20)
	var imp := siphon.debug_place(0, "siphon_imp", 0, true)
	var fat := siphon.debug_place(1, "barrow_wall", 0, true)
	check(siphon.apply(0, {"type": "attack", "iid": imp, "target_kind": "unit", "target_iid": fat}).ok, "siphon attack")
	check(pass_to_focus(siphon), "siphon resolves")
	check(int(siphon.players[0].life) == 22, "siphon healed the damage dealt")
	check(_has_event(siphon, "heal"), "heal event")

	var twin = boot()
	twin.debug_begin("combat")
	var brand := twin.debug_place(0, "twin_brand", 0, true)
	check(int(twin._live_unit(brand).attacks_left) == 2, "twinstrike readies two swings")
	check(twin.apply(0, {"type": "attack", "iid": brand, "target_kind": "warden"}).ok, "first swing")
	check(pass_to_focus(twin), "first swing resolves")
	check(int(twin._live_unit(brand).attacks_left) == 1, "one swing left")
	check(twin.apply(0, {"type": "attack", "iid": brand, "target_kind": "warden"}).ok, "second swing")
	check(pass_to_focus(twin), "second swing resolves")
	check(int(twin.players[1].life) == 24, "two hits of 2 plus two on-attack pings")
	check(twin.validate(0, {"type": "attack", "iid": brand, "target_kind": "warden"}) != "", "no third swing")


func _test_aura_and_tax() -> void:
	var duel = boot()
	duel.debug_begin("main")
	duel.debug_energy(0, 8)
	var cap := duel.debug_place(0, "brand_captain", 0, true)
	var ally := duel.debug_place(0, "cinder_skirmisher", 1, true)
	check(int(duel.attack_value(ally)) == 3, "aura adds 1 attack")
	var mute := duel.debug_hand(0, "mute_sigil")
	check(duel.apply(0, {"type": "play", "iid": mute, "targets": [cap]}).ok, "silence captain")
	check(pass_to_focus(duel), "silence aura")
	check(int(duel.attack_value(ally)) == 2, "silenced aura source stops buffing")
	check(duel._live_unit(cap).keywords.is_empty(), "captain lost guard")

	var tax = boot()
	tax.debug_begin("main")
	tax.debug_place(1, "hush_beacon", 0, true)
	tax.debug_energy(0, 1)
	var foe := tax.debug_place(1, "barrow_mite", 1, true)
	var bolt := tax.debug_hand(0, "fracture_bolt")
	check(not tax.apply(0, {"type": "play", "iid": bolt, "targets": [foe]}).ok, "tax makes a 1-cost spell cost 2")
	tax.debug_energy(0, 2)
	check(tax.apply(0, {"type": "play", "iid": bolt, "targets": [foe]}).ok, "paying the tax works")


func _test_bot_game() -> void:
	var ember: Dictionary = CardDBScript.load_deck("res://data/decks/emberline.json")
	var glass: Dictionary = CardDBScript.load_deck("res://data/decks/glassward.json")
	var duel = DuelScript.new(db, ember.cards, glass.cards, 7)
	var steps := 0
	var damage := 0
	while int(duel.winner) < 0 and steps < 4000:
		var pid := int(duel.actor())
		if pid < 0:
			check(false, "bot game stuck in %s" % duel.window)
			return
		var action: Dictionary = BotScript.choose(duel, pid)
		var res: Dictionary = duel.apply(pid, action)
		if not res.ok:
			check(false, "bot illegal %s on %s" % [res.get("reason", ""), action])
			return
		steps += 1
	check(int(duel.winner) >= 0, "bot game ended")
	check(steps < 4000, "bot game bounded")
	for ev in duel.events:
		if str(ev.get("type", "")) == "damage":
			damage += 1
	check(damage > 0, "the game dealt damage")
	check(str(duel.win_reason) == "life" or str(duel.win_reason) == "deck", "win reason")
	print("  bot game steps %d winner %d via %s" % [steps, duel.winner, duel.win_reason])


func _test_mirevault_art() -> void:
	var deck: Dictionary = CardDBScript.load_deck("res://data/decks/mirevault.json")
	var painted := 0
	for id in deck.cards:
		var card: Dictionary = db[id]
		var path := "res://art/mirevault/%s.png" % str(id)
		check(str(card.get("art", "")) == path, "mire deck art path " + str(id))
		var image := Image.new()
		check(image.load(path) == OK, "mire deck art file " + str(id))
		painted += 1
	check(str(db.peat_spore.get("art", "")) == "res://art/mirevault/peat_spore.png", "peat spore art")
	var spore := Image.new()
	check(spore.load("res://art/mirevault/peat_spore.png") == OK, "peat spore file")
	check(not db.cinder_skirmisher.has("art"), "emberline keeps the emblem")
	check(not db.latch_of_glass.has("art"), "glassward keeps the emblem")
	check(painted == 32, "mire deck painted count")


func _test_flashes_and_table() -> void:
	for kind in ["play", "damage", "heal", "destroy", "buff", "trap_reveal", "chain_resolve"]:
		check(FlashScript.style_for(kind) == kind, "flash style " + kind)
	check(FlashScript.style_for("summon") == "play", "summon flash uses the play burst")
	check(FlashScript.style_for("not_an_event") == "", "unknown events stay quiet")

	var main = MainScene.instantiate()
	root.add_child(main)
	check(main.db.size() == 100, "menu loaded the card pool")
	main.start_faction("emberline", 1)
	var table = main.get_node_or_null("Table")
	check(table != null and table.duel != null, "table started a duel")
	if table == null or table.duel == null:
		return
	table.tick.stop()
	check(table.duel.players[0].hand.size() == 4, "opening hand is four")
	check(table.you_hand.get_child_count() == 4, "hand widgets match the rules hand")
	check(table.you_lanes.get_child_count() == 5, "five lanes")
	check(table.opp_lanes.get_child_count() == 5, "five enemy lanes")
	var before: int = int(table.duel.revision)
	table.fx.burst(Vector2(120, 80), "damage", "-2")
	check(table.fx.get_child_count() == 1, "a flash spawns without touching state")
	table.fx.skip_all()
	check(int(table.duel.revision) == before, "flashes do not change the duel")

	var steps := 0
	while steps < 16 and int(table.duel.winner) < 0:
		var pid := int(table.duel.actor())
		if pid == 1:
			table._on_tick()
		elif str(table.duel.window) == "focus" and table._has_type("end_phase"):
			table._press_end()
		else:
			table._press_pass()
		steps += 1
	check(steps == 16 or int(table.duel.winner) >= 0, "the table advanced through the rules API")
	check(str(table.duel.phase) != "draw" or int(table.duel.turn_number) > 1, "phases moved past the opening draw")
	check(table.log_label.text.find("Phase") >= 0, "the log shows rules events")
	check(table.you_hand.get_child_count() == table.duel.players[0].hand.size(), "hand stays in sync")
	main.queue_free()


func _has_event(duel, type_name: String) -> bool:
	for ev in duel.events:
		if str(ev.get("type", "")) == type_name:
			return true
	return false
