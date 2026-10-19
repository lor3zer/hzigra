class_name Track
extends Node3D

## Строит трассу целиком из кода: сплайн, дорогу, поребрики, отбойники,
## старт, декорации, небо и освещение. Также отвечает за проекцию
## позиции машины на трассу (прогресс круга, боковое смещение).

const SPACING := 3.0

var def: Dictionary
var theme: Dictionary
var is_open := false
var pts := PackedVector3Array()
var tangents := PackedVector3Array()
var normals := PackedVector3Array()   # вектор "вправо" относительно направления движения
var cum := PackedFloat32Array()
var radius := PackedFloat32Array()
var length := 0.0
var half_width := 9.0
var wall_dist := 21.0
var half_size := 450.0                # для открытой карты
var cones := PackedVector3Array()     # статичные препятствия (полигон)
var bbox := Rect2()
var night := false
var sun: DirectionalLight3D
var girl: StartGirl
var stands: Stands
var crowd_spots: Array[Vector3] = []
static var _tex_cache := {}

var _rng := RandomNumberGenerator.new()


func build(d: Dictionary, reverse: bool, tod: int, shadows: bool) -> void:
	def = d
	theme = d["theme"]
	is_open = d.get("open", false)
	half_width = d.get("width", 18.0) * 0.5
	wall_dist = half_width + d.get("runoff", 12.0)
	half_size = d.get("size", 900.0) * 0.5
	night = tod == 2
	_rng.seed = hash(d["id"])
	var cps: Array = d["points"].duplicate()
	if reverse:
		var first = cps.pop_front()
		cps.reverse()
		cps.push_front(first)
	_sample(cps)
	_build_environment(tod, shadows)
	_build_ground()
	if is_open:
		_build_open_area()
	else:
		_build_road()
		_build_walls()
	_build_start()
	_build_scenery()


# ---------------------------------------------------------------- геометрия

static func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	# центростремительный сплайн Катмулла-Рома (без петель и заломов)
	var t0 := 0.0
	var t1 := t0 + sqrt(maxf(p0.distance_to(p1), 0.01))
	var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 0.01))
	var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 0.01))
	var tt := lerpf(t1, t2, t)
	var a1 := p0 * (t1 - tt) / (t1 - t0) + p1 * (tt - t0) / (t1 - t0)
	var a2 := p1 * (t2 - tt) / (t2 - t1) + p2 * (tt - t1) / (t2 - t1)
	var a3 := p2 * (t3 - tt) / (t3 - t2) + p3 * (tt - t2) / (t3 - t2)
	var b1 := a1 * (t2 - tt) / (t2 - t0) + a2 * (tt - t0) / (t2 - t0)
	var b2 := a2 * (t3 - tt) / (t3 - t1) + a3 * (tt - t1) / (t3 - t1)
	return b1 * (t2 - tt) / (t2 - t1) + b2 * (tt - t1) / (t2 - t1)


func _sample(cps: Array) -> void:
	var n := cps.size()
	var dense := PackedVector2Array()
	for i in n:
		var p0: Vector2 = cps[(i - 1 + n) % n]
		var p1: Vector2 = cps[i]
		var p2: Vector2 = cps[(i + 1) % n]
		var p3: Vector2 = cps[(i + 2) % n]
		var steps := maxi(4, int(ceil(p1.distance_to(p2))))
		for s in steps:
			dense.append(_cr(p0, p1, p2, p3, float(s) / steps))
	# равномерная перевыборка с шагом SPACING
	var res := PackedVector2Array()
	res.append(dense[0])
	var acc := 0.0
	var m := dense.size()
	for j in m:
		var a := dense[j]
		var b := dense[(j + 1) % m]
		var seg := a.distance_to(b)
		while acc + seg >= SPACING:
			var t := (SPACING - acc) / seg
			a = a.lerp(b, t)
			res.append(a)
			seg = a.distance_to(b)
			acc = 0.0
		acc += seg
	if res[res.size() - 1].distance_to(res[0]) < SPACING * 0.5:
		res.remove_at(res.size() - 1)

	var cnt := res.size()
	pts.resize(cnt)
	tangents.resize(cnt)
	normals.resize(cnt)
	cum.resize(cnt)
	radius.resize(cnt)
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for i in cnt:
		pts[i] = Vector3(res[i].x, 0.0, res[i].y)
		mn = mn.min(res[i])
		mx = mx.max(res[i])
	bbox = Rect2(mn, mx - mn)
	var total := 0.0
	for i in cnt:
		cum[i] = total
		total += pts[i].distance_to(pts[(i + 1) % cnt])
		var t := (pts[(i + 1) % cnt] - pts[(i - 1 + cnt) % cnt]).normalized()
		tangents[i] = t
		normals[i] = Vector3(-t.z, 0.0, t.x)
	length = total
	for i in cnt:
		var a := pts[(i - 4 + cnt) % cnt]
		var b := pts[i]
		var c := pts[(i + 4) % cnt]
		var cross := (b - a).x * (c - a).z - (b - a).z * (c - a).x
		if absf(cross) < 0.001:
			radius[i] = 99999.0
		else:
			radius[i] = a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (2.0 * absf(cross))


