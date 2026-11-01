class_name CardDB
extends RefCounted

static func load_all() -> Dictionary:
	var db := {}
	var dir := DirAccess.open("res://data/cards")
	if dir == null:
		push_error("Cannot open res://data/cards")
		return db
	for file_name in dir.get_files():
		if not str(file_name).ends_with(".json"):
			continue
		var path := "res://data/cards/%s" % file_name
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_ARRAY:
			push_error("Bad card file %s" % path)
			continue
		for entry in parsed:
			var card = _norm(entry)
			var id := str(card.get("id", ""))
			if id == "" or db.has(id):
				push_error("Bad or duplicate card id in %s" % path)
				continue
			db[id] = card
	return db


static func load_deck(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Bad deck %s" % path)
		return {"name": "", "faction": "", "cards": []}
	parsed["cards"] = _norm(parsed.get("cards", []))
	return parsed


static func _norm(value):
	match typeof(value):
		TYPE_FLOAT:
			if value == floor(value):
				return int(value)
			return value
		TYPE_ARRAY:
			var arr := []
			for item in value:
				arr.append(_norm(item))
			return arr
		TYPE_DICTIONARY:
			var out := {}
			for key in value.keys():
				out[str(key)] = _norm(value[key])
			return out
		_:
			return value
