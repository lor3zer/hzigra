class_name EngineSound
extends Node3D

## Звук машины. Мотор — три зацикленных слоя (газ на низах, газ на верхах,
## сброс газа), они смешиваются и транспонируются по текущим оборотам.
## Сверху: турбина и перепускной клапан, выстрелы в выхлоп при сбросе газа,
## щелчки переключений, визг шин, ветер, удары.
## Машина игрока звучит "в салоне" (2D), соперники — в 3D, с затуханием.

static var _streams := {}

var car: Car
var local := false
var _lo: Node
var _hi: Node
var _off: Node
var _turbo: Node
var _screech: Node
var _wind: Node
var _shots: Array = []
var _next_shot := 0
var _prev_throttle := 0.0
var _boost := 0.0
var _pops: Array = []
var _prev_wall := 0.0
var _t := 0.0
var _gain := 0.0   # дБ: машина игрока громче


static func stream(name: String, loop: bool) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var path := "res://audio/%s.wav" % name
	if not ResourceLoader.exists(path):
		var ogg: AudioStreamOggVorbis = load("res://audio/%s.ogg" % name)
		ogg.loop = loop
		_streams[name] = ogg
		return ogg
	var s: AudioStreamWAV = load(path)
	if loop and s.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		# запасной вариант, если в .import не включено зацикливание
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / 2
	_streams[name] = s
	return s


static func _db(g: float) -> float:
	return linear_to_db(maxf(g, 0.0001))


func setup(c: Car, is_local: bool) -> void:
	car = c
	local = is_local
	_gain = -1.0 if is_local else 2.0
	car.shifted.connect(_on_shift)
	refresh()


## Пересобрать плееры (например, после смены машины).
func refresh() -> void:
	for ch in get_children():
		ch.queue_free()
	_shots.clear()
	var k: String = car.eng.get("samples", car.def.get("engine", "v8x"))
	_lo = _loop("eng_%s_lo" % k)
	_hi = _loop("eng_%s_hi" % k)
	_off = _loop("eng_%s_off" % k) if local else null
	_turbo = _loop("turbo") if local and bool(car.eng["turbo"]) else null
	_screech = _loop("screech")
	_wind = _loop("wind") if local else null
	for i in (4 if local else 2):
		_shots.append(_player(null))


func _player(s: AudioStream) -> Node:
	var p: Node
	if local:
		p = AudioStreamPlayer.new()
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 10.0
		p3.max_distance = 280.0
		p3.max_db = 3.0
		p = p3
	p.stream = s
	p.bus = "SFX"
	add_child(p)
	return p


func _loop(name: String) -> Node:
	var p := _player(stream(name, true))
	p.volume_db = -80.0
	p.play()
	return p


func shot(name: String, gain := 1.0, pitch := 1.0) -> void:
	if _shots.is_empty():
		return
	var p: Node = _shots[_next_shot]
	_next_shot = (_next_shot + 1) % _shots.size()
	p.stream = stream(name, false)
	p.volume_db = _db(gain) + _gain
	p.pitch_scale = pitch
	p.play()


func impact(strength: float) -> void:
	shot("hit", clampf(strength, 0.15, 1.0), randf_range(0.85, 1.1))


func _on_shift(up: bool) -> void:
	if local:
		shot("shift", 0.35, randf_range(0.9, 1.1))
	# "выстрел" при переключении под нагрузкой (как у роботизированных коробок)
	if up and car.throttle_level > 0.6 and bool(car.eng["pops"]):
		shot("pop0", 0.45, randf_range(1.1, 1.4))
		car.model.backfire()


func _process(dt: float) -> void:
	if car == null or not is_instance_valid(car) or _lo == null:
		return
	_t += dt
	var e: Dictionary = car.eng
	var rpm := car.rpm
	var load := car.throttle_level
	var lo_rpm: float = e["lo_rpm"]
	var hi_rpm: float = e["hi_rpm"]
	var redline: float = e["redline"]

	# мотор: равномощностный кроссфейд низ/верх, отдельный слой сброса газа
	var x := clampf((rpm - lo_rpm) / (hi_rpm - lo_rpm), 0.0, 1.0)
	var on: float
	if _off:
		on = 0.12 + 0.88 * pow(load, 0.7)
	else:
		on = lerpf(0.5, 1.0, load)
	if car.limiter:
		on *= 1.0 if fmod(_t, 0.09) < 0.05 else 0.35
	_lo.volume_db = _db(cos(x * PI * 0.5) * on) + _gain
	_hi.volume_db = _db(sin(x * PI * 0.5) * on) + _gain
	_lo.pitch_scale = clampf(rpm / lo_rpm, 0.15, 4.0)
	_hi.pitch_scale = clampf(rpm / hi_rpm, 0.15, 4.0)
	if _off:
		_off.volume_db = _db((1.0 - load) * 0.8) + _gain
		_off.pitch_scale = clampf(rpm / float(e["off_rpm"]), 0.15, 4.0)

	# турбина
	var throttle_now := car.in_throttle if local else load
	if _turbo:
		var target := 0.0
		if throttle_now > 0.5:
			target = clampf((rpm / redline - 0.25) / 0.45, 0.0, 1.0)
		_boost = move_toward(_boost, target, dt * (1.1 if target > _boost else 5.0))
		_turbo.volume_db = _db(_boost * 0.3)
		_turbo.pitch_scale = 0.55 + 0.6 * _boost

	# сброс газа: клапан и выстрелы в выхлоп
	if _prev_throttle > 0.6 and throttle_now < 0.2 and rpm > redline * 0.5:
		if bool(e["turbo"]) and local and _boost > 0.3:
			var flutter: bool = car.def.get("engine", "") in ["i4t", "i6t"]
			shot("flutter" if flutter else "bov", 0.4 + 0.5 * _boost, randf_range(0.95, 1.1))
		if bool(e["pops"]):
			for i in randi_range(2, 5):
				_pops.append(_t + randf_range(0.05, 0.9))
	_prev_throttle = throttle_now
	for i in range(_pops.size() - 1, -1, -1):
		if _t >= _pops[i]:
			_pops.remove_at(i)
			shot("pop%d" % (randi() % 3), randf_range(0.5, 0.9), randf_range(0.85, 1.2))
			car.model.backfire()

	# шины
	var s := clampf(car.slip, 0.0, 1.0)
	_screech.volume_db = _db(s * 0.75)
	_screech.pitch_scale = 0.9 + 0.2 * s

	# ветер
	if _wind:
		var w := clampf(absf(car.speed) / 75.0, 0.0, 1.0)
		_wind.volume_db = _db(w * w * 0.5)
		_wind.pitch_scale = 0.8 + 0.5 * w

	# удары о стену
	if car.wall_hit > _prev_wall + 0.1:
		impact(car.wall_hit)
	_prev_wall = car.wall_hit
