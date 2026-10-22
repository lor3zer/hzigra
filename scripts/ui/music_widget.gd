class_name MusicWidget
extends PanelContainer

## Мини-плеер музыки: номер трека, время, прогресс и кнопки
## «назад», «пауза/играть», «вперёд». Работает и на паузе гонки.

static var _icons := {}

var _title: Label
var _time: Label
var _bar: ProgressBar
var _play: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(380, 0)
	var vb := VBoxContainer.new()
	add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	_title = UITheme.label("", 20, Color(1, 0.92, 0.5))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_time = UITheme.label("", 18, Color(0.7, 0.75, 0.85))
	top.add_child(_time)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(0, 8)
	vb.add_child(_bar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	row.add_child(_button("prev", Music.prev))
	_play = _button("pause", Music.toggle_pause)
	row.add_child(_play)
	row.add_child(_button("next", Music.next))
	if Music.tracks.is_empty():
		_title.text = "Музыка не найдена"


func _button(icon: String, cb: Callable) -> Button:
	var b := UITheme.button("", cb, Vector2(84, 50))
	b.icon = _icon(icon)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	return b


func _process(_dt: float) -> void:
	if Music.tracks.is_empty():
		return
	var pos := Music.position()
	var total := Music.length()
	_title.text = ("Пауза · " if Music.is_paused() else "Музыка · ") + Music.title()
	_time.text = "%d:%02d / %d:%02d" % [int(pos) / 60, int(pos) % 60, int(total) / 60, int(total) % 60]
	_bar.value = pos / total if total > 0.0 else 0.0
	_play.icon = _icon("play" if Music.is_paused() else "pause")


## Иконки рисуются в коде: шрифт может не содержать символов ⏮ ⏯ ⏭.
static func _icon(kind: String) -> Texture2D:
	if _icons.has(kind):
		return _icons[kind]
	var n := 28
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var white := Color(1, 1, 1)
	var tri := func(x0: float, x1: float, right: bool):
		# треугольник остриём вправо или влево, высота во весь значок
		for x in range(int(x0), int(x1)):
			var f := (x - x0) / (x1 - x0)
			var h := (1.0 - f if right else f) * (n * 0.42)
			for y in range(int(n * 0.5 - h), int(n * 0.5 + h) + 1):
				img.set_pixel(x, clampi(y, 0, n - 1), white)
	var bar := func(x0: int, x1: int):
		img.fill_rect(Rect2i(x0, 4, x1 - x0, n - 8), white)
	match kind:
		"play":
			tri.call(8.0, 23.0, true)
		"pause":
			bar.call(7, 12)
			bar.call(16, 21)
		"next":
			tri.call(5.0, 19.0, true)
			bar.call(19, 23)
		"prev":
			bar.call(5, 9)
			tri.call(9.0, 23.0, false)
	var tex := ImageTexture.create_from_image(img)
	_icons[kind] = tex
	return tex
