extends Node

## Корневой узел: переключает меню и сцену гонки.

const MenuScript := preload("res://scripts/ui/menu.gd")

var current: Node


func _ready() -> void:
	Game.main = self
	Net.race_start.connect(start_race)
	Net.back_to_lobby.connect(func(): show_menu("lobby"))
	Net.server_lost.connect(_on_server_lost)
	show_menu("main")


func _clear() -> void:
	get_tree().paused = false
	if current:
		current.queue_free()
		current = null


func show_menu(screen := "main") -> void:
	_clear()
	var m: Control = MenuScript.new()
	add_child(m)
	current = m
	m.open(screen)


func start_race(config: Dictionary, grid: Array) -> void:
	_clear()
	var r := Race.new()
	add_child(r)
	current = r
	r.setup(config, grid)


func _on_server_lost() -> void:
	if Game.pending_message == "":
		Game.pending_message = "Соединение с хостом потеряно"
	show_menu("mp")
