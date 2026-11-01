extends Node2D

## Short, parallel flashes. Skipping frees them immediately; the rules state is already final.

const MAP := {
	"play": "play",
	"summon": "play",
	"damage": "damage",
	"heal": "heal",
	"destroy": "destroy",
	"buff": "buff",
	"trap_reveal": "trap_reveal",
	"chain_resolve": "chain_resolve",
	"silence": "silence",
	"negate": "negate",
	"attack": "attack",
	"ward": "ward",
	"bounce": "bounce",
	"phase": "phase",
	"win": "win",
}

const COLOR := {
	"play": Color("f2c14e"),
	"damage": Color("e15b5b"),
	"heal": Color("7dce7a"),
	"destroy": Color("c9c2d6"),
	"buff": Color("f0c14a"),
	"trap_reveal": Color("d27bff"),
	"chain_resolve": Color("9ad7ff"),
	"silence": Color("8eb4ff"),
	"negate": Color("ff8b7b"),
	"attack": Color("ffb087"),
	"ward": Color("d7ecff"),
	"bounce": Color("7fd0c8"),
	"phase": Color("f4efe6"),
	"win": Color("f4efe6"),
}


static func style_for(event_type: String) -> String:
	return str(MAP.get(event_type, ""))


func burst(world_pos: Vector2, style: String, text: String) -> void:
	var color: Color = COLOR.get(style, Color.WHITE)
	var host := Node2D.new()
	host.position = to_local(world_pos)
	add_child(host)

	var plate := ColorRect.new()
	plate.color = Color(0.08, 0.05, 0.06, 0.88)
	plate.position = Vector2(-96, -20)
	plate.size = Vector2(192, 36)
	host.add_child(plate)
	var stripe := ColorRect.new()
	stripe.color = color
	stripe.position = Vector2(-96, 14)
	stripe.size = Vector2(192, 3)
	host.add_child(stripe)

	var label := Label.new()
	label.text = text
	label.position = Vector2(-96, -18)
	label.size = Vector2(192, 32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18 if style != "chain_resolve" else 22)
	label.add_theme_color_override("font_color", color)
	host.add_child(label)

	var bits := CPUParticles2D.new()
	bits.one_shot = true
	bits.explosiveness = 0.92
	bits.amount = 12 if style == "phase" else 32
	bits.lifetime = 0.48
	bits.spread = 180.0
	bits.gravity = Vector2(0, 40)
	bits.initial_velocity_min = 30.0
	bits.initial_velocity_max = 150.0
	bits.scale_amount_min = 2.0
	bits.scale_amount_max = 6.0
	bits.color = color
	bits.emitting = true
	host.add_child(bits)

	var tween := host.create_tween()
	tween.tween_property(host, "position", host.position + Vector2(0, -42), 0.45)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.12)
	tween.chain().tween_callback(func() -> void: host.queue_free())


func skip_all() -> void:
	for child in get_children():
		child.queue_free()
