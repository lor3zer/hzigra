class_name CarModel
extends Node3D

## Модель машины по описанию из CarBodies.
## Кузов — поверхность из поперечных сечений (loft): профили вида сбоку
## (порог, линия максимальной ширины, плечо, капот, крыша) и сверху (ширина,
## завал боковин). Фары, решётки, воздухозаборники и фонари — плоские
## «наклейки», спроецированные на кузов спереди, сзади, сбоку или сверху.
## Зеркала, антикрылья, выхлоп, сплиттер — простые призмы.
## Всё статичное сливается в один меш по материалам (несколько draw call'ов
## на машину) и кэшируется по машине и тюнингу.
## Машина смотрит в -Z, начало координат — центр на уровне земли.

const HALF := 12            # точек в половине сечения (P0 — низ по центру, P11 — верх по центру)
const RING := 22            # точек в полном кольце
const SMOOTH_COS := 0.76    # сглаживать нормали между гранями, если угол меньше ~40°
const PART_UV := Vector2(0.5, 0.01)   # место текстуры деталей без швов (для навесных деталей)

## Тюнинг: одинаковый набор для всех машин (0 — заводской вариант).
const TUNING := [
	["wing", "Антикрыло", ["Заводское", "Без крыла", "Спойлер", "GT-крыло", "Большое крыло"]],
	["front", "Передний бампер", ["Заводской", "Сплиттер", "Агрессивный"]],
	["skirts", "Пороги", ["Заводские", "Карбоновые"]],
	["rear", "Задний бампер", ["Заводской", "Диффузор"]],
	["hood", "Капот", ["Заводской", "С жабрами", "Карбоновый"]],
	["rims", "Диски", ["Заводские", "5 спиц", "Многоспицевые", "Сетка", "Турбина"]],
	["rim_color", "Цвет дисков", ["Заводской", "Серебро", "Чёрный", "Золото", "Графит"]],
]
const RIM_TYPES := ["", "five", "multi", "mesh", "turbine"]
const RIM_COLOR_KEYS := ["", "silver", "black", "gold", "gunmetal"]

const RIM_COLORS := {"silver": Color(0.8, 0.81, 0.84), "black": Color(0.07, 0.07, 0.08),
	"gold": Color(0.82, 0.64, 0.26), "gunmetal": Color(0.3, 0.32, 0.35)}

## Спицы дисков: число групп, спиц в группе, ширина у ступицы/обода, развал пары.
const RIMS := {
	"five": {"n": 5, "k": 1, "w0": 0.075, "w1": 0.06, "sp": 0.0},
	"multi": {"n": 10, "k": 1, "w0": 0.034, "w1": 0.03, "sp": 0.0},
	"mesh": {"n": 14, "k": 1, "w0": 0.02, "w1": 0.02, "sp": 0.0, "cross": true},
	"turbine": {"n": 9, "k": 1, "w0": 0.04, "w1": 0.05, "sp": 0.0, "twist": 0.35, "face": true},
	"twin5": {"n": 5, "k": 2, "w0": 0.032, "w1": 0.03, "sp": 0.13},
	"y5": {"n": 5, "k": 2, "w0": 0.05, "w1": 0.028, "sp": 0.2, "y": true},
	"ten": {"n": 10, "k": 1, "w0": 0.03, "w1": 0.026, "sp": 0.0, "twist": 0.12},
	"trident": {"n": 5, "k": 3, "w0": 0.03, "w1": 0.022, "sp": 0.16, "y": true},
}

static var _body_cache := {}
static var _mat_cache := {}
static var _wheel_cache := {}

var body: Node3D
var wheels: Array[Node3D] = []
var steer_pivots: Array[Node3D] = []
var _wheel_side: Array[float] = []
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
var _b: Dictionary          # описание кузова (CarBodies)
var _L := 4.5
var _W := 1.9
var _c := 0.12
var _wr: Array = [0.34, 0.34]
var _tire: Array = [0.26, 0.3]
var _axle_z: Array = [0.0, 0.0]
var _tune: Dictionary = {}
var _tools := {}
var _sec_cache := {}
var _fine_front: Array = []
var _fine_rear: Array = []


func tune_value(key: String) -> int:
	return int(_tune.get(key, 0))


# ---------------------------------------------------------------- материалы

