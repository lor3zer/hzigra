class_name Scenery
extends RefCounted

## Декорации вокруг трассы: деревья, кусты, камни, трава, хижины и дома.
## Всё собирается в MultiMesh-пачки (один вызов отрисовки на тип детали).

const CELL := 40.0

var track: Track
var rng: RandomNumberGenerator
var night := false
var _batches := {}      # ключ -> {"mesh", "mat", "xf": Array[Transform3D], "col": PackedColorArray}
var _grid := {}         # ячейка -> индексы точек трассы
var _occupied: Array = []   # [Vector3, радиус] — занятые места (дома)
static var _meshes := {}
static var _mats := {}


func _init(t: Track) -> void:
	track = t
	rng = t._rng
	night = t.night
	for i in range(0, t.pts.size(), 2):
		var key := _cell(t.pts[i])
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


## Расстояние до осевой линии трассы (быстро, по сетке).
func dist_to_track(p: Vector3, max_d := 200.0) -> float:
	var c := _cell(p)
	var r := int(ceil(max_d / CELL))
	var best := INF
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not _grid.has(k):
				continue
			for i in _grid[k]:
				var q: Vector3 = track.pts[i]
				var d := Vector2(q.x - p.x, q.z - p.z).length()
				if d < best:
					best = d
	return best


func _free_spot(p: Vector3, radius: float) -> bool:
	for o in _occupied:
		if (o[0] as Vector3).distance_to(p) < radius + float(o[1]):
			return false
	return true


# ---------------------------------------------------------------- ресурсы

static func mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh
	match key:
		"cyl":
			m = Track._cyl(1.0, 1.0, 1.0, 8)
		"cyl_taper":
			m = Track._cyl(0.65, 1.0, 1.0, 7)
		"cone":
			m = Track._cyl(0.0, 1.0, 1.0, 9)
		"sphere":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = 9
			s.rings = 5
			m = s
		"rock":
			var r := SphereMesh.new()
			r.radius = 0.5
			r.height = 1.0
			r.radial_segments = 6
			r.rings = 3
			m = r
		"box":
			m = BoxMesh.new()
		"prism":
			var p := PrismMesh.new()
			p.size = Vector3.ONE
			m = p
		"tuft":
			m = Track._cyl(0.0, 1.0, 1.0, 5)
		"leaf":
			var b := BoxMesh.new()
			b.size = Vector3(0.5, 0.05, 2.6)
			m = b
	_meshes[key] = m
	return m


static func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	match key:
		"bark":
			m.albedo_texture = Track.tex("bark.jpg")
		"foliage":
			m.albedo_texture = Track.tex("foliage.jpg")
			m.uv1_scale = Vector3(2, 2, 1)
		"rock":
			m.albedo_texture = Track.tex("rock.jpg")
		"wood":
			m.albedo_texture = Track.tex("wood.jpg")
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.3, 0.3, 0.3)
		"plaster":
			m.albedo_texture = Track.tex("plaster.jpg")
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.25, 0.25, 0.25)
		"roof":
			m.albedo_texture = Track.tex("roof.jpg")
			m.uv1_scale = Vector3(3, 2, 1)
		"facade", "facade_night":
			m.albedo_texture = Track.tex("facade.jpg")
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.05, 0.04, 0.05)
			if key == "facade_night":
				m.emission_enabled = true
				m.emission_texture = Track.tex("facade_emit.jpg")
				m.emission_energy_multiplier = 1.6
		"dark":
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(0.08, 0.08, 0.1)
		"glass":
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(0.25, 0.32, 0.4)
			m.roughness = 0.15
			m.metallic = 0.5
		"window_lit":
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(1.0, 0.85, 0.55)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.8, 0.5)
			m.emission_energy_multiplier = 1.5
		_:
			pass
	_mats[key] = m
	return m


func add(mesh_key: String, mat_key: String, xf: Transform3D, col := Color.WHITE) -> void:
	var key := mesh_key + "|" + mat_key
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh(mesh_key), "mat": mat(mat_key), "xf": [], "col": PackedColorArray()}
	_batches[key]["xf"].append(xf)
	_batches[key]["col"].append(col)


