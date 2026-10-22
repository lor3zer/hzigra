extends Node

## Демо-заезд для записи видео со звуком (Movie Maker):
## godot --path . --write-movie demo.avi --fixed-fps 30 res://tests/demo.tscn -- <трасса> <машина> <секунды>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var track_id := args[0] if args.size() > 0 else "valley"
	var car_id := args[1] if args.size() > 1 else "audax_s8"
	var seconds := float(args[2]) if args.size() > 2 else 30.0
	Game.settings["car"] = car_id
	Game.settings["camera"] = 0
	Game.settings["sound"] = true
	Game.settings["volume"] = 0.8
	Game.settings["music"] = 0.0 if args.size() > 3 and args[3] == "nomusic" else 0.5
	Game.apply_audio()
	Game.last_race = {"track": track_id, "laps": 3, "opponents": 5, "difficulty": 2, "reverse": false, "tod": (2 if track_id == "city" else 1), "collisions": true}
	var main = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().process_frame
	Game.start_single_race()
	var race = main.current
	race.drivers[1] = AIDriver.new(race.player, race.track, 1.0, race.cars)
	race.player.ctrl = Car.Ctrl.AI
	await get_tree().create_timer(seconds).timeout
	get_tree().quit()
