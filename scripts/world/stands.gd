class_name Stands
extends RefCounted

## Трибуны со зрителями: главная у старта и небольшие у опасных поворотов.
## Зрители — MultiMesh с шейдером, каждый подпрыгивает в своём ритме.

const CROWD_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform float jump = 0.14;
void vertex() {
	float id = float(INSTANCE_ID);
	float ph = fract(sin(id * 12.9898) * 43758.5453) * 6.2831;
	float rate = 3.0 + fract(id * 0.37) * 3.5;
	VERTEX.y += max(0.0, sin(TIME * rate + ph)) * jump;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
}
"""

const SHIRTS := [Color(0.9, 0.15, 0.12), Color(0.1, 0.35, 0.85), Color(0.95, 0.8, 0.1), Color(0.95, 0.95, 0.95),
	Color(0.12, 0.12, 0.14), Color(0.1, 0.65, 0.3), Color(1.0, 0.5, 0.1), Color(0.6, 0.2, 0.75)]
const SKIN := [Color(0.96, 0.8, 0.68), Color(0.88, 0.68, 0.52), Color(0.7, 0.5, 0.36), Color(0.45, 0.32, 0.24)]

static var _shader: Shader

var track: Track
var rng: RandomNumberGenerator
var emitters: Array[Vector3] = []
var occupied: Array = []
var _bodies: Array = []
var _body_cols := PackedColorArray()
var _heads: Array = []
var _head_cols := PackedColorArray()


func _init(t: Track) -> void:
	track = t
	rng = t._rng


static func _crowd_mat() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CROWD_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	return m


## Трибуна: локальная ось X направлена от трассы, Z — вдоль трассы.
func build_stand(parent: Node3D, xf: Transform3D, length: float, rows: int, roof: bool) -> void:
	var node := Node3D.new()
	node.transform = xf
	parent.add_child(node)
	var concrete := Track._tex_mat("concrete.jpg", Color(0.85, 0.85, 0.88), Vector3(0.3, 0.3, 0.3), true)
	var seat_cols := [Color(0.2, 0.35, 0.75), Color(0.75, 0.15, 0.15), Color(0.2, 0.6, 0.35)]
	var seat_mat := Track._mat(seat_cols[rng.randi() % seat_cols.size()], 0.7)
	for r in rows:
		var h := 0.6 + r * 0.75
		var step := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.5, h, length)
		step.mesh = bm
		step.material_override = concrete
		step.position = Vector3(r * 1.5, h * 0.5, 0)
		node.add_child(step)
		var seat := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.5, 0.12, length)
		seat.mesh = sm
		seat.material_override = seat_mat
		seat.position = Vector3(r * 1.5 + 0.3, h + 0.06, 0)
		node.add_child(seat)
		var count := int(length / 0.72)
		for i in count:
			if rng.randf() > 0.82:
				continue
			var z := -length * 0.5 + (i + 0.5) * length / count + rng.randf_range(-0.1, 0.1)
			var base: Vector3 = xf * Vector3(r * 1.5 + 0.1, h + 0.55, z)
			var yaw := Track.yaw_from_dir(-(xf.basis.x))
			_bodies.append(Transform3D(Basis(Vector3.UP, yaw), base))
			_body_cols.append(SHIRTS[rng.randi() % SHIRTS.size()])
			_heads.append(Transform3D(Basis(), base + Vector3(0, 0.62, 0)))
			_head_cols.append(SKIN[rng.randi() % SKIN.size()])
	# ограждение с рекламными щитами
	var fence := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.15, 1.2, length)
	fence.mesh = fm
	fence.material_override = Track._mat(Color(0.9, 0.9, 0.92), 0.5)
	fence.position = Vector3(-1.0, 0.6, 0)
	node.add_child(fence)
	var ads := [Color(0.9, 0.1, 0.1), Color(0.1, 0.3, 0.9), Color(1.0, 0.8, 0.0), Color(0.1, 0.1, 0.1)]
	var nads := int(length / 6.0)
	for i in nads:
		var ad := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.05, 0.8, 5.0)
		ad.mesh = am
		ad.material_override = Track._mat(ads[i % ads.size()], 0.6)
		ad.position = Vector3(-1.1, 0.6, -length * 0.5 + (i + 0.5) * length / nads)
		node.add_child(ad)
	if roof:
		var top := 0.6 + rows * 0.75 + 3.0
		var rm := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(rows * 1.5 + 2.0, 0.3, length + 2.0)
		rm.mesh = rb
		rm.material_override = Track._mat(Color(0.92, 0.92, 0.95), 0.5)
		rm.position = Vector3(rows * 0.75 - 0.5, top, 0)
		node.add_child(rm)
		for zz: float in [-length * 0.5, 0.0, length * 0.5]:
			var post := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.3, top, 0.3)
			post.mesh = pm
			post.material_override = concrete
			post.position = Vector3(rows * 1.5, top * 0.5, zz)
			node.add_child(post)
	emitters.append(xf * Vector3(rows * 0.75, 3.0, 0))
	occupied.append([xf.origin, length * 0.6])


## Трибуны у самых крутых поворотов (с внешней стороны).
func build_corner_stands(parent: Node3D, scenery: Scenery, max_count := 5) -> void:
	var n := track.pts.size()
	var cands: Array = []
	for i in n:
		var r := track.radius[i]
		if r > 75.0:
			continue
		var is_min := true
		for k in range(-12, 13):
			if track.radius[(i + k + n) % n] < r:
				is_min = false
				break
		if is_min:
			cands.append(i)
	cands.sort_custom(func(a, b): return track.radius[a] < track.radius[b])
	var placed: Array = []
	for i in cands:
		if placed.size() >= max_count:
			break
		var far := true
		for j in placed:
			var d := absf(track.cum[i] - track.cum[j])
			if minf(d, track.length - d) < 220.0:
				far = false
		if not far or track.cum[i] < 120.0 or track.cum[i] > track.length - 60.0:
			continue
		var t0 := track.tangents[(i - 5 + n) % n]
		var t1 := track.tangents[(i + 5) % n]
		var nrm := track.normals[i]
		var side_out := -signf((t1 - t0).dot(nrm))
		var out_dir := nrm * side_out
		var pos := track.pts[i] + out_dir * (track.wall_dist + 4.0)
		var length := 26.0
		var ok := scenery.dist_to_track(pos, 120.0) > track.wall_dist + 2.5
		var ends := [pos + track.tangents[i] * length * 0.5, pos - track.tangents[i] * length * 0.5]
		for e in ends:
			if scenery.dist_to_track(e, 120.0) < track.wall_dist + 2.0:
				ok = false
		if not ok:
			continue
		var x := out_dir.normalized()
		var z := x.cross(Vector3.UP).normalized()
		build_stand(parent, Transform3D(Basis(x, Vector3.UP, z), pos), length, 4, false)
		placed.append(i)


func flush(parent: Node3D) -> void:
	if _bodies.is_empty():
		return
	var body := CapsuleMesh.new()
	body.radius = 0.2
	body.height = 0.95
	body.radial_segments = 6
	body.rings = 2
	var head := SphereMesh.new()
	head.radius = 0.12
	head.height = 0.24
	head.radial_segments = 6
	head.rings = 4
	for pair in [[body, _bodies, _body_cols], [head, _heads, _head_cols]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = pair[0]
		var xfs: Array = pair[1]
		var cols: PackedColorArray = pair[2]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _crowd_mat()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
