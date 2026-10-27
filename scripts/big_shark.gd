extends Node2D
## Большая акула (ивент): в 3 раза больше обычной. Плывёт тенью под водой, а потом
## выпрыгивает с открытой пастью и кусает всех в овальной зоне. Перед прыжком тень темнеет
## и показывает красную зону укуса — успей уплыть.

const C = preload("res://scripts/cfg.gd")

enum V { SHADOW, JUMP }

var game: Node2D
var zone := 0      # «родная» зона (едет к берегу вместе с ней)
var zone_u := 0.5  # положение внутри зоны: 0 — нижний край, 1 — верхний
var dir := 1.0
var vis: int = V.SHADOW
var vis_timer := 3.0
var age := 0.0


func setup(g: Node2D, z: int, from_left: bool) -> void:
	game = g
	zone = z
	zone_u = randf_range(0.3, 0.7)
	dir = 1.0 if from_left else -1.0
	position.x = -300.0 if from_left else C.W + 300.0
	vis_timer = _shadow_time()
	z_index = 1
	scale = Vector2.ONE * C.ART_SCALE * C.BIG_SHARK_SCALE  # фигура задана как у обычной акулы для поля 720×1280
	tick(0.0)


func _shadow_time() -> float:
	var lo: float = game.by_difficulty([C.BIG_SHARK_SHADOW_TIME[0][0], C.BIG_SHARK_SHADOW_TIME[1][0]])
	var hi: float = game.by_difficulty([C.BIG_SHARK_SHADOW_TIME[0][1], C.BIG_SHARK_SHADOW_TIME[1][1]])
	return randf_range(lo, hi)


func tick(delta: float) -> void:
	age += delta
	if vis == V.SHADOW:
		position.x += dir * C.BIG_SHARK_SPEED * delta  # во время прыжка зависает на месте
	var base_y: float = lerpf(game.zone_y[zone], game.zone_y[zone + 1], zone_u)
	position.y = clampf(base_y, game.wall_y + 60.0, C.SHORE_Y - 60.0)
	vis_timer -= delta
	# не прыгаем (и не начинаем предупреждать), пока не заплыли на экран — иначе нечестно
	if vis == V.SHADOW and (position.x < 150.0 or position.x > C.W - 150.0):
		vis_timer = maxf(vis_timer, C.BIG_SHARK_WARN + 0.3)
	if vis_timer <= 0.0:
		if vis == V.SHADOW:
			vis = V.JUMP
			vis_timer = C.BIG_SHARK_JUMP_TIME
		else:
			vis = V.SHADOW
			vis_timer = _shadow_time()
	z_index = 4 if vis == V.JUMP else 1  # в прыжке — поверх серферов
	queue_redraw()


func is_jumping() -> bool:
	return vis == V.JUMP


## Скоро прыжок — тень темнеет (для отрисовки и для ботов).
func is_warning() -> bool:
	return vis == V.SHADOW and vis_timer < C.BIG_SHARK_WARN


## Попал ли серфер в овальную зону укуса.
func in_hit_zone(p: Vector2) -> bool:
	var d := p - position
	return pow(d.x / C.BIG_SHARK_HIT_RX, 2.0) + pow(d.y / C.BIG_SHARK_HIT_RY, 2.0) < 1.0


func is_gone() -> bool:
	return (dir > 0.0 and position.x > C.W + 350.0) or (dir < 0.0 and position.x < -350.0)


func _ellipse(rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


## Контур зоны укуса (в мировых px переводим в масштаб рисунка).
func _hit_outline(col: Color, width: float) -> void:
	var k := 1.0 / scale.x
	var pts := PackedVector2Array()
	for i in 41:
		var a := TAU * i / 40.0
		pts.append(Vector2(cos(a) * C.BIG_SHARK_HIT_RX * k, sin(a) * C.BIG_SHARK_HIT_RY * k))
	draw_polyline(pts, col, width)


func _draw() -> void:
	if vis == V.SHADOW:
		var warn := is_warning()
		var alpha := 0.35
		if warn:
			alpha = 0.45 + 0.2 * sin(age * 20.0)  # пульсирует перед прыжком
			_hit_outline(Color(1, 0.15, 0.1, 0.8), 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(dir, 1.0))
		_ellipse(40, 14, Color(0.02, 0.08, 0.18, alpha))
		draw_colored_polygon(PackedVector2Array([Vector2(-34, 0), Vector2(-52, -14), Vector2(-48, 0), Vector2(-52, 14)]), Color(0.02, 0.08, 0.18, alpha))
		return

	# прыжок: всплеск вокруг, тело выше воды, открытая пасть с зубами
	var k := 1.0 - absf(vis_timer / C.BIG_SHARK_JUMP_TIME * 2.0 - 1.0)  # 0 → 1 (вершина) → 0
	_hit_outline(Color(1, 0.1, 0.1, 0.9), 1.0)
	draw_arc(Vector2.ZERO, 30 + 10 * k, 0, TAU, 32, Color(1, 1, 1, 0.8), 1.2)
	draw_set_transform(Vector2(0, -6 * k), 0.0, Vector2(dir, 1.0) * (1.0 + 0.15 * k))
	draw_colored_polygon(PackedVector2Array([Vector2(-32, 0), Vector2(-54, -18), Vector2(-48, 0), Vector2(-54, 18)]), Color(0.38, 0.43, 0.48))
	_ellipse(40, 15, Color(0.45, 0.5, 0.56))
	draw_colored_polygon(PackedVector2Array([Vector2(-6, -10), Vector2(4, -28), Vector2(12, -10)]), Color(0.36, 0.41, 0.46))
	draw_colored_polygon(PackedVector2Array([Vector2(20, 0), Vector2(48, -16), Vector2(48, 16)]), Color(0.7, 0.05, 0.05))  # пасть
	for i in 4:
		draw_colored_polygon(PackedVector2Array([Vector2(28 + i * 5, -10 + i * 1.5), Vector2(31 + i * 5, -4), Vector2(34 + i * 5, -11 + i * 1.5)]), Color.WHITE)
		draw_colored_polygon(PackedVector2Array([Vector2(28 + i * 5, 10 - i * 1.5), Vector2(31 + i * 5, 4), Vector2(34 + i * 5, 11 - i * 1.5)]), Color.WHITE)
	draw_circle(Vector2(22, -7), 2.5, Color.BLACK)
