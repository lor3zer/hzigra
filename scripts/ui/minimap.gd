class_name Minimap
extends Control

var race: Node
var _poly := PackedVector2Array()
var _origin := Vector2.ZERO
var _scale := 1.0


func setup(r: Node) -> void:
	race = r
	var t: Track = r.track
	var b := t.bbox
	if t.is_open:
		b = Rect2(-t.half_size, -t.half_size, t.half_size * 2.0, t.half_size * 2.0)
	var pad := 12.0
	_scale = minf((size.x - pad * 2.0) / b.size.x, (size.y - pad * 2.0) / b.size.y)
	_origin = Vector2(pad, pad) + (size - Vector2(pad, pad) * 2.0 - b.size * _scale) * 0.5 - b.position * _scale
	_poly.clear()
	for i in range(0, t.pts.size(), 4):
		_poly.append(_map(t.pts[i]))
	_poly.append(_poly[0])


func _map(p: Vector3) -> Vector2:
	return _origin + Vector2(p.x, p.z) * _scale


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if race == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35)
	sb.set_corner_radius_all(12)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	draw_polyline(_poly, Color(1, 1, 1, 0.85), 4.0, true)
	draw_circle(_poly[0], 4.0, Color(1, 0.9, 0.2))
	for car in race.cars:
		if not is_instance_valid(car):
			continue
		var p := _map(car.position)
		if car == race.player:
			draw_circle(p, 7.0, Color.WHITE)
			draw_circle(p, 5.0, Color(1.0, 0.2, 0.3))
		else:
			draw_circle(p, 4.5, CarDB.paint_color(car.paint).lightened(0.2))
