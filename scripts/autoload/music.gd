extends Node

## Фоновая музыка: плейлист из res://audio/music/track*.ogg в случайном порядке.
## Играет и в меню, и в гонке (в гонке чуть тише).

signal track_changed(title: String)

var player: AudioStreamPlayer
var tracks: Array[String] = []
var _order: Array = []
var _idx := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(1, 21):
		var p := "res://audio/music/track%d.ogg" % i
		if ResourceLoader.exists(p):
			tracks.append(p)
	player = AudioStreamPlayer.new()
	player.bus = "Music"
	add_child(player)
	player.finished.connect(next)
	next()


func next() -> void:
	if tracks.is_empty():
		return
	if _order.is_empty():
		_order = range(tracks.size())
		_order.shuffle()
		# не повторяем только что игравший трек
		if _order.size() > 1 and _order[0] == _idx:
			_order.push_back(_order.pop_front())
	_idx = _order.pop_front()
	var s: AudioStream = load(tracks[_idx])
	if s is AudioStreamOggVorbis:
		s.loop = false
	player.stream = s
	player.play()
	track_changed.emit(title())


func title() -> String:
	return "Трек %d из %d" % [_idx + 1, tracks.size()] if _idx >= 0 else ""


func set_race(on: bool) -> void:
	player.volume_db = -4.0 if on else 0.0
