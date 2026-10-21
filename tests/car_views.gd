extends Node3D

## Машина с шести ракурсов (нужен дисплей, напр. xvfb-run).
## godot --path . res://tests/car_views.tscn -- <папка> <id машины> [tuned] [paint]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shots"
	var id: String = args[1] if args.size() > 1 else CarDB.CARS[0]["id"]
	var tuned := args.size() > 2 and args[2] == "tuned"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
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
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.4, 0.41, 0.43)
	floor_mi.material_override = fm
	add_child(floor_mi)
	var c := CarDB.get_car(id)
	var m := CarModel.new()
	add_child(m)
	var tune := {}
	if tuned:
		tune = {"wing": 3, "front": 2, "skirts": 1, "rear": 1, "hood": 1, "rims": 2, "rim_color": 2}
	var t0 := Time.get_ticks_msec()
	m.build(c, int(args[3]) if args.size() > 3 else int(c["paint"]), tune)
	print("build %s: %d ms" % [id, Time.get_ticks_msec() - t0])
	var tris := 0
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh as ArrayMesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			tris += mesh.surface_get_array_len(si) / 3
	t0 = Time.get_ticks_msec()
	var m2 := CarModel.new()
	add_child(m2)
	m2.build(c, 0, {"wing": 4, "rims": 1})
	print("rebuild with other tune: %d ms, triangles: %d" % [Time.get_ticks_msec() - t0, tris])
	m2.queue_free()
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var views := [
		["34f", Vector3(4.2, 1.6, -4.6), 34.0], ["34r", Vector3(-4.2, 1.7, 4.8), 34.0],
		["side", Vector3(8.5, 0.75, 0.0), 32.0], ["front", Vector3(0.0, 0.8, -8.0), 22.0],
		["rear", Vector3(0.0, 0.9, 8.0), 22.0], ["top", Vector3(0.01, 9.0, 0.0), 32.0],
	]
	for v in views:
		cam.position = v[1]
		cam.fov = v[2]
		cam.look_at(Vector3(0, 0.6 if v[0] != "top" else 0.0, 0), Vector3.UP if v[0] != "top" else Vector3.FORWARD)
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("%s_%s%s.png" % [id, v[0], "_t" if tuned else ""]))
	get_tree().quit()