static func _m(color: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


static func _glow(color: Color, energy := 2.5) -> StandardMaterial3D:
	var m := _m(color * 0.5, 0.3)
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	return m


static func shared(key: String) -> StandardMaterial3D:
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: StandardMaterial3D
	match key:
		"glass":
			m = _m(Color(0.035, 0.04, 0.05), 0.05, 0.9)
		"dark":
			m = _m(Color(0.03, 0.03, 0.035), 0.85)
		"trim":
			m = _m(Color(0.025, 0.025, 0.03), 0.22, 0.35)
		"chrome":
			m = _m(Color(0.86, 0.87, 0.9), 0.1, 1.0)
		"tire":
			m = _m(Color(0.75, 0.75, 0.75), 0.92)
			m.albedo_texture = Track.tex("tire.png")
			m.uv1_scale = Vector3(1, 6, 1)
		"head":
			m = _glow(Color(1.0, 0.97, 0.9), 2.2)
			m.albedo_texture = Track.tex("headlight.png")
			m.emission_texture = Track.tex("headlight.png")
		"drl":
			m = _glow(Color(0.85, 0.92, 1.0), 3.0)
		"amber":
			m = _glow(Color(1.0, 0.55, 0.08), 1.2)
		"carbon":
			m = _m(Color(1, 1, 1), 0.3, 0.3)
			m.albedo_texture = Track.tex("carbon.png")
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(6, 6, 6)
		"grille":
			m = _m(Color(1, 1, 1), 0.6, 0.2)
			m.albedo_texture = Track.tex("grille.png")
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(9, 9, 9)
		"plate":
			m = _m(Color(0.92, 0.92, 0.9), 0.6)
		"disc":
			m = _m(Color(0.42, 0.42, 0.44), 0.45, 0.8)
		"interior":
			m = _m(Color(0.12, 0.1, 0.09), 0.8)
		_:
			m = _m(Color.MAGENTA)
	_mat_cache[key] = m
	return m


# ---------------------------------------------------------------- профили

## Монотонный кубический сплайн по точкам [t, v] (без выбросов между точками).
static func _curve(pts: Variant, t: float) -> float:
	if pts is float or pts is int:
		return float(pts)
	var n: int = pts.size()
	if n == 1 or t <= float(pts[0][0]):
		return float(pts[0][1])
	if t >= float(pts[n - 1][0]):
		return float(pts[n - 1][1])
	var k := 0
	while k < n - 2 and t > float(pts[k + 1][0]):
		k += 1
	var t0: float = pts[k][0]
	var t1: float = pts[k + 1][0]
	var v0: float = pts[k][1]
	var v1: float = pts[k + 1][1]
	var h := t1 - t0
	var m0 := _slope(pts, k)
	var m1 := _slope(pts, k + 1)
	var u := (t - t0) / h
	var u2 := u * u
	var u3 := u2 * u
	return (2 * u3 - 3 * u2 + 1) * v0 + (u3 - 2 * u2 + u) * h * m0 + (-2 * u3 + 3 * u2) * v1 + (u3 - u2) * h * m1


static func _slope(pts: Array, i: int) -> float:
	var n := pts.size()
	var dp := 0.0
	var dn := 0.0
	if i > 0:
		dp = (float(pts[i][1]) - float(pts[i - 1][1])) / (float(pts[i][0]) - float(pts[i - 1][0]))
	if i < n - 1:
		dn = (float(pts[i + 1][1]) - float(pts[i][1])) / (float(pts[i + 1][0]) - float(pts[i][0]))
	if i == 0:
		return dn
	if i == n - 1:
		return dp
	if dp * dn <= 0.0:
		return 0.0
	return 2.0 * dp * dn / (dp + dn)


func _cv(key: String, t: float) -> float:
	return _curve(_b[key], t)


## Высота крыши по оси; 0 — вне остекления.
func _roof(t: float) -> float:
	var pts: Array = _b["roof"]
	if t < float(pts[0][0]) or t > float(pts[pts.size() - 1][0]):
		return 0.0
	return _curve(pts, t)


## Поперечное сечение (правая половина): 12 точек от низа по центру до верха по центру.
## P1-P2 — внутренняя стенка колёсной арки, P3 — нижняя кромка боковины,
## P4 — ребро порога, P5 — линия максимальной ширины, P7 — плечо,
## P8..P11 — крышка капота/багажника или остекление и крыша.
func _sec(t: float) -> Dictionary:
	var key := snappedf(t, 0.00001)
	if _sec_cache.has(key):
		return _sec_cache[key]
	var z := -_L * 0.5 + t * _L
	var hw := _W * 0.5
	var w := hw * _cv("w", t)
	var yb := _c + _cv("lo", t)
	var ya := yb
	for i in 2:
		var dz: float = z - float(_axle_z[i])
		var ra: float = float(_wr[i]) + 0.06
		if absf(dz) < ra:
			ya = maxf(ya, float(_wr[i]) + sqrt(ra * ra - dz * dz) - 0.01)
	var y_zh := maxf(_cv("zh", t), ya + 0.05)
	var y_sh := maxf(_cv("sh", t), y_zh + 0.04)
	var y_top := _cv("top", t)
	var ws := w * _cv("tuck", t)
	var y_roof := _roof(t)
	var base := maxf(y_sh, y_top)
	var g := clampf((y_roof - base) / 0.06, 0.0, 1.0)
	g = g * g * (3.0 - 2.0 * g)
	var wi := minf(w * 0.86, hw - maxf(float(_tire[0]), float(_tire[1])) - 0.07)
	var p := PackedVector2Array()
	p.resize(HALF)
	p[0] = Vector2(0, yb)
	p[1] = Vector2(wi, yb)
	p[2] = Vector2(wi, ya)
	p[3] = Vector2(w * 0.955, ya)
	p[4] = Vector2(w * 0.987, minf(ya + 0.075, y_zh - 0.02))
	p[5] = Vector2(w, y_zh)
	p[6] = Vector2(lerpf(w, ws, 0.4), lerpf(y_zh, y_sh, 0.55))
	p[7] = Vector2(ws, y_sh)
	var gw := ws * _cv("ghw", t)
	var gt := minf(hw * _cv("ght", t), gw - 0.03)
	var hood := [Vector2(ws * 0.9, y_sh + 0.006 + (y_top - y_sh) * 0.2), Vector2(ws * 0.6, lerpf(y_sh, y_top, 0.75)),
		Vector2(ws * 0.3, lerpf(y_sh, y_top, 0.96)), Vector2(0, y_top)]
	var glass := [Vector2(gw, y_sh + 0.012), Vector2(gt, y_roof - 0.045), Vector2(gt * 0.55, y_roof - 0.01), Vector2(0, y_roof)]
	for i in 4:
		p[8 + i] = (hood[i] as Vector2).lerp(glass[i], g)
	var s := {"t": t, "z": z, "p": p, "g": g, "yb": yb, "ya": ya, "y_sh": y_sh, "y_zh": y_zh}
	_sec_cache[key] = s
	return s


## Точка на поверхности: t — вдоль машины, u — по половине кольца (0..11).
func _surf(t: float, u: float, side: float) -> Vector3:
	var p: PackedVector2Array = _sec(t)["p"]
	var i := clampi(int(floor(u)), 0, HALF - 2)
	var q := p[i].lerp(p[i + 1], clampf(u - i, 0.0, 1.0))
	return Vector3(q.x * side, q.y, -_L * 0.5 + t * _L)


# ---------------------------------------------------------------- кузов

func _t_list() -> Array:
	var ts := []
	var n := 46
	for i in n:
		ts.append(0.5 - 0.5 * cos(PI * float(i) / (n - 1)))
	var axles: Array = _b["axles"]
	for i in 2:
		var ra: float = (float(_wr[i]) + 0.06) / _L
		for k in range(-7, 8):
			ts.append(float(axles[i]) + ra * k / 7.0)
	for key in ["ws", "side", "rear"]:
		for v in _b.get(key, []):
			ts.append(float(v))
	for pl in _b.get("pillars", []):
		ts.append(float(pl[0]) - float(pl[1]))
		ts.append(float(pl[0]) + float(pl[1]))
	for d in _b.get("deck", []):
		ts.append(float(d[0]))
		ts.append(float(d[1]))
	ts.sort()
	var out := []
	for t in ts:
		if t < 0.0 or t > 1.0:
			continue
		if out.is_empty() or t - float(out[out.size() - 1]) > 0.0015:
			out.append(t)
	if float(out[out.size() - 1]) < 1.0:
		out.append(1.0)
	return out


func _panel_mat(k: int, t: float, g: float) -> String:
	if k <= 2:
		return "dark"
	if k <= 7:
		return "paint"
	if g < 0.5:
		if k >= 9:
			for d in _b.get("deck", []):
				if t >= float(d[0]) and t <= float(d[1]):
					return d[2]
		return "paint"
	var ws: Array = _b["ws"]
	var side: Array = _b["side"]
	var rear: Array = _b.get("rear", [])
	if k == 8:
		if t >= float(side[0]) and t <= float(side[1]):
			for pl in _b.get("pillars", []):
				if absf(t - float(pl[0])) <= float(pl[1]) + 0.0001:
					return _b.get("pillar_mat", "trim")
			return "glass"
		if t < float(side[0]):
			return _b.get("a_mat", "paint")
		return "paint"
	if t <= float(ws[1]):
		return "glass"
	if not rear.is_empty() and t >= float(rear[0]) and t <= float(rear[1]):
		return "glass"
	return _b.get("roof_mat", "paint")


func _build_body() -> void:
	var ts := _t_list()
	var ns := ts.size()
	var secs: Array = []
	var rings: Array = []
	for t in ts:
		var s := _sec(float(t))
		secs.append(s)
		var p: PackedVector2Array = s["p"]
		var z: float = s["z"]
		var ring := PackedVector3Array()
		for i in HALF:
			ring.append(Vector3(p[i].x, p[i].y, z))
		for i in range(HALF - 2, 0, -1):
			ring.append(Vector3(-p[i].x, p[i].y, z))
		rings.append(ring)
	# нормали граней
	var qn: Array = []
	for i in ns - 1:
		var row: Array = []
		for k in RING:
			var k1 := (k + 1) % RING
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][k1]
			var d: Vector3 = rings[i + 1][k]
			var c: Vector3 = rings[i + 1][k1]
			var n := (b - a).cross(d - a) + (d - c).cross(b - c)
			row.append(n.normalized() if n.length_squared() > 1e-14 else Vector3.ZERO)
		qn.append(row)
	# ориентация наружу: середина правой боковины должна смотреть в +X
	var sign := -1.0 if qn[int(ns / 2)][5].x < 0.0 else 1.0
	for i in ns - 1:
		var tm: float = (float(ts[i]) + float(ts[i + 1])) * 0.5
		var gm: float = (float(secs[i]["g"]) + float(secs[i + 1]["g"])) * 0.5
		for k in RING:
			var fn: Vector3 = qn[i][k] * sign
			if fn == Vector3.ZERO:
				continue
			var half_k := k if k < HALF - 1 else RING - 1 - k
			var mat := _panel_mat(half_k, tm, gm)
			var k1 := (k + 1) % RING
			var vs: Array = []
			var nrm: Array = []
			var uvs: Array = []
			for cnr in [[i, k], [i, k1], [i + 1, k1], [i + 1, k]]:
				var ii: int = cnr[0]
				var j: int = cnr[1]
				vs.append(rings[ii][j])
				var v := float(j) / RING
				if j == 0 and k == RING - 1:
					v = 1.0
				uvs.append(Vector2(float(ts[ii]), v))
				# сглаживание: соседние грани вокруг вершины с близкой нормалью
				var nsum := Vector3.ZERO
				for sec in [ii - 1, ii]:
					if sec < 0 or sec >= ns - 1:
						continue
					for kk in [(j - 1 + RING) % RING, j]:
						var qv: Vector3 = qn[sec][kk] * sign
						if qv != Vector3.ZERO and qv.dot(fn) > SMOOTH_COS:
							nsum += qv
				nrm.append(nsum.normalized() if nsum.length_squared() > 1e-12 else fn)
			_emit_tri(mat, [vs[0], vs[1], vs[2]], [nrm[0], nrm[1], nrm[2]], fn, [uvs[0], uvs[1], uvs[2]])
			_emit_tri(mat, [vs[0], vs[2], vs[3]], [nrm[0], nrm[2], nrm[3]], fn, [uvs[0], uvs[2], uvs[3]])
	# торцы: нос и корма
	for end in [0, ns - 1]:
		var ring: PackedVector3Array = rings[end]
		var center := Vector3.ZERO
		for q in ring:
			center += q
		center /= ring.size()
		var fn := Vector3(0, 0, -1) if end == 0 else Vector3(0, 0, 1)
		var tu := 0.0 if end == 0 else 1.0
		for k in RING:
			_emit_tri("paint", [center, ring[k], ring[(k + 1) % RING]], [fn, fn, fn], fn,
				[PART_UV, Vector2(tu, float(k) / RING), Vector2(tu, float(k + 1) / RING)])