## Проекция точки на осевую линию. hint < 0 — полный поиск.
func project(p: Vector3, hint: int) -> Dictionary:
	var n := pts.size()
	var best_d := INF
	var best_i := 0
	var best_t := 0.0
	var from := 0
	var to := n
	if hint >= 0:
		from = hint - 14
		to = hint + 15
	for k in range(from, to):
		var i := posmod(k, n)
		var a := pts[i]
		var ab := pts[(i + 1) % n] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * t
		var dx := p.x - q.x
		var dz := p.z - q.z
		var dd := dx * dx + dz * dz
		if dd < best_d:
			best_d = dd
			best_i = i
			best_t = t
	if hint >= 0 and best_d > (wall_dist + 8.0) * (wall_dist + 8.0) and not is_open:
		return project(p, -1)
	var j := (best_i + 1) % n
	var seg := pts[best_i].distance_to(pts[j])
	var nrm := normals[best_i].lerp(normals[j], best_t).normalized()
	var q2 := pts[best_i].lerp(pts[j], best_t)
	return {
		"idx": best_i,
		"dist": cum[best_i] + best_t * seg,
		"lat": Vector3(p.x - q2.x, 0.0, p.z - q2.z).dot(nrm),
		"normal": nrm,
		"tangent": tangents[best_i].lerp(tangents[j], best_t).normalized(),
	}


func index_at_distance(d: float) -> int:
	d = fposmod(d, length)
	var lo := 0
	var hi := cum.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if cum[mid] <= d:
			lo = mid
		else:
			hi = mid - 1
	return lo


static func yaw_from_dir(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## Позиция на стартовой решётке: шахматный порядок за линией старта.
func grid_slot(slot: int) -> Dictionary:
	var back := 10.0 + float(slot / 2) * 10.0 + float(slot % 2) * 5.0
	var i := index_at_distance(length - back)
	var side := -1.0 if slot % 2 == 0 else 1.0
	var pos := pts[i] + normals[i] * side * half_width * 0.42
	return {"pos": pos, "yaw": yaw_from_dir(tangents[i])}


# ---------------------------------------------------------------- материалы

## Четырёхугольник a-b-c-d с лицевой стороной в направлении n
## (в Godot лицевыми считаются грани с обходом по часовой стрелке).
static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uvs := PackedVector2Array()) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	if (b - a).cross(c - a).dot(n) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	var vs := [a, b, c, d]
	for i in order:
		if not uvs.is_empty():
			st.set_uv(uvs[i])
		st.add_vertex(vs[i])


static func tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = load("res://textures/" + name)
	return _tex_cache[name]


## Материал с текстурой. triplanar — для коробок без развёртки (масштаб в метрах^-1).
static func _tex_mat(name: String, color: Color, uv_scale := Vector3.ONE, triplanar := false, vc := false) -> StandardMaterial3D:
	var m := _mat(color, 0.9)
	m.albedo_texture = tex(name)
	m.uv1_scale = uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.vertex_color_use_as_albedo = vc
	m.metallic_specular = 0.2
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
	return m


