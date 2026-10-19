class_name CarModel
extends Node3D

## Модель машины. Кузов строится как поверхность из поперечных сечений
## (loft) по профилям из стиля: линия плеча, ширина, остекление, арки колёс.
## Стиль задаёт силуэт (хэтчбек, маслкар, GT, среднемоторный, родстер...),
## детали (фары, фонари, выхлоп, антикрыло, диски) добавляются отдельно.
## Машина смотрит в -Z, начало координат — центр на уровне земли.

const SECTIONS := 44

## Профили: [t, значение], t = 0 — нос, 1 — корма.
## belt — высота линии плеча (доля H), width — полуширина (доля W/2),
## cabin — [начало лобового, конец лобового, конец крыши, конец заднего стекла],
## gh_w / gh_top — ширина остекления у основания / у крыши (доля ширины).
const STYLES := {
	"hatch": {"axles": [0.17, 0.83],
		"belt": [[0, .40], [.05, .50], [.17, .58], [.3, .62], [.6, .64], [.85, .66], [.97, .62], [1, .52]],
		"width": [[0, .82], [.06, .94], [.17, 1], [.5, .96], [.83, 1], [.95, .95], [1, .86]],
		"cabin": [.29, .43, .82, .97], "roof": 1.0, "gh_w": .88, "gh_top": .72, "hood_dip": .02,
		"head": "slim", "tail": "split", "exhaust": "center", "wing": 4},
	"muscle": {"axles": [0.2, 0.8],
		"belt": [[0, .50], [.04, .56], [.2, .60], [.38, .62], [.62, .63], [.8, .64], [.96, .64], [1, .58]],
		"width": [[0, .9], [.04, .97], [.2, 1], [.5, .97], [.8, 1], [.96, .98], [1, .92]],
		"cabin": [.38, .52, .68, .81], "roof": 1.0, "gh_w": .86, "gh_top": .7, "hood_dip": .0,
		"head": "quad", "tail": "bar", "exhaust": "quad", "wing": 1, "scoop": "hood"},
	"gt": {"axles": [0.19, 0.79],
		"belt": [[0, .42], [.06, .5], [.19, .56], [.36, .58], [.6, .6], [.79, .62], [.95, .58], [1, .5]],
		"width": [[0, .8], [.07, .93], [.19, 1], [.45, .93], [.79, 1], [.95, .92], [1, .82]],
		"cabin": [.37, .5, .64, .9], "roof": 1.0, "gh_w": .84, "gh_top": .62, "hood_dip": .03,
		"head": "slim", "tail": "strip", "exhaust": "quad", "wing": 1},
	"jdm": {"axles": [0.18, 0.8],
		"belt": [[0, .45], [.06, .52], [.2, .58], [.34, .6], [.65, .62], [.85, .64], [1, .6]],
		"width": [[0, .86], [.05, .96], [.18, 1], [.5, .95], [.8, 1], [.97, .96], [1, .9]],
		"cabin": [.33, .46, .66, .8], "roof": 1.0, "gh_w": .86, "gh_top": .68, "hood_dip": .02,
		"head": "slim", "tail": "round", "exhaust": "dual", "wing": 2},
	"rear911": {"axles": [0.16, 0.78],
		"belt": [[0, .40], [.06, .52], [.16, .62], [.3, .54], [.55, .6], [.78, .67], [.94, .6], [1, .5]],
		"width": [[0, .78], [.06, .9], [.16, .97], [.35, .88], [.6, .93], [.78, 1], [.95, .92], [1, .84]],
		"cabin": [.32, .47, .6, .95], "roof": 1.0, "gh_w": .84, "gh_top": .6, "hood_dip": .04,
		"head": "round", "tail": "bar", "exhaust": "center", "wing": 1},
	"sedan": {"axles": [0.17, 0.8],
		"belt": [[0, .48], [.05, .55], [.25, .6], [.6, .63], [.9, .64], [1, .58]],
		"width": [[0, .86], [.05, .95], [.17, 1], [.5, .97], [.8, 1], [.97, .95], [1, .9]],
		"cabin": [.3, .43, .72, .88], "roof": 1.0, "gh_w": .86, "gh_top": .66, "hood_dip": .02, "doors": 4,
		"head": "slim", "tail": "bar", "exhaust": "none", "wing": 0},
	"mid": {"axles": [0.17, 0.76],
		"belt": [[0, .30], [.05, .40], [.17, .5], [.3, .46], [.42, .52], [.6, .6], [.76, .66], [.92, .62], [1, .56]],
		"width": [[0, .78], [.06, .9], [.17, .97], [.42, .9], [.6, .95], [.76, 1], [.94, .95], [1, .88]],
		"cabin": [.3, .45, .56, .86], "roof": 1.0, "gh_w": .78, "gh_top": .55, "hood_dip": .03, "intake": true,
		"head": "slim", "tail": "strip", "exhaust": "center", "wing": 1},
	"roadster": {"axles": [0.18, 0.8],
		"belt": [[0, .42], [.06, .52], [.18, .6], [.35, .6], [.7, .64], [.85, .66], [1, .58]],
		"width": [[0, .8], [.07, .93], [.18, 1], [.45, .93], [.8, 1], [.95, .92], [1, .84]],
		"cabin": [.4, .48, .48, .48], "roof": .9, "gh_w": .84, "gh_top": .7, "hood_dip": .02, "open": true,
		"head": "round", "tail": "round", "exhaust": "dual", "wing": 0},
	"wedge": {"axles": [0.17, 0.75],
		"belt": [[0, .24], [.08, .36], [.17, .46], [.32, .5], [.5, .58], [.75, .68], [1, .68]],
		"width": [[0, .8], [.08, .92], [.17, .98], [.45, .9], [.75, 1], [.97, 1], [1, .95]],
		"cabin": [.28, .47, .58, .8], "roof": 1.0, "gh_w": .76, "gh_top": .5, "hood_dip": .02, "intake": true,
		"head": "slim", "tail": "bar", "exhaust": "twin_center", "wing": 3, "scoop": "roof"},
	"curvy": {"axles": [0.17, 0.77],
		"belt": [[0, .28], [.06, .4], [.17, .54], [.32, .48], [.55, .56], [.77, .66], [.94, .58], [1, .46]],
		"width": [[0, .76], [.06, .9], [.17, .98], [.42, .9], [.77, 1], [.95, .9], [1, .78]],
		"cabin": [.3, .47, .57, .93], "roof": 1.0, "gh_w": .78, "gh_top": .55, "hood_dip": .03, "intake": true,
		"head": "slim", "tail": "strip", "exhaust": "center", "wing": 1},
	"longtail": {"axles": [0.16, 0.68],
		"belt": [[0, .27], [.06, .38], [.16, .52], [.3, .47], [.5, .55], [.68, .66], [.9, .64], [1, .6]],
		"width": [[0, .76], [.06, .9], [.16, .98], [.4, .9], [.68, 1], [.95, .9], [1, .82]],
		"cabin": [.28, .44, .54, .92], "roof": 1.0, "gh_w": .76, "gh_top": .52, "hood_dip": .03, "intake": true,
		"head": "slim", "tail": "strip", "exhaust": "twin_center", "wing": 1, "fin": true},
	"lmp": {"axles": [0.18, 0.74],
		"belt": [[0, .22], [.08, .35], [.18, .62], [.27, .62], [.36, .42], [.6, .45], [.74, .66], [.86, .66], [1, .62]],
		"width": [[0, .9], [.08, .98], [.18, 1], [.4, .92], [.74, 1], [1, .98]],
		"cabin": [.33, .46, .56, .72], "roof": .98, "gh_w": .5, "gh_top": .36, "hood_dip": .0, "intake": true,
		"head": "slim", "tail": "strip", "exhaust": "center", "wing": 3, "fin": true},
}