## Текстура швов (оттенки серого, умножается на цвет краски).
## u — вдоль машины (t), v — по кольцу: полоса 8 px на каждую панель.
func _detail_texture() -> ImageTexture:
	var w := 512
	var h := RING * 8
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 1, 1))
	var shade := func(x0: int, x1: int, y0: int, y1: int, k: float):
		for x in range(maxi(x0, 0), mini(x1, w)):
			for y in range(maxi(y0, 0), mini(y1, h)):
				img.set_pixel(x, y, img.get_pixel(x, y) * k)
	# k — номер панели половины; справа полоса k, слева — RING-1-k
	var both := func(t0: float, t1: float, k0: int, k1: int, f: float, y0 := 0, y1 := 8, right_only := false):
		for k in range(k0, k1 + 1):
			for band in ([k] if right_only else [k, RING - 1 - k]):
				shade.call(int(t0 * w), int(t1 * w) + 1, band * 8 + y0, band * 8 + y1, f)
	both.call(0.0, 1.0, 3, 3, 0.8)           # тень порога
	for s in _b.get("seams", []):
		both.call(float(s[0]), float(s[0]), int(s[1]), int(s[2]), 0.42)
	for s in _b.get("hlines", []):
		both.call(float(s[0]), float(s[1]), int(s[2]), int(s[2]), 0.5, int(s[3]), int(s[3]) + 1)
	for s in _b.get("handles", []):
		both.call(float(s[0]) - 0.012, float(s[0]), int(s[1]), int(s[1]), 0.35, 2, 5)
	if _b.has("fuel"):
		var f: Array = _b["fuel"]
		both.call(float(f[0]) - 0.012, float(f[0]), int(f[1]), int(f[1]), 0.6, 1, 7, true)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- вывод геометрии

func _tool(key: String) -> SurfaceTool:
	if not _tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = st
	return _tools[key]


## Треугольник; порядок вершин подбирается так, чтобы лицевая сторона смотрела по fn
## (в Godot лицевые грани — по часовой стрелке, если смотреть снаружи).
func _emit_tri(key: String, vs: Array, ns: Array, fn: Vector3, uvs: Array = []) -> void:
	var st := _tool(key)
	var order := [0, 1, 2]
	if (vs[1] - vs[0]).cross(vs[2] - vs[0]).dot(fn) > 0.0:
		order = [0, 2, 1]
	for o in order:
		st.set_normal(ns[o])
		st.set_uv(uvs[o] if not uvs.is_empty() else PART_UV)
		st.add_vertex(vs[o])


func _flat_quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
	var n := (b - a).cross(d - a) + (d - c).cross(b - c)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	if n.dot(out) < 0.0:
		n = -n
	_emit_tri(key, [a, b, c], [n, n, n], n)
	_emit_tri(key, [a, c, d], [n, n, n], n)


## Призма: многоугольник poly, вытянутый вдоль оси axis от d0 до d1.
## axis 0: poly в (z, y), вдоль X; 1: poly в (x, z), вдоль Y; 2: poly в (x, y), вдоль Z.
func _prism(key: String, poly: PackedVector2Array, d0: float, d1: float, axis: int, xf := Transform3D.IDENTITY) -> void:
	var map := func(p: Vector2, d: float) -> Vector3:
		match axis:
			0:
				return xf * Vector3(d, p.y, p.x)
			1:
				return xf * Vector3(p.x, d, p.y)
		return xf * Vector3(p.x, p.y, d)
	var n := poly.size()
	var center := Vector3.ZERO
	for p in poly:
		center += map.call(p, (d0 + d1) * 0.5)
	center /= n
	var idx := Geometry2D.triangulate_polygon(poly)
	for cap in [d0, d1]:
		var cn: Vector3 = (map.call(Vector2.ZERO, cap) - map.call(Vector2.ZERO, (d0 + d1) * 0.5)).normalized()
		for i in range(0, idx.size(), 3):
			var a: Vector3 = map.call(poly[idx[i]], cap)
			var b: Vector3 = map.call(poly[idx[i + 1]], cap)
			var c: Vector3 = map.call(poly[idx[i + 2]], cap)
			_emit_tri(key, [a, b, c], [cn, cn, cn], cn)
	var cw := Geometry2D.is_polygon_clockwise(poly)
	for i in n:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % n]
		var e := (p1 - p0).normalized()
		var n2 := Vector2(e.y, -e.x) if not cw else Vector2(-e.y, e.x)
		var mid: Vector2 = (p0 + p1) * 0.5
		var out: Vector3 = map.call(mid + n2, (d0 + d1) * 0.5) - map.call(mid, (d0 + d1) * 0.5)
		_flat_quad(key, map.call(p0, d0), map.call(p1, d0), map.call(p1, d1), map.call(p0, d1), out)


## Брусок по восьми углам: a — четыре угла «начала», b — «конца» (по кругу).
func _beam(key: String, a: Array, b: Array) -> void:
	var c := Vector3.ZERO
	for p in a + b:
		c += p
	c /= 8.0
	_flat_quad(key, a[0], a[1], a[2], a[3], (a[0] + a[2]) * 0.5 - c)
	_flat_quad(key, b[0], b[1], b[2], b[3], (b[0] + b[2]) * 0.5 - c)
	for i in 4:
		var j := (i + 1) % 4
		_flat_quad(key, a[i], a[j], b[j], b[i], (a[i] + b[j]) * 0.5 - c)