static func _mat(color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _vc_mat(rough := 0.9) -> StandardMaterial3D:
	var m := _mat(Color.WHITE, rough)
	m.vertex_color_use_as_albedo = true
	return m


static func _emissive(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := _mat(color)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _add_mesh(mesh: Mesh, mat: Material, shadow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# ---------------------------------------------------------------- окружение

func _build_environment(tod: int, shadows: bool) -> void:
	var sky_top: Color
	var sky_hor: Color
	var sun_col: Color
	var sun_energy: float
	var sun_elev: float
	var amb := 0.42
	match tod:
		0:
			sky_top = Color(0.22, 0.45, 0.85)
			sky_hor = Color(0.72, 0.82, 0.95)
			sun_col = Color(1.0, 0.97, 0.9)
			sun_energy = 1.45
			sun_elev = -52.0
		1:
			sky_top = Color(0.22, 0.2, 0.45)
			sky_hor = Color(1.0, 0.55, 0.3)
			sun_col = Color(1.0, 0.68, 0.42)
			sun_energy = 1.0
			sun_elev = -14.0
		_:
			sky_top = Color(0.01, 0.015, 0.05)
			sky_hor = Color(0.08, 0.09, 0.2)
			sun_col = Color(0.55, 0.65, 1.0)
			sun_energy = 0.35
			sun_elev = -40.0
			amb = 0.9

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = sky_top
	sky_mat.sky_horizon_color = sky_hor
	sky_mat.ground_horizon_color = sky_hor
	sky_mat.ground_bottom_color = sky_top.darkened(0.5)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = amb
	env.ambient_light_sky_contribution = 0.65
	env.ambient_light_color = Color(0.62, 0.6, 0.55)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = sky_hor
	env.fog_density = 0.00045 if tod != 2 else 0.0012
	if tod == 2:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.32, 0.36, 0.55)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = sun_col
	sun.light_energy = sun_energy
	sun.rotation_degrees = Vector3(sun_elev, -35.0, 0.0)
	sun.shadow_enabled = shadows and tod != 2
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _build_ground() -> void:
	var center := bbox.get_center()
	var plane := PlaneMesh.new()
	plane.size = Vector2(9000, 9000)
	var mat := _tex_mat(theme.get("ground_tex", "grass.jpg"), theme.get("ground_tint", Color(0.9, 0.9, 0.9)), Vector3(900, 900, 1))
	var mi := _add_mesh(plane, mat)
	mi.position = Vector3(center.x, -0.02, center.y)

	if theme.get("water", false):
		var sea := PlaneMesh.new()
		sea.size = Vector2(9000, 3000)
		var wm := _mat(Color(0.05, 0.35, 0.55), 0.08, 0.3)
		var w := _add_mesh(sea, wm)
		w.position = Vector3(center.x, 0.0, bbox.end.y + 160.0 + 1500.0)
		var beach := PlaneMesh.new()
		beach.size = Vector2(9000, 60)
		var b := _add_mesh(beach, _tex_mat("sand.jpg", Color(1, 1, 1), Vector3(400, 3, 1)))
		b.position = Vector3(center.x, -0.01, bbox.end.y + 140.0)

	# далёкие горы / холмы по горизонту
	var hill := CylinderMesh.new()
	hill.top_radius = 0.0
	hill.bottom_radius = 1.0
	hill.height = 1.0
	hill.radial_segments = 7
	hill.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = hill
	mm.instance_count = 18
	for i in mm.instance_count:
		var ang := TAU * i / mm.instance_count + _rng.randf_range(-0.12, 0.12)
		var dist := _rng.randf_range(2300.0, 2900.0)
		var r := _rng.randf_range(350.0, 650.0)
		var h := _rng.randf_range(160.0, 420.0)
		var pos := Vector3(center.x + cos(ang) * dist, h * 0.5 - 20.0, center.y + sin(ang) * dist)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(r, h, r)), pos))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mtn := _tex_mat("rock.jpg", theme["mountain"], Vector3(6, 3, 1))
	mmi.material_override = mtn
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# ---------------------------------------------------------------- дорога

## Лента вдоль трассы между смещениями off_a..off_b. color_fn(i) -> Color или null (пропуск).
func _ribbon(off_a: float, off_b: float, y: float, color_fn: Callable, uv_len := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	for i in n:
		var col = color_fn.call(i)
		if col == null:
			continue
		var j := (i + 1) % n
		var a0 := pts[i] + normals[i] * off_a + Vector3(0, y, 0)
		var b0 := pts[i] + normals[i] * off_b + Vector3(0, y, 0)
		var a1 := pts[j] + normals[j] * off_a + Vector3(0, y, 0)
		var b1 := pts[j] + normals[j] * off_b + Vector3(0, y, 0)
		var v0 := cum[i] / uv_len if uv_len > 0.0 else 0.0
		var v1 := (cum[i] + pts[i].distance_to(pts[j])) / uv_len if uv_len > 0.0 else 1.0
		st.set_color(col)
		st.set_normal(Vector3.UP)
		quad(st, a0, b0, b1, a1, Vector3.UP, PackedVector2Array([Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)]))
	return st.commit()