const RIM_COLORS := {"silver": Color(0.8, 0.81, 0.84), "black": Color(0.07, 0.07, 0.08),
	"gold": Color(0.82, 0.64, 0.26), "gunmetal": Color(0.3, 0.32, 0.35)}

static var _body_cache := {}
static var _mat_cache := {}

var body: Node3D
var wheels: Array[Node3D] = []
var steer_pivots: Array[Node3D] = []
var flame: MeshInstance3D
var brake_lights: StandardMaterial3D
var _flame_nitro: StandardMaterial3D
var _flame_fire: StandardMaterial3D
var _spin := 0.0
var _roll := 0.0
var _pitch := 0.0
var _backfire := 0.0
var wheel_r := 0.34

# параметры текущей сборки
var _st: Dictionary
var _L := 4.5
var _W := 1.9
var _H := 1.25
var _c := 0.13
var _wr := 0.34
var _tw := 0.27


# ---------------------------------------------------------------- материалы

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


static func shared(key: String) -> StandardMaterial3D:
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: StandardMaterial3D
	match key:
		"glass":
			m = _m(Color(0.07, 0.09, 0.13), 0.04, 0.85)
		"dark":
			m = _m(Color(0.035, 0.035, 0.04), 0.85)
		"trim":
			m = _m(Color(0.08, 0.08, 0.09), 0.35, 0.3)
		"chrome":
			m = _m(Color(0.85, 0.86, 0.9), 0.12, 1.0)
		"tire":
			m = _m(Color(0.06, 0.06, 0.065), 0.92)
		"head":
			m = _glow(Color(1.0, 0.97, 0.88), 2.2)
		"drl":
			m = _glow(Color(0.85, 0.92, 1.0), 3.0)
		"plate":
			m = _m(Color(0.92, 0.92, 0.9), 0.6)
		"interior":
			m = _m(Color(0.12, 0.1, 0.09), 0.8)
		_:
			m = _m(Color.MAGENTA)
	_mat_cache[key] = m
	return m


# ---------------------------------------------------------------- профили

