extends Node2D
## Серфер: игрок или бот. Пока рисуется простыми фигурами вместо спрайта.

const C = preload("res://scripts/cfg.gd")

enum S { LOUNGER, BEACH, WATER, DEAD }

var game: Node2D
var lane := 0
var is_bot := false
var display_name := ""
var color := Color.WHITE
var state: int = S.LOUNGER
var holding := false
var returning := false  # уже побывал в воде: на пляже сносит обратно к лежаку
var touching_wall := false
var wall_touch_time := 0.0  # сколько секунд за раунд серфер касался вала (в сумме)
var score := 0.0    # сохранённые очки (на лежаке)
var unsaved := 0.0  # временные очки, набранные в воде: сохраняются на лежаке, при гибели — только 30%
var lives := C.LIVES
var respawn_timer := 0.0  # > 0 — серфер погиб и скоро вернётся на лежак
var bomb_cd := 0.0        # перезарядка бомбы, сек
var invuln := 0.0         # > 0 — бессмертие от кубка, сколько секунд осталось
var rockets := C.ROCKET_START  # сколько ракет при себе (стартовый набор + покупка на пляже)
var back_holding := false # палец на пляже (нижней полосе), пока серфер в воде
var accel_t := 0.0        # сколько секунд палец держат подряд (для разгона до ×1,7)
var dash_v := 0.0         # скорость рывка (гаснет), px/с: минус — вперёд, плюс — назад
var dash_cd := 0.0        # перезарядка рывка
var last_vy := 0.0        # текущая вертикальная скорость в воде (для упреждения ботов)

# Поведение бота
var bot_going_out := false
var bot_rest := 0.0
var bot_target_off := 97.0  # запасная цель: на сколько пикселей ниже вала держится бот
var bot_target_zone := 4    # в какую зону плывёт бот (3 = x8 … 7 = x128)
var bot_trip_time := 0.0    # сколько секунд бот уже в воде в этом заплыве
var bot_trip_len := 15.0    # пробыв в воде столько секунд, бот плывёт сохраняться на лежак
var bot_flee := 0.0
var bot_tornado_wait := 0.0  # > 0 — бот пережидает торнадо у полосы
var bot_big_flee := 0.0      # > 0 — бот уплывает от большой акулы
var bot_strike_flee := 0.0   # > 0 — бот уплывает из-под молнии
var bot_strike_y := 0.0      # где ударит молния, от которой он уплывает
var bot_look := 0.0
var bot_awareness := 0.7
var bot_greed := 0.5

var _font: Font


func setup(g: Node2D, l: int, bot: bool) -> void:
	game = g
	lane = l
	is_bot = bot
	color = C.SURFER_COLORS[l]
	display_name = C.BOT_NAMES[l] if bot else "ТЫ"
	position = Vector2(C.lane_x(l), C.LOUNGER_Y)
	z_index = 2
	scale = Vector2(C.ART_SCALE, C.ART_SCALE)  # фигура серфера задана для поля 720×1280
	_font = ThemeDB.fallback_font
	if bot:
		bot_greed = randf_range(0.75, 1.0)
		bot_awareness = randf_range(0.5, 0.9)
		bot_rest = randf_range(0.0, 0.6)
		_plan_trip()


## Палец на экране: в воде — плывём к валу, на пляже — бежим к воде.
func press() -> void:
	holding = true
	back_holding = false
	if state == S.LOUNGER:
		state = S.BEACH


## Палец на пляже, пока серфер в воде: плывём к берегу.
func press_back() -> void:
	holding = false
	back_holding = true


func release() -> void:
	holding = false
	back_holding = false


## Рывок в воде: dir = -1 — вперёд (к валу), +1 — назад (к берегу).
func dash(dir: float) -> void:
	if state != S.WATER or dash_cd > 0.0:
		return
	dash_v = dir * C.DASH_SPEED
	dash_cd = C.DASH_COOLDOWN


func is_alive() -> bool:
	return state != S.DEAD


## Погиб и жизней больше нет — выбыл до конца раунда.
func is_out() -> bool:
	return state == S.DEAD and lives <= 0


func in_water() -> bool:
	return state == S.WATER


func on_lounger() -> bool:
	return state == S.LOUNGER


## Вертикальная скорость в воде (px/с): минус — к валу, плюс — к берегу. Нужна ботам для упреждения.
func velocity_y() -> float:
	if state != S.WATER:
		return 0.0
	return last_vy


## Гибель в воде: DEATH_PENALTY (70%) временных очков сгорает, остальное идёт в счёт.
## Возвращает, сколько очков потеряно.
func die() -> float:
	var lost := unsaved * C.DEATH_PENALTY
	score += unsaved - lost
	unsaved = 0.0
	state = S.DEAD
	holding = false
	back_holding = false
	_reset_swim()
	modulate = Color.WHITE
	lives -= 1
	if lives > 0:
		respawn_timer = C.RESPAWN_DELAY
	hide()
	return lost