func _box(key: String, center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var poly := PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	_prism(key, poly, -h.z, h.z, 2, Transform3D(basis, center))


## Тело вращения вокруг оси X: profile — точки (x, r), crease — без сглаживания.
func _lathe(key: String, profile: Array, segs: int, xf := Transform3D.IDENTITY, crease := false) -> void:
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		for s in segs:
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var d0 := Vector3(0, cos(a0), sin(a0))
			var d1 := Vector3(0, cos(a1), sin(a1))
			var v := [Vector3(p0.x, 0, 0) + d0 * p0.y, Vector3(p0.x, 0, 0) + d1 * p0.y,
				Vector3(p1.x, 0, 0) + d1 * p1.y, Vector3(p1.x, 0, 0) + d0 * p1.y]
			var dir := p1 - p0
			var nr := Vector2(-dir.y, dir.x).normalized()   # нормаль профиля: наружу, если профиль идёт к +X
			var n0 := (Vector3(nr.x, 0, 0) + d0 * nr.y).normalized()
			var n1 := (Vector3(nr.x, 0, 0) + d1 * nr.y).normalized()
			var fn := (n0 + n1).normalized()
			if crease or fn == Vector3.ZERO:
				fn = (v[1] - v[0]).cross(v[3] - v[0]).normalized()
				if fn.dot(n0 + n1) < 0.0:
					fn = -fn
			var vv: Array = []
			for q in v:
				vv.append(xf * q)
			var b := xf.basis
			var nn := [b * n0, b * n1, b * n1, b * n0]
			var fw := (b * fn).normalized()
			_emit_tri(key, [vv[0], vv[1], vv[2]], [nn[0], nn[1], nn[2]], fw)
			_emit_tri(key, [vv[0], vv[2], vv[3]], [nn[0], nn[2], nn[3]], fw)


func _commit() -> Dictionary:
	var mesh := ArrayMesh.new()
	var slots := {}
	for key in _tools:
		var st: SurfaceTool = _tools[key]
		st.commit(mesh)
		var i := mesh.get_surface_count() - 1
		slots[key] = i
		if key != "paint" and key != "tail" and not key.begins_with("@"):
			mesh.surface_set_material(i, shared(key))
	_tools = {}
	return {"mesh": mesh, "slots": slots}


# ---------------------------------------------------------------- проекции

## Пиксельный шаг сетки по осям вида (единицы осей: t — доля длины, остальное — метры).
func _unit(view: String) -> Vector2:
	match view:
		"side", "surf":
			return Vector2(_L, 1.0 if view == "side" else 0.12)
		"top":
			return Vector2(1.0, _L)
	return Vector2.ONE


func _fine(rear: bool) -> Array:
	var arr := _fine_rear if rear else _fine_front
	if arr.is_empty():
		for i in 161:
			var t := 0.0025 * i
			if rear:
				t = 1.0 - t
			var s := _sec(t)
			arr.append([t, s["p"]])
	return arr


## Глубина кузова спереди/сзади в точке (x, y): первое сечение, внутри которого
## лежит точка, уточнённое делением отрезка пополам.
func _end_t(x: float, y: float, rear: bool) -> float:
	var q := Vector2(maxf(absf(x), 0.001), y)
	var arr := _fine(rear)
	for i in arr.size():
		if Geometry2D.is_point_in_polygon(q, arr[i][1]):
			if i == 0:
				return float(arr[0][0])
			var a: float = arr[i - 1][0]
			var b: float = arr[i][0]
			for k in 7:
				var m := (a + b) * 0.5
				if Geometry2D.is_point_in_polygon(q, _sec(m)["p"]):
					b = m
				else:
					a = m
			return (a + b) * 0.5
	return float(arr[arr.size() - 1][0])


func _side_x(p: PackedVector2Array, y: float) -> float:
	if y <= p[3].y:
		return p[3].x
	var top := 9 if p[9].y > p[8].y + 0.005 else 8
	for i in range(3, top):
		if p[i + 1].y <= p[i].y:
			return p[i].x
		if y <= p[i + 1].y:
			return lerpf(p[i].x, p[i + 1].x, (y - p[i].y) / (p[i + 1].y - p[i].y))
	return p[top].x


func _top_y(p: PackedVector2Array, x: float) -> float:
	for i in range(HALF - 1, 7, -1):
		var a := p[i]
		var b := p[i - 1]
		if x <= b.x:
			return lerpf(a.y, b.y, (x - a.x) / maxf(b.x - a.x, 0.0001))
	return p[7].y


func _rel(d: Dictionary, t: float) -> float:
	match d.get("rel", ""):
		"sh":
			return float(_sec(t)["y_sh"])
		"lo":
			return float(_sec(t)["yb"])
		"zh":
			return float(_sec(t)["y_zh"])
	return 0.0


## Точка поверхности для координат наклейки (a, b) и сторона s; dir — направление «наружу».
func _proj(d: Dictionary, a: float, b: float, s: float) -> Array:
	var view: String = d["v"]
	match view:
		"side":
			var p: PackedVector2Array = _sec(a)["p"]
			var y := b + _rel(d, a)
			return [Vector3(s * _side_x(p, y), y, -_L * 0.5 + a * _L), Vector3(s, 0, 0)]
		"top":
			var p2: PackedVector2Array = _sec(b)["p"]
			return [Vector3(a * s, _top_y(p2, absf(a)), -_L * 0.5 + b * _L), Vector3.UP]
		"front", "rear":
			var rear := view == "rear"
			var t := _end_t(a, b, rear)
			return [Vector3(a * s, b, -_L * 0.5 + t * _L), Vector3(0, 0, 1 if rear else -1)]
	# surf: (t, u)
	var q := _surf(a, b, s)
	var e1 := _surf(minf(a + 0.004, 1.0), b, s) - _surf(maxf(a - 0.004, 0.0), b, s)
	var e2 := _surf(a, b + 0.05, s) - _surf(a, b - 0.05, s)
	var n := e1.cross(e2).normalized()
	if n.dot(Vector3(q.x, q.y - 0.6, 0)) < 0.0:
		n = -n
	return [q, n]


static func circle(cx: float, cy: float, r: float, n := 16, sx := 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(Vector2(cx + cos(a) * r * sx, cy + sin(a) * r))
	return out


func _decal_poly(d: Dictionary) -> PackedVector2Array:
	if d.has("c"):
		var c: Array = d["c"]
		return circle(c[0], c[1], c[2], 18, float(c[3]) if c.size() > 3 else 1.0)
	var out := PackedVector2Array()
	for p in d["p"]:
		out.append(Vector2(p[0], p[1]))
	return out


## Наклейка: многоугольник режется сеткой, куски проецируются на кузов.
func _decal(d: Dictionary) -> void:
	var poly := _decal_poly(d)
	var view: String = d["v"]
	var unit := _unit(view)
	var res: float = d.get("res", 0.06)
	var lift: float = d.get("lift", 0.006)
	var sides := [1.0, -1.0] if d.get("sym", true) else [1.0]
	var pieces := _grid(poly, Vector2(res, res) / unit)
	for s: float in sides:
		_project(pieces, d, s, d["m"], lift, poly)
		if d.has("rim"):
			var rim: Array = d["rim"]
			_project(_outline(poly, float(rim[0]), unit, res), d, s, rim[1], lift + 0.002, poly)


func _grid(poly: PackedVector2Array, cell: Vector2) -> Array:
	var r := _bbox(poly)
	var na := maxi(1, ceili(r.size.x / cell.x))
	var nb := maxi(1, ceili(r.size.y / cell.y))
	var sa := r.size.x / na
	var sb := r.size.y / nb
	var out := []
	for i in na:
		for j in nb:
			var x0 := r.position.x + i * sa
			var y0 := r.position.y + j * sb
			var c := PackedVector2Array([Vector2(x0, y0), Vector2(x0 + sa, y0), Vector2(x0 + sa, y0 + sb), Vector2(x0, y0 + sb)])
			out.append_array(Geometry2D.intersect_polygons(c, poly))
	return out


static func _bbox(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


## Окантовка многоугольника: полоска шириной width (в метрах) снаружи, кусками.
func _outline(poly: PackedVector2Array, width: float, unit: Vector2, res: float) -> Array:
	var n := poly.size()
	var m := PackedVector2Array()
	for p in poly:
		m.append(p * unit)
	var sgn := -1.0 if Geometry2D.is_polygon_clockwise(m) else 1.0
	var outer := PackedVector2Array()
	for i in n:
		var e0 := (m[i] - m[(i - 1 + n) % n]).normalized()
		var e1 := (m[(i + 1) % n] - m[i]).normalized()
		var n0 := Vector2(e0.y, -e0.x) * sgn
		var n1 := Vector2(e1.y, -e1.x) * sgn
		var mid := (n0 + n1).normalized()
		var k := 1.0 / maxf(mid.dot(n0), 0.5)
		outer.append(m[i] + mid * width * k)
	var out := []
	for i in n:
		var j := (i + 1) % n
		var steps := maxi(1, ceili(m[i].distance_to(m[j]) / res))
		for s in steps:
			var f0 := float(s) / steps
			var f1 := float(s + 1) / steps
			var q := PackedVector2Array([m[i].lerp(m[j], f0), m[i].lerp(m[j], f1), outer[i].lerp(outer[j], f1), outer[i].lerp(outer[j], f0)])
			for k2 in 4:
				q[k2] = q[k2] / unit
			out.append(q)
	return out


func _project(pieces: Array, d: Dictionary, s: float, mat: String, lift: float, poly: PackedVector2Array) -> void:
	var r := _bbox(poly)
	var cache := {}
	var tris: Array = []
	var acc := {}
	for piece: PackedVector2Array in pieces:
		var idx := Geometry2D.triangulate_polygon(piece)
		for i in range(0, idx.size(), 3):
			var tri: Array = []
			for j in 3:
				var q: Vector2 = piece[idx[i + j]]
				var key := Vector2i(roundi(q.x * 100000.0), roundi(q.y * 100000.0))
				if not cache.has(key):
					var pr := _proj(d, q.x, q.y, s)
					cache[key] = [pr[0], pr[1], q]
				tri.append(key)
			var a: Vector3 = cache[tri[0]][0]
			var b: Vector3 = cache[tri[1]][0]
			var c: Vector3 = cache[tri[2]][0]
			var n := (b - a).cross(c - a)
			if n.length_squared() < 1e-16:
				continue
			n = n.normalized()
			if n.dot(cache[tri[0]][1]) < 0.0:
				n = -n
			tris.append([tri, n])
			for k in tri:
				acc[k] = acc.get(k, Vector3.ZERO) + n
	# подъём над кузовом — по усреднённой нормали в вершине, чтобы не уходить под краску
	var lifted := {}
	for k in acc:
		var an: Vector3 = acc[k]
		lifted[k] = (cache[k][0] as Vector3) + an.normalized() * lift
	for e in tris:
		var tri: Array = e[0]
		var fn: Vector3 = e[1]
		var vs: Array = []
		var ns: Array = []
		var uvs: Array = []
		for k in tri:
			vs.append(lifted[k])
			var an: Vector3 = acc[k]
			ns.append(an.normalized() if an.dot(fn) > 0.5 * an.length() else fn)
			var q: Vector2 = cache[k][2]
			uvs.append(Vector2((q.x - r.position.x) / maxf(r.size.x, 1e-5), 1.0 - (q.y - r.position.y) / maxf(r.size.y, 1e-5)))
		_emit_tri(mat, vs, ns, fn, uvs)


# ---------------------------------------------------------------- сборка

func build(def: Dictionary, paint_index: int, tune: Dictionary = {}) -> void:
	for c in get_children():
		c.queue_free()
	wheels.clear()
	steer_pivots.clear()
	_wheel_side.clear()
	_tune = tune
	_setup(def)
	if Net.dedicated:
		# выделенному серверу графика не нужна
		body = Node3D.new()
		add_child(body)
		return

	# кузов с заводскими деталями — один на модель; антикрыло и тюнинг — отдельный
	# маленький меш на каждую комбинацию (у ботов тюнинг случайный)
	var base_key: String = "base|" + def["id"]
	var tkey := ""
	for slot in TUNING:
		tkey += str(tune_value(slot[0]))
	var tune_key: String = "tune|%s|%s" % [def["id"], tkey]
	if not _body_cache.has(base_key) or not _body_cache.has(tune_key):
		_sec_cache.clear()
		_fine_front.clear()
		_fine_rear.clear()
		if not _body_cache.has(base_key):
			_tools = {}
			_build_body()
			for d in _b.get("decals", []):
				_decal(d)
			_build_parts()
			var res := _commit()
			res["detail"] = _detail_texture()
			res["flame"] = _flame_pos()
			_body_cache[base_key] = res
		if not _body_cache.has(tune_key):
			_tools = {}
			if tune_value("wing") == 0 and not _b.get("wing", {}).is_empty():
				_wing(_b["wing"])
			_build_tuning()
			_body_cache[tune_key] = _commit() if not _tools.is_empty() else {}
		_sec_cache.clear()
		_fine_front.clear()
		_fine_rear.clear()
	var cached: Dictionary = _body_cache[base_key]

	var paint := _m(CarDB.paint_color(paint_index), 0.3, 0.72)
	paint.albedo_texture = cached["detail"]
	paint.metallic_specular = 0.7
	brake_lights = _glow(Color(0.85, 0.015, 0.02), 1.0)
	brake_lights.albedo_texture = Track.tex("taillight.png")
	brake_lights.emission_texture = Track.tex("taillight.png")
	body = Node3D.new()
	add_child(body)
	for part: Dictionary in [cached, _body_cache[tune_key]]:
		if part.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = part["mesh"]
		var slots: Dictionary = part["slots"]
		if slots.has("paint"):
			mi.set_surface_override_material(slots["paint"], paint)
		if slots.has("tail"):
			mi.set_surface_override_material(slots["tail"], brake_lights)
		body.add_child(mi)

	# пламя из выхлопа: синее для нитро, оранжевое для выстрелов
	_flame_nitro = _glow(Color(0.35, 0.6, 1.0), 4.0)
	_flame_fire = _glow(Color(1.0, 0.5, 0.1), 5.0)
	flame = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.12
	cone.height = 0.8
	cone.radial_segments = 8
	cone.rings = 1
	flame.mesh = cone
	flame.material_override = _flame_nitro
	flame.position = cached["flame"] + Vector3(0, 0, 0.42)
	flame.rotation = Vector3(-PI * 0.5, 0, 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.visible = false
	body.add_child(flame)

	_build_wheels(def)


func _setup(def: Dictionary) -> void:
	_b = CarBodies.get_body(def["id"])
	_L = def["len"]
	_W = def["wid"]
	_c = float(_b["clear"])
	_wr = _b["wr"]
	_tire = _b["tire"]
	var axles: Array = _b["axles"]
	_axle_z = [-_L * 0.5 + float(axles[0]) * _L, -_L * 0.5 + float(axles[1]) * _L]
	wheel_r = (float(_wr[0]) + float(_wr[1])) * 0.5


func _flame_pos() -> Vector3:
	var ex: Array = _b.get("exhaust", [])
	if ex.is_empty():
		return Vector3(0, _c + 0.15, _L * 0.5)
	var e: Dictionary = ex[0]
	var z := -_L * 0.5 + _end_t(float(e["x"]), float(e["y"]), true) * _L
	return Vector3(float(e["x"]), float(e["y"]), z)


# ---------------------------------------------------------------- навесные детали

func _build_parts() -> void:
	for p in _b.get("parts", []):
		match p["type"]:
			"mirror":
				_mirror(p)
			"splitter":
				_splitter(float(p.get("depth", 0.12)), float(p.get("width", 0.9)), p.get("m", "dark"), float(p.get("y", 0.0)))
			"diffuser":
				_diffuser(int(p.get("fins", 4)), float(p.get("width", 0.75)), float(p.get("h", 0.14)), p.get("m", "dark"))
			"wiper":
				_wipers()
			"antenna":
				_antenna(float(p["t"]))
			"snorkel":
				_snorkel(p)
			"box":
				var c: Array = p["at"]
				var sz: Array = p["size"]
				for s: float in ([1.0, -1.0] if p.get("sym", false) else [1.0]):
					var rot: Array = p.get("rot", [0, 0, 0])
					_box(p["m"], Vector3(float(c[0]) * s, float(c[1]), float(c[2])), Vector3(sz[0], sz[1], sz[2]),
						Basis.from_euler(Vector3(rot[0], float(rot[1]) * s, float(rot[2]) * s)))
			"blade":
				_blade(p)
	for e in _b.get("exhaust", []):
		_exhaust(e, 1.0)
		if e.get("sym", true) and absf(float(e["x"])) > 0.01:
			_exhaust(e, -1.0)


func _mirror(p: Dictionary) -> void:
	var t: float = p["t"]
	var s := _sec(t)
	var pts: PackedVector2Array = s["p"]
	var base := Vector3(pts[8].x, pts[8].y + float(p.get("dy", 0.04)), float(s["z"]))
	var out: float = p.get("out", 0.13)
	var mw: float = p.get("w", 0.2)
	var mh: float = p.get("h", 0.1)
	var shape := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		var c := Vector2(cos(a), sin(a))
		# скруглённый прямоугольник
		shape.append(Vector2(signf(c.x) * pow(absf(c.x), 0.5) * mw * 0.5, signf(c.y) * pow(absf(c.y), 0.5) * mh * 0.5))
	for sd: float in [1.0, -1.0]:
		var center := Vector3((base.x + out) * sd, base.y + mh * 0.3, base.z + 0.02)
		var xf := Transform3D(Basis(Vector3.UP, -sd * 0.12), center)
		_prism("paint", shape, -0.05, 0.05, 2, xf)
		var glass := PackedVector2Array()
		for q in shape:
			glass.append(q * 0.86)
		_prism("glass", glass, 0.05, 0.056, 2, xf)
		var b0 := Vector3(base.x * sd, base.y - 0.03, base.z - 0.03)
		var b1 := center + Vector3(-sd * mw * 0.32, -mh * 0.25, 0.0)
		var up := Vector3(0, 0.022, 0)
		var fw := Vector3(0, 0, 0.05)
		_beam(p.get("arm", "paint"), [b0 - up - fw, b0 + up - fw, b0 + up + fw, b0 - up + fw],
			[b1 - up - fw * 0.6, b1 + up - fw * 0.6, b1 + up + fw * 0.6, b1 - up + fw * 0.6])


func _splitter(depth: float, width: float, mat: String, dy := 0.0) -> void:
	var s := _sec(0.02)
	var y: float = float(s["yb"]) - 0.01 + dy
	var w: float = float((s["p"] as PackedVector2Array)[3].x) * 2.0 * width
	var z := -_L * 0.5
	var poly := PackedVector2Array([Vector2(-w * 0.5, z + 0.12), Vector2(w * 0.5, z + 0.12), Vector2(w * 0.47, z - depth),
		Vector2(-w * 0.47, z - depth)])
	_prism(mat, poly, y - 0.012, y + 0.012, 1)


func _diffuser(fins: int, width: float, h: float, mat: String) -> void:
	var s := _sec(0.985)
	var y: float = s["yb"]
	var w := _W * width
	var z := _L * 0.5
	var plate := PackedVector2Array([Vector2(-w * 0.5, z - 0.5), Vector2(w * 0.5, z - 0.5), Vector2(w * 0.5, z + 0.02), Vector2(-w * 0.5, z + 0.02)])
	_prism(mat, plate, y - 0.03, y - 0.01, 1)
	for i in fins:
		var x := -w * 0.4 + w * 0.8 * float(i) / maxf(fins - 1, 1)
		var fin := PackedVector2Array([Vector2(z - 0.55, y - 0.02), Vector2(z + 0.02, y - 0.02), Vector2(z + 0.02, y + h)])
		_prism(mat, fin, x - 0.008, x + 0.008, 0)


func _wipers() -> void:
	var ws: Array = _b["ws"]
	var t: float = float(ws[0]) + 0.012
	var s := _sec(t)
	var y: float = float((s["p"] as PackedVector2Array)[11].y) + 0.012
	var z: float = s["z"]
	for x: float in [-0.42, 0.12]:
		var a := Vector3(x, y, z)
		var b := Vector3(x + 0.48, y + 0.012, z + 0.03)
		var d := Vector3(0, 0.008, 0)
		var f := Vector3(0, 0, 0.008)
		_beam("dark", [a - d - f, a + d - f, a + d + f, a - d + f], [b - d - f, b + d - f, b + d + f, b - d + f])


func _antenna(t: float) -> void:
	var s := _sec(t)
	var y: float = (s["p"] as PackedVector2Array)[11].y
	var z: float = s["z"]
	var poly := PackedVector2Array([Vector2(z - 0.08, y - 0.01), Vector2(z + 0.1, y - 0.01), Vector2(z + 0.07, y + 0.06)])
	_prism("trim", poly, -0.025, 0.025, 0)


func _snorkel(p: Dictionary) -> void:
	var t0: float = p["t0"]
	var t1: float = p["t1"]
	var hgt: float = p.get("h", 0.1)
	var w: float = p.get("w", 0.22)
	var s0 := _sec(t0)
	var s1 := _sec(t1)
	var y0: float = (s0["p"] as PackedVector2Array)[11].y
	var y1: float = (s1["p"] as PackedVector2Array)[11].y
	var z0: float = s0["z"]
	var z1: float = s1["z"]
	var prof := PackedVector2Array([Vector2(z0, y0 - 0.02), Vector2(z1, y1 - 0.02), Vector2(z1, y1 + 0.02), Vector2(z0 + 0.06, y0 + hgt),
		Vector2(z0, y0 + hgt)])
	_prism(p.get("m", "paint"), prof, -w * 0.5, w * 0.5, 0)
	_box("dark", Vector3(0, y0 + hgt * 0.55, z0 - 0.004), Vector3(w * 0.8, hgt * 0.7, 0.01))


## Произвольная плоская деталь по профилю сбоку (z через t, y в метрах), толщиной th.
func _blade(p: Dictionary) -> void:
	var prof := PackedVector2Array()
	for q in p["p"]:
		prof.append(Vector2(-_L * 0.5 + float(q[0]) * _L, float(q[1])))
	var x: float = p["x"]
	var th: float = p.get("th", 0.03)
	for sd: float in ([1.0, -1.0] if p.get("sym", true) else [1.0]):
		_prism(p.get("m", "paint"), prof, sd * x - th * 0.5, sd * x + th * 0.5, 0)


func _exhaust(e: Dictionary, sd: float) -> void:
	var x := float(e["x"]) * sd
	var y: float = e["y"]
	var t := _end_t(x, y, true)
	var z := -_L * 0.5 + t * _L + float(e.get("out", 0.03))
	var shape: String = e.get("shape", "round")
	var r: float = e.get("r", 0.05)
	if shape == "square":
		var w: float = e.get("w", 0.1)
		var h: float = e.get("h", 0.07)
		_box("chrome", Vector3(x, y, z - 0.08), Vector3(w, h, 0.16))
		_box("dark", Vector3(x, y, z + 0.002), Vector3(w * 0.82, h * 0.72, 0.01))
		return
	var sx: float = e.get("sx", 1.0)
	# ось вращения X поворачиваем назад (+Z), овал — растяжением по ширине
	var xf := Transform3D(Basis.from_scale(Vector3(sx, 1, 1)) * Basis(Vector3.UP, -PI * 0.5), Vector3(x, y, z))
	_lathe("chrome", [Vector2(-0.18, r * 0.9), Vector2(-0.01, r), Vector2(0.0, r * 0.8)], 14, xf)
	_lathe("dark", [Vector2(0.0, r * 0.8), Vector2(-0.01, 0.0)], 14, xf)


## Антикрыло: chord — хорда, h — высота над крышкой багажника, span — размах.
func _wing(w: Dictionary) -> void:
	var t: float = w["t"]
	var s := _sec(t)
	var deck: float = (s["p"] as PackedVector2Array)[11].y
	var z: float = s["z"]
	var kind: String = w.get("type", "wing")
	var mat: String = w.get("m", "dark")
	if kind == "lip":
		var ww: float = float((s["p"] as PackedVector2Array)[7].x) * 2.0 * float(w.get("span", 0.9))
		var hh: float = w.get("h", 0.05)
		var lip := PackedVector2Array([Vector2(z - 0.16, deck - 0.01), Vector2(z + 0.04, deck - 0.01), Vector2(z + 0.06, deck + hh)])
		_prism(mat, lip, -ww * 0.5, ww * 0.5, 0)
		return
	var span: float = w.get("span", _W * 0.95)
	var chord: float = w.get("chord", 0.32)
	var h: float = w.get("h", 0.3)
	var aoa: float = w.get("aoa", 0.12)
	var foil := PackedVector2Array()
	var th := chord * 0.11
	for i in 9:
		var u := float(i) / 8.0
		foil.append(Vector2(-chord * 0.5 + u * chord, th * sin(PI * pow(u, 0.6)) * (1.0 - u * 0.4)))
	for i in range(7, 0, -1):
		var u := float(i) / 8.0
		foil.append(Vector2(-chord * 0.5 + u * chord, -th * 0.35 * sin(PI * u)))
	var rot := Transform2D(-aoa, Vector2.ZERO)
	for i in foil.size():
		foil[i] = rot * foil[i] + Vector2(z, deck + h)
	_prism(mat, foil, -span * 0.5, span * 0.5, 0)
	# торцевые пластины
	if w.get("plates", true):
		var pl := PackedVector2Array([Vector2(z - chord * 0.6, deck + h - chord * 0.25), Vector2(z + chord * 0.55, deck + h - chord * 0.3),
			Vector2(z + chord * 0.6, deck + h + chord * 0.32), Vector2(z - chord * 0.45, deck + h + chord * 0.18)])
		for sd: float in [1.0, -1.0]:
			_prism(w.get("plate_m", mat), pl, sd * span * 0.5 - 0.008, sd * span * 0.5 + 0.008, 0)
	# стойки
	var px: float = w.get("posts", 0.3)
	for sd: float in [1.0, -1.0]:
		var x := sd * span * px
		var post := PackedVector2Array([Vector2(z - 0.02, deck - 0.03), Vector2(z + 0.12, deck - 0.03), Vector2(z + 0.08, deck + h),
			Vector2(z - 0.06, deck + h)])
		_prism(w.get("post_m", mat), post, x - 0.012, x + 0.012, 0)


# ---------------------------------------------------------------- тюнинг

func _build_tuning() -> void:
	var carbon := "carbon"
	match tune_value("wing"):
		2:
			_wing({"type": "lip", "t": 0.975, "h": 0.06, "span": 0.92, "m": "paint"})
		3:
			_wing({"t": 0.93, "h": 0.3, "chord": 0.3, "span": _W * 0.92, "m": carbon, "post_m": "dark"})
		4:
			_wing({"t": 0.92, "h": 0.42, "chord": 0.4, "span": _W * 1.0, "aoa": 0.18, "m": carbon, "plate_m": "paint", "post_m": "dark"})
	match tune_value("front"):
		1:
			_splitter(0.12, 0.98, carbon, -0.005)
		2:
			_splitter(0.18, 1.02, carbon, -0.005)
			# клыки на углах бампера
			for k in 2:
				var y := _c + 0.2 + k * 0.1
				var x := _W * 0.5 * 0.86
				var z := -_L * 0.5 + _end_t(x, y, false) * _L
				var fin := PackedVector2Array([Vector2(z + 0.16, y + 0.03), Vector2(z - 0.03, y - 0.01), Vector2(z - 0.03, y + 0.01)])
				for sd: float in [1.0, -1.0]:
					_prism(carbon, fin, sd * (x - 0.1), sd * (x + 0.07), 0)
	if tune_value("skirts") == 1:
		var axles: Array = _b["axles"]
		var z0: float = float(_axle_z[0]) + float(_wr[0]) + 0.1
		var z1: float = float(_axle_z[1]) - float(_wr[1]) - 0.1
		var sm := _sec((float(axles[0]) + float(axles[1])) * 0.5)
		var x: float = (sm["p"] as PackedVector2Array)[3].x
		var yb: float = sm["yb"]
		var prof := PackedVector2Array([Vector2(z0, yb - 0.025), Vector2(z1, yb - 0.025), Vector2(z1, yb + 0.06), Vector2(z0, yb + 0.06)])
		for sd: float in [1.0, -1.0]:
			_prism(carbon, prof, sd * (x - 0.02), sd * (x + 0.05), 0)
	if tune_value("rear") == 1:
		_diffuser(5, 0.82, 0.24, carbon)
	match tune_value("hood"):
		1:
			for k in 2:
				_decal({"v": "top", "m": "grille", "p": [[0.2, 0.1 + k * 0.05], [0.42, 0.1 + k * 0.05], [0.42, 0.13 + k * 0.05], [0.2, 0.13 + k * 0.05]],
					"res": 0.05, "rim": [0.012, "trim"], "lift": 0.01})
		2:
			var ws: Array = _b["ws"]
			var t1: float = float(ws[0]) - 0.015
			var pts := []
			for i in 9:
				var t := lerpf(0.035, t1, float(i) / 8.0)
				var p: PackedVector2Array = _sec(t)["p"]
				pts.append([p[8].x * 0.97, t])
			for i in range(8, -1, -1):
				pts.append([0.0, lerpf(0.035, t1, float(i) / 8.0)])
			_decal({"v": "top", "m": carbon, "p": pts, "res": 0.12, "lift": 0.008})


# ---------------------------------------------------------------- колёса

func _build_wheels(def: Dictionary) -> void:
	var rim_type: String = def.get("rim", "five")
	if tune_value("rims") > 0:
		rim_type = RIM_TYPES[tune_value("rims")]
	var rim_key: String = def.get("rim_color", "silver")
	if tune_value("rim_color") > 0:
		rim_key = RIM_COLOR_KEYS[tune_value("rim_color")]
	var rim_mat := _rim_mat(rim_key)
	var cal_mat := _m(def.get("caliper", Color(0.8, 0.08, 0.06)), 0.4, 0.2)
	var axles: Array = _b["axles"]
	for i in 2:
		var r: float = _wr[i]
		var tw: float = _tire[i]
		var key := "%s|%s|%d" % [def["id"], rim_type, i]
		if not _wheel_cache.has(key):
			_wheel_cache[key] = _wheel_mesh(r, tw, rim_type)
		var wm: Dictionary = _wheel_cache[key]
		var s := _sec(float(axles[i]))
		var outer: float = (s["p"] as PackedVector2Array)[3].x - 0.015
		for sd: float in [1.0, -1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(sd * (outer - tw * 0.5), r, float(_axle_z[i]))
			add_child(pivot)
			var flip := Node3D.new()
			if sd < 0.0:
				flip.rotation.y = PI
			pivot.add_child(flip)
			# суппорт не вращается вместе с колесом
			var cal := MeshInstance3D.new()
			cal.mesh = wm["caliper"]
			cal.material_override = cal_mat
			flip.add_child(cal)
			var spin := Node3D.new()
			flip.add_child(spin)
			var mi := MeshInstance3D.new()
			mi.mesh = wm["mesh"]
			var slots: Dictionary = wm["slots"]
			if slots.has("@rim"):
				mi.set_surface_override_material(slots["@rim"], rim_mat)
			spin.add_child(mi)
			wheels.append(spin)
			_wheel_side.append(sd)
			if i == 0:
				steer_pivots.append(pivot)


static func _rim_mat(key: String) -> StandardMaterial3D:
	var k := "rim_" + key
	if not _mat_cache.has(k):
		_mat_cache[k] = _m(RIM_COLORS.get(key, RIM_COLORS["silver"]), 0.25, 0.85)
	return _mat_cache[k]


## Колесо, лицевой стороной в +X: шина, обод со спицами, тормозной диск, суппорт.
func _wheel_mesh(r: float, tw: float, rim_type: String) -> Dictionary:
	_tools = {}
	var hw := tw * 0.5
	var rr := r * 0.73                 # радиус обода
	# шина: скруглённая боковина
	var prof := [Vector2(-hw * 0.85, rr * 0.98), Vector2(-hw, rr + (r - rr) * 0.35), Vector2(-hw * 0.96, r - 0.035),
		Vector2(-hw * 0.75, r - 0.004), Vector2(hw * 0.75, r - 0.004), Vector2(hw * 0.96, r - 0.035),
		Vector2(hw, rr + (r - rr) * 0.35), Vector2(hw * 0.85, rr * 0.98)]
	_lathe("tire", prof, 24)
	# обод: закраина и бочка
	var face := hw * 0.86
	_lathe("@rim", [Vector2(face - 0.03, rr * 0.97), Vector2(face, rr * 1.0), Vector2(face + 0.004, rr * 0.93), Vector2(face - 0.01, rr * 0.9)], 24, Transform3D.IDENTITY, true)
	_lathe("dark", [Vector2(face - 0.012, rr * 0.9), Vector2(-hw * 0.7, rr * 0.92)], 20)
	# тормозной диск
	_lathe("disc", [Vector2(-0.02, rr * 0.38), Vector2(-0.02, rr * 0.82), Vector2(0.01, rr * 0.82), Vector2(0.01, rr * 0.38)], 20, Transform3D.IDENTITY, true)
	# ступица
	var dish := 0.06
	var hub_x := face - dish
	_lathe("@rim", [Vector2(hub_x - 0.02, 0.085), Vector2(hub_x + 0.01, 0.08), Vector2(hub_x + 0.02, 0.05), Vector2(hub_x + 0.024, 0.0)], 12, Transform3D.IDENTITY, true)
	# спицы
	var spec: Dictionary = RIMS.get(rim_type, RIMS["five"])
	var n: int = spec["n"]
	var k: int = spec["k"]
	var w0: float = spec["w0"]
	var w1: float = spec["w1"]
	var sp: float = spec["sp"]
	var twist: float = spec.get("twist", 0.0)
	var th := 0.026
	if spec.get("face", false):
		_lathe("@rim", [Vector2(face - 0.022, rr * 0.9), Vector2(face - 0.024, rr * 0.3)], 22, Transform3D.IDENTITY, true)
	for g in n:
		var a := TAU * g / n
		for j in k:
			var off := (float(j) - (k - 1) * 0.5) * sp
			var a1 := a + off + twist
			var a0 := a + (0.0 if spec.get("y", false) else off)
			_spoke(a0, a1, 0.07, rr * 0.92, w0, w1, hub_x + 0.01, face - 0.008, th)
			if spec.get("cross", false):
				_spoke(a - twist, a + 0.35, 0.07, rr * 0.92, w0, w1, hub_x + 0.01, face - 0.008, th)
	var res := _commit()
	# суппорт: на заднем верхнем секторе диска
	_tools = {}
	var ca := PI * 0.3
	var cal_c := Vector3(0.0, cos(ca) * rr * 0.62, sin(ca) * rr * 0.62)
	_box("dark", cal_c, Vector3(0.07, rr * 0.5, rr * 0.28), Basis(Vector3.RIGHT, -ca))
	var cm := _commit()
	res["caliper"] = cm["mesh"]
	return res


func _spoke(a0: float, a1: float, r0: float, r1: float, w0: float, w1: float, x0: float, x1: float, th: float) -> void:
	var d0 := Vector3(0, cos(a0), sin(a0))
	var d1 := Vector3(0, cos(a1), sin(a1))
	var t0 := Vector3(0, -sin(a0), cos(a0))
	var t1 := Vector3(0, -sin(a1), cos(a1))
	var c0 := Vector3(x0, 0, 0) + d0 * r0
	var c1 := Vector3(x1, 0, 0) + d1 * r1
	var hx := Vector3(th * 0.5, 0, 0)
	_beam("@rim", [c0 - t0 * w0 * 0.5 - hx, c0 + t0 * w0 * 0.5 - hx, c0 + t0 * w0 * 0.5 + hx, c0 - t0 * w0 * 0.5 + hx],
		[c1 - t1 * w1 * 0.5 - hx, c1 + t1 * w1 * 0.5 - hx, c1 + t1 * w1 * 0.5 + hx, c1 - t1 * w1 * 0.5 + hx])


# ---------------------------------------------------------------- анимация

func backfire() -> void:
	_backfire = 0.07


## Вращение колёс, поворот передних, крен и клевок кузова, пламя.
func animate(dt: float, speed: float, steer: float, lat_acc: float, lon_acc: float, braking: bool, nitro: bool) -> void:
	_spin = fmod(_spin - speed / wheel_r * dt, TAU)
	for i in wheels.size():
		wheels[i].rotation.x = _spin * _wheel_side[i]
	for p in steer_pivots:
		p.rotation.y = -steer * 0.45
	_roll = lerpf(_roll, clampf(lat_acc * 0.006, -0.06, 0.06), 1.0 - exp(-6.0 * dt))
	_pitch = lerpf(_pitch, clampf(-lon_acc * 0.004, -0.04, 0.04), 1.0 - exp(-6.0 * dt))
	if body:
		body.rotation = Vector3(_pitch, 0.0, _roll)
	if brake_lights:
		brake_lights.emission_energy_multiplier = 3.5 if braking else 1.0
	if flame:
		_backfire -= dt
		var fire := _backfire > 0.0
		flame.visible = nitro or fire
		if flame.visible:
			flame.material_override = _flame_fire if fire and not nitro else _flame_nitro
			flame.scale = Vector3.ONE * randf_range(0.8, 1.25) * (0.7 if fire and not nitro else 1.0)
