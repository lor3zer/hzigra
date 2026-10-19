class_name CarDB
extends RefCounted

## Каталог автомобилей. Все марки вымышленные.
## top      — максимальная скорость, км/ч
## accel    — базовое ускорение, м/с²
## handling — максимальная скорость поворота, рад/с
## grip     — боковое сцепление, g
## brake    — замедление при торможении, м/с²
## mass     — масса, кг (влияет на столкновения)
## len/wid/hgt — габариты кузова, м
## cabin    — длина кабины (доля длины), cab_off — смещение кабины (доля длины, + назад)
## spoiler  — 0 нет, 1 лип, 2 большое антикрыло

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

const CLASS_NAMES := {"sport": "Спорт", "hyper": "Гипер"}

const CARS := [
	# ---------------- СПОРТ ----------------
	{"id": "kestrel_rs", "name": "Kestrel RS", "class": "sport", "top": 258.0, "accel": 7.0, "handling": 1.8, "grip": 2.05, "brake": 15.0, "mass": 1320.0,
		"len": 4.3, "wid": 1.85, "hgt": 1.3, "cabin": 0.46, "cab_off": 0.02, "spoiler": 1, "paint": 0},
	{"id": "aurora_gt", "name": "Aurora GT", "class": "sport", "top": 290.0, "accel": 7.6, "handling": 1.65, "grip": 2.0, "brake": 15.5, "mass": 1560.0,
		"len": 4.6, "wid": 1.95, "hgt": 1.3, "cabin": 0.42, "cab_off": 0.08, "spoiler": 0, "paint": 8},
	{"id": "raptor_v8", "name": "Raptor V8", "class": "sport", "top": 305.0, "accel": 8.0, "handling": 1.55, "grip": 1.95, "brake": 15.0, "mass": 1650.0,
		"len": 4.75, "wid": 1.98, "hgt": 1.32, "cabin": 0.4, "cab_off": 0.12, "spoiler": 1, "paint": 2},
	{"id": "nordwind", "name": "Nordwind Coupe", "class": "sport", "top": 270.0, "accel": 7.3, "handling": 1.75, "grip": 2.1, "brake": 16.0, "mass": 1450.0,
		"len": 4.5, "wid": 1.88, "hgt": 1.34, "cabin": 0.48, "cab_off": 0.04, "spoiler": 0, "paint": 1},
	{"id": "sakura_tr", "name": "Sakura Turbo R", "class": "sport", "top": 280.0, "accel": 7.8, "handling": 1.85, "grip": 2.15, "brake": 15.5, "mass": 1400.0,
		"len": 4.45, "wid": 1.86, "hgt": 1.3, "cabin": 0.45, "cab_off": 0.03, "spoiler": 2, "paint": 4},
	{"id": "mistral_s", "name": "Mistral S", "class": "sport", "top": 265.0, "accel": 7.1, "handling": 1.95, "grip": 2.2, "brake": 16.5, "mass": 1180.0,
		"len": 4.1, "wid": 1.8, "hgt": 1.2, "cabin": 0.42, "cab_off": 0.0, "spoiler": 1, "paint": 9},
	{"id": "bolt_gte", "name": "Bolt GT-E", "class": "sport", "top": 262.0, "accel": 9.2, "handling": 1.6, "grip": 2.0, "brake": 15.0, "mass": 1900.0,
		"len": 4.8, "wid": 1.95, "hgt": 1.38, "cabin": 0.55, "cab_off": 0.02, "spoiler": 0, "paint": 4},
	{"id": "cobalt_400", "name": "Cobalt 400", "class": "sport", "top": 300.0, "accel": 7.9, "handling": 1.6, "grip": 2.0, "brake": 15.0, "mass": 1600.0,
		"len": 4.65, "wid": 1.95, "hgt": 1.28, "cabin": 0.4, "cab_off": 0.1, "spoiler": 1, "paint": 1},
	{"id": "tempesta", "name": "Tempesta 4C", "class": "sport", "top": 275.0, "accel": 7.4, "handling": 2.0, "grip": 2.25, "brake": 16.0, "mass": 1100.0,
		"len": 4.0, "wid": 1.86, "hgt": 1.18, "cabin": 0.4, "cab_off": -0.02, "spoiler": 0, "paint": 0},
	{"id": "ronin_gtr", "name": "Ronin GT-R", "class": "sport", "top": 315.0, "accel": 8.4, "handling": 1.7, "grip": 2.1, "brake": 16.0, "mass": 1740.0,
		"len": 4.7, "wid": 1.9, "hgt": 1.36, "cabin": 0.47, "cab_off": 0.04, "spoiler": 2, "paint": 8},
	# ---------------- ГИПЕР ----------------
	{"id": "vortex_x1", "name": "Vortex X1", "class": "hyper", "top": 350.0, "accel": 10.5, "handling": 1.8, "grip": 2.5, "brake": 18.0, "mass": 1420.0,
		"len": 4.6, "wid": 2.0, "hgt": 1.15, "cabin": 0.36, "cab_off": -0.04, "spoiler": 2, "paint": 6},
	{"id": "phantom_h", "name": "Phantom Hyper", "class": "hyper", "top": 380.0, "accel": 11.0, "handling": 1.7, "grip": 2.4, "brake": 18.0, "mass": 1500.0,
		"len": 4.7, "wid": 2.02, "hgt": 1.14, "cabin": 0.35, "cab_off": -0.02, "spoiler": 1, "paint": 3},
	{"id": "zenith_w16", "name": "Zenith W16", "class": "hyper", "top": 420.0, "accel": 11.5, "handling": 1.55, "grip": 2.3, "brake": 17.5, "mass": 1990.0,
		"len": 4.55, "wid": 2.04, "hgt": 1.2, "cabin": 0.38, "cab_off": 0.0, "spoiler": 1, "paint": 1},
	{"id": "chimera_ev", "name": "Chimera EV", "class": "hyper", "top": 360.0, "accel": 13.0, "handling": 1.75, "grip": 2.45, "brake": 18.0, "mass": 2150.0,
		"len": 4.75, "wid": 2.0, "hgt": 1.18, "cabin": 0.4, "cab_off": 0.0, "spoiler": 0, "paint": 9},
	{"id": "aether_u", "name": "Aether Ultra", "class": "hyper", "top": 395.0, "accel": 11.2, "handling": 1.7, "grip": 2.5, "brake": 18.5, "mass": 1450.0,
		"len": 4.65, "wid": 2.0, "hgt": 1.12, "cabin": 0.34, "cab_off": -0.05, "spoiler": 2, "paint": 4},
	{"id": "leviathan", "name": "Leviathan SS", "class": "hyper", "top": 410.0, "accel": 11.0, "handling": 1.6, "grip": 2.35, "brake": 17.5, "mass": 1750.0,
		"len": 4.8, "wid": 2.05, "hgt": 1.16, "cabin": 0.36, "cab_off": 0.0, "spoiler": 1, "paint": 0},
	{"id": "spectre_lm", "name": "Spectre LM", "class": "hyper", "top": 370.0, "accel": 10.8, "handling": 1.95, "grip": 2.7, "brake": 19.5, "mass": 1280.0,
		"len": 4.9, "wid": 2.0, "hgt": 1.08, "cabin": 0.32, "cab_off": -0.08, "spoiler": 2, "paint": 5},
	{"id": "tachyon_rr", "name": "Tachyon RR", "class": "hyper", "top": 400.0, "accel": 12.0, "handling": 1.75, "grip": 2.55, "brake": 18.5, "mass": 1550.0,
		"len": 4.7, "wid": 2.02, "hgt": 1.13, "cabin": 0.35, "cab_off": -0.03, "spoiler": 2, "paint": 2},
	{"id": "eclipse_v", "name": "Eclipse Venom", "class": "hyper", "top": 435.0, "accel": 11.8, "handling": 1.5, "grip": 2.25, "brake": 17.0, "mass": 1350.0,
		"len": 4.75, "wid": 2.0, "hgt": 1.12, "cabin": 0.34, "cab_off": -0.02, "spoiler": 1, "paint": 7},
	{"id": "nova_h", "name": "Nova Hyperion", "class": "hyper", "top": 390.0, "accel": 12.5, "handling": 1.85, "grip": 2.6, "brake": 19.0, "mass": 1600.0,
		"len": 4.6, "wid": 2.02, "hgt": 1.14, "cabin": 0.36, "cab_off": -0.04, "spoiler": 2, "paint": 1},
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
