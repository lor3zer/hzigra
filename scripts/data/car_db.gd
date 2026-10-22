class_name CarDB
extends RefCounted

## Каталог автомобилей. Прототипы — реальные машины, марки и названия вымышленные.
## top      — максимальная скорость, км/ч
## accel    — базовое ускорение, м/с² (см. zero_to_100)
## handling — максимальная скорость поворота, рад/с
## grip     — боковое сцепление, g
## brake    — замедление при торможении, м/с²
## mass     — масса, кг (влияет на столкновения)
## len/wid/hgt — габариты кузова, м; форма кузова — в CarBodies
## engine   — тип мотора (EngineDB.ENGINES), gears — передач в коробке
## rim/rim_color/caliper — диски (CarModel.RIMS) и суппорты

const PAINTS := [
	Color(0.86, 0.06, 0.1),   # красный
	Color(0.05, 0.35, 0.9),   # синий
	Color(0.95, 0.75, 0.05),  # жёлтый
	Color(0.1, 0.1, 0.12),    # чёрный
	Color(0.92, 0.92, 0.95),  # белый
	Color(0.1, 0.7, 0.3),     # зелёный
	Color(1.0, 0.45, 0.05),   # оранжевый
	Color(0.55, 0.1, 0.8),    # фиолетовый
	Color(0.55, 0.58, 0.62),  # серебро
	Color(0.0, 0.75, 0.85),   # бирюза
]

const PAINT_NAMES := ["Красный", "Синий", "Жёлтый", "Чёрный", "Белый", "Зелёный", "Оранжевый", "Фиолетовый", "Серебро", "Бирюза"]

## Классы по порядку; wip — класс в разработке (виден в гараже, машин пока нет).
const CLASSES := [
	{"id": "sport", "name": "Спорт", "color": Color(0.2, 0.75, 1.0)},
	{"id": "super", "name": "Супер", "color": Color(1.0, 0.75, 0.2)},
	{"id": "hyper", "name": "Гипер", "color": Color(1.0, 0.35, 0.3)},
	{"id": "rally", "name": "Ралли", "color": Color(0.55, 0.85, 0.35), "wip": true},
]

const CLASS_NAMES := {"sport": "Спорт", "super": "Супер", "hyper": "Гипер", "rally": "Ралли"}

