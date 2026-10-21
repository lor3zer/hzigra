extends Node3D

## Витрина всех машин (нужен дисплей, напр. xvfb-run).
## godot --path . res://tests/models_shot.tscn -- <папка>

func _ready() -> void:
	var out := "user://shots"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.72)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.36, 0.38)
	floor_mi.material_override = fm
	add_child(floor_mi)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var cars := CarDB.CARS
	var start := 0
	var count := cars.size()
	if args.size() > 2:
		start = int(args[1])
		count = int(args[2])
	for i in count:
		var c: Dictionary = cars[start + i]
		var m := CarModel.new()
		add_child(m)
		var tune := {}
		if args.size() > 3 and args[3] == "tuned":
			tune = {"wing": 3 + i % 2, "front": 1 + i % 2, "skirts": 1, "rear": 1, "hood": 1 + i % 2, "rims": 1 + i % 4, "rim_color": 1 + i % 4}
		m.build(c, int(c["paint"]), tune)
		m.position = Vector3((i % 5) * 6.5, 0, (i / 5) * 7.0)
		m.rotation.y = -0.75
		var l := Label3D.new()
		l.text = c["name"]
		l.font_size = 64
		l.pixel_size = 0.006
		l.position = m.position + Vector3(0, 2.0, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
	var rows := int(ceil(count / 5.0))
	cam.fov = 40
	cam.position = Vector3(12, 9 + rows * 2.5, rows * 7.0 + 9)
	cam.look_at(Vector3(12, 0, (rows - 1) * 3.5))
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var suffix := "_tuned" if args.size() > 3 and args[3] == "tuned" else ""
	get_viewport().get_texture().get_image().save_png(out.path_join("models_%d%s.png" % [start, suffix]))
	# крупный план
	cam.fov = 35
	for k in mini(count, 5):
		var p := Vector3((k % 5) * 6.0, 0, 0)
		cam.position = p + Vector3(5.2, 1.9, -2.6)
		cam.look_at(p + Vector3(0, 0.55, 0))
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("model_%d%s.png" % [start + k, suffix]))
	get_tree().quit()