func _build_road() -> void:
	var hw := half_width
	var asphalt := _tex_mat("asphalt.jpg", Color.WHITE, Vector3.ONE, false, true)
	asphalt.roughness = 0.85
	var road_col := Color(0.44, 0.44, 0.46)
	_add_mesh(_ribbon(-hw, hw, 0.0, func(_i): return road_col, 12.0), asphalt)

	var white := Color(0.95, 0.95, 0.95)
	var lines := _vc_mat()
	_add_mesh(_ribbon(-hw + 0.35, -hw + 0.6, 0.02, func(_i): return white), lines)
	_add_mesh(_ribbon(hw - 0.6, hw - 0.35, 0.02, func(_i): return white), lines)
	_add_mesh(_ribbon(-0.15, 0.15, 0.02, func(i): return white if int(cum[i] / 6.0) % 3 == 0 else null), lines)

	var red := Color(0.85, 0.1, 0.1)
	var curb := func(i):
		if radius[i] > 260.0:
			return null
		return red if int(cum[i] / 4.0) % 2 == 0 else white
	_add_mesh(_ribbon(hw, hw + 1.4, 0.03, curb), lines)
	_add_mesh(_ribbon(-hw - 1.4, -hw, 0.03, curb), lines)

	var run_col: Color = theme.get("runoff_tint", Color(1, 1, 1))
	var run_mat := _tex_mat(theme.get("runoff_tex", "gravel.jpg"), Color.WHITE, Vector3(1, 1, 1), false, true)
	_add_mesh(_ribbon(hw, wall_dist, 0.005, func(_i): return run_col, 8.0), run_mat)
	_add_mesh(_ribbon(-wall_dist, -hw, 0.005, func(_i): return run_col, 8.0), run_mat)


func _build_walls() -> void:
	var ca: Color = theme["wall_a"]
	var cb: Color = theme["wall_b"]
	var h := 1.1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	for side: float in [-1.0, 1.0]:
		for i in n:
			var j := (i + 1) % n
			var a := pts[i] + normals[i] * side * wall_dist
			var b := pts[j] + normals[j] * side * wall_dist
			var col := ca if int(cum[i] / 6.0) % 2 == 0 else cb
			st.set_color(col)
			st.set_normal(-normals[i] * side)
			var u0 := cum[i] / 4.0
			var u1 := u0 + pts[i].distance_to(pts[j]) / 4.0
			quad(st, a, b, b + Vector3(0, h, 0), a + Vector3(0, h, 0), -normals[i] * side,
				PackedVector2Array([Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0.7), Vector2(u0, 0.7)]))
			# верхняя грань
			var a2 := pts[i] + normals[i] * side * (wall_dist + 0.5)
			var b2 := pts[j] + normals[j] * side * (wall_dist + 0.5)
			st.set_color(Color(0.6, 0.6, 0.62))
			st.set_normal(Vector3.UP)
			quad(st, a + Vector3(0, h, 0), b + Vector3(0, h, 0), b2 + Vector3(0, h, 0), a2 + Vector3(0, h, 0), Vector3.UP,
				PackedVector2Array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 0.1), Vector2(u0, 0.1)]))
	_add_mesh(st.commit(), _tex_mat("concrete.jpg", Color.WHITE, Vector3.ONE, false, true))