func flush(parent: Node3D) -> void:
	for key in _batches:
		var b: Dictionary = _batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = b["mesh"]
		var xfs: Array = b["xf"]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_color(i, b["col"][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = b["mat"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
	_batches.clear()


static func _xf(pos: Vector3, scale: Vector3, yaw := 0.0, tilt := Vector3.ZERO) -> Transform3D:
	var b := Basis(Vector3.UP, yaw)
	if tilt != Vector3.ZERO:
		b = b * Basis.from_euler(tilt)
	return Transform3D(b * Basis.from_scale(scale), pos)


# ---------------------------------------------------------------- растительность

func pine(p: Vector3, h: float, snowy := false) -> void:
	var green := Color(0.42, 0.62, 0.42).darkened(rng.randf_range(0.0, 0.25))
	add("cyl", "bark", _xf(p + Vector3(0, h * 0.15, 0), Vector3(0.22, h * 0.3, 0.22)), Color.WHITE)
	var tiers := 3
	for k in tiers:
		var f := float(k) / tiers
		var w := h * (0.36 - f * 0.1)
		var th := h * 0.42
		var y := h * (0.25 + f * 0.24) + th * 0.5
		add("cone", "foliage", _xf(p + Vector3(0, y, 0), Vector3(w, th, w), rng.randf() * TAU), green)
		if snowy:
			add("cone", "foliage", _xf(p + Vector3(0, y + th * 0.18, 0), Vector3(w * 0.72, th * 0.66, w * 0.72)), Color(0.97, 0.98, 1.0))


func broadleaf(p: Vector3, h: float, autumn := false) -> void:
	var green := Color(0.5, 0.7, 0.38).darkened(rng.randf_range(0.0, 0.3))
	if autumn and rng.randf() < 0.4:
		green = Color(0.85, 0.6, 0.25).darkened(rng.randf_range(0.0, 0.2))
	add("cyl_taper", "bark", _xf(p + Vector3(0, h * 0.25, 0), Vector3(0.25, h * 0.5, 0.25)), Color.WHITE)
	var r := h * 0.32
	for k in 3:
		var off := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.3), rng.randf_range(-0.5, 0.5)) * r
		var s := r * rng.randf_range(1.5, 2.1)
		add("sphere", "foliage", _xf(p + Vector3(0, h * 0.62, 0) + off, Vector3(s, s * 0.85, s), rng.randf() * TAU), green)


func bush(p: Vector3, s: float, col: Color) -> void:
	add("sphere", "foliage", _xf(p + Vector3(0, s * 0.3, 0), Vector3(s * 1.4, s * 0.8, s * 1.2), rng.randf() * TAU), col)


func rock(p: Vector3, s: float) -> void:
	add("rock", "rock", _xf(p + Vector3(0, s * 0.15, 0), Vector3(s * rng.randf_range(0.8, 1.4), s * rng.randf_range(0.5, 0.9), s), rng.randf() * TAU,
		Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))), Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.3)))


func tuft(p: Vector3, col: Color) -> void:
	for k in 3:
		var o := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var h := rng.randf_range(0.35, 0.7)
		add("tuft", "foliage", _xf(p + o + Vector3(0, h * 0.5, 0), Vector3(0.12, h, 0.12), 0.0,
			Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))), col)


func cactus(p: Vector3, h: float) -> void:
	var col := Color(0.4, 0.6, 0.35).darkened(rng.randf_range(0.0, 0.2))
	add("cyl", "foliage", _xf(p + Vector3(0, h * 0.5, 0), Vector3(0.32, h, 0.32)), col)
	for side: float in [-1.0, 1.0]:
		if rng.randf() < 0.7:
			var ay := h * rng.randf_range(0.35, 0.6)
			var yaw := rng.randf() * TAU
			var dir := Vector3(cos(yaw), 0, sin(yaw)) * side
			add("cyl", "foliage", Transform3D(Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(0.18, 0.9, 0.18)), p + Vector3(0, ay, 0) + dir * 0.45), col)
			add("cyl", "foliage", _xf(p + Vector3(0, ay + 0.6, 0) + dir * 0.9, Vector3(0.2, 1.3, 0.2)), col)


func palm(p: Vector3, h: float) -> void:
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
	var segs := 4
	var top := p
	for k in segs:
		var y0 := h * k / segs
		var base := p + Vector3(lean.x * y0 * y0 * 0.2, y0, lean.z * y0 * y0 * 0.2)
		add("cyl_taper", "bark", _xf(base + Vector3(0, h / segs * 0.5, 0), Vector3(0.2, h / segs * 1.05, 0.2), 0.0, Vector3(lean.z * 1.5, 0, -lean.x * 1.5)), Color(0.9, 0.85, 0.75))
		top = base + Vector3(0, h / segs, 0)
	for k in 7:
		var yaw := TAU * k / 7.0 + rng.randf() * 0.4
		var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.45), top + Vector3(sin(yaw) * 1.1, -0.3, cos(yaw) * 1.1))
		add("leaf", "foliage", xf, Color(0.35, 0.6, 0.28).darkened(rng.randf_range(0.0, 0.2)))


# ---------------------------------------------------------------- постройки

