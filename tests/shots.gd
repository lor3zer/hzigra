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
	main.show_menu("settings")
	await _wait(5)
	await _shot("menu_settings")
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
		if id == "valley":
			await _wait(80)
			var cam := Camera3D.new()
			race.add_child(cam)
			var g: Node3D = race.track.girl
			cam.global_position = g.global_position + g.global_basis * Vector3(-1.6, 1.3, -3.4)
			cam.look_at(g.global_position + Vector3(0, 1.1, 0))
			cam.current = true
			await _wait(20)
			await _shot("girl")
			if race.track.crowd_spots.size() > 1:
				var sp: Vector3 = race.track.crowd_spots[1]
				cam.global_position = sp + Vector3(25, 10, 25)
				cam.look_at(sp)
				await _wait(5)
				await _shot("stand")
			race.camera.current = true
			cam.queue_free()
		await _wait(60 * 5)
		await _shot("race_" + id)
		if id == "valley":
			race.hud.toggle_pause()
			await _wait(5)
			await _shot("pause")
			race.hud._open_settings()
			await _wait(5)
			await _shot("pause_settings")
			race.hud._resume()
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", name)