func _build_start() -> void:
	var img := Image.create(16, 2, false, Image.FORMAT_RGB8)
	for x in 16:
		for y in 2:
			img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color(0.05, 0.05, 0.05))
	var tex := ImageTexture.create_from_image(img)
	var m := _mat(Color.WHITE)
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var plane := PlaneMesh.new()
	plane.size = Vector2(half_width * 2.0, 2.5)
	var mi := _add_mesh(plane, m)
	var yaw := yaw_from_dir(tangents[0])
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), pts[0] + Vector3(0, 0.04, 0))

	# арка старта
	var arch := Node3D.new()
	arch.transform = mi.transform
	add_child(arch)
	var w := half_width + 2.5
	var dark := _mat(Color(0.12, 0.12, 0.15), 0.5, 0.4)
	for s: float in [-1.0, 1.0]:
		var pil := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 8.0, 1.0)
		pil.mesh = bm
		pil.material_override = dark
		pil.position = Vector3(s * w, 4.0, 0)
		arch.add_child(pil)
	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(w * 2.0 + 1.0, 2.0, 1.0)
	beam.mesh = beam_mesh
	beam.material_override = _mat(Color(0.05, 0.4, 0.85), 0.4)
	beam.position = Vector3(0, 8.0, 0)
	arch.add_child(beam)
	for s: float in [-1.0, 1.0]:
		var lbl := Label3D.new()
		lbl.text = "NITRO RUSH"
		lbl.font_size = 160
		lbl.pixel_size = 0.01
		lbl.outline_size = 0
		lbl.modulate = Color(1, 1, 1)
		lbl.position = Vector3(0, 8.0, s * 0.52)
		lbl.rotation.y = 0.0 if s > 0 else PI
		arch.add_child(lbl)

	# девушка с флагами слева от линии старта, лицом к решётке
	girl = StartGirl.new()
	add_child(girl)
	girl.build(theme.get("wall_b", Color(0.8, 0.1, 0.1)))
	var gp := pts[0] - normals[0] * (half_width + 2.2) + tangents[0] * 3.0
	girl.position = gp
	girl.rotation.y = yaw_from_dir(-tangents[0])

	if is_open:
		return
	# главная трибуна справа от стартовой прямой
	stands = Stands.new(self)
	var k := index_at_distance(70.0)
	var off := wall_dist + 5.0
	var stand_pos := pts[k] + normals[k] * off
	if _clear_of_track(stand_pos, wall_dist + 4.0):
		var x := normals[k]
		var z := x.cross(Vector3.UP).normalized()
		stands.build_stand(self, Transform3D(Basis(x, Vector3.UP, z), stand_pos), 70.0, 6, true)


func _clear_of_track(p: Vector3, min_dist: float) -> bool:
	var md2 := min_dist * min_dist
	for i in range(0, pts.size(), 3):
		var dx := pts[i].x - p.x
		var dz := pts[i].z - p.z
		if dx * dx + dz * dz < md2:
			return false
	return true


# ---------------------------------------------------------------- полигон

