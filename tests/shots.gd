extends Node

## Скриншоты для визуальной проверки (нужен дисплей, напр. xvfb-run).
## godot --path . res://tests/shots.tscn -- <папка>

var out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scripts/main.gd").new()
	add_child(main)
	await _wait(10)
	await _shot("menu_main")
	main.show_menu("garage")
	await _wait(10)
	await _shot("menu_garage")
	main.show_menu("race")
	await _wait(5)
	await _shot("menu_race")
	main.show_menu("mp")
	await _wait(5)
	await _shot("menu_mp")
	var tods := {"valley": 0, "desert": 1, "snow": 0, "city": 2, "coast": 0, "polygon": 0}
	var only := args.slice(1)
	for id in tods:
		if not only.is_empty() and not id in only:
			continue
		Game.last_race = {"track": id, "laps": 3, "opponents": 5, "difficulty": 1, "reverse": false, "tod": tods[id], "collisions": true}
		Game.start_single_race()
		var race = main.current
		race.player.ctrl = Car.Ctrl.AI
		race.drivers[1] = AIDriver.new(race.player, race.track, 0.9, race.cars)
		await _wait(60 * 5)
		await _shot("race_" + id)
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", name)
