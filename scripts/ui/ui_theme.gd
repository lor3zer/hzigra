class_name UITheme
extends RefCounted

const ACCENT := Color(0.18, 0.82, 1.0)
const ACCENT2 := Color(1.0, 0.18, 0.35)
const PANEL := Color(0.06, 0.08, 0.13, 0.92)


static func box(bg: Color, border: Color, radius := 14, border_w := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	t.set_stylebox("normal", "Button", box(Color(0.1, 0.13, 0.2, 0.95), Color(ACCENT, 0.45)))
	t.set_stylebox("hover", "Button", box(Color(0.13, 0.18, 0.28, 0.98), ACCENT))
	t.set_stylebox("pressed", "Button", box(Color(0.0, 0.5, 0.75), Color(0.6, 1, 1)))
	t.set_stylebox("disabled", "Button", box(Color(0.1, 0.1, 0.12, 0.6), Color(0.3, 0.3, 0.3, 0.4)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.6, 0.6))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, Color(ACCENT, 0.35), 18))
	t.set_stylebox("panel", "Panel", box(PANEL, Color(ACCENT, 0.35), 18))
	t.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.04, 0.07), Color(ACCENT, 0.5), 10))
	t.set_stylebox("focus", "LineEdit", box(Color(0.03, 0.04, 0.07), ACCENT, 10))
	t.set_color("font_color", "Label", Color(0.92, 0.95, 1.0))
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 4)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_constant("h_separation", "GridContainer", 18)
	t.set_constant("v_separation", "GridContainer", 6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.15)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(6)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_font_size("font_size", "ProgressBar", 1)
	t.set_color("font_color", "ProgressBar", Color(0, 0, 0, 0))
	return t


static func label(text: String, size := 26, color := Color(0.92, 0.95, 1.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, min_size := Vector2(0, 64)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.pressed.connect(cb)
	return b


## Строка выбора «название  <  значение  >».
static func selector(parent: Control, title: String, options: Array, idx: int, cb: Callable, label_w := 250.0) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := label(title, 26)
	l.custom_minimum_size.x = label_w
	row.add_child(l)
	var state := {"i": clampi(idx, 0, options.size() - 1)}
	var val := label(str(options[state["i"]]), 26, Color(1, 0.92, 0.5))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.custom_minimum_size.x = 300
	var step := func(d: int):
		state["i"] = posmod(state["i"] + d, options.size())
		val.text = str(options[state["i"]])
		cb.call(state["i"])
	row.add_child(button("<", step.bind(-1), Vector2(70, 56)))
	row.add_child(val)
	row.add_child(button(">", step.bind(1), Vector2(70, 56)))