static func _curve(pts: Array, t: float) -> float:
	# кубическая интерполяция Эрмита по точкам [t, v]
	var n := pts.size()
	if t <= pts[0][0]:
		return pts[0][1]
	if t >= pts[n - 1][0]:
		return pts[n - 1][1]
	var k := 0
	while k < n - 2 and t > pts[k + 1][0]:
		k += 1
	var t0: float = pts[k][0]
	var t1: float = pts[k + 1][0]
	var v0: float = pts[k][1]
	var v1: float = pts[k + 1][1]
	var m0 := (v1 - v0) / (t1 - t0) if k == 0 else (v1 - float(pts[k - 1][1])) / (t1 - float(pts[k - 1][0]))
	var m1 := (v1 - v0) / (t1 - t0) if k + 2 >= n else (float(pts[k + 2][1]) - v0) / (float(pts[k + 2][0]) - t0)
	var h := t1 - t0
	var u := (t - t0) / h
	var u2 := u * u
	var u3 := u2 * u
	return (2 * u3 - 3 * u2 + 1) * v0 + (u3 - 2 * u2 + u) * h * m0 + (-2 * u3 + 3 * u2) * v1 + (u3 - u2) * h * m1


func _sec(t: float) -> Dictionary:
	var z := -_L * 0.5 + t * _L
	var belt := _H * _curve(_st["belt"], t)
	var w := _W * 0.5 * minf(_curve(_st["width"], t), 1.0)
	var arch := _c
	for ta in _st["axles"]:
		var dz: float = (t - float(ta)) * _L
		var ra := _wr + 0.07
		if absf(dz) < ra:
			arch = maxf(arch, _wr + sqrt(ra * ra - dz * dz))
	belt = maxf(belt, arch + 0.1)   # крыло над колесом
	var te := 0.06
	var e := 1.0
	if t < te:
		e = sqrt(maxf(0.0, 1.0 - pow(1.0 - t / te, 2)))
	elif t > 1.0 - te:
		e = sqrt(maxf(0.0, 1.0 - pow(1.0 - (1.0 - t) / te, 2)))
	w *= lerpf(0.62, 1.0, e)
	belt = _c + (belt - _c) * lerpf(0.62, 1.0, e)
	arch = minf(arch, belt - 0.06)

	var cab: Array = _st["cabin"]
	var roof_h: float = _H * float(_st["roof"])
	var roof := belt
	var open: bool = _st.get("open", false)
	if t > cab[0] and t < cab[3] + 0.0001:
		if t < cab[1]:
			var u: float = (t - cab[0]) / (cab[1] - cab[0])
			roof = lerpf(belt, roof_h, sin(u * PI * 0.5))
		elif t <= cab[2]:
			var u2: float = (t - cab[1]) / maxf(cab[2] - cab[1], 0.001)
			roof = roof_h - 0.03 * pow(2.0 * u2 - 1.0, 2)
		elif not open:
			var u3: float = (t - cab[2]) / maxf(cab[3] - cab[2], 0.001)
			roof = lerpf(roof_h, belt, 1.0 - cos(u3 * PI * 0.5))
		roof = maxf(roof, belt)
	if open and t > cab[1]:
		roof = belt
	var g := clampf((roof - belt) / 0.08, 0.0, 1.0)
	return {"t": t, "z": z, "belt": belt, "w": w, "arch": arch, "roof": roof, "g": g}


func _half(s: Dictionary) -> Array:
	var w: float = s["w"]
	var belt: float = s["belt"]
	var arch: float = s["arch"]
	var roof: float = s["roof"]
	var g: float = s["g"]
	var c := _c
	var w_in := minf(w * 0.9, _W * 0.5 - _tw - 0.05)
	var ys := maxf(arch + 0.05, c + (belt - c) * 0.45)
	var y5 := maxf(ys + 0.03, belt - 0.07)
	var dip: float = _H * float(_st.get("hood_dip", 0.02))
	var p6 := Vector2(lerpf(w * 0.9, w * float(_st["gh_w"]), g), belt)
	var p7 := Vector2(w * 0.5, belt - dip * 0.6).lerp(Vector2(w * float(_st["gh_top"]), roof), g)
	var p8 := Vector2(0, belt - dip).lerp(Vector2(0, roof + 0.025), g)
	return [Vector2(0, c), Vector2(w_in, c), Vector2(w_in, arch), Vector2(w * 0.97, arch),
		Vector2(w, ys), Vector2(w * 0.985, y5), p6, p7, p8]


# ---------------------------------------------------------------- кузов

const RING := 16
const SMOOTH := [false, false, false, false, true, true, false, false, true, false, false, true, true, false, false, false]
# тип панели между точками кольца k и k+1
const PANEL := ["dark", "dark", "dark", "paint", "paint", "paint", "gh", "roof", "roof", "gh", "paint", "paint", "paint", "dark", "dark", "dark"]


