extends Node2D
## Акула. Плывёт поперёк полос и по кругу меняет состояние видимости:
## тень -> пузыри -> плавник -> полная видимость (кусает!) -> снова тень.

const C = preload("res://scripts/cfg.gd")

enum V { SHADOW, BUBBLES, FIN, FULL }

## Виды траекторий (доли — SHARK_TRICKY_* в cfg.gd):
## STRAIGHT — почти прямо, WAVE — плавная волна, DIAGONAL — плывёт наискосок и отражается,
## ZIGZAG — резкий зигзаг, LOOP — петли, DASH — рывками (то медленно, то быстро).
enum P { STRAIGHT, WAVE, DIAGONAL, ZIGZAG, LOOP, DASH }

var game: Node2D
var zone := 0      # «родная» зона акулы (для квот)
var zone_u := 0.5  # положение внутри своей зоны: 0 — нижний край, 1 — верхний (зона едет вместе с валом)
var dir := 1.0
var speed := 80.0
var pattern: int = P.WAVE
var amp := 25.0     # размах отклонения (пиксели)
var freq := 1.0     # частота волны / петель
var drift := 0.0    # для DIAGONAL: вертикальная скорость, px/с
var base_x := 0.0
var face := 1.0     # куда смотрит морда: 1 вправо, -1 влево
var tilt := 0.0     # наклон корпуса по направлению движения
var vis: int = V.SHADOW
var vis_timer := 2.0
var age := 0.0


func setup(g: Node2D, z: int, u: float, from_left: bool) -> void:
	game = g
	zone = z
	zone_u = u
	dir = 1.0 if from_left else -1.0
	face = dir
	speed = _pick_type_speed() * randf_range(1.0 - C.SHARK_SPEED_SPREAD, 1.0 + C.SHARK_SPEED_SPREAD)
	base_x = -90.0 if from_left else C.W + 90.0
	pattern = _pick_pattern()
	age = randf_range(0.0, 10.0)  # разная начальная фаза, чтобы акулы не двигались синхронно
	match pattern:
		P.STRAIGHT:
			amp = randf_range(3.0, 9.0)  # лёгкое покачивание, чтобы не выглядело как по линейке
			freq = randf_range(0.8, 1.5)
		P.WAVE:
			amp = randf_range(22.5, 67.5)
			freq = randf_range(0.6, 1.5)
		P.DIAGONAL:
			drift = randf_range(52.5, 112.5) * (1.0 if randf() < 0.5 else -1.0)
		P.ZIGZAG:
			amp = randf_range(37.5, 75.0)
			freq = speed * randf_range(0.7, 1.2)  # скорость по вертикали, px/с — зависит от типа акулы
		P.LOOP:
			amp = randf_range(52.5, 82.5)       # радиус петли
			freq = speed / amp * randf_range(1.3, 1.8)  # быстрее поступательного — получаются петли
		P.DASH:
			amp = randf_range(7.5, 22.5)
			freq = randf_range(1.0, 1.8)
	vis = V.SHADOW
	vis_timer = randf_range(0.3, 1.5)  # выплывает в тени и вскоре начинает всплывать
	z_index = 1
	scale = Vector2(C.ART_SCALE, C.ART_SCALE)  # фигура акулы задана для поля 720×1280
	tick(0.0)

## Тип акулы (медленная / средняя / быстрая): доли зависят от сложности и характера зоны.
func _pick_type_speed() -> float:
	var weights := []
	for i in C.SHARK_SPEEDS.size():
		var w := lerpf(C.SHARK_TYPE_WEIGHTS_START[i], C.SHARK_TYPE_WEIGHTS_PEAK[i], game.difficulty)
		weights.append(w * C.SHARK_TYPE_ZONE_FACTOR[zone][i])
	return C.SHARK_SPEEDS[_pick_weighted(weights)]


## Траектория: с некоторой вероятностью «хитрая», иначе почти прямая.
func _pick_pattern() -> int:
	var tricky := minf(0.9, game.by_difficulty(C.SHARK_TRICKY_SHARE) * C.SHARK_TRICKY_ZONE_FACTOR[zone])
	if randf() >= tricky:
		return P.STRAIGHT
	return P.WAVE + _pick_weighted(C.SHARK_TRICKY_PATTERNS[zone])


