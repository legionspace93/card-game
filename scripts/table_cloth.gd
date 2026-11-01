extends Control

## The duel table: ash boards, a coal rift, and a quiet grain. Not a flat fill.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var s := size
	if s.x < 8.0 or s.y < 8.0:
		return
	draw_rect(Rect2(Vector2.ZERO, s), Color("2a1a16"))
	draw_rect(Rect2(18, 18, s.x - 36, s.y * 0.42), Color("3a241c"))
	draw_rect(Rect2(18, s.y * 0.5, s.x - 36, s.y * 0.46), Color("1a100e"))
	var rift_y := s.y * 0.47
	draw_rect(Rect2(0, rift_y - 28, s.x, 56), Color(0.72, 0.28, 0.08, 0.55))
	draw_rect(Rect2(0, rift_y - 6, s.x, 12), Color(1.0, 0.62, 0.22, 0.9))
	draw_line(Vector2(24, rift_y), Vector2(s.x - 24, rift_y), Color(1, 0.86, 0.55, 0.95), 2.0)
	draw_rect(Rect2(Vector2.ZERO, s), Color("6a3a22"), false, 10.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 14014
	for _i in 220:
		var p := Vector2(rng.randf() * s.x, rng.randf() * s.y)
		var warm := rng.randf() > 0.5
		var col := Color(0.95, 0.55, 0.25, 0.045) if warm else Color(0.7, 0.85, 0.75, 0.035)
		draw_circle(p, rng.randf_range(0.7, 1.8), col)
	draw_rect(Rect2(0, 0, s.x, 36), Color(0, 0, 0, 0.28))
	draw_rect(Rect2(0, s.y - 48, s.x, 48), Color(0, 0, 0, 0.38))
	draw_rect(Rect2(0, 0, 28, s.y), Color(0, 0, 0, 0.18))
	draw_rect(Rect2(s.x - 28, 0, 28, s.y), Color(0, 0, 0, 0.18))