const CARS := [
	# ---------------- СПОРТ ----------------
	# большой полноприводный седан с V8 битурбо (прототип — Audi S8)
	{"id": "audax_s8", "name": "Audax S8", "class": "sport", "top": 305.0, "accel": 7.6, "handling": 1.55, "grip": 1.95, "brake": 15.5,
		"mass": 2100.0, "len": 5.19, "wid": 1.95, "hgt": 1.47, "paint": 8, "engine": "v8tt", "gears": 8,
		"rim": "multi", "rim_color": "silver", "caliper": Color(0.8, 0.08, 0.06)},
	# полноприводный седан с V8 битурбо (прототип — BMW M5 F90)
	{"id": "bavaro_m5", "name": "Bavaro M5", "class": "sport", "top": 305.0, "accel": 8.5, "handling": 1.62, "grip": 2.0, "brake": 16.0,
		"mass": 1940.0, "len": 4.97, "wid": 1.9, "hgt": 1.47, "paint": 1, "engine": "v8tt", "gears": 8,
		"rim": "twin5", "rim_color": "gunmetal", "caliper": Color(0.1, 0.3, 0.85)},
	# бизнес-седан с V8 битурбо (прототип — Mercedes-AMG E63)
	{"id": "mercator_e63", "name": "Mercator E63 AMX", "class": "sport", "top": 300.0, "accel": 8.5, "handling": 1.58, "grip": 1.98, "brake": 16.0,
		"mass": 1955.0, "len": 4.99, "wid": 1.91, "hgt": 1.46, "paint": 3, "engine": "v8tt", "gears": 9,
		"rim": "multi", "rim_color": "gunmetal", "caliper": Color(0.85, 0.1, 0.08)},
	# ---------------- СУПЕР ----------------
	# переднемоторное купе с атмосферным V12 (прототип — Ferrari 812)
	{"id": "ferrano_821", "name": "Ferrano 821 Rapido", "class": "super", "top": 340.0, "accel": 9.9, "handling": 1.72, "grip": 2.2,
		"brake": 17.0, "mass": 1630.0, "len": 4.66, "wid": 1.97, "hgt": 1.28, "paint": 0, "engine": "v12", "gears": 7,
		"rim": "y5", "rim_color": "gunmetal", "caliper": Color(0.95, 0.78, 0.05)},
	# среднемоторное купе с атмосферным V8 (прототип — Chevrolet Corvette C8)
	{"id": "corvane_k8", "name": "Corvane K8", "class": "super", "top": 312.0, "accel": 9.9, "handling": 1.85, "grip": 2.3,
		"brake": 17.0, "mass": 1570.0, "len": 4.63, "wid": 1.93, "hgt": 1.23, "paint": 2, "engine": "v8x", "gears": 8,
		"rim": "trident", "rim_color": "gunmetal", "caliper": Color(0.85, 0.1, 0.08)},
	# электрическое купе с тоннелями в корме (прототип — Lotus Evija)
	{"id": "lotar_evira", "name": "Lotar Evira", "class": "super", "top": 320.0, "accel": 11.0, "handling": 1.85, "grip": 2.45, "brake": 18.0,
		"mass": 1680.0, "len": 4.46, "wid": 2.0, "hgt": 1.12, "paint": 5, "engine": "ev", "gears": 1,
		"rim": "ten", "rim_color": "black", "caliper": Color(0.95, 0.75, 0.1)},
	# электрический гран-турер, 1900 л.с. (прототип — Pininfarina Battista)
	{"id": "pinnaforte_batista", "name": "Pinnaforte Batista", "class": "super", "top": 350.0, "accel": 13.0, "handling": 1.65, "grip": 2.25, "brake": 17.5,
		"mass": 2200.0, "len": 4.91, "wid": 2.04, "hgt": 1.21, "paint": 4, "engine": "ev", "gears": 1,
		"rim": "turbine", "rim_color": "silver", "caliper": Color(0.1, 0.4, 0.9)},
	# клиновидное купе с атмосферным V12 (прототип — Lamborghini Aventador SVJ)
	{"id": "lambrini_aventura", "name": "Lambrini Aventura SV", "class": "super", "top": 350.0, "accel": 10.2, "handling": 1.85, "grip": 2.45, "brake": 18.0,
		"mass": 1525.0, "len": 4.94, "wid": 2.1, "hgt": 1.14, "paint": 7, "engine": "v12", "gears": 7,
		"rim": "y5", "rim_color": "black", "caliper": Color(0.95, 0.78, 0.05)},
	# ---------------- ГИПЕР ----------------
	# гибридный гиперкар с V8 битурбо и активным крылом (прототип — McLaren P1)
	{"id": "mclane_p1", "name": "McLane P-One", "class": "hyper", "top": 350.0, "accel": 10.4, "handling": 1.9, "grip": 2.55,
		"brake": 18.5, "mass": 1490.0, "len": 4.59, "wid": 1.95, "hgt": 1.19, "paint": 6, "engine": "v8f", "gears": 7,
		"rim": "ten", "rim_color": "silver", "caliper": Color(0.75, 0.75, 0.78)},
	# трековый гиперкар с V8 битурбо и огромным крылом (прототип — Koenigsegg Jesko)
	{"id": "konigsvald_jesper", "name": "Konigsvald Jesper", "class": "hyper", "top": 480.0, "accel": 11.3, "handling": 1.95, "grip": 2.7, "brake": 19.0,
		"mass": 1420.0, "len": 4.61, "wid": 2.03, "hgt": 1.21, "paint": 9, "engine": "v8f", "gears": 9,
		"rim": "ten", "rim_color": "gunmetal", "caliper": Color(0.85, 0.1, 0.08)},
	# гиперкар-рекордсмен с V8 битурбо (прототип — Hennessey Venom F5)
	{"id": "hennerson_f5", "name": "Hennerson Venin F5", "class": "hyper", "top": 500.0, "accel": 10.8, "handling": 1.75, "grip": 2.45, "brake": 18.5,
		"mass": 1385.0, "len": 4.72, "wid": 1.96, "hgt": 1.12, "paint": 0, "engine": "v8tt", "gears": 7,
		"rim": "twin5", "rim_color": "black", "caliper": Color(0.85, 0.1, 0.08)},
]


static func get_car(id: String) -> Dictionary:
	for c in CARS:
		if c["id"] == id:
			return c
	return CARS[0]


static func index_of(id: String) -> int:
	for i in CARS.size():
		if CARS[i]["id"] == id:
			return i
	return 0


static func cars_of_class(cls: String) -> Array:
	var out := []
	for c in CARS:
		if c["class"] == cls:
			out.append(c)
	return out


static func has_car(id: String) -> bool:
	for c in CARS:
		if c["id"] == id:
			return true
	return false


static func class_info(cls: String) -> Dictionary:
	for c in CLASSES:
		if c["id"] == cls:
			return c
	return CLASSES[0]


static func paint_color(i: int) -> Color:
	return PAINTS[posmod(i, PAINTS.size())]


## Время разгона 0-100 км/ч по модели из Car.simulate (для экрана гаража).
static func zero_to_100(c: Dictionary) -> float:
	var v := 0.0
	var t := 0.0
	var top: float = c["top"] / 3.6
	var acc: float = c["accel"]
	while v < 27.78 and t < 30.0:
		var r := v / top
		v += acc * maxf(0.0, 1.0 - r * r) * 0.01
		t += 0.01
	return t