func _build_open_area() -> void:
	var s := half_size
	var pad := PlaneMesh.new()
	pad.size = Vector2(s * 2.0, s * 2.0)
	var am := _tex_mat("asphalt.jpg", Color(0.48, 0.48, 0.5), Vector3(70, 70, 1))
	_add_mesh(pad, am).position = Vector3(0, 0.0, 0)

	# разметка маршрута для ИИ: пунктир
	var yellow := Color(1.0, 0.8, 0.1)
	_add_mesh(_ribbon(-0.3, 0.3, 0.02, func(i): return yellow if int(cum[i] / 6.0) % 2 == 0 else null), _vc_mat())
	_add_mesh(_ribbon(-half_width, -half_width + 0.3, 0.02, func(_i): return Color(0.9, 0.9, 0.9)), _vc_mat())
	_add_mesh(_ribbon(half_width - 0.3, half_width, 0.02, func(_i): return Color(0.9, 0.9, 0.9)), _vc_mat())

	# дрифт-круг
	_ring(Vector3(0, 0, -60), 55.0, 0.6, Color(0.95, 0.95, 0.95))
	_ring(Vector3(0, 0, -60), 18.0, 0.6, Color(0.95, 0.2, 0.2))
	# восьмёрка
	_ring(Vector3(-170, 0, 130), 32.0, 0.5, Color(0.2, 0.8, 1.0))
	_ring(Vector3(-106, 0, 130), 32.0, 0.5, Color(0.2, 0.8, 1.0))

	# конусы: слалом и "ворота"
	for i in 9:
		cones.append(Vector3(80.0 + i * 22.0, 0, 120.0))
	for i in 6:
		cones.append(Vector3(110.0 + i * 30.0, 0, -150.0 + (i % 2) * 8.0))
		cones.append(Vector3(110.0 + i * 30.0, 0, -165.0 + (i % 2) * 8.0))
	for i in 12:
		var a := TAU * i / 12.0
		cones.append(Vector3(cos(a) * 18.0, 0, -60.0 + sin(a) * 18.0))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 0.35
	cone.height = 0.9
	cone.radial_segments = 10
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	mm.instance_count = cones.size()
	for i in cones.size():
		mm.set_instance_transform(i, Transform3D(Basis(), cones[i] + Vector3(0, 0.45, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat(Color(1.0, 0.4, 0.0), 0.6)
	add_child(mmi)

	# ограждение по периметру
	var wall_mat := _mat(theme["wall_a"], 0.6)
	for k in 4:
		var w := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(s * 2.0 + 2.0, 1.2, 1.0)
		w.mesh = bm
		w.material_override = wall_mat
		var ang := k * PI * 0.5
		w.transform = Transform3D(Basis(Vector3.UP, ang), Vector3(sin(ang) * (s + 0.5), 0.6, cos(ang) * (s + 0.5)))
		add_child(w)


func _ring(c: Vector3, r: float, w: float, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(col)
	st.set_normal(Vector3.UP)
	var seg := 64
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * (r - w * 0.5) + Vector3(0, 0.02, 0)
		var p1 := c + Vector3(cos(a0), 0, sin(a0)) * (r + w * 0.5) + Vector3(0, 0.02, 0)
		var p2 := c + Vector3(cos(a1), 0, sin(a1)) * (r + w * 0.5) + Vector3(0, 0.02, 0)
		var p3 := c + Vector3(cos(a1), 0, sin(a1)) * (r - w * 0.5) + Vector3(0, 0.02, 0)
		quad(st, p0, p1, p2, p3, Vector3.UP)
	_add_mesh(st.commit(), _vc_mat())


# ---------------------------------------------------------------- декорации

func _build_scenery() -> void:
	var scenery := Scenery.new(self)
	if stands == null:
		stands = Stands.new(self)
	if not is_open:
		stands.build_corner_stands(self, scenery, 5)
	stands.flush(self)
	scenery._occupied.append_array(stands.occupied)
	crowd_spots = stands.emitters
	scenery.build(self)
	if night and not is_open:
		_build_lamps()


static func _cyl(top: float, bottom: float, h: float, segs := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


func _build_lamps() -> void:
	var poles := MultiMesh.new()
	poles.transform_format = MultiMesh.TRANSFORM_3D
	poles.mesh = _cyl(0.12, 0.15, 1.0, 6)
	var heads := MultiMesh.new()
	heads.transform_format = MultiMesh.TRANSFORM_3D
	var hb := BoxMesh.new()
	hb.size = Vector3(1.6, 0.25, 0.6)
	heads.mesh = hb
	var spots: Array[Transform3D] = []
	var glow: Array[Transform3D] = []
	var step := 20
	var i := 0
	var side := 1.0
	while i < pts.size():
		var p := pts[i] + normals[i] * side * (wall_dist + 1.0)
		spots.append(Transform3D(Basis().scaled(Vector3(1, 9, 1)), p + Vector3(0, 4.5, 0)))
		var head_pos := pts[i] + normals[i] * side * (wall_dist - 0.2) + Vector3(0, 9, 0)
		glow.append(Transform3D(Basis(Vector3.UP, yaw_from_dir(normals[i])), head_pos))
		side = -side
		i += step
	poles.instance_count = spots.size()
	heads.instance_count = glow.size()
	for k in spots.size():
		poles.set_instance_transform(k, spots[k])
		heads.set_instance_transform(k, glow[k])
	var a := MultiMeshInstance3D.new()
	a.multimesh = poles
	a.material_override = _mat(Color(0.3, 0.3, 0.33), 0.5, 0.5)
	add_child(a)
	var b := MultiMeshInstance3D.new()
	b.multimesh = heads
	b.material_override = _emissive(Color(1.0, 0.85, 0.55), 3.0)
	add_child(b)
	# мягкая подсветка дороги: полупрозрачные "пятна" света под фонарями
	var pool := _vc_mat()
	pool.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pool.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var warm := Color(0.35, 0.28, 0.15, 1.0)
	_add_mesh(_ribbon(-half_width, half_width, 0.025, func(k):
		var phase := float(k % step) / step
		var t := 1.0 - absf(phase - 0.0) * 2.0 if phase < 0.5 else 1.0 - absf(phase - 1.0) * 2.0
		return Color(warm.r * t, warm.g * t, warm.b * t, 1.0)), pool)
