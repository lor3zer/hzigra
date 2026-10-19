extends Node

## Headless-проверка: геометрия трасс, заезд ботов, экраны меню.
## Запуск: godot --headless --fixed-fps 60 --path . res://tests/sim_test.tscn

var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	_check_geometry()
	for t in TrackDB.TRACKS:
		await _race(t["id"], false)
	await _race("valley", true)
	await _menus()
	print("TESTS DONE, failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _fail(msg: String) -> void:
	failures += 1
	print("FAIL: ", msg)


func _check_geometry() -> void:
	for d in TrackDB.TRACKS:
		for rev in [false, true]:
			var t := Track.new()
			add_child(t)
			t.build(d, rev, 0, false)
			var min_r := INF
			for r in t.radius:
				min_r = minf(min_r, r)
			var n := t.pts.size()
			var gap := int((t.wall_dist * 3.0) / Track.SPACING) + 8
			var min_sep := INF
			for i in range(0, n, 2):
				for j in range(0, n, 2):
					var di := absi(i - j)
					di = mini(di, n - di)
					if di < gap:
						continue
					min_sep = minf(min_sep, t.pts[i].distance_to(t.pts[j]))
			print("%-8s rev=%s len=%.0fm samples=%d minR=%.1f wall=%.1f minSep=%.1f" % [d["id"], rev, t.length, n, min_r, t.wall_dist, min_sep])
			if not d.get("open", false):
				if min_r < t.wall_dist + 4.0:
					_fail("%s: corner radius %.1f < wall %.1f (inner wall folds)" % [d["id"], min_r, t.wall_dist])
				if min_sep < t.wall_dist * 2.0 + 6.0:
					_fail("%s: track parts too close (%.1f)" % [d["id"], min_sep])
			t.free()


func _race(track_id: String, reverse: bool) -> void:
	var cfg := {"mode": "race", "net": false, "track": track_id, "laps": 2, "opponents": 5, "difficulty": 2,
		"reverse": reverse, "tod": 2 if track_id == "city" else 0, "collisions": true}
	var grid := Game._ai_entries(5, "hyper", -1)
	grid.append_array(Game._ai_entries(1, "sport", -10))
	grid.append({"id": 1, "name": "P", "car": "kestrel_rs", "paint": 0, "ai": false})
	Game.settings["sound"] = false
	var race := Race.new()
	add_child(race)
	race.setup(cfg, grid)
	race.player.ctrl = Car.Ctrl.AI
	race.drivers[1] = AIDriver.new(race.player, race.track, 1.0, race.cars)
	var hits := {}
	var prev := {}
	var offroad := {}
	var frames := 0
	var limit := 60 * 400
	while frames < limit:
		await get_tree().process_frame
		frames += 1
		for c in race.cars:
			if c.wall_hit > prev.get(c, 0.0) + 0.05:
				hits[c] = hits.get(c, 0) + 1
			prev[c] = c.wall_hit
			if c.offroad:
				offroad[c] = offroad.get(c, 0) + 1
		var all_done := true
		for c in race.cars:
			if not c.finished:
				all_done = false
		if all_done:
			break
	print("--- race %s rev=%s: %.1fs game time" % [track_id, reverse, race.race_time])
	for c in race.standings():
		print("  %-14s %-12s fin=%s time=%s best=%s walls=%d offroad=%.1fs" % [c.def["name"], c.driver_name, c.finished,
			Game.fmt_time(c.finish_time), Game.fmt_time(c.best_lap), hits.get(c, 0), offroad.get(c, 0) / 60.0])
		if not c.finished and not race.track.is_open:
			_fail("%s: %s did not finish" % [track_id, c.def["name"]])
	race.free()


func _menus() -> void:
	var main = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().process_frame
	for s in ["main", "race", "sandbox", "garage", "settings", "mp", "main"]:
		main.show_menu(s)
		for i in 5:
			await get_tree().process_frame
		print("menu ok: ", s)
	Game.last_sandbox["track"] = "polygon"
	Game.last_sandbox["opponents"] = 3
	Game.start_sandbox()
	for i in 120:
		await get_tree().process_frame
	print("sandbox ok")
	Game.last_race["opponents"] = 3
	Game.start_single_race()
	for i in 300:
		await get_tree().process_frame
	var race = main.current
	race.hud.toggle_pause()
	await get_tree().process_frame
	race.hud.toggle_pause()
	race.hud.show_results()
	for i in 5:
		await get_tree().process_frame
	print("race ui ok")
	main.show_menu("main")
	await get_tree().process_frame
	main.queue_free()
