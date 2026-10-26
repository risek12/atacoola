extends Node2D
## Сундук: кто первый тапнет, тот получает бонусные очки.

const C = preload("res://scripts/cfg.gd")

var age := 0.0
var bot_time := 3.0  # через сколько секунд сундук может перехватить бот


func _ready() -> void:
	z_index = 3
	scale = Vector2(C.ART_SCALE, C.ART_SCALE)  # фигура сундука задана для поля 720×1280
	bot_time = randf_range(2.0, 9.0)


func tick(delta: float) -> void:
	age += delta
	# мигает перед исчезновением
	visible = age < C.CHEST_LIFE - 1.5 or int(age * 8.0) % 2 == 0
	queue_redraw()


func _draw() -> void:
	var bob := sin(age * 4.0) * 3.0
	draw_rect(Rect2(-24, -14 + bob, 48, 30), Color(0.55, 0.32, 0.12))
	draw_rect(Rect2(-24, -14 + bob, 48, 10), Color(0.7, 0.42, 0.16))
	draw_rect(Rect2(-24, -14 + bob, 48, 30), Color(1, 0.85, 0.2), false, 3.0)
	draw_rect(Rect2(-5, -6 + bob, 10, 10), Color(1, 0.85, 0.2))