func _ring(s: Dictionary) -> PackedVector3Array:
	var h := _half(s)
	var z: float = s["z"]
	var out := PackedVector3Array()
	for p in h:
		out.append(Vector3(p.x, p.y, z))
	for k in range(7, 0, -1):
		var p: Vector2 = h[k]
		out.append(Vector3(-p.x, p.y, z))
	return out


func _panel_mat(kind: String, t: float, g: float) -> String:
	if kind != "gh" and kind != "roof":
		return kind
	var cab: Array = _st["cabin"]
	var open: bool = _st.get("open", false)
	if g < 0.5:
		if open and kind == "roof" and t > cab[1] and t < cab[1] + 0.2:
			return "interior"
		if open and kind == "gh" and t > cab[1] and t < cab[1] + 0.2:
			return "interior"
		return "paint"
	if kind == "roof":
		if t < cab[1] + 0.005:
			return "glass"
		if t > cab[2] and t < cab[2] + (cab[3] - cab[2]) * 0.75:
			return "glass"
		return "paint"
	# боковое остекление со стойками
	var side_end: float = cab[2] + (cab[3] - cab[2]) * 0.5
	if t < cab[1] - 0.01 or t > side_end:
		return "paint"
	var b_pillar: float = lerpf(cab[1], side_end, 0.6 if int(_st.get("doors", 2)) == 2 else 0.45)
	if absf(t - b_pillar) < 0.012:
		return "trim"
	if int(_st.get("doors", 2)) == 4 and absf(t - lerpf(cab[1], side_end, 0.85)) < 0.01:
		return "trim"
	return "glass"


func _build_body() -> Dictionary:
	var secs: Array = []
	var rings: Array = []
	for i in SECTIONS:
		var t := 0.5 - 0.5 * cos(PI * float(i) / (SECTIONS - 1))
		var s := _sec(t)
		secs.append(s)
		rings.append(_ring(s))

	# нормали граней
	var qn: Array = []
	var sign := 1.0
	for i in SECTIONS - 1:
		var row: Array = []
		for k in RING:
			var k1 := (k + 1) % RING
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][k1]
			var d: Vector3 = rings[i + 1][k]
			var c: Vector3 = rings[i + 1][k1]
			var n := (b - a).cross(d - a) + (c - b).cross(c - d)
			row.append(n.normalized() if n.length_squared() > 1e-12 else Vector3.ZERO)
		qn.append(row)
	# ориентация наружу: боковая панель справа должна смотреть в +X
	var mid := int(SECTIONS / 2)
	if qn[mid][4].x < 0.0:
		sign = -1.0

	var tools := {}
	for i in SECTIONS - 1:
		var tm: float = (float(secs[i]["t"]) + float(secs[i + 1]["t"])) * 0.5
		var gm: float = (float(secs[i]["g"]) + float(secs[i + 1]["g"])) * 0.5
		for k in RING:
			var fn: Vector3 = qn[i][k] * sign
			if fn == Vector3.ZERO:
				continue
			var mat := _panel_mat(PANEL[k], tm, gm)
			var k1 := (k + 1) % RING
			var corners := [[i, k], [i, k1], [i + 1, k1], [i + 1, k]]
			var vs: Array = []
			var ns: Array = []
			for cnr in corners:
				var ii: int = cnr[0]
				var j: int = cnr[1]
				vs.append(rings[ii][j])
				var nsum := Vector3.ZERO
				for sec in [ii - 1, ii]:
					if sec < 0 or sec >= SECTIONS - 1:
						continue
					nsum += qn[sec][k]
					if SMOOTH[j]:
						var other := (k - 1 + RING) % RING if j == k else (k + 1) % RING
						nsum += qn[sec][other]
				nsum *= sign
				ns.append(nsum.normalized() if nsum.length_squared() > 1e-12 else fn)
			_emit_quad(tools, mat, vs, ns, fn)

	# торцы: нос и корма
	for end in [0, SECTIONS - 1]:
		var ring: PackedVector3Array = rings[end]
		var center := Vector3.ZERO
		for p in ring:
			center += p
		center /= ring.size()
		var fn := Vector3(0, 0, -1) if end == 0 else Vector3(0, 0, 1)
		for k in RING:
			var a := ring[k]
			var b := ring[(k + 1) % RING]
			_emit_tri(tools, "paint" if PANEL[k] != "dark" else "dark", [center, a, b], [fn, fn, fn], fn)

	var mesh := ArrayMesh.new()
	var slots := {}
	for key in ["paint", "glass", "dark", "trim", "interior"]:
		if tools.has(key):
			var st: SurfaceTool = tools[key]
			st.commit(mesh)
			slots[key] = mesh.get_surface_count() - 1
			if key != "paint":
				mesh.surface_set_material(slots[key], shared(key))
	return {"mesh": mesh, "slots": slots}


func _tool(tools: Dictionary, key: String) -> SurfaceTool:
	if not tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = st
	return tools[key]