func _pick_weighted(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return weights.size() - 1


func tick(delta: float) -> void:
	age += delta
	var old_pos := position
	var cur_speed := speed
	var off := Vector2.ZERO
	match pattern:
		P.STRAIGHT, P.WAVE:
			off.y = sin(age * freq) * amp
		P.DIAGONAL:
			# гуляет по своей зоне и чуть заплывает в соседние
			var h: float = game.zone_height(zone)
			zone_u += drift * delta / maxf(h, 1.0)
			if zone_u < -0.2 or zone_u > 1.2:
				drift = -drift
				zone_u = clampf(zone_u, -0.2, 1.2)
			off.y = sin(age * 2.0) * 9.0
		P.ZIGZAG:
			off.y = pingpong(age * freq, amp * 2.0) - amp
		P.LOOP:
			off = Vector2(sin(age * freq), -cos(age * freq)) * amp
			off.x *= dir
		P.DASH:
			cur_speed = speed * (0.4 + 1.2 * pow(maxf(0.0, sin(age * freq)), 2.0))
			off.y = sin(age * 3.0) * amp
	base_x += dir * cur_speed * delta
	var base_y: float = lerpf(game.zone_y[zone], game.zone_y[zone + 1], zone_u)
	position.x = base_x + off.x
	position.y = clampf(base_y + off.y, game.wall_y + 30.0, C.SHORE_Y - 30.0)

	# Поворачиваем акулу по направлению движения (но не строго вверх/вниз)
	var vel := position - old_pos
	if delta > 0.0 and vel.length() > 0.01:
		if absf(vel.x) > 0.3:
			face = signf(vel.x)
		var target_tilt := clampf(atan2(vel.y, absf(vel.x)), -0.7, 0.7)
		tilt = lerpf(tilt, target_tilt, minf(1.0, delta * 8.0))

	vis_timer -= delta
	if vis_timer <= 0.0:
		match vis:
			# Чем выше сложность, тем короче предупреждение и тем чаще акула всплывает
			V.SHADOW:
				vis = V.BUBBLES
				vis_timer = game.by_difficulty(C.SHARK_BUBBLES_TIME)
			V.BUBBLES:
				vis = V.FIN
				vis_timer = game.by_difficulty(C.SHARK_FIN_TIME)
			V.FIN:
				vis = V.FULL
				vis_timer = game.by_difficulty(C.SHARK_BITE_TIME)
			V.FULL:
				vis = V.SHADOW
				var calm_min: float = game.by_difficulty([C.SHARK_CALM_TIME[0][0], C.SHARK_CALM_TIME[1][0]])
				var calm_max: float = game.by_difficulty([C.SHARK_CALM_TIME[0][1], C.SHARK_CALM_TIME[1][1]])
				vis_timer = randf_range(calm_min, calm_max)
	queue_redraw()


func can_bite() -> bool:
	return vis == V.FULL


func is_visible_threat() -> bool:
	return vis != V.SHADOW


func is_gone() -> bool:
	return (dir > 0.0 and base_x > C.W + 180.0) or (dir < 0.0 and base_x < -180.0)


func _ellipse(rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, tilt * face, Vector2(face, 1.0))  # морда смотрит туда, куда плывёт
	match vis:
		V.SHADOW:
			_ellipse(40, 14, Color(0.02, 0.1, 0.2, 0.35))
		V.BUBBLES:
			_ellipse(40, 14, Color(0.02, 0.1, 0.2, 0.25))
			for i in 3:
				var off := Vector2(i * 14 - 10, -sin(age * 5.0 + i) * 8.0 - 4.0)
				draw_arc(off, 5.0 + i, 0, TAU, 12, Color.WHITE, 2.0)
		V.FIN:
			_ellipse(40, 14, Color(0.02, 0.1, 0.2, 0.3))
			draw_colored_polygon(PackedVector2Array([Vector2(-8, 8), Vector2(6, -22), Vector2(14, 8)]), Color(0.35, 0.4, 0.45))
			draw_arc(Vector2(3, 8), 18, PI * 0.1, PI * 0.9, 12, Color.WHITE, 2.0)
		V.FULL:
			draw_colored_polygon(PackedVector2Array([Vector2(-32, 0), Vector2(-54, -18), Vector2(-48, 0), Vector2(-54, 18)]), Color(0.4, 0.45, 0.5))
			_ellipse(40, 14, Color(0.45, 0.5, 0.56))
			draw_colored_polygon(PackedVector2Array([Vector2(-6, -10), Vector2(4, -28), Vector2(12, -10)]), Color(0.38, 0.43, 0.48))
			draw_circle(Vector2(26, -4), 3, Color.BLACK)
			draw_line(Vector2(18, 6), Vector2(38, 3), Color(0.8, 0.1, 0.1), 3.0)
			draw_arc(Vector2.ZERO, C.BITE_RADIUS / C.ART_SCALE, 0, TAU, 24, Color(1, 0.2, 0.2, 0.5), 2.0)