func _windows(c: Vector3, yaw: float, w: float, d: float, floors: int, lit_chance: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	for f in floors:
		var y := 1.5 + f * 2.8
		for side: float in [-1.0, 1.0]:
			var count := maxi(1, int(w / 2.8))
			for i in count:
				var x := -w * 0.5 + (i + 0.5) * w / count
				var pos := c + b * Vector3(x, y, side * (d * 0.5 + 0.03))
				var key := "window_lit" if night and rng.randf() < lit_chance else "glass"
				add("box", key, Transform3D(b * Basis.from_scale(Vector3(1.0, 1.2, 0.08)), pos))


func hut(c: Vector3, yaw: float, snowy := false) -> void:
	var w := rng.randf_range(4.0, 6.0)
	var d := rng.randf_range(3.5, 5.0)
	var h := rng.randf_range(2.4, 3.0)
	add("box", "wood", _xf(c + Vector3(0, h * 0.5, 0), Vector3(w, h, d), yaw), Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.3)))
	var roof_col := Color(0.45, 0.32, 0.22) if not snowy else Color(0.97, 0.98, 1.0)
	add("prism", "roof" if not snowy else "plaster", _xf(c + Vector3(0, h + 0.8, 0), Vector3(d + 0.8, 1.6, w + 0.8), yaw + PI * 0.5), roof_col)
	var b := Basis(Vector3.UP, yaw)
	add("box", "dark", Transform3D(b * Basis.from_scale(Vector3(1.0, 1.9, 0.1)), c + b * Vector3(0, 0.95, d * 0.5 + 0.03)))
	_windows(c, yaw, w * 0.6, d, 1, 0.6)
	_occupied.append([c, maxf(w, d)])


func house(c: Vector3, yaw: float) -> void:
	var w := rng.randf_range(7.0, 11.0)
	var d := rng.randf_range(6.0, 8.0)
	var floors := 1 if rng.randf() < 0.6 else 2
	var h := floors * 2.9 + 0.3
	var wall: Color = [Color(0.95, 0.9, 0.8), Color(0.85, 0.9, 0.95), Color(0.95, 0.85, 0.75), Color(0.9, 0.95, 0.85), Color(1, 1, 1)][rng.randi() % 5]
	add("box", "plaster", _xf(c + Vector3(0, h * 0.5, 0), Vector3(w, h, d), yaw), wall)
	var roof: Color = [Color(0.75, 0.3, 0.22), Color(0.4, 0.42, 0.48), Color(0.5, 0.33, 0.25)][rng.randi() % 3]
	add("prism", "roof", _xf(c + Vector3(0, h + 1.3, 0), Vector3(d + 1.0, 2.6, w + 1.0), yaw + PI * 0.5), roof)
	var b := Basis(Vector3.UP, yaw)
	add("box", "plaster", Transform3D(b * Basis.from_scale(Vector3(0.7, 2.2, 0.7)), c + b * Vector3(w * 0.25, h + 1.8, 0)), Color(0.6, 0.35, 0.3))
	add("box", "dark", Transform3D(b * Basis.from_scale(Vector3(1.1, 2.1, 0.1)), c + b * Vector3(-w * 0.2, 1.05, d * 0.5 + 0.04)))
	_windows(c, yaw, w, d, floors, 0.5)
	_occupied.append([c, maxf(w, d)])


func adobe(c: Vector3, yaw: float) -> void:
	var w := rng.randf_range(6.0, 10.0)
	var d := rng.randf_range(5.0, 8.0)
	var h := rng.randf_range(3.0, 5.5)
	var col := Color(0.92, 0.78, 0.58).darkened(rng.randf_range(0.0, 0.15))
	add("box", "plaster", _xf(c + Vector3(0, h * 0.5, 0), Vector3(w, h, d), yaw), col)
	add("box", "plaster", _xf(c + Vector3(0, h + 0.25, 0), Vector3(w + 0.3, 0.5, d + 0.3), yaw), col.darkened(0.08))
	var b := Basis(Vector3.UP, yaw)
	add("box", "dark", Transform3D(b * Basis.from_scale(Vector3(1.0, 2.0, 0.1)), c + b * Vector3(0, 1.0, d * 0.5 + 0.04)))
	for k in 3:
		add("cyl", "wood", Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.1, 0.8, 0.1)), c + b * Vector3(-w * 0.3 + k * w * 0.3, h - 0.4, d * 0.5 + 0.35)))
	_windows(c, yaw, w * 0.7, d, 1, 0.5)
	_occupied.append([c, maxf(w, d)])


func tower(c: Vector3, yaw: float) -> void:
	var w := rng.randf_range(16, 30)
	var d := rng.randf_range(16, 30)
	var h := rng.randf_range(22, 110)
	var col := Color.from_hsv(rng.randf_range(0.55, 0.65), 0.1, rng.randf_range(0.6, 1.0))
	add("box", "facade_night" if night else "facade", _xf(c + Vector3(0, h * 0.5, 0), Vector3(w, h, d), yaw), col)
	# крыша: техническая надстройка
	add("box", "plaster", _xf(c + Vector3(0, h + 1.5, 0), Vector3(w * 0.3, 3.0, d * 0.3), yaw), Color(0.6, 0.6, 0.62))
	_occupied.append([c, maxf(w, d) * 0.75])


