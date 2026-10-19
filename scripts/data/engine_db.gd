class_name EngineDB
extends RefCounted

## Сгенерировано tools/gen_audio.py — не править вручную.
## *_rpm — обороты, на которых записан семпл (для транспонирования).

const ENGINES := {
	"i4t": {"name": "Рядная 4, турбо", "lo_rpm": 2600.0, "hi_rpm": 6800.0, "off_rpm": 4200.0, "idle": 950.0, "redline": 7300.0, "gears": 6, "turbo": true, "pops": true},
	"f6": {"name": "Оппозитная 6", "lo_rpm": 3000.0, "hi_rpm": 8200.0, "off_rpm": 5000.0, "idle": 900.0, "redline": 9000.0, "gears": 7, "turbo": false, "pops": true},
	"v8x": {"name": "V8 (кросс-плейн)", "lo_rpm": 2300.0, "hi_rpm": 6200.0, "off_rpm": 3800.0, "idle": 800.0, "redline": 6900.0, "gears": 6, "turbo": false, "pops": true},
	"v8f": {"name": "V8 битурбо (флэт-плейн)", "lo_rpm": 3000.0, "hi_rpm": 8000.0, "off_rpm": 5000.0, "idle": 950.0, "redline": 8600.0, "gears": 7, "turbo": true, "pops": true},
	"i6t": {"name": "Рядная 6, битурбо", "lo_rpm": 2600.0, "hi_rpm": 7000.0, "off_rpm": 4200.0, "idle": 850.0, "redline": 7600.0, "gears": 6, "turbo": true, "pops": true},
	"v10": {"name": "V10", "lo_rpm": 3200.0, "hi_rpm": 8600.0, "off_rpm": 5200.0, "idle": 1000.0, "redline": 9000.0, "gears": 7, "turbo": false, "pops": true},
	"v12": {"name": "V12", "lo_rpm": 3200.0, "hi_rpm": 8800.0, "off_rpm": 5400.0, "idle": 1000.0, "redline": 9300.0, "gears": 7, "turbo": false, "pops": false},
	"w16": {"name": "W16, четыре турбины", "lo_rpm": 2200.0, "hi_rpm": 6400.0, "off_rpm": 3800.0, "idle": 750.0, "redline": 7000.0, "gears": 7, "turbo": true, "pops": false},
	"ev": {"name": "Электро", "lo_rpm": 3000.0, "hi_rpm": 10000.0, "off_rpm": 6000.0, "idle": 0.0, "redline": 14000.0, "gears": 1, "turbo": false, "pops": false},
}