## Новая жизнь: серфер снова на своём лежаке, счётчик касаний вала обнулён.
func _respawn() -> void:
	state = S.LOUNGER
	position = Vector2(C.lane_x(lane), C.LOUNGER_Y)
	returning = false
	holding = false
	touching_wall = false
	wall_touch_time = 0.0
	modulate = Color.WHITE
	bot_going_out = false
	bot_flee = 0.0
	bot_rest = randf_range(0.3, 1.0)
	show()
	queue_redraw()
	game.on_respawn(self)


func _reset_swim() -> void:
	accel_t = 0.0
	dash_v = 0.0


## Конец раунда: выжившие сохраняют все временные очки.
func finish() -> void:
	if state != S.DEAD:
		score += unsaved
		unsaved = 0.0
	holding = false


func tick(delta: float) -> void:
	if state == S.DEAD:
		if respawn_timer > 0.0:
			respawn_timer -= delta
			if respawn_timer <= 0.0:
				_respawn()
		return
	dash_cd = maxf(dash_cd - delta, 0.0)
	invuln = maxf(invuln - delta, 0.0)
	if is_bot:
		_bot_think(delta)

	match state:
		S.BEACH:
			# держишь палец — бежишь к воде; отпустил после заплыва — откатываешься к лежаку
			if holding:
				position.y -= C.BEACH_RUN_SPEED * delta
			elif returning:
				position.y += C.BEACH_BACK * delta
			if position.y <= C.SHORE_Y:
				state = S.WATER
				returning = true
			elif position.y >= C.LOUNGER_Y:
				if returning:
					_arrive_lounger()
				else:
					position.y = C.LOUNGER_Y
		S.WATER:
			# разгон от тапов спадает сам, если тапать перестали
			# держишь палец — плавно разгоняешься до ×SWIM_ACCEL_MAX; отпустил — сразу снос, разгон сброшен
			if holding or back_holding:
				accel_t += delta
			else:
				accel_t = 0.0
			var k := lerpf(1.0, C.SWIM_ACCEL_MAX, clampf(accel_t / C.SWIM_ACCEL_TIME, 0.0, 1.0))
			var vy := C.DRIFT_SPEED
			if holding:
				vy = -C.SWIM_SPEED * k     # палец на море — к валу
			elif back_holding:
				vy = C.DRIFT_SPEED * k     # палец на пляже — к берегу
			vy += dash_v
			dash_v *= exp(-C.DASH_DECAY * delta)
			last_vy = vy
			position.y += vy * delta
			position.y = maxf(position.y, game.wall_y + C.WALL_GAP)
			if position.y > C.SHORE_Y:
				state = S.BEACH
				_reset_swim()

	# Касание вала: мигаем красным, а за WALL_TOUCH_LIMIT секунд в сумме — проигрыш
	touching_wall = state == S.WATER and position.y <= game.wall_y + C.WALL_GAP + 1.5 and invuln <= 0.0
	if touching_wall:
		wall_touch_time += delta
		modulate = Color(1, 0.25, 0.25) if int(wall_touch_time * 10.0) % 2 == 0 else Color.WHITE
		if wall_touch_time >= C.WALL_TOUCH_LIMIT:
			modulate = Color.WHITE
			game.wash_away(self)
			return
	else:
		modulate = Color.WHITE

	if state == S.WATER:
		var mult: int = game.points_mult_at(position.y)  # зона x1…x128, в золотой зоне — x256
		unsaved += mult * game.points_rate * delta
	queue_redraw()


func _arrive_lounger() -> void:
	position.y = C.LOUNGER_Y
	state = S.LOUNGER
	returning = false
	if unsaved >= 1.0:
		game.on_saved(self, int(unsaved))
	score += unsaved
	unsaved = 0.0
	bot_going_out = false
	bot_rest = randf_range(0.3, 1.0)


func _plan_trip() -> void:
	# Цель — одна из зон x8…x128; чем жаднее бот, тем чаще он лезет в хардкорные зоны.
	bot_target_zone = clampi(3 + int(randf() * (0.6 + 0.4 * bot_greed) * 5.0), 3, C.ZONES - 1)
	bot_target_off = lerpf(112.0, 87.0, bot_greed) + randf_range(-4.5, 4.5)
	bot_trip_time = 0.0
	bot_trip_len = randf_range(10.0, 25.0)


## Куда плыть боту: середина выбранной зоны. Если её уже сжал вал — ближайшая живая зона выше,
## а если и их нет — просто чуть ниже вала.
func _bot_target_y() -> float:
	for z in range(bot_target_zone, C.ZONES):
		if game.zone_height(z) >= 60.0:
			return (game.zone_y[z] + game.zone_y[z + 1]) * 0.5
	return game.wall_y + bot_target_off


