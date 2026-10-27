extends Node2D
## Подбираемый предмет на воде: сундук (очки) или кубок (бессмертие).
## Кто первый тапнет, тот и забрал; через случайное время его может перехватить бот.

const C = preload("res://scripts/cfg.gd")

var kind := "chest"  # "chest" или "trophy"
var age := 0.0
var life := C.CHEST_LIFE
var bot_time := 3.0  # через сколько секунд предмет может перехватить бот


func _ready() -> void:
	z_index = 3
	scale = Vector2(C.ART_SCALE, C.ART_SCALE)  # фигура задана для поля 720×1280
	bot_time = randf_range(2.0, 9.0)
	life = C.TROPHY_LIFE if kind == "trophy" else C.CHEST_LIFE


func tick(delta: float) -> void:
	age += delta
	# мигает перед исчезновением
	visible = age < life - 1.5 or int(age * 8.0) % 2 == 0
	queue_redraw()


func _draw() -> void:
	var bob := sin(age * 4.0) * 3.0
	if kind == "trophy":
		# золотой кубок с сиянием
		draw_circle(Vector2(0, bob - 4), 24 + sin(age * 6.0) * 2.0, Color(1, 0.9, 0.3, 0.25))
		draw_colored_polygon(PackedVector2Array([Vector2(-14, -20 + bob), Vector2(14, -20 + bob), Vector2(9, -2 + bob), Vector2(-9, -2 + bob)]), Color(1, 0.8, 0.15))
		draw_arc(Vector2(-14, -13 + bob), 6, PI * 0.5, PI * 1.5, 10, Color(1, 0.8, 0.15), 3.0)
		draw_arc(Vector2(14, -13 + bob), 6, -PI * 0.5, PI * 0.5, 10, Color(1, 0.8, 0.15), 3.0)
		draw_rect(Rect2(-3, -2 + bob, 6, 8), Color(0.9, 0.7, 0.1))
		draw_rect(Rect2(-10, 6 + bob, 20, 5), Color(0.75, 0.55, 0.1))
		draw_line(Vector2(-6, -17 + bob), Vector2(-4, -7 + bob), Color(1, 1, 0.8, 0.9), 2.0)
		return
	draw_rect(Rect2(-24, -14 + bob, 48, 30), Color(0.55, 0.32, 0.12))
	draw_rect(Rect2(-24, -14 + bob, 48, 10), Color(0.7, 0.42, 0.16))
	draw_rect(Rect2(-24, -14 + bob, 48, 30), Color(1, 0.85, 0.2), false, 3.0)
	draw_rect(Rect2(-5, -6 + bob, 10, 10), Color(1, 0.85, 0.2))
