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
		"theme": {"ground_tex": "grass.jpg", "ground_tint": Color(0.92, 0.95, 0.9), "runoff_tex": "gravel.jpg", "ground": Color(0.3, 0.52, 0.2), "runoff": Color(0.38, 0.58, 0.26), "wall_a": Color(0.92, 0.92, 0.92),
			"wall_b": Color(0.1, 0.35, 0.85), "scenery": "pines", "mountain": Color(0.26, 0.4, 0.3), "water": false},
		"points": [Vector2(0, 0), Vector2(380, 0), Vector2(470, 25), Vector2(495, 95), Vector2(450, 150), Vector2(370, 165),
			Vector2(320, 215), Vector2(330, 285), Vector2(395, 320), Vector2(420, 390), Vector2(370, 450), Vector2(280, 455),
			Vector2(220, 500), Vector2(200, 580), Vector2(120, 620), Vector2(30, 600), Vector2(-20, 540), Vector2(-10, 470),
			Vector2(-70, 420), Vector2(-150, 440), Vector2(-230, 420), Vector2(-280, 350), Vector2(-250, 270), Vector2(-300, 200),
			Vector2(-290, 110), Vector2(-220, 50), Vector2(-120, 20)],
	},
	{
		"id": "desert", "name": "Песчаная буря", "desc": "Скоростные прямые и шиканы в пустыне",
		"width": 20.0, "runoff": 14.0,
		"theme": {"ground_tex": "sand.jpg", "ground_tint": Color(1, 0.97, 0.92), "runoff_tex": "gravel.jpg", "runoff_tint": Color(1, 0.92, 0.8), "ground": Color(0.85, 0.7, 0.45), "runoff": Color(0.78, 0.62, 0.4), "wall_a": Color(0.95, 0.95, 0.95),
			"wall_b": Color(0.9, 0.2, 0.1), "scenery": "cactus", "mountain": Color(0.7, 0.45, 0.3), "water": false},
		"points": [Vector2(0, 0), Vector2(560, 0), Vector2(640, 25), Vector2(700, 0), Vector2(770, 30), Vector2(850, 130),
			Vector2(840, 250), Vector2(760, 300), Vector2(680, 265), Vector2(600, 300), Vector2(580, 380), Vector2(490, 450),
			Vector2(400, 420), Vector2(320, 460), Vector2(240, 530), Vector2(140, 520), Vector2(85, 455), Vector2(95, 370),
			Vector2(40, 315), Vector2(-50, 330), Vector2(-150, 390), Vector2(-240, 340), Vector2(-260, 240), Vector2(-215, 160),
			Vector2(-225, 80), Vector2(-140, 15)],
	},
	{
		"id": "snow", "name": "Снежный перевал", "desc": "Техничная трасса с серией поворотов",
		"width": 17.0, "runoff": 11.0,
		"theme": {"ground_tex": "snow.jpg", "ground_tint": Color(1, 1, 1), "runoff_tex": "snow.jpg", "runoff_tint": Color(0.92, 0.94, 0.98), "ground": Color(0.9, 0.92, 0.96), "runoff": Color(0.82, 0.85, 0.9), "wall_a": Color(0.85, 0.1, 0.1),
			"wall_b": Color(0.95, 0.95, 0.95), "scenery": "snow_pines", "mountain": Color(0.75, 0.8, 0.9), "water": false},
		"points": [Vector2(0, 0), Vector2(300, 0), Vector2(400, 40), Vector2(430, 140), Vector2(360, 210), Vector2(370, 300),
			Vector2(470, 340), Vector2(560, 300), Vector2(640, 360), Vector2(630, 470), Vector2(540, 520), Vector2(530, 610),
			Vector2(440, 680), Vector2(330, 660), Vector2(280, 580), Vector2(180, 560), Vector2(90, 620), Vector2(-20, 660),
			Vector2(-140, 620), Vector2(-180, 520), Vector2(-130, 440), Vector2(-190, 360), Vector2(-230, 270), Vector2(-160, 190),
			Vector2(-210, 100), Vector2(-120, 20)],
	},
	{
		"id": "city", "name": "Ночной город", "desc": "Уличная трасса среди небоскрёбов",
		"width": 17.0, "runoff": 9.0,
		"theme": {"ground_tex": "concrete.jpg", "ground_tint": Color(0.5, 0.5, 0.53), "runoff_tex": "asphalt.jpg", "runoff_tint": Color(0.5, 0.5, 0.52), "ground": Color(0.22, 0.23, 0.26), "runoff": Color(0.3, 0.3, 0.33), "wall_a": Color(0.95, 0.95, 0.95),
			"wall_b": Color(0.15, 0.15, 0.17), "scenery": "buildings", "mountain": Color(0.2, 0.22, 0.3), "water": false, "night": true},
		"points": [Vector2(0, 0), Vector2(460, 0), Vector2(560, 10), Vector2(600, 90), Vector2(600, 250), Vector2(680, 300),
			Vector2(700, 420), Vector2(620, 500), Vector2(500, 510), Vector2(440, 570), Vector2(330, 580), Vector2(250, 520),
			Vector2(230, 420), Vector2(150, 360), Vector2(50, 380), Vector2(0, 460), Vector2(-90, 520), Vector2(-210, 500),
			Vector2(-270, 420), Vector2(-230, 340), Vector2(-290, 270), Vector2(-340, 190), Vector2(-330, 80), Vector2(-260, 10),
			Vector2(-150, 0)],
	},
	{
		"id": "coast", "name": "Прибрежное кольцо", "desc": "Сверхскоростная трасса у моря",
		"width": 20.0, "runoff": 14.0,
		"theme": {"ground_tex": "grass.jpg", "ground_tint": Color(0.95, 1, 0.9), "runoff_tex": "sand.jpg", "ground": Color(0.42, 0.6, 0.25), "runoff": Color(0.88, 0.82, 0.62), "wall_a": Color(0.95, 0.95, 0.95),
			"wall_b": Color(0.0, 0.6, 0.65), "scenery": "palms", "mountain": Color(0.35, 0.5, 0.35), "water": true},
		"points": [Vector2(0, 0), Vector2(650, 0), Vector2(880, 60), Vector2(980, 200), Vector2(930, 320), Vector2(840, 330),
			Vector2(780, 400), Vector2(820, 500), Vector2(760, 600), Vector2(620, 610), Vector2(520, 540), Vector2(420, 600),
			Vector2(300, 640), Vector2(180, 600), Vector2(110, 520), Vector2(0, 560), Vector2(-130, 520), Vector2(-200, 420),
			Vector2(-170, 320), Vector2(-240, 240), Vector2(-230, 110), Vector2(-140, 20)],
	},
	{
		"id": "polygon", "name": "Полигон", "desc": "Открытая площадка: дрифт-круг, слалом, свободная езда", "open": true,
		"width": 24.0, "runoff": 0.0, "size": 900.0,
		"theme": {"ground_tex": "grass.jpg", "ground_tint": Color(0.9, 0.95, 0.9), "runoff_tex": "gravel.jpg", "ground": Color(0.32, 0.5, 0.22), "runoff": Color(0.3, 0.3, 0.32), "wall_a": Color(1.0, 0.8, 0.1),
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
