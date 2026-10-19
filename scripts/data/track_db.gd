class_name TrackDB
extends RefCounted

## Трассы задаются контрольными точками (метры, плоскость XZ).
## Через точки проводится замкнутый сплайн Катмулла-Рома. Точка 0 — линия старта.

const TOD_NAMES := ["День", "Закат", "Ночь"]
const DIFFICULTY_NAMES := ["Лёгкий", "Средний", "Сложный"]

const TRACKS := [
	{
		"id": "valley", "name": "Зелёная долина", "desc": "Классическая трасса среди сосен",
		"width": 18.0, "runoff": 12.0,
		"theme": {"ground": Color(0.3, 0.52, 0.2), "runoff": Color(0.38, 0.58, 0.26), "wall_a": Color(0.92, 0.92, 0.92),
			"wall_b": Color(0.1, 0.35, 0.85), "scenery": "pines", "mountain": Color(0.26, 0.4, 0.3), "water": false},
		"points": [Vector2(0, 0), Vector2(400, 0), Vector2(560, 40), Vector2(620, 160), Vector2(560, 280), Vector2(420, 300),
			Vector2(320, 380), Vector2(340, 520), Vector2(240, 620), Vector2(60, 600), Vector2(-40, 500), Vector2(-160, 480),
			Vector2(-300, 420), Vector2(-360, 280), Vector2(-300, 140), Vector2(-160, 50)],
	},
	{
		"id": "desert", "name": "Песчаная буря", "desc": "Скоростные прямые и шиканы в пустыне",
		"width": 20.0, "runoff": 14.0,
		"theme": {"ground": Color(0.85, 0.7, 0.45), "runoff": Color(0.78, 0.62, 0.4), "wall_a": Color(0.95, 0.95, 0.95),
			"wall_b": Color(0.9, 0.2, 0.1), "scenery": "cactus", "mountain": Color(0.7, 0.45, 0.3), "water": false},
		"points": [Vector2(0, 0), Vector2(600, 0), Vector2(800, 80), Vector2(860, 260), Vector2(780, 420), Vector2(600, 460),
			Vector2(450, 390), Vector2(300, 440), Vector2(150, 540), Vector2(-50, 520), Vector2(-200, 400), Vector2(-230, 200),
			Vector2(-150, 50)],
	},
	{
		"id": "snow", "name": "Снежный перевал", "desc": "Техничная трасса с серией поворотов",
		"width": 17.0, "runoff": 11.0,
		"theme": {"ground": Color(0.9, 0.92, 0.96), "runoff": Color(0.82, 0.85, 0.9), "wall_a": Color(0.85, 0.1, 0.1),
			"wall_b": Color(0.95, 0.95, 0.95), "scenery": "snow_pines", "mountain": Color(0.75, 0.8, 0.9), "water": false},
		"points": [Vector2(0, 0), Vector2(300, 0), Vector2(420, 50), Vector2(450, 180), Vector2(370, 270), Vector2(400, 380),
			Vector2(520, 420), Vector2(580, 540), Vector2(500, 660), Vector2(330, 660), Vector2(240, 560), Vector2(110, 570),
			Vector2(-10, 660), Vector2(-160, 620), Vector2(-200, 470), Vector2(-110, 360), Vector2(-200, 250), Vector2(-210, 110),
			Vector2(-120, 20)],
	},
	{
		"id": "city", "name": "Ночной город", "desc": "Уличная трасса среди небоскрёбов",
		"width": 17.0, "runoff": 9.0,
		"theme": {"ground": Color(0.22, 0.23, 0.26), "runoff": Color(0.3, 0.3, 0.33), "wall_a": Color(0.95, 0.95, 0.95),
			"wall_b": Color(0.15, 0.15, 0.17), "scenery": "buildings", "mountain": Color(0.2, 0.22, 0.3), "water": false, "night": true},
		"points": [Vector2(0, 0), Vector2(500, 0), Vector2(610, 40), Vector2(650, 150), Vector2(650, 400), Vector2(610, 510),
			Vector2(500, 550), Vector2(320, 550), Vector2(240, 500), Vector2(210, 400), Vector2(140, 340), Vector2(40, 350),
			Vector2(-30, 420), Vector2(-70, 510), Vector2(-170, 560), Vector2(-300, 520), Vector2(-350, 410), Vector2(-350, 130),
			Vector2(-300, 30), Vector2(-190, 0)],
	},
	{
		"id": "coast", "name": "Прибрежное кольцо", "desc": "Сверхскоростная трасса у моря",
		"width": 20.0, "runoff": 14.0,
		"theme": {"ground": Color(0.42, 0.6, 0.25), "runoff": Color(0.88, 0.82, 0.62), "wall_a": Color(0.95, 0.95, 0.95),
			"wall_b": Color(0.0, 0.6, 0.65), "scenery": "palms", "mountain": Color(0.35, 0.5, 0.35), "water": true},
		"points": [Vector2(0, 0), Vector2(700, 0), Vector2(950, 100), Vector2(1050, 300), Vector2(950, 520), Vector2(700, 600),
			Vector2(450, 560), Vector2(250, 640), Vector2(0, 620), Vector2(-200, 500), Vector2(-250, 300), Vector2(-180, 100)],
	},
	{
		"id": "polygon", "name": "Полигон", "desc": "Открытая площадка: дрифт-круг, слалом, свободная езда", "open": true,
		"width": 24.0, "runoff": 0.0, "size": 900.0,
		"theme": {"ground": Color(0.32, 0.5, 0.22), "runoff": Color(0.3, 0.3, 0.32), "wall_a": Color(1.0, 0.8, 0.1),
			"wall_b": Color(0.15, 0.15, 0.15), "scenery": "pines", "mountain": Color(0.3, 0.42, 0.32), "water": false},
		"points": [Vector2(-300, 300), Vector2(200, 300), Vector2(330, 220), Vector2(330, -220), Vector2(200, -320),
			Vector2(-200, -320), Vector2(-330, -200), Vector2(-330, 180)],
	},
]


static func get_track(id: String) -> Dictionary:
	for t in TRACKS:
		if t["id"] == id:
			return t
	return TRACKS[0]


static func index_of(id: String) -> int:
	for i in TRACKS.size():
		if TRACKS[i]["id"] == id:
			return i
	return 0


## Трассы для гонок (без открытого полигона).
static func race_tracks() -> Array:
	var out := []
	for t in TRACKS:
		if not t.get("open", false):
			out.append(t)
	return out
