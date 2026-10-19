class_name CarModel
extends Node3D

## Низкополигональная модель машины, собранная из примитивов.
## Машина смотрит в сторону -Z, начало координат — центр на уровне земли.

const CLEARANCE := 0.14
const WHEEL_R := 0.34

var body: Node3D
var wheels: Array[Node3D] = []        # узлы вращения колёс
var steer_pivots: Array[Node3D] = []  # передние оси
var flame: MeshInstance3D
var brake_lights: StandardMaterial3D
var _spin := 0.0
var _roll := 0.0
var _pitch := 0.0


static func frustum(bw: float, bl: float, tw: float, tl: float, h: float, top_z := 0.0) -> ArrayMesh:
	var b := [Vector3(-bw / 2, 0, -bl / 2), Vector3(bw / 2, 0, -bl / 2), Vector3(bw / 2, 0, bl / 2), Vector3(-bw / 2, 0, bl / 2)]
	var t := [Vector3(-tw / 2, h, -tl / 2 + top_z), Vector3(tw / 2, h, -tl / 2 + top_z), Vector3(tw / 2, h, tl / 2 + top_z), Vector3(-tw / 2, h, tl / 2 + top_z)]
	var faces := [
		[t[0], t[1], t[2], t[3]], [b[3], b[2], b[1], b[0]],
		[b[0], b[1], t[1], t[0]], [b[1], b[2], t[2], t[1]],
		[b[2], b[3], t[3], t[2]], [b[3], b[0], t[0], t[3]],
	]
	var center := Vector3(0, h * 0.5, top_z * 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var n: Vector3 = (f[1] - f[0]).cross(f[2] - f[0])
		if n.length_squared() < 1e-8:
			n = (f[2] - f[1]).cross(f[3] - f[1])
		n = n.normalized()
		var fc: Vector3 = (f[0] + f[1] + f[2] + f[3]) * 0.25
		if n.dot(fc - center) < 0.0:
			n = -n
		st.set_normal(n)
		Track.quad(st, f[0], f[1], f[2], f[3], n)
	return st.commit()


static func _m(color: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _glow(color: Color, energy := 2.5) -> StandardMaterial3D:
	var m := _m(color)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func build(def: Dictionary, paint_index: int) -> void:
	for c in get_children():
		c.queue_free()
	wheels.clear()
	steer_pivots.clear()

	var L: float = def["len"]
	var W: float = def["wid"]
	var H: float = def["hgt"]
	var cab: float = def["cabin"]
	var cab_off: float = def["cab_off"]
	var paint := _m(CarDB.paint_color(paint_index), 0.22, 0.55)
	var glass := _m(Color(0.1, 0.13, 0.19), 0.05, 0.7)
	var dark := _m(Color(0.06, 0.06, 0.07), 0.8)
	var hyper: bool = def["class"] == "hyper"

	body = Node3D.new()
	add_child(body)

	var low_h := H * 0.44
	# нижняя часть кузова (длинный капот + корма)
	_part(body, frustum(W, L, W * 0.93, L * 0.88, low_h, 0.04 * L), paint, Vector3(0, CLEARANCE, 0))
	# передний "клин"
	_part(body, frustum(W * 0.96, 0.6, W * 0.9, 0.2, low_h * 0.55, 0.2), paint, Vector3(0, CLEARANCE, -L * 0.5 - 0.15))
	# сплиттер и диффузор
	_part(body, _box(Vector3(W * 0.98, 0.06, 0.5)), dark, Vector3(0, CLEARANCE + 0.02, -L * 0.5 - 0.1))
	_part(body, _box(Vector3(W * 0.9, 0.12, 0.35)), dark, Vector3(0, CLEARANCE + 0.08, L * 0.5 - 0.1))
	# кабина (стекло) и крыша
	var cab_len := L * cab
	var cab_h := H * 0.36 * (0.85 if hyper else 1.0)
	var cab_y := CLEARANCE + low_h
	var cab_z := cab_off * L
	_part(body, frustum(W * 0.8, cab_len, W * 0.6, cab_len * 0.48, cab_h, cab_len * 0.12), glass, Vector3(0, cab_y, cab_z))
	_part(body, _box(Vector3(W * 0.58, 0.04, cab_len * 0.44)), paint, Vector3(0, cab_y + cab_h, cab_z + cab_len * 0.12))
	# боковые воздухозаборники у гиперкаров
	if hyper:
		for s: float in [-1.0, 1.0]:
			_part(body, _box(Vector3(0.06, low_h * 0.5, L * 0.18)), dark, Vector3(s * W * 0.47, CLEARANCE + low_h * 0.55, L * 0.08))

	# фары и фонари
	var head := _glow(Color(1.0, 0.98, 0.9), 2.0)
	brake_lights = _glow(Color(1.0, 0.05, 0.05), 1.0)
	for s: float in [-1.0, 1.0]:
		_part(body, _box(Vector3(W * 0.22, 0.08, 0.06)), head, Vector3(s * W * 0.32, CLEARANCE + low_h * 0.72, -L * 0.5 + 0.02))
	if hyper:
		_part(body, _box(Vector3(W * 0.85, 0.06, 0.05)), brake_lights, Vector3(0, CLEARANCE + low_h * 0.8, L * 0.47))
	else:
		for s: float in [-1.0, 1.0]:
			_part(body, _box(Vector3(W * 0.24, 0.1, 0.05)), brake_lights, Vector3(s * W * 0.33, CLEARANCE + low_h * 0.78, L * 0.47))

	# антикрыло
	var sp: int = def["spoiler"]
	if sp == 1:
		_part(body, frustum(W * 0.9, 0.18, W * 0.9, 0.05, 0.1, 0.06), paint, Vector3(0, CLEARANCE + low_h, L * 0.42))
	elif sp == 2:
		var wing_y := CLEARANCE + low_h + 0.38
		_part(body, _box(Vector3(W * 0.98, 0.05, 0.38)), dark, Vector3(0, wing_y, L * 0.42))
		for s: float in [-1.0, 1.0]:
			_part(body, _box(Vector3(0.05, 0.38, 0.12)), dark, Vector3(s * W * 0.3, wing_y - 0.19, L * 0.42))
			_part(body, _box(Vector3(0.04, 0.16, 0.42)), paint, Vector3(s * W * 0.49, wing_y + 0.02, L * 0.42))

	# пламя нитро
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.14
	cone.height = 0.9
	cone.radial_segments = 8
	flame = _part(body, cone, _glow(Color(0.3, 0.6, 1.0), 4.0), Vector3(0, CLEARANCE + 0.22, L * 0.5 + 0.45))
	flame.rotation_degrees.x = -90.0
	flame.visible = false

	# колёса
	var tire := CylinderMesh.new()
	tire.top_radius = WHEEL_R
	tire.bottom_radius = WHEEL_R
	tire.height = 0.28
	tire.radial_segments = 14
	tire.rings = 1
	var rim := CylinderMesh.new()
	rim.top_radius = WHEEL_R * 0.62
	rim.bottom_radius = WHEEL_R * 0.62
	rim.height = 0.3
	rim.radial_segments = 6
	rim.rings = 1
	var rim_mat := _m(Color(0.75, 0.76, 0.78), 0.3, 0.8)
	for zs: float in [-1.0, 1.0]:
		for xs: float in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(xs * (W * 0.5 - 0.15), WHEEL_R, zs * L * 0.31)
			add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			var t := _part(spin, tire, dark, Vector3.ZERO)
			t.rotation_degrees.z = 90.0
			var r := _part(spin, rim, rim_mat, Vector3.ZERO)
			r.rotation_degrees.z = 90.0
			wheels.append(spin)
			if zs < 0.0:
				steer_pivots.append(pivot)


## Анимация: вращение колёс, поворот передних, крен и клевок кузова.
func animate(dt: float, speed: float, steer: float, lat_acc: float, lon_acc: float, braking: bool, nitro: bool) -> void:
	_spin = fmod(_spin - speed / WHEEL_R * dt, TAU)
	for w in wheels:
		w.rotation.x = _spin
	for p in steer_pivots:
		p.rotation.y = -steer * 0.45
	_roll = lerpf(_roll, clampf(lat_acc * 0.006, -0.06, 0.06), 1.0 - exp(-6.0 * dt))
	_pitch = lerpf(_pitch, clampf(-lon_acc * 0.004, -0.04, 0.04), 1.0 - exp(-6.0 * dt))
	if body:
		body.rotation = Vector3(_pitch, 0.0, _roll)
	if brake_lights:
		brake_lights.emission_energy_multiplier = 4.0 if braking else 1.0
	if flame:
		flame.visible = nitro
		if nitro:
			flame.scale = Vector3.ONE * randf_range(0.8, 1.25)