func _emit_quad(tools: Dictionary, key: String, vs: Array, ns: Array, fn: Vector3) -> void:
	_emit_tri(tools, key, [vs[0], vs[1], vs[2]], [ns[0], ns[1], ns[2]], fn)
	_emit_tri(tools, key, [vs[0], vs[2], vs[3]], [ns[0], ns[2], ns[3]], fn)


func _emit_tri(tools: Dictionary, key: String, vs: Array, ns: Array, fn: Vector3) -> void:
	var st := _tool(tools, key)
	var order := [0, 1, 2]
	# лицевые грани в Godot — по часовой стрелке, если смотреть снаружи
	if (vs[1] - vs[0]).cross(vs[2] - vs[0]).dot(fn) > 0.0:
		order = [0, 2, 1]
	for o in order:
		st.set_normal(ns[o])
		st.add_vertex(vs[o])


## Точка на поверхности кузова: t — вдоль машины, u — по половине кольца (0..8).
func _surf(t: float, u: float, side: float) -> Vector3:
	var h := _half(_sec(t))
	var i := clampi(int(floor(u)), 0, 7)
	var p: Vector2 = (h[i] as Vector2).lerp(h[i + 1], u - i)
	return Vector3(p.x * side, p.y, -_L * 0.5 + t * _L)


## Накладка на поверхность кузова (фары, фонари): повторяет форму кузова.
func _patch(t0: float, t1: float, u0: float, u1: float, side: float, lift := 0.012) -> ArrayMesh:
	var nt := 4
	var nu := 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for a in nt + 1:
		var row: Array = []
		for b in nu + 1:
			row.append(_surf(lerpf(t0, t1, float(a) / nt), lerpf(u0, u1, float(b) / nu), side))
		grid.append(row)
	var center := Vector3(0, (_c + _H * 0.5) * 0.5, -_L * 0.5 + (t0 + t1) * 0.5 * _L)
	# общий вектор подъёма для всей накладки, чтобы не было щелей
	var g0: Vector3 = grid[0][0]
	var g1: Vector3 = grid[0][nu]
	var g2: Vector3 = grid[nt][nu]
	var g3: Vector3 = grid[nt][0]
	var avg := (g1 - g0).cross(g3 - g0) + (g2 - g1).cross(g2 - g3)
	avg = avg.normalized()
	if avg.dot((g0 + g2) * 0.5 - center) < 0.0:
		avg = -avg
	for a in nt:
		for b in nu:
			var p0: Vector3 = grid[a][b]
			var p1: Vector3 = grid[a][b + 1]
			var p2: Vector3 = grid[a + 1][b + 1]
			var p3: Vector3 = grid[a + 1][b]
			var n := (p1 - p0).cross(p3 - p0) + (p2 - p1).cross(p2 - p3)
			if n.length_squared() < 1e-12:
				continue
			n = n.normalized()
			if n.dot(avg) < 0.0:
				n = -n
			st.set_normal(n)
			Track.quad(st, p0 + avg * lift, p1 + avg * lift, p2 + avg * lift, p3 + avg * lift, n)
	return st.commit()


# ---------------------------------------------------------------- сборка

