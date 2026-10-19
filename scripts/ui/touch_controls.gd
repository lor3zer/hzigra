class_name TouchControls
extends Control

## Сенсорное управление с поддержкой мультитача: каждый палец
## привязан к своей зоне, пальцем можно "переехать" между кнопками.

var steer := 0.0
var gas := 0.0
var brake := 0.0
var nitro := false
var nitro_level := 100.0
var show_steer := true

var _touches := {}   # индекс пальца -> имя зоны
var _zones := {}     # имя -> Rect2


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var s := size
	var b := clampf(s.y * 0.22, 100.0, 170.0)
	var m := 22.0
	_zones = {
		"left": Rect2(m, s.y - b - m, b, b),
		"right": Rect2(m * 1.6 + b, s.y - b - m, b, b),
		"brake": Rect2(s.x - m * 1.6 - b * 1.9, s.y - b * 0.9 - m, b * 0.9, b * 0.9),
		"gas": Rect2(s.x - m - b, s.y - b * 1.3 - m, b, b * 1.3),
		"nitro": Rect2(s.x - m - b * 0.85, s.y - b * 1.3 - m * 1.6 - b * 0.8, b * 0.75, b * 0.75),
	}
	queue_redraw()


func reset() -> void:
	_touches.clear()
	_apply()


func _hit(p: Vector2) -> String:
	for z in _zones:
		if z in ["left", "right"] and not show_steer:
			continue
		var r: Rect2 = _zones[z]
		if r.grow(14.0).has_point(p):
			return z
	return ""


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = _hit(event.position)
		else:
			_touches.erase(event.index)
		_apply()
	elif event is InputEventScreenDrag:
		if _touches.has(event.index):
			_touches[event.index] = _hit(event.position)
			_apply()


func _apply() -> void:
	var active := {}
	for z in _touches.values():
		active[z] = true
	steer = (1.0 if active.has("right") else 0.0) - (1.0 if active.has("left") else 0.0)
	gas = 1.0 if active.has("gas") else 0.0
	brake = 1.0 if active.has("brake") else 0.0
	nitro = active.has("nitro")
	queue_redraw()


func _is_active(z: String) -> bool:
	return z in _touches.values()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for z in _zones:
		if z in ["left", "right"] and not show_steer:
			continue
		var r: Rect2 = _zones[z]
		var on := _is_active(z)
		var base := Color(1, 1, 1, 0.16)
		var border := Color(1, 1, 1, 0.5)
		match z:
			"gas":
				base = Color(0.1, 0.9, 0.4, 0.28)
			"brake":
				base = Color(1.0, 0.25, 0.25, 0.28)
			"nitro":
				base = Color(0.2, 0.6, 1.0, 0.3)
		if on:
			base.a = 0.6
			border = Color.WHITE
		var c := r.get_center()
		if z == "gas":
			var sb := StyleBoxFlat.new()
			sb.bg_color = base
			sb.border_color = border
			sb.set_border_width_all(3)
			sb.set_corner_radius_all(28)
			draw_style_box(sb, r)
		else:
			draw_circle(c, r.size.x * 0.5, base)
			draw_arc(c, r.size.x * 0.5 - 1.5, 0.0, TAU, 48, border, 3.0, true)
		var h := r.size.x * 0.22
		match z:
			"left":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-h, 0), c + Vector2(h * 0.7, -h), c + Vector2(h * 0.7, h)]), Color(1, 1, 1, 0.9))
			"right":
				draw_colored_polygon(PackedVector2Array([c + Vector2(h, 0), c + Vector2(-h * 0.7, -h), c + Vector2(-h * 0.7, h)]), Color(1, 1, 1, 0.9))
			"gas":
				draw_string(font, Vector2(r.position.x, c.y + 12), "ГАЗ", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 30)
			"brake":
				draw_string(font, Vector2(r.position.x, c.y + 10), "ТОРМОЗ", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22)
			"nitro":
				# индикатор заряда по кругу
				draw_arc(c, r.size.x * 0.5 - 6, -PI * 0.5, -PI * 0.5 + TAU * nitro_level / 100.0, 40, Color(0.4, 0.8, 1.0), 6.0)
				draw_string(font, Vector2(r.position.x, c.y + 9), "NOS", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24)