func _bot_think(delta: float) -> void:
	match state:
		S.LOUNGER:
			bot_rest -= delta
			if bot_rest <= 0.0:
				bot_going_out = true
				_plan_trip()
				press()  # бежит к воде, удерживая
		S.BEACH:
			holding = bot_going_out
		S.WATER:
			bot_look -= delta
			if bot_look <= 0.0:
				bot_look = 0.25
				if randf() < bot_awareness and game.danger_near(position, C.BOT_DANGER_DIST):
					bot_flee = randf_range(0.4, 0.8)
				if randf() < bot_awareness and game.big_shark_near(position, C.BOT_BIG_SHARK_DIST):
					bot_big_flee = randf_range(0.6, 1.0)
				var strike_y: float = game.lightning_threat_y(position)
				if not is_nan(strike_y) and randf() < bot_awareness:
					bot_strike_flee = 0.6
					bot_strike_y = strike_y
				if game.tornado_band_alive() and absf(position.y - game.tornado_y()) < 180.0 \
						and game.tornado_threat(position.x) and randf() < bot_awareness + 0.2:
					bot_tornado_wait = 0.35
			if bot_flee > 0.0:
				bot_flee -= delta
				holding = false
			elif position.y < game.wall_y + C.WALL_GAP + 37.5 and randf() < bot_awareness * 0.3:
				# бот замечает вал и отплывает от него (реакция не мгновенная)
				bot_flee = randf_range(0.4, 0.8)
				holding = false
			elif not bot_going_out:
				holding = false
			else:
				var target_y: float = _bot_target_y()
				if game.gold_active():
					# золотая зона — жадные боты плывут в неё
					var span: Vector2 = game.gold_span()
					var gold_mid := (span.x + span.y) * 0.5
					if bot_greed > 0.85 or absf(gold_mid - target_y) < 300.0:
						target_y = gold_mid
				holding = position.y > target_y
				bot_trip_time += delta
				if bot_trip_time >= bot_trip_len:
					bot_going_out = false  # нагулялся — плывёт сохраняться
			# большая акула рядом: уплываем от неё по вертикали (выше неё — к валу, ниже — к берегу)
			if bot_big_flee > 0.0:
				bot_big_flee -= delta
				if game.big_shark:
					holding = position.y < game.big_shark.position.y
			# под молнией: уплываем из круга по вертикали
			if bot_strike_flee > 0.0:
				bot_strike_flee -= delta
				holding = position.y < bot_strike_y
			# торнадо близко: на полосу не лезем, а с неё уходим в ближнюю сторону
			if bot_tornado_wait > 0.0:
				bot_tornado_wait -= delta
				holding = position.y < game.tornado_y()


func _draw() -> void:
	# На пляже и лежаке серфер рисуется вместе с пляжем, который «прилипает» к низу экрана,
	# и поверх него; в воде — под пляжем, как и всё море.
	if state == S.WATER:
		z_index = 2
	else:
		z_index = 6
		draw_set_transform(Vector2(0.0, game.beach_dy() / C.ART_SCALE))
	if state == S.WATER:
		# доска
		draw_rect(Rect2(-10, -28, 20, 56), Color(1.0, 0.95, 0.75))
		draw_rect(Rect2(-10, -28, 20, 56), Color(0, 0, 0, 0.4), false, 2.0)
		if holding:
			# след от гребка
			draw_line(Vector2(-12, 30), Vector2(-22, 48), Color.WHITE, 3.0)
			draw_line(Vector2(12, 30), Vector2(22, 48), Color.WHITE, 3.0)
	draw_circle(Vector2(0, 2), 14, color)
	draw_circle(Vector2(0, -14), 9, Color(0.95, 0.78, 0.6))
	if not is_bot:
		draw_arc(Vector2.ZERO, 30, 0, TAU, 32, Color.WHITE, 3.0)
	if invuln > 0.0 and (invuln > 1.0 or int(invuln * 8.0) % 2 == 0):
		# бессмертие от кубка: золотое сияние (мигает в последнюю секунду)
		draw_circle(Vector2.ZERO, 34, Color(1, 0.85, 0.2, 0.25))
		draw_arc(Vector2.ZERO, 36, 0, TAU, 32, Color(1, 0.85, 0.2, 0.9), 3.0)
	if wall_touch_time > 0.0:
		# полоска «запаса» касания вала
		var left := 1.0 - wall_touch_time / C.WALL_TOUCH_LIMIT
		draw_rect(Rect2(-25, 34, 50, 6), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(-25, 34, 50 * left, 6), Color(1, 0.3, 0.3))
