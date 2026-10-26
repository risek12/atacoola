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
var run_speed := 0.0
var returning := false  # уже побывал в воде: на пляже сносит обратно к лежаку
var touching_wall := false
var wall_touch_time := 0.0  # сколько секунд за раунд серфер касался вала (в сумме)
var score := 0.0    # сохранённые очки (на лежаке)
var unsaved := 0.0  # временные очки, набранные в воде: сохраняются на лежаке, при гибели — только 30%
var lives := C.LIVES
var respawn_timer := 0.0  # > 0 — серфер погиб и скоро вернётся на лежак
var bomb_cd := 0.0        # перезарядка бомбы, сек

# Поведение бота
var bot_going_out := false
var bot_rest := 0.0
var bot_tap_timer := 0.0
var bot_target_off := 97.0  # на сколько пикселей ниже вала держится бот
var bot_bank_at := 20.0     # набрав столько временных очков, бот плывёт сохраняться на лежак
var bot_flee := 0.0
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


func press() -> void:
	holding = true
	if state == S.LOUNGER or state == S.BEACH:
		state = S.BEACH
		run_speed += C.RUN_IMPULSE


func release() -> void:
	holding = false


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
	return -C.SWIM_SPEED if holding else C.DRIFT_SPEED


## Гибель в воде: DEATH_PENALTY (70%) временных очков сгорает, остальное идёт в счёт.
## Возвращает, сколько очков потеряно.
func die() -> float:
	var lost := unsaved * C.DEATH_PENALTY
	score += unsaved - lost
	unsaved = 0.0
	state = S.DEAD
	holding = false
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
	run_speed = 0.0
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
	if is_bot:
		_bot_think(delta)

	match state:
		S.BEACH:
			run_speed *= exp(-C.RUN_DECAY * delta)
			var back := C.BEACH_BACK if returning else 0.0
			position.y -= (run_speed - back) * delta
			if position.y <= C.SHORE_Y:
				state = S.WATER
				returning = true
				run_speed = 0.0
			elif position.y >= C.LOUNGER_Y:
				if returning:
					_arrive_lounger()
				else:
					position.y = C.LOUNGER_Y
		S.WATER:
			position.y += (-C.SWIM_SPEED if holding else C.DRIFT_SPEED) * delta
			position.y = maxf(position.y, game.wall_y + C.WALL_GAP)
			if position.y > C.SHORE_Y:
				state = S.BEACH

	# Касание вала: мигаем красным, а за WALL_TOUCH_LIMIT секунд в сумме — проигрыш
	touching_wall = state == S.WATER and position.y <= game.wall_y + C.WALL_GAP + 1.5
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
		var mult: int = game.points_mult_at(position.y)  # зона x1…x16 или золотая x32
		unsaved += mult * game.points_rate * delta
	queue_redraw()


func _arrive_lounger() -> void:
	position.y = C.LOUNGER_Y
	state = S.LOUNGER
	run_speed = 0.0
	returning = false
	if unsaved >= 1.0:
		game.on_saved(self, int(unsaved))
	score += unsaved
	unsaved = 0.0
	bot_going_out = false
	bot_rest = randf_range(0.3, 1.0)


func _plan_trip() -> void:
	# Цель — самая доходная зона x16, она всегда прямо под валом. Жаднее — ближе к валу.
	bot_target_off = lerpf(112.0, 87.0, bot_greed) + randf_range(-4.5, 4.5)
	bot_bank_at = randf_range(50.0, 120.0) * (0.5 + bot_greed)


func _bot_tap(delta: float) -> void:
	bot_tap_timer -= delta
	if bot_tap_timer <= 0.0:
		bot_tap_timer = randf_range(0.11, 0.2)
		press()
		release()


func _bot_think(delta: float) -> void:
	match state:
		S.LOUNGER:
			bot_rest -= delta
			if bot_rest <= 0.0:
				bot_going_out = true
				_plan_trip()
				_bot_tap(delta)
		S.BEACH:
			if bot_going_out:
				_bot_tap(delta)
		S.WATER:
			bot_look -= delta
			if bot_look <= 0.0:
				bot_look = 0.25
				if randf() < bot_awareness and game.danger_near(position, C.BOT_DANGER_DIST):
					bot_flee = randf_range(0.4, 0.8)
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
				var target_y: float = game.wall_y + bot_target_off
				if game.gold_active():
					# золотая зона — жадные боты плывут в неё
					var span: Vector2 = game.gold_span()
					if bot_greed > 0.85 or span.x - game.wall_y < bot_target_off:
						target_y = (span.x + span.y) * 0.5
				holding = position.y > target_y
				if unsaved >= bot_bank_at:
					bot_going_out = false  # набрал достаточно — плывёт сохраняться


func _draw() -> void:
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
	if wall_touch_time > 0.0:
		# полоска «запаса» касания вала
		var left := 1.0 - wall_touch_time / C.WALL_TOUCH_LIMIT
		draw_rect(Rect2(-25, 34, 50, 6), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(-25, 34, 50 * left, 6), Color(1, 0.3, 0.3))
