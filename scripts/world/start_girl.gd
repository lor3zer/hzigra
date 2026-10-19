class_name StartGirl
extends Node3D

## Девушка с флагами у стартовой линии: на отсчёте поднимает флаги,
## на старте резко опускает их и машет. Собрана из примитивов.

enum State { IDLE, READY, GO, CHEER }

var _state := State.IDLE
var _t := 0.0
var _state_t := 0.0
var _arm_l: Node3D
var _arm_r: Node3D
var _torso: Node3D
var _head: Node3D
var _flags: Array[Node3D] = []


static func _m(c: Color, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scale := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _caps(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 3
	return c


static func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 6
	return s


func build(team: Color) -> void:
	var skin := _m(Color(0.95, 0.78, 0.66), 0.6)
	var hair := _m(Color(0.28, 0.17, 0.1), 0.5)
	var jacket := _m(team, 0.5)
	var white := _m(Color(0.96, 0.96, 0.96), 0.6)
	var pants := _m(Color(0.1, 0.1, 0.12), 0.7)
	# ноги
	for s: float in [-1.0, 1.0]:
		_part(self, _caps(0.075, 0.86), pants, Vector3(s * 0.1, 0.47, 0))
		_part(self, BoxMesh.new(), white, Vector3(s * 0.1, 0.05, -0.04), Vector3(0.12, 0.1, 0.26))
	_torso = Node3D.new()
	_torso.position = Vector3(0, 0.92, 0)
	add_child(_torso)
	_part(_torso, _caps(0.15, 0.5), pants, Vector3(0, 0.05, 0), Vector3(1.1, 1, 0.8))
	_part(_torso, _caps(0.16, 0.62), jacket, Vector3(0, 0.33, 0), Vector3(1.05, 1, 0.75))
	_part(_torso, BoxMesh.new(), white, Vector3(0, 0.33, -0.12), Vector3(0.06, 0.45, 0.02))
	_part(_torso, _caps(0.045, 0.14), skin, Vector3(0, 0.66, 0))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.8, 0)
	_torso.add_child(_head)
	_part(_head, _sph(0.11), skin, Vector3.ZERO, Vector3(0.9, 1.1, 0.95))
	_part(_head, _sph(0.12), hair, Vector3(0, 0.035, 0.03), Vector3(0.95, 1.0, 0.95))
	_part(_head, _caps(0.05, 0.3), hair, Vector3(0, -0.06, 0.13), Vector3.ONE, Vector3(0.5, 0, 0))   # хвостик
	_part(_head, BoxMesh.new(), white, Vector3(0, 0.1, -0.07), Vector3(0.24, 0.04, 0.12))           # козырёк кепки
	# руки с флагами
	var flag_tex := _checker()
	for s: float in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(s * 0.2, 0.55, 0)
		_torso.add_child(arm)
		_part(arm, _caps(0.05, 0.62), jacket, Vector3(0, -0.28, 0))
		_part(arm, _sph(0.05), skin, Vector3(0, -0.6, 0))
		var flag := Node3D.new()
		flag.position = Vector3(0, -0.62, 0)
		arm.add_child(flag)
		_part(flag, Track._cyl(0.012, 0.012, 0.7, 6), white, Vector3(0, -0.2, -0.1), Vector3.ONE, Vector3(PI * 0.5 - 0.3, 0, 0))
		var cloth := QuadMesh.new()
		cloth.size = Vector2(0.55, 0.4)
		var cm := StandardMaterial3D.new()
		cm.albedo_texture = flag_tex
		cm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		cm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_part(flag, cloth, cm, Vector3(s * 0.28, -0.25, -0.45), Vector3.ONE, Vector3(-0.3, PI * 0.5, 0))
		_flags.append(flag)
		if s < 0.0:
			_arm_l = arm
		else:
			_arm_r = arm


static func _checker() -> ImageTexture:
	var img := Image.create(8, 6, false, Image.FORMAT_RGB8)
	for x in 8:
		for y in 6:
			img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color(0.05, 0.05, 0.05))
	return ImageTexture.create_from_image(img)


func ready_pose() -> void:
	_state = State.READY
	_state_t = 0.0


func go() -> void:
	_state = State.GO
	_state_t = 0.0


func _process(dt: float) -> void:
	_t += dt
	_state_t += dt
	var la := 0.15   # поворот рук вокруг X (вперёд-вверх), 0 — вниз
	var ra := 0.15
	var spread := 0.15
	match _state:
		State.IDLE:
			la = 0.15 + sin(_t * 1.3) * 0.05
			ra = la
		State.READY:
			# флаги высоко над головой
			var k := minf(_state_t / 0.6, 1.0)
			la = lerpf(0.15, 3.0, k) + sin(_t * 6.0) * 0.03
			ra = la
			spread = lerpf(0.15, 0.35, k)
		State.GO:
			# резкий взмах вниз
			var k := minf(_state_t / 0.25, 1.0)
			la = lerpf(3.0, 0.9, k)
			ra = la
			spread = 0.5
			if _state_t > 0.6:
				_state = State.CHEER
				_state_t = 0.0
		State.CHEER:
			la = 2.6 + sin(_t * 9.0) * 0.5
			ra = 2.6 + sin(_t * 9.0 + PI) * 0.5
			spread = 0.4
			if _state_t > 3.0:
				_state = State.IDLE
	_arm_l.rotation = Vector3(la, 0, -spread)
	_arm_r.rotation = Vector3(ra, 0, spread)
	_torso.rotation.z = sin(_t * 1.1) * 0.03
	_head.rotation.y = sin(_t * 0.7) * 0.25
