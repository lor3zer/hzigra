class_name EngineAudio
extends AudioStreamPlayer

## Процедурный звук мотора: пила + треугольник + немного шума,
## частота зависит от скорости и "передачи".

const RATE := 22050.0

var playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _phase2 := 0.0
var _freq := 45.0
var _target := 45.0
var _vol := 0.0
var _target_vol := 0.15
var _lp := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	stream = gen
	volume_db = -6.0
	play()
	playback = get_stream_playback()


func set_engine(speed: float, top: float, throttle: float, nitro: bool) -> void:
	var gears := 6
	var span := top / gears
	var v := absf(speed)
	var g := mini(int(v / span), gears - 1)
	var frac := clampf((v - g * span) / span, 0.0, 1.0)
	_target = 42.0 + 95.0 * frac + 9.0 * g + throttle * 8.0
	if nitro:
		_target *= 1.08
	_target_vol = 0.1 + 0.12 * throttle + 0.05 * frac


func _process(_dt: float) -> void:
	if playback == null:
		return
	var n := playback.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		_freq += (_target - _freq) * 0.0015
		_vol += (_target_vol - _vol) * 0.002
		_phase = fmod(_phase + _freq / RATE, 1.0)
		_phase2 = fmod(_phase2 + _freq * 0.5 / RATE, 1.0)
		var s := (_phase * 2.0 - 1.0) * 0.55 + (absf(_phase2 * 4.0 - 2.0) - 1.0) * 0.45 + randf_range(-0.08, 0.08)
		_lp += (s - _lp) * 0.3
		buf[i] = Vector2(_lp, _lp) * _vol
	playback.push_buffer(buf)
