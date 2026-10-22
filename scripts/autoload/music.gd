extends Node

## Фоновая музыка: плейлист из res://audio/music/track*.ogg в случайном порядке.
## Играет и в меню, и в гонке (в гонке чуть тише).

signal track_changed(title: String)

var player: AudioStreamPlayer
var tracks: Array[String] = []
var _order: Array = []
var _idx := -1
var _history: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Net.dedicated:
		return
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
	if tracks.is_empty() or player == null:
		return
	if _idx >= 0:
		_history.append(_idx)
		if _history.size() > 20:
			_history.pop_front()
	if _order.is_empty():
		_order = range(tracks.size())
		_order.shuffle()
		# не повторяем только что игравший трек
		if _order.size() > 1 and _order[0] == _idx:
			_order.push_back(_order.pop_front())
	_play(_order.pop_front())


## Назад: в начале трека — предыдущий трек, иначе — к началу текущего.
func prev() -> void:
	if player == null or _idx < 0:
		return
	if player.get_playback_position() > 3.0 or _history.is_empty():
		player.play()
		player.stream_paused = false
		return
	_order.push_front(_idx)
	_play(_history.pop_back())


func _play(i: int) -> void:
	_idx = i
	var s: AudioStream = load(tracks[_idx])
	if s is AudioStreamOggVorbis:
		s.loop = false
	player.stream = s
	player.play()
	player.stream_paused = false
	track_changed.emit(title())


func toggle_pause() -> void:
	if player and player.stream:
		player.stream_paused = not player.stream_paused


func is_paused() -> bool:
	return player != null and player.stream_paused


## Позиция и длина текущего трека, секунды.
func position() -> float:
	return player.get_playback_position() if player and player.playing else 0.0


func length() -> float:
	return player.stream.get_length() if player and player.stream else 0.0


func title() -> String:
	return "Трек %d из %d" % [_idx + 1, tracks.size()] if _idx >= 0 else ""


func set_race(on: bool) -> void:
	if player == null:
		return
	player.volume_db = -4.0 if on else 0.0