func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(r: float, h: float, segs := 16, r_top := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r if r_top < 0.0 else r_top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func style_of(def: Dictionary) -> Dictionary:
	var st: Dictionary = STYLES.get(def.get("style", "gt"), STYLES["gt"]).duplicate(true)
	var look: Dictionary = def.get("look", {})
	for k in look:
		st[k] = look[k]
	return st


func build(def: Dictionary, paint_index: int) -> void:
	for c in get_children():
		c.queue_free()
	wheels.clear()
	steer_pivots.clear()

	_st = style_of(def)
	_L = def["len"]
	_W = def["wid"]
	_H = def["hgt"]
	var hyper: bool = def["class"] == "hyper"
	_c = 0.11 if hyper else 0.13
	_wr = 0.35 if hyper else 0.33
	_tw = 0.3 if hyper else 0.26
	wheel_r = _wr

	var key: String = def["id"]
	if not _body_cache.has(key):
		_body_cache[key] = _build_body()
	var cached: Dictionary = _body_cache[key]

	var paint := _m(CarDB.paint_color(paint_index), 0.18, 0.6)
	body = Node3D.new()
	add_child(body)
	var bmi := MeshInstance3D.new()
	bmi.mesh = cached["mesh"]
	bmi.set_surface_override_material(cached["slots"]["paint"], paint)
	body.add_child(bmi)

	_build_details(paint)
	_build_wheels(def)


func _build_details(paint: StandardMaterial3D) -> void:
	var dark := shared("dark")
	var trim := shared("trim")
	var cab: Array = _st["cabin"]
	var front := _sec(0.0)
	var nose := _sec(0.035)
	var rear := _sec(0.985)
	var tail := _sec(1.0)
	var zf: float = front["z"]
	var zr: float = tail["z"]

	# сплиттер, решётка, диффузор, номер
	_part(body, _box(Vector3(_W * 0.86, 0.04, 0.3)), dark, Vector3(0, _c + 0.02, zf + 0.08))
	var grille_w: float = float(front["w"]) * 1.25
	_part(body, _box(Vector3(grille_w, (float(front["belt"]) - _c) * 0.38, 0.06)), dark,
		Vector3(0, _c + (float(front["belt"]) - _c) * 0.3, zf - 0.005))
	_part(body, _box(Vector3(_W * 0.8, 0.14, 0.4)), dark, Vector3(0, _c + 0.07, zr - 0.12))
	for i in 5:
		_part(body, _box(Vector3(0.03, 0.16, 0.36)), dark, Vector3(-_W * 0.3 + i * _W * 0.15, _c + 0.05, zr - 0.08))
	_part(body, _box(Vector3(0.52, 0.12, 0.02)), shared("plate"), Vector3(0, _c + (float(tail["belt"]) - _c) * 0.45, zr + 0.012))

	# фары — накладки на скруглённых углах носа
	brake_lights = _glow(Color(0.9, 0.02, 0.03), 1.2)
	var head := shared("head")
	for s: float in [-1.0, 1.0]:
		match _st.get("head", "slim"):
			"round":
				var pc := _surf(0.03, 5.2, s)
				var pn := (pc - _surf(0.06, 5.2, s)).normalized()
				var lamp := _part(body, _cyl(0.1, 0.06, 16), head, pc + pn * 0.01)
				lamp.basis = Basis(Quaternion(Vector3.UP, pn))
			"quad":
				_part(body, _patch(0.012, 0.042, 4.3, 5.0, s), head, Vector3.ZERO)
				_part(body, _patch(0.012, 0.042, 5.25, 5.9, s), head, Vector3.ZERO)
			_:
				_part(body, _patch(0.018, 0.075, 5.05, 5.85, s), head, Vector3.ZERO)
				_part(body, _patch(0.012, 0.05, 4.55, 4.75, s, 0.016), shared("drl"), Vector3.ZERO)

	# задние фонари
	var tail_kind: String = _st.get("tail", "bar")
	var tz: float = zr + 0.006
	var ty: float = _c + (float(tail["belt"]) - _c) * 0.75
	for s: float in [-1.0, 1.0]:
		match tail_kind:
			"round":
				for o: float in [0.0, 0.24]:
					_part(body, _cyl(0.075, 0.04, 14), brake_lights, Vector3(s * (float(tail["w"]) * 0.62 - o), ty, tz), Vector3(PI * 0.5, 0, 0))
			"split":
				_part(body, _patch(0.955, 0.995, 4.6, 5.9, s), brake_lights, Vector3.ZERO)
			"strip":
				_part(body, _patch(0.975, 0.997, 5.5, 5.95, s), brake_lights, Vector3.ZERO)
			_:
				_part(body, _patch(0.97, 0.997, 4.9, 5.9, s), brake_lights, Vector3.ZERO)
	if tail_kind == "strip" or tail_kind == "bar":
		_part(body, _box(Vector3(float(tail["w"]) * 1.5, 0.04 if tail_kind == "strip" else 0.07, 0.03)), brake_lights, Vector3(0, ty + 0.03, tz))

	# выхлоп
	var chrome := shared("chrome")
	var ex := _cyl(0.05, 0.22, 10)
	var ey := _c + 0.12
	var tips: Array = []
	match _st.get("exhaust", "dual"):
		"dual":
			tips = [Vector2(-_W * 0.33, ey), Vector2(_W * 0.33, ey)]
		"quad":
			tips = [Vector2(-_W * 0.36, ey), Vector2(-_W * 0.27, ey), Vector2(_W * 0.27, ey), Vector2(_W * 0.36, ey)]
		"center":
			tips = [Vector2(-0.07, ey), Vector2(0.07, ey)]
		"twin_center":
			tips = [Vector2(-0.09, float(tail["belt"]) - 0.16), Vector2(0.09, float(tail["belt"]) - 0.16)]
	for p in tips:
		_part(body, ex, chrome, Vector3(p.x, p.y, zr + 0.02), Vector3(PI * 0.5, 0, 0))
		_part(body, _cyl(0.035, 0.05, 8), dark, Vector3(p.x, p.y, zr + 0.13), Vector3(PI * 0.5, 0, 0))

	# пламя: синее для нитро, оранжевое для выстрелов
	_flame_nitro = _glow(Color(0.35, 0.6, 1.0), 4.0)
	_flame_fire = _glow(Color(1.0, 0.5, 0.1), 5.0)
	var fx: float = tips[0].x if not tips.is_empty() else 0.0
	var fy: float = tips[0].y if not tips.is_empty() else ey
	flame = _part(body, _cyl(0.0, 0.8, 8, 0.12), _flame_nitro, Vector3(fx, fy, zr + 0.5), Vector3(-PI * 0.5, 0, 0))
	flame.visible = false

	# зеркала
	var ms := _sec(float(cab[0]) + 0.03)
	for s: float in [-1.0, 1.0]:
		var mx: float = float(ms["w"]) * float(_st["gh_w"]) + 0.09
		_part(body, _box(Vector3(0.13, 0.085, 0.15)), paint, Vector3(s * mx, float(ms["belt"]) + 0.07, float(ms["z"])))
		_part(body, _box(Vector3(0.12, 0.025, 0.04)), trim, Vector3(s * (mx - 0.07), float(ms["belt"]) + 0.04, float(ms["z"])))

	# воздухозаборники по бокам
	if _st.get("intake", false):
		var si := _sec(float(cab[2]) + 0.03)
		for s: float in [-1.0, 1.0]:
			var y0: float = _c + (float(si["belt"]) - _c) * 0.55
			_part(body, _box(Vector3(0.05, (float(si["belt"]) - _c) * 0.4, _L * 0.12)), dark,
				Vector3(s * float(si["w"]) * 0.99, y0, float(si["z"])), Vector3(0, s * 0.12, 0))

	# воздухозаборник на капоте / крыше
	match _st.get("scoop", ""):
		"hood":
			var sh := _sec(0.24)
			_part(body, CarModel.frustum(_W * 0.3, _L * 0.16, _W * 0.22, _L * 0.12, 0.08, 0.0), paint,
				Vector3(0, float(sh["belt"]) - _H * float(_st.get("hood_dip", 0.0)) - 0.01, float(sh["z"])))
			_part(body, _box(Vector3(_W * 0.2, 0.05, 0.02)), dark, Vector3(0, float(sh["belt"]) + 0.03, float(sh["z"]) - _L * 0.07))
		"roof":
			var sr := _sec(float(cab[2]))
			_part(body, CarModel.frustum(0.36, 0.7, 0.26, 0.5, 0.14, 0.05), paint, Vector3(0, float(sr["roof"]) - 0.02, float(sr["z"]) + 0.3))
			_part(body, _box(Vector3(0.26, 0.09, 0.02)), dark, Vector3(0, float(sr["roof"]) + 0.06, float(sr["z"]) - 0.02))

	# плавник
	if _st.get("fin", false):
		var f0 := _sec(float(cab[2]))
		var f1 := _sec(0.97)
		var fl: float = float(f1["z"]) - float(f0["z"])
		_part(body, CarModel.frustum(0.03, fl, 0.03, fl * 0.7, 0.16, fl * 0.15), paint,
			Vector3(0, float(f0["roof"]) - 0.02 + (float(f1["belt"]) - float(f0["roof"])) * 0.4, (float(f0["z"]) + float(f1["z"])) * 0.5),
			Vector3(-atan2(float(f0["roof"]) - float(f1["belt"]), fl) * 0.9, 0, 0))

	# открытый кокпит: сиденья и дуги
	if _st.get("open", false):
		var sc := _sec(float(cab[1]) + 0.08)
		for s: float in [-1.0, 1.0]:
			_part(body, _box(Vector3(0.45, 0.42, 0.12)), shared("interior"), Vector3(s * 0.32, float(sc["belt"]) + 0.08, float(sc["z"]) + 0.15), Vector3(-0.2, 0, 0))
			_part(body, CarModel.frustum(0.36, 0.5, 0.2, 0.2, 0.16, 0.12), paint, Vector3(s * 0.32, float(sc["belt"]) - 0.02, float(sc["z"]) + 0.55))
		_part(body, _box(Vector3(0.4, 0.04, 0.2)), shared("interior"), Vector3(-0.32, float(sc["belt"]) + 0.12, float(sc["z"]) - 0.45))

	# антикрыло
	var wing: int = int(_st.get("wing", 0))
	var wr := _sec(0.93)
	var deck: float = float(wr["roof"])
	match wing:
		1:
			_part(body, CarModel.frustum(float(wr["w"]) * 1.8, 0.16, float(wr["w"]) * 1.8, 0.05, 0.07, 0.05), paint, Vector3(0, deck - 0.01, float(wr["z"]) + 0.04))
		2, 3:
			var span := _W * (0.98 if wing == 2 else 1.02)
			var h := 0.32 if wing == 2 else 0.42
			var chord := 0.32 if wing == 2 else 0.42
			_part(body, _box(Vector3(span, 0.045, chord)), dark, Vector3(0, deck + h, float(wr["z"])), Vector3(0.12, 0, 0))
			for s: float in [-1.0, 1.0]:
				_part(body, _box(Vector3(0.03, chord * 0.9, chord * 1.15)), paint, Vector3(s * span * 0.5, deck + h + 0.02, float(wr["z"])))
				_part(body, _box(Vector3(0.04, h, 0.1)), dark, Vector3(s * span * 0.28, deck + h * 0.5, float(wr["z"]) + 0.02))
		4:
			var re := _sec(float(cab[2]))
			_part(body, _box(Vector3(float(re["w"]) * 1.4, 0.04, 0.3)), paint, Vector3(0, float(re["roof"]) + 0.01, float(re["z"]) + 0.12), Vector3(0.15, 0, 0))


static var _wheel_cache := {}


func _build_wheels(def: Dictionary) -> void:
	var rim_type: String = def.get("rim", "five")
	var rim_col: Color = RIM_COLORS.get(def.get("rim_color", "silver"), RIM_COLORS["silver"])
	var rim_mat := _m(rim_col, 0.25, 0.85)
	var cal_mat := _m(def.get("caliper", Color(0.8, 0.08, 0.06)), 0.4, 0.2)
	var rim_r := _wr * 0.72
	# шина — тор с эллиптическим профилем, чтобы диск был виден
	var tire_mesh := TorusMesh.new()
	tire_mesh.inner_radius = rim_r * 0.96
	tire_mesh.outer_radius = _wr
	tire_mesh.rings = 24
	tire_mesh.ring_segments = 10
	var tire_scale := _tw / (_wr - rim_r * 0.96)
	var barrel := _cyl(rim_r * 0.98, _tw * 0.86, 22)
	var hub := _cyl(0.06, _tw * 0.96, 8)
	var lip := TorusMesh.new()
	lip.inner_radius = rim_r * 0.9
	lip.outer_radius = rim_r * 1.02
	lip.rings = 22
	lip.ring_segments = 6
	var axles: Array = _st["axles"]
	for ta in axles:
		var z: float = -_L * 0.5 + float(ta) * _L
		for s: float in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(s * (_W * 0.5 - _tw * 0.5 - 0.03), _wr, z)
			add_child(pivot)
			# суппорт не вращается вместе с колесом
			_part(pivot, _box(Vector3(_tw * 0.5, rim_r * 0.55, rim_r * 0.5)), cal_mat, Vector3(-s * 0.02, rim_r * 0.35, -rim_r * 0.35))
			var spin := Node3D.new()
			pivot.add_child(spin)
			_part(spin, tire_mesh, shared("tire"), Vector3.ZERO, Vector3(0, 0, PI * 0.5)).scale = Vector3(1, tire_scale, 1)
			_part(spin, barrel, shared("dark"), Vector3(-s * 0.02, 0, 0), Vector3(0, 0, PI * 0.5))
			var face := s * (_tw * 0.47)
			_part(spin, hub, rim_mat, Vector3.ZERO, Vector3(0, 0, PI * 0.5))
			_part(spin, lip, rim_mat, Vector3(face, 0, 0), Vector3(0, 0, PI * 0.5))
			if rim_type == "turbine":
				_part(spin, _cyl(rim_r * 0.92, 0.02, 22), rim_mat, Vector3(face * 0.97, 0, 0), Vector3(0, 0, PI * 0.5))
			var spokes := 5
			var sw := 0.07
			match rim_type:
				"multi":
					spokes = 10
					sw = 0.035
				"mesh":
					spokes = 14
					sw = 0.022
				"turbine":
					spokes = 8
					sw = 0.04
			var spoke := _box(Vector3(0.03, rim_r * 0.95, sw))
			for k in spokes:
				var a := TAU * k / spokes
				var dir := Vector3(0, cos(a), sin(a))
				var tilt := 0.35 if rim_type == "mesh" and k % 2 == 1 else 0.0
				_part(spin, spoke, rim_mat, Vector3(face * 0.97, 0, 0) + dir * rim_r * 0.48, Vector3(a + tilt, 0, 0))
			wheels.append(spin)
			if float(ta) < 0.5:
				steer_pivots.append(pivot)


## Простой усечённый параллелепипед (для мелких деталей).
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


# ---------------------------------------------------------------- анимация

func backfire() -> void:
	_backfire = 0.07


## Вращение колёс, поворот передних, крен и клевок кузова, пламя.
func animate(dt: float, speed: float, steer: float, lat_acc: float, lon_acc: float, braking: bool, nitro: bool) -> void:
	_spin = fmod(_spin - speed / wheel_r * dt, TAU)
	for w in wheels:
		w.rotation.x = _spin
	for p in steer_pivots:
		p.rotation.y = -steer * 0.45
	_roll = lerpf(_roll, clampf(lat_acc * 0.006, -0.06, 0.06), 1.0 - exp(-6.0 * dt))
	_pitch = lerpf(_pitch, clampf(-lon_acc * 0.004, -0.04, 0.04), 1.0 - exp(-6.0 * dt))
	if body:
		body.rotation = Vector3(_pitch, 0.0, _roll)
	if brake_lights:
		brake_lights.emission_energy_multiplier = 5.0 if braking else 1.2
	if flame:
		_backfire -= dt
		var fire := _backfire > 0.0
		flame.visible = nitro or fire
		if flame.visible:
			flame.material_override = _flame_fire if fire and not nitro else _flame_nitro
			flame.scale = Vector3.ONE * randf_range(0.8, 1.25) * (0.7 if fire and not nitro else 1.0)