# ---------------------------------------------------------------- расстановка

func _rand_point(ext: float) -> Vector3:
	var center := track.bbox.get_center()
	return Vector3(center.x + rng.randf_range(-ext, ext), 0, center.y + rng.randf_range(-ext, ext))


func _ok(p: Vector3, min_d: float, max_d := 1e9) -> bool:
	if track.theme.get("water", false) and p.z > track.bbox.end.y + 110.0:
		return false
	if track.is_open:
		return not (absf(p.x) < track.half_size + 12.0 and absf(p.z) < track.half_size + 12.0) and (max_d > 1e8 or absf(p.x) < track.half_size + max_d)
	var d := dist_to_track(p, minf(max_d, 240.0) + CELL)
	return d > min_d and d < max_d


func build(parent: Node3D) -> void:
	var kind: String = track.theme["scenery"]
	var wall := track.wall_dist
	var ext := maxf(track.bbox.size.x, track.bbox.size.y) * 0.5 + 340.0
	var grass_col: Color = {"pines": Color(0.55, 0.75, 0.35), "cactus": Color(0.75, 0.68, 0.4),
		"snow_pines": Color(0.9, 0.93, 0.97), "palms": Color(0.55, 0.72, 0.35), "buildings": Color(0.45, 0.6, 0.35)}.get(kind, Color(0.55, 0.75, 0.35))

	# поселения: группы домов недалеко от трассы
	var villages := 7 if kind != "buildings" else 0
	for v in villages:
		var vc := Vector3.ZERO
		var found := false
		for tries in 60:
			vc = _rand_point(ext * 0.8)
			if _ok(vc, wall + 45.0, 200.0):
				found = true
				break
		if not found:
			continue
		for k in rng.randi_range(3, 6):
			var p := vc + Vector3(rng.randf_range(-35, 35), 0, rng.randf_range(-35, 35))
			if not _ok(p, wall + 22.0) or not _free_spot(p, 9.0):
				continue
			var yaw := atan2(vc.x - p.x, vc.z - p.z) + rng.randf_range(-0.3, 0.3)
			match kind:
				"cactus":
					adobe(p, yaw)
				"snow_pines":
					hut(p, yaw, true)
				"palms":
					if rng.randf() < 0.5:
						hut(p, yaw)
					else:
						house(p, yaw)
				_:
					if rng.randf() < 0.45:
						hut(p, yaw)
					else:
						house(p, yaw)

	# город: кварталы высоток
	if kind == "buildings":
		for i in 360:
			var p := _rand_point(ext)
			if _ok(p, wall + 28.0) and _free_spot(p, 14.0):
				tower(p, rng.randf_range(-0.2, 0.2))

	# деревья и крупная растительность
	var trees := 520 if kind != "buildings" else 120
	for i in trees:
		var p := _rand_point(ext)
		if not _ok(p, wall + 7.0) or not _free_spot(p, 3.0):
			continue
		var h := rng.randf_range(7.0, 17.0)
		match kind:
			"cactus":
				if rng.randf() < 0.75:
					cactus(p, rng.randf_range(3.0, 7.0))
				else:
					rock(p, rng.randf_range(2.0, 6.0))
			"snow_pines":
				pine(p, h, true)
			"palms":
				if rng.randf() < 0.6:
					palm(p, rng.randf_range(7.0, 12.0))
				else:
					broadleaf(p, h * 0.8)
			"buildings":
				broadleaf(p, h * 0.7)
			_:
				if rng.randf() < 0.5:
					pine(p, h)
				else:
					broadleaf(p, h, true)

	# кусты, камни и трава у дороги
	for i in 260:
		var p := _rand_point(ext * 0.7)
		if not _ok(p, wall + 4.0, wall + 90.0):
			continue
		if rng.randf() < 0.3 or kind == "cactus" and rng.randf() < 0.6:
			rock(p, rng.randf_range(0.6, 2.2))
		elif kind != "snow_pines":
			bush(p, rng.randf_range(0.8, 2.0), grass_col.darkened(rng.randf_range(0.1, 0.35)))
		else:
			bush(p, rng.randf_range(0.8, 2.0), Color(0.95, 0.97, 1.0))
	if kind != "snow_pines" and kind != "buildings":
		var n := track.pts.size()
		for i in 1100:
			var k := rng.randi() % n
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var p: Vector3 = track.pts[k] + track.normals[k] * side * rng.randf_range(wall + 1.5, wall + 40.0)
			p.y = 0.0
			if track.is_open or _ok(p, wall + 1.2):
				tuft(p, grass_col.darkened(rng.randf_range(0.0, 0.3)))
	flush(parent)
