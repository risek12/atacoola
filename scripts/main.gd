extends Node2D
## Главный скрипт прототипа: раунд, вал волн, зоны очков, акулы, сундук и итоги.

const C = preload("res://scripts/cfg.gd")
const SurferScript = preload("res://scripts/surfer.gd")
const SharkScript = preload("res://scripts/shark.gd")
const ChestScript = preload("res://scripts/chest.gd")
const BigSharkScript = preload("res://scripts/big_shark.gd")

enum State { COUNTDOWN, PLAYING, RESULTS }

var state: int = State.COUNTDOWN
var countdown := 3.0
var message_timer := 0.0
var round_time := 0.0
var difficulty := 0.0  # 0 — начало раунда, 1 — пик (см. DIFFICULTY_PEAK_TIME)
var points_rate := 1.0  # базовая ставка очков/с, растёт за матч (см. POINTS_RATE)
var aiming := false         # игрок нажал «Бомба» и выбирает, куда её сбросить
var aim_pos := Vector2.ZERO # куда сейчас наведён прицел (координаты поля)
var aim_screen := Vector2.ZERO  # где прицел на экране (палец/мышь)
var aim_shown := false      # прицел уже наводили (мышью или пальцем) — можно рисовать круг
var aim_held := false       # палец на экране: бомба упадёт, когда его отпустят
var touch_down := false     # палец на экране (управление серфером)
var touch_start := Vector2.ZERO  # где палец коснулся экрана (для свайпа)
var touch_time := 0.0       # когда коснулся
var swiped := false         # в этом касании уже был свайп
var touch_on_beach := false # касание пришлось на пляж (нижнюю полосу), пока серфер в воде
var bombs: Array = []       # летящие бомбы: {target: Vector2, t: float}
var tornadoes: Array = []   # торнадо на полосе: {x, dir, warn} — warn > 0: ещё мигает стрелка у края
var tornado_timer := 0.0    # сколько осталось до следующего торнадо
var big_shark: Node2D = null  # большая акула (не больше одной за раз)
var big_shark_timer := 0.0
var strikes: Array = []     # молнии: {target, t} — t растёт до LIGHTNING_WARN, потом удар
var flashes: Array = []     # следы ударов для отрисовки: {target, life}
var lightning_timer := 0.0
var gold_times: Array = []  # когда (секунда раунда) появятся золотые зоны
var gold_timer := 0.0       # > 0 — золотая зона активна, столько секунд ей осталось
var gold_off := 0.0         # верх золотой зоны: на сколько пикселей ниже вала
var wall_y := C.WALL_START_Y
var zone_y: Array = []  # границы зон по Y (см. _update_zones)
var cam_scroll := 0.0   # на сколько px камера поднята над пляжем (см. _fit_to_screen)
var view_top := 0.0     # верх экрана в координатах поля
var time_passed := 0.0
var surfers: Array = []
var sharks: Array = []
var pickups: Array = []      # предметы на воде: сундуки и кубки
var chest_timer := 12.0
var trophy_timer := 12.0
var rocket_shots: Array = [] # летящие ракеты: {pos, dir, owner}
var shark_timer := 1.5
var death_marks: Array = []  # метки гибели: {lane, x, off} — off = на сколько ниже вала (едут вместе с ним)
var floaters: Array = []  # всплывающие надписи "+30", "Ам!"
var sparks: Array = []    # искры салюта
var firework_timer := 0.0
var winner_lane := -1
var coins := 0
var player: Node2D
var overlay: Node2D
var beach_layer: Node2D
var font: Font

@onready var countdown_label: Label = $HUD/CountdownLabel
@onready var timer_label: Label = $HUD/TimerLabel
@onready var coins_label: Label = $HUD/CoinsLabel
@onready var rate_label: Label = $HUD/RateLabel
@onready var bomb_button: Button = $UI/BombButton
@onready var rocket_button: Button = $UI/RocketButton
@onready var rockets_label: Label = $HUD/RocketsLabel
@onready var result_panel: Control = $HUD/ResultPanel
@onready var result_label: Label = $HUD/ResultPanel/ResultLabel
@onready var restart_button: Button = $HUD/ResultPanel/RestartButton


func _ready() -> void:
	font = ThemeDB.fallback_font
	overlay = Node2D.new()
	overlay.z_index = 10
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	beach_layer = Node2D.new()
	beach_layer.z_index = 5  # над морем, акулами и плывущими серферами; серферы на пляже — ещё выше
	add_child(beach_layer)
	beach_layer.draw.connect(_draw_beach)
	restart_button.pressed.connect(start_round)
	bomb_button.pressed.connect(_on_bomb_button)
	rocket_button.pressed.connect(_on_buy_rocket)
	_load_coins()
	start_round()


func start_round() -> void:
	for s in surfers:
		s.queue_free()
	for sh in sharks:
		sh.queue_free()
	for pk in pickups:
		pk.queue_free()
	pickups.clear()
	rocket_shots.clear()
	surfers.clear()
	sharks.clear()
	death_marks.clear()
	floaters.clear()
	sparks.clear()

	for i in C.LANES:
		var s := SurferScript.new()
		s.setup(self, i, i != C.PLAYER_LANE)
		add_child(s)
		surfers.append(s)
		if i == C.PLAYER_LANE:
			player = s

	round_time = 0.0
	difficulty = 0.0
	points_rate = C.POINTS_RATE[0]
	gold_timer = 0.0
	_schedule_gold()
	aiming = false
	bombs.clear()
	tornadoes.clear()
	tornado_timer = C.TORNADO_FIRST_DELAY
	if big_shark:
		big_shark.queue_free()
		big_shark = null
	big_shark_timer = C.BIG_SHARK_FIRST_DELAY
	strikes.clear()
	flashes.clear()
	lightning_timer = C.LIGHTNING_FIRST_DELAY
	wall_y = C.WALL_START_Y
	cam_scroll = 0.0
	_update_zones()
	shark_timer = 0.3
	chest_timer = randf_range(C.CHEST_FIRST_DELAY[0], C.CHEST_FIRST_DELAY[1])
	trophy_timer = randf_range(C.TROPHY_FIRST_DELAY[0], C.TROPHY_FIRST_DELAY[1])
	winner_lane = -1
	state = State.COUNTDOWN
	countdown = 3.0
	result_panel.hide()
	countdown_label.add_theme_font_size_override("font_size", 165)
	countdown_label.show()
	_update_coins_label()


func _process(delta: float) -> void:
	time_passed += delta
	match state:
		State.COUNTDOWN:
			countdown -= delta
			if countdown > 0.0:
				countdown_label.text = str(ceili(countdown))
			else:
				state = State.PLAYING
				_show_message("GO!", 0.8, 165)
		State.PLAYING:
			_update_round(delta)
		State.RESULTS:
			_update_fireworks(delta)

	if message_timer > 0.0:
		message_timer -= delta
		if message_timer <= 0.0 and state == State.PLAYING:
			countdown_label.hide()

	_fit_to_screen(delta)
	_update_effects(delta)
	timer_label.text = "%d" % ceili(C.ROUND_TIME - round_time)
	rate_label.text = "Очки ×%.1f" % points_rate
	_update_bomb_button()
	queue_redraw()
	beach_layer.queue_redraw()
	overlay.queue_redraw()
	bomb_button.position.y = 1641.0 + beach_dy()  # кнопки едут вместе с пляжем
	rocket_button.position.y = 1641.0 + beach_dy()
	_update_rocket_ui()


func _unhandled_input(event: InputEvent) -> void:
	if state != State.PLAYING:
		return
	if aiming:
		_aim_input(event)  # прицеливание работает и после гибели
		return
	if not player.is_alive():
		return
	# На телефоне касание пальцем приходит как нажатие левой кнопки мыши, а ведение пальцем — как движение мыши.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var p: Vector2 = (make_input_local(event) as InputEventMouseButton).position
			for pk in pickups:
				if pk.visible and p.distance_to(pk.position) < 90.0:
					_collect(pk, player)
					return
			touch_down = true
			touch_start = event.position
			touch_time = time_passed
			swiped = false
			touch_on_beach = player.in_water() and p.y > C.SHORE_Y + beach_dy()
			if touch_on_beach:
				player.press_back()  # палец на пляже — к берегу
			else:
				player.press()       # палец на море — к валу (на пляже — бег к воде)
		else:
			touch_down = false
			player.release()
	elif event is InputEventMouseMotion and touch_down and not swiped:
		# свайп: быстро провёл пальцем вверх/вниз — рывок, влево/вправо — ракета
		var d: Vector2 = event.position - touch_start
		if time_passed - touch_time <= C.SWIPE_MAX_TIME:
			if absf(d.y) >= C.SWIPE_MIN_DIST and absf(d.y) > absf(d.x):
				swiped = true
				if d.y < 0.0:
					player.dash(-1.0)  # вверх — рывок вперёд
				else:
					player.dash(1.0)   # вниз — рывок назад
					player.release()   # и больше не гребём вперёд
			elif absf(d.x) >= C.SWIPE_MIN_DIST and absf(d.x) > absf(d.y):
				swiped = true
				_fire_rocket(player, signf(d.x))
	elif event is InputEventKey and not event.echo:
		# клавиатура — для проверки на компьютере: пробел — плыть, ↑/W и ↓/S — рывки, ←/A и →/D — ракеты
		if event.keycode == KEY_SPACE:
			if event.pressed:
				player.press()
			else:
				player.release()
		elif event.pressed and (event.keycode == KEY_UP or event.keycode == KEY_W):
			player.dash(-1.0)
		elif event.pressed and (event.keycode == KEY_DOWN or event.keycode == KEY_S):
			player.dash(1.0)
		elif event.pressed and (event.keycode == KEY_LEFT or event.keycode == KEY_A):
			_fire_rocket(player, -1.0)
		elif event.pressed and (event.keycode == KEY_RIGHT or event.keycode == KEY_D):
			_fire_rocket(player, 1.0)


# ---------------- Раунд ----------------

func _update_round(delta: float) -> void:
	round_time += delta
	var progress := clampf(round_time / C.ROUND_TIME, 0.0, 1.0)
	difficulty = pow(clampf(round_time / C.DIFFICULTY_PEAK_TIME, 0.0, 1.0), C.DIFFICULTY_CURVE)
	points_rate = lerpf(C.POINTS_RATE[0], C.POINTS_RATE[1], progress)
	# Вал разгоняется: скорость плавно растёт до максимума к WALL_RAMP_TIME
	var wall_speed := lerpf(C.WALL_SPEED_START, C.WALL_SPEED_MAX, clampf(round_time / C.WALL_RAMP_TIME, 0.0, 1.0))
	wall_y = minf(wall_y + wall_speed * delta, C.WALL_END_Y)
	_update_zones()

	for s in surfers:
		s.tick(delta)
	for sh in sharks.duplicate():
		sh.tick(delta)
		# уплыла за край экрана или её зону вытеснили — убираем
		if sh.is_gone() or zone_height(sh.zone) < C.ZONE_MIN_HEIGHT:
			sharks.erase(sh)
			sh.queue_free()

	_update_gold(delta)
	_update_tornadoes(delta, progress)
	_update_big_shark(delta)
	_update_lightning(delta)
	_update_bombs(delta)
	_spawn_sharks(delta)
	_check_bites()
	_update_pickups(delta)
	_update_rockets(delta)

	if progress >= 1.0 or surfers.all(func(s): return s.is_out()):
		_end_round()


## Пересчёт границ зон. Зоны укладываются от вала вниз, каждая со своей исходной высотой,
## поэтому доходные зоны едут к берегу вместе с валом, а нижние сжимаются и исчезают.
## zone_y[i] — нижняя граница зоны i, zone_y[i + 1] — верхняя.
func _update_zones() -> void:
	zone_y.resize(C.ZONES + 1)
	zone_y[C.ZONES] = wall_y
	var y := wall_y
	for i in range(C.ZONES - 1, -1, -1):
		y = minf(y + C.ZONE_HEIGHTS[i], C.SHORE_Y)
		zone_y[i] = y
	zone_y[0] = C.SHORE_Y


## Серфер воскрес — убираем метку его прошлой гибели.
func on_respawn(s: Node2D) -> void:
	death_marks = death_marks.filter(func(d): return d["lane"] != s.lane)


## Серфер вернулся на лежак и сохранил временные очки.
func on_saved(s: Node2D, amount: int) -> void:
	_add_floater(Vector2(C.lane_x(s.lane), C.LOUNGER_Y - 60.0 + beach_dy()), "+%d" % amount, Color(0.4, 1.0, 0.4))


# ---------------- Золотая зона (всегда x256) ----------------

## Заранее выбираем 1–2 момента появления, разнося их по матчу.
func _schedule_gold() -> void:
	gold_times.clear()
	var count := randi_range(C.GOLD_COUNT[0], C.GOLD_COUNT[1])
	var span := (C.ROUND_TIME - 10.0 - C.GOLD_DURATION - 8.0) / count  # от 8 с до конца, минус запас
	for i in count:
		gold_times.append(8.0 + span * i + randf_range(0.0, span - C.GOLD_DURATION))


func gold_height() -> float:
	return C.GOLD_HEIGHT


func gold_active() -> bool:
	return gold_timer > 0.0


## Верх и низ золотой зоны по Y.
func gold_span() -> Vector2:
	var top := wall_y + gold_off
	return Vector2(top, minf(top + gold_height(), C.SHORE_Y))


func _update_gold(delta: float) -> void:
	if gold_active():
		gold_timer -= delta
		return
	if not gold_times.is_empty() and round_time >= gold_times[0]:
		gold_times.pop_front()
		gold_timer = C.GOLD_DURATION
		var room := C.SHORE_Y - wall_y - gold_height()
		gold_off = randf_range(0.0, maxf(room, 0.0))
		_add_floater(Vector2(C.W * 0.5, wall_y + gold_off + gold_height() * 0.5), "ЗОЛОТАЯ ЗОНА x%d!" % C.GOLD_POINTS, C.GOLD_COLOR)


# ---------------- Торнадо ----------------

## Центр красной полосы: граница зон x32 и x64 (нижний край x64).
func tornado_y() -> float:
	return minf(zone_y[6], C.SHORE_Y)


## Полоса ещё в море (а не прижата валом к берегу).
func tornado_band_alive() -> bool:
	return tornado_y() < C.SHORE_Y - 30.0


func tornado_speed() -> float:
	return lerpf(C.TORNADO_SPEED[0], C.TORNADO_SPEED[1], clampf(round_time / C.ROUND_TIME, 0.0, 1.0))


## Подходит ли торнадо к точке x в ближайшие ~0,9 с (для ботов: стоит ли сейчас лезть на полосу).
func tornado_threat(x: float) -> bool:
	var reach := C.TORNADO_RADIUS + 60.0
	for t in tornadoes:
		var ahead: float = (x - t["x"]) * t["dir"]  # >0 — точка впереди по ходу торнадо
		if ahead > -reach and ahead < reach + tornado_speed() * (0.9 + t["warn"]):
			return true
	return false


func _update_tornadoes(delta: float, progress: float) -> void:
	var speed := tornado_speed()
	# новое торнадо
	tornado_timer -= delta
	if tornado_timer <= 0.0 and tornado_band_alive():
		tornado_timer = lerpf(C.TORNADO_INTERVAL[0], C.TORNADO_INTERVAL[1], progress) * randf_range(0.8, 1.2)
		var dir := 1.0 if randf() < 0.5 else -1.0
		var start_x := -C.TORNADO_RADIUS if dir > 0.0 else C.W + C.TORNADO_RADIUS
		tornadoes.append({"x": start_x, "dir": dir, "warn": C.TORNADO_WARN})
	# полёт и гибель тех, кого задело
	var ty := tornado_y()
	for t in tornadoes.duplicate():
		if t["warn"] > 0.0:
			t["warn"] -= delta
			continue
		t["x"] += t["dir"] * speed * delta
		for s in surfers:
			if s.in_water() and absf(s.position.y - ty) < C.TORNADO_BAND * 0.5 + 21.0 \
					and absf(s.position.x - t["x"]) < C.TORNADO_RADIUS:
				_eliminate(s, "Вжух!", "Тебя унесло торнадо!")
		if t["x"] < -C.TORNADO_RADIUS * 2.0 or t["x"] > C.W + C.TORNADO_RADIUS * 2.0:
			tornadoes.erase(t)


# ---------------- Большая акула ----------------

func _update_big_shark(delta: float) -> void:
	if big_shark:
		big_shark.tick(delta)
		if big_shark.is_jumping():
			for s in surfers:
				if s.in_water() and big_shark.in_hit_zone(s.position):
					_eliminate(s, "Ам!!!", "Тебя проглотила\nбольшая акула!")
		if big_shark.is_gone() or zone_height(big_shark.zone) < C.ZONE_MIN_HEIGHT * 2.0:
			big_shark.queue_free()
			big_shark = null
		return
	big_shark_timer -= delta
	if big_shark_timer > 0.0:
		return
	big_shark_timer = by_difficulty(C.BIG_SHARK_INTERVAL) * randf_range(0.8, 1.2)
	# зона: над полосой торнадо — втрое чаще; сжатые валом зоны не берём
	var weights := []
	for i in C.ZONES:
		weights.append(C.BIG_SHARK_ZONE_WEIGHTS[i] if zone_height(i) >= 200.0 else 0.0)
	if weights.all(func(w): return w == 0.0):
		return
	big_shark = BigSharkScript.new()
	add_child(big_shark)
	big_shark.setup(self, _pick_weighted(weights), randf() < 0.5)

## Для ботов: большая акула рядом (видна тень, скоро прыжок или прыгает).
func big_shark_near(pos: Vector2, dist: float) -> bool:
	return big_shark != null and big_shark.position.distance_to(pos) < dist


# ---------------- Молния ----------------

## Где может ударить молния: вода между валом и полосой торнадо (зоны x64, x128). Vector2(верх, низ).
func lightning_area() -> Vector2:
	return Vector2(wall_y + 40.0, tornado_y() - C.TORNADO_BAND * 0.5 - 20.0)


func _update_lightning(delta: float) -> void:
	# новый удар
	lightning_timer -= delta
	var area := lightning_area()
	if lightning_timer <= 0.0 and tornado_band_alive() and area.y - area.x > 100.0:
		lightning_timer = by_difficulty(C.LIGHTNING_INTERVAL) * randf_range(0.8, 1.2)
		var target := Vector2(randf_range(60.0, C.W - 60.0), randf_range(area.x, area.y))
		var victims := surfers.filter(func(s): return s.in_water() and s.position.y > area.x and s.position.y < area.y)
		if not victims.is_empty() and randf() < C.LIGHTNING_AIM_CHANCE:
			# целимся в серфера — туда, где он будет к удару, и с небольшой ошибкой
			var v = victims.pick_random()
			target = v.position + Vector2(0.0, v.velocity_y() * C.LIGHTNING_WARN)
			target += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 50.0
			target.y = clampf(target.y, area.x, area.y)
		strikes.append({"target": target, "t": 0.0})
	# удары
	for st in strikes.duplicate():
		st["t"] += delta
		if st["t"] < C.LIGHTNING_WARN:
			continue
		strikes.erase(st)
		var pos: Vector2 = st["target"]
		for s in surfers:
			if s.in_water() and s.position.distance_to(pos) < C.LIGHTNING_RADIUS:
				_eliminate(s, "Бах!", "Тебя ударило\nмолнией!")
		flashes.append({"target": pos, "life": 0.3})
		for k in 20:  # искры
			var vel := Vector2.from_angle(TAU * k / 20.0) * randf_range(150.0, 350.0)
			sparks.append({"pos": pos, "vel": vel, "life": 0.5, "color": C.LIGHTNING_COLOR})
	for f in flashes.duplicate():
		f["life"] -= delta
		if f["life"] <= 0.0:
			flashes.erase(f)


## Для ботов: скоро ли рядом ударит молния. Возвращает Y места удара или NAN, если опасности нет.
func lightning_threat_y(pos: Vector2) -> float:
	for st in strikes:
		var target: Vector2 = st["target"]
		if target.distance_to(pos) < C.LIGHTNING_RADIUS + 60.0:
			return target.y
	return NAN


# ---------------- Бомба ----------------

## Кнопка видна, пока игрок сидит на лежаке или погиб (тогда бросок дороже).
func _update_bomb_button() -> void:
	var show_it: bool = state == State.PLAYING and (player.on_lounger() or not player.is_alive())
	bomb_button.visible = show_it
	if not show_it:
		aiming = false
		return
	if aiming:
		bomb_button.text = "Отмена"
		bomb_button.disabled = false
	elif player.bomb_cd > 0.0:
		bomb_button.text = "Бомба %d с" % ceili(player.bomb_cd)
		bomb_button.disabled = true
	else:
		bomb_button.text = "Бомба −%d" % bomb_cost(player)
		bomb_button.disabled = player.score < bomb_cost(player)


## Нажатие на кнопку: включает выбор места (повторное нажатие — отмена).
func _on_bomb_button() -> void:
	aiming = not aiming
	aim_shown = false
	aim_held = false


## Стоимость броска: после гибели — дороже (BOMB_DEAD_COST_MULT).
func bomb_cost(s: Node2D) -> int:
	return C.BOMB_COST * (C.BOMB_DEAD_COST_MULT if not s.is_alive() else 1)


## Прицеливание: круг взрыва следует за мышью или пальцем.
## Мышь: бросок по клику. Палец: прижал — видишь круг, водишь — двигаешь, отпустил — бросок.
func _aim_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		aim_screen = event.position
		aim_pos = (make_input_local(event) as InputEventMouseMotion).position
		aim_shown = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		aim_screen = event.position
		aim_pos = (make_input_local(event) as InputEventMouseButton).position
		aim_shown = true
		if event.pressed:
			aim_held = true
		elif aim_held:
			aim_held = false
			if _aim_ok(aim_pos):
				aiming = false
				_throw_bomb(player, aim_pos)
			else:
				_add_floater(aim_pos, "Только в море!", Color(0.9, 0.9, 0.9))


## Бомбу можно бросить только в море — между валом и линией прибоя
## (и не туда, где море сейчас закрыто «прилипшим» к низу экрана пляжем).
func _aim_ok(p: Vector2) -> bool:
	return p.y > wall_y and p.y < C.SHORE_Y + beach_dy()


## Бросок бомбы любым серфером (игроком или ботом).
func _throw_bomb(thrower: Node2D, target: Vector2) -> void:
	var cost := bomb_cost(thrower)
	var mult: int = C.BOMB_DEAD_REWARD_MULT if not thrower.is_alive() else C.BOMB_REWARD_MULT
	thrower.score -= cost
	thrower.bomb_cd = C.BOMB_COOLDOWN
	bombs.append({"target": target, "t": 0.0, "reward": cost * mult, "thrower": thrower})
	_add_floater(Vector2(C.lane_x(thrower.lane), C.LOUNGER_Y - 60.0 + beach_dy()), "−%d" % cost, Color(1, 0.6, 0.3))


## Боты тоже бросают бомбы: с лежака или после гибели, в серферов в воде (и в игрока).
## Целятся с упреждением — туда, где цель окажется к моменту взрыва, — но с ошибкой.
func _bot_bombs(delta: float) -> void:
	for bot in surfers:
		if not bot.is_bot or bot.is_out():
			continue
		var can_throw: bool = (bot.on_lounger() or not bot.is_alive()) and bot.bomb_cd <= 0.0 \
				and bot.score >= bomb_cost(bot)
		if not can_throw or randf() >= C.BOT_BOMB_CHANCE * delta:
			continue
		var targets := surfers.filter(func(s): return s != bot and s.in_water())
		if targets.is_empty():
			continue
		var victim = targets.pick_random()
		var lead := Vector2(0.0, victim.velocity_y() * C.BOMB_FALL_TIME)
		var miss := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * C.BOT_BOMB_AIM_ERROR
		var target: Vector2 = victim.position + lead + miss
		target.y = clampf(target.y, wall_y + 15.0, C.SHORE_Y - 15.0)
		_throw_bomb(bot, target)


func _update_bombs(delta: float) -> void:
	for s in surfers:
		s.bomb_cd = maxf(s.bomb_cd - delta, 0.0)
	_bot_bombs(delta)
	for b in bombs.duplicate():
		b["t"] += delta
		if b["t"] < C.BOMB_FALL_TIME:
			continue
		bombs.erase(b)
		var pos: Vector2 = b["target"]
		var thrower: Node2D = b["thrower"]
		var hits := 0
		for s in surfers:
			if s != thrower and s.in_water() and s.position.distance_to(pos) < C.BOMB_RADIUS:
				_eliminate(s, "Бум!", "Тебя подорвал\n%s!" % thrower.display_name)
				hits += 1
		if hits > 0:
			var reward: int = b["reward"] * hits
			thrower.score += reward
			_add_floater(Vector2(C.lane_x(thrower.lane), C.LOUNGER_Y - 60.0 + beach_dy()), "Попал! +%d" % reward, Color(0.4, 1.0, 0.4))
		# на месте взрыва — ник того, кто бросил
		_add_floater(pos + Vector2(0, -C.BOMB_RADIUS * 0.6), "Бомба: %s" % thrower.display_name, Color(1, 0.6, 0.2))
		for k in 28:  # вспышка взрыва
			var vel := Vector2.from_angle(TAU * k / 28.0) * randf_range(120.0, 300.0)
			sparks.append({"pos": pos, "vel": vel, "life": 0.6, "color": Color(1.0, randf_range(0.3, 0.7), 0.1)})


## Множитель очков в точке: зона x1…x128, а внутри золотой зоны — всегда x256.
func points_mult_at(y: float) -> int:
	var zone := zone_at(y)
	if zone < 0:
		return 0
	if gold_active():
		var span := gold_span()
		if y >= span.x and y <= span.y:
			return C.GOLD_POINTS
	return C.ZONE_POINTS[zone]


func zone_height(zone: int) -> float:
	return zone_y[zone] - zone_y[zone + 1]


func zone_at(y: float) -> int:
	if y >= C.SHORE_Y:
		return -1
	for i in range(C.ZONES - 1, -1, -1):
		if y <= zone_y[i]:
			return i
	return 0


func danger_near(pos: Vector2, dist: float) -> bool:
	for sh in sharks:
		if sh.is_visible_threat() and sh.position.distance_to(pos) < dist:
			return true
	return false


## Значение настройки при текущей сложности: pair = [в начале, на пике].
func by_difficulty(pair: Array) -> float:
	return lerpf(pair[0], pair[1], difficulty)


## Сколько акул сейчас должно быть в зоне.
func shark_quota(zone: int) -> int:
	if zone_height(zone) < C.ZONE_MIN_HEIGHT:
		return 0
	return roundi(lerpf(C.SHARK_QUOTA_START[zone], C.SHARK_QUOTA_PEAK[zone], difficulty))


func _spawn_sharks(delta: float) -> void:
	shark_timer -= delta
	if shark_timer > 0.0:
		return
	# Ищем зону, где сильнее всего не хватает акул до квоты (при равенстве — случайную)
	var counts := []
	counts.resize(C.ZONES)
	counts.fill(0)
	for sh in sharks:
		counts[sh.zone] += 1
	var best_zone := -1
	var best_lack := 0
	for i in C.ZONES:
		var lack: int = shark_quota(i) - counts[i]
		if lack > best_lack or (lack == best_lack and lack > 0 and randf() < 0.5):
			best_zone = i
			best_lack = lack
	if best_zone < 0:
		return  # все квоты заполнены
	shark_timer = by_difficulty(C.SHARK_SPAWN_INTERVAL) * randf_range(0.7, 1.3)
	var sh := SharkScript.new()
	add_child(sh)
	sh.setup(self, best_zone, randf_range(0.15, 0.85), randf() < 0.5)
	sharks.append(sh)


func _check_bites() -> void:
	for sh in sharks:
		if not sh.can_bite():
			continue
		for s in surfers:
			if s.in_water() and s.position.distance_to(sh.position) < C.BITE_RADIUS:
				_kill(s)


func _kill(s: Node2D) -> void:
	_eliminate(s, "Ам!", "Тебя съели!")


## Серфер слишком долго касался вала волн.
func wash_away(s: Node2D) -> void:
	_eliminate(s, "Смыло!", "Тебя смыло волной!")


func _eliminate(s: Node2D, floater_text: String, player_message: String) -> void:
	if s.invuln > 0.0:
		return  # бессмертие от кубка — никакие угрозы не страшны
	death_marks.append({"lane": s.lane, "x": s.position.x, "off": s.position.y - wall_y})
	var lost: float = s.die()
	_add_floater(s.position, "%s −%d" % [floater_text, int(lost)], Color(1, 0.3, 0.3))
	if s == player:
		if s.lives > 0:
			_show_message("%s\nВозврат через %d с" % [player_message, int(C.RESPAWN_DELAY)], 2.0)
		else:
			_show_message("%s\nЖизни кончились" % player_message, 2.5)


# ---------------- Ракеты ----------------

## Кнопка «Ракета» видна, пока игрок на пляже или на лежаке.
func _update_rocket_ui() -> void:
	rockets_label.text = "Ракеты: %d/%d" % [player.rockets, C.ROCKET_MAX]
	var on_land: bool = state == State.PLAYING and player.is_alive() and not player.in_water()
	rocket_button.visible = on_land
	if not on_land:
		return
	if player.rockets >= C.ROCKET_MAX:
		rocket_button.text = "Ракет %d/%d" % [player.rockets, C.ROCKET_MAX]
		rocket_button.disabled = true
	else:
		rocket_button.text = "Ракета −%d" % C.ROCKET_COST
		rocket_button.disabled = player.score < C.ROCKET_COST


func _on_buy_rocket() -> void:
	if player.rockets >= C.ROCKET_MAX or player.score < C.ROCKET_COST:
		return
	player.score -= C.ROCKET_COST
	player.rockets += 1
	_add_floater(Vector2(C.lane_x(player.lane), C.LOUNGER_Y - 60.0 + beach_dy()), "Ракета! −%d" % C.ROCKET_COST, Color(1, 0.6, 0.3))


## Выстрел ракетой вбок (dir = −1 влево, +1 вправо) — только из воды.
func _fire_rocket(s: Node2D, dir: float) -> void:
	if not s.in_water():
		return
	if s.rockets <= 0:
		_add_floater(s.position + Vector2(0, -60), "Нет ракет", Color(0.85, 0.85, 0.85))
		return
	s.rockets -= 1
	rocket_shots.append({"pos": s.position + Vector2(dir * 45.0, 0.0), "dir": dir, "owner": s})


## Полёт ракет: первая активная акула или соперник на пути — уничтожены, ракета тоже.
func _update_rockets(delta: float) -> void:
	for r in rocket_shots.duplicate():
		r["pos"] += Vector2(r["dir"] * C.ROCKET_SPEED * delta, 0.0)
		var pos: Vector2 = r["pos"]
		var shooter: Node2D = r["owner"]
		var hit := false
		for sh in sharks.duplicate():
			if sh.can_bite() and sh.position.distance_to(pos) < C.ROCKET_HIT + 20.0:
				sharks.erase(sh)
				sh.queue_free()
				_add_floater(pos + Vector2(0, -50), "Акула сбита!", Color(1, 0.6, 0.3))
				hit = true
				break
		if not hit and big_shark and big_shark.is_jumping() and big_shark.in_hit_zone(pos):
			big_shark.queue_free()
			big_shark = null
			_add_floater(pos + Vector2(0, -80), "Большая акула сбита!", Color(1, 0.6, 0.3))
			hit = true
		if not hit:
			for s in surfers:
				if s != shooter and s.in_water() and s.position.distance_to(pos) < C.ROCKET_HIT:
					_eliminate(s, "Ракета!", "Тебя сбил ракетой\n%s!" % shooter.display_name)
					hit = true
					break
		if hit:
			for k in 16:  # взрыв
				var vel := Vector2.from_angle(TAU * k / 16.0) * randf_range(120.0, 260.0)
				sparks.append({"pos": pos, "vel": vel, "life": 0.5, "color": Color(1.0, randf_range(0.4, 0.8), 0.2)})
		if hit or pos.x < -100.0 or pos.x > C.W + 100.0:
			rocket_shots.erase(r)


# ---------------- Сундуки и кубки ----------------

func _spawn_pickup(kind: String) -> void:
	var pk := ChestScript.new()
	pk.kind = kind
	pk.position = Vector2(randf_range(90.0, C.W - 90.0), randf_range(wall_y + 120.0, C.SHORE_Y - 60.0))
	add_child(pk)
	pickups.append(pk)


func _update_pickups(delta: float) -> void:
	# сундуки — по таймеру, не дожидаясь, пока исчезнет прошлый
	chest_timer -= delta
	if chest_timer <= 0.0:
		chest_timer = randf_range(C.CHEST_INTERVAL[0], C.CHEST_INTERVAL[1])
		_spawn_pickup("chest")
	# кубок — только когда прошлого уже нет
	if not pickups.any(func(pk): return pk.kind == "trophy"):
		trophy_timer -= delta
		if trophy_timer <= 0.0:
			_spawn_pickup("trophy")
	for pk in pickups.duplicate():
		pk.tick(delta)
		if pk.age >= pk.life:
			_remove_pickup(pk)
		elif pk.age >= pk.bot_time:
			var bots := surfers.filter(func(s): return s.is_bot and s.is_alive())
			if bots.is_empty():
				_remove_pickup(pk)
			else:
				_collect(pk, bots.pick_random())


## Серфер забрал предмет: сундук — очки, кубок — бессмертие.
func _collect(pk: Node2D, s: Node2D) -> void:
	if pk.kind == "trophy":
		s.invuln = C.TROPHY_INVULN
		_add_floater(pk.position, "%s: бессмертие %d с!" % [s.display_name, int(C.TROPHY_INVULN)], Color(1, 0.9, 0.3))
	else:
		var reward := chest_reward()
		s.score += reward
		_add_floater(pk.position, "%s +%d" % [s.display_name, reward], Color(1, 0.85, 0.2))
	_remove_pickup(pk)


## Награда за сундук: очки/с в зоне x128 прямо сейчас × CHEST_REWARD_MULT.
func chest_reward() -> int:
	return int(C.ZONE_POINTS[C.ZONES - 1] * points_rate * C.CHEST_REWARD_MULT)


func _remove_pickup(pk: Node2D) -> void:
	if pk.kind == "trophy":
		trophy_timer = randf_range(C.TROPHY_INTERVAL[0], C.TROPHY_INTERVAL[1])
	pickups.erase(pk)
	pk.queue_free()


func _end_round() -> void:
	state = State.RESULTS
	for s in surfers:
		s.finish()
		s.queue_redraw()
	var ranking := surfers.duplicate()
	ranking.sort_custom(func(a, b): return a.score > b.score)

	var lines := PackedStringArray(["ИТОГИ РАУНДА", ""])
	for i in ranking.size():
		var s = ranking[i]
		var prize := 0
		if i < C.PRIZES.size() and int(s.score) > 0:
			prize = C.PRIZES[i]
		var line := "%d. %s — %d" % [i + 1, s.display_name, int(s.score)]
		if prize > 0:
			line += "  (+%d монет)" % prize
		lines.append(line)
		if s == player and prize > 0:
			coins += prize
			_save_coins()

	if int(ranking[0].score) > 0:
		winner_lane = ranking[0].lane
	result_label.text = "\n".join(lines)
	result_panel.show()
	countdown_label.hide()
	_update_coins_label()


# ---------------- Эффекты и сообщения ----------------

## Крупная надпись по центру. Короткие («GO!») — огромным шрифтом, длинные — поменьше.
func _show_message(text: String, duration: float, font_size: int = 84) -> void:
	countdown_label.add_theme_font_size_override("font_size", font_size)
	countdown_label.text = text
	countdown_label.show()
	message_timer = duration


func _add_floater(pos: Vector2, text: String, col: Color) -> void:
	floaters.append({"pos": pos, "text": text, "life": 1.2, "color": col})


func _update_fireworks(delta: float) -> void:
	if winner_lane < 0:
		return
	firework_timer -= delta
	if firework_timer > 0.0:
		return
	firework_timer = 0.35
	var center := Vector2(C.lane_x(winner_lane) + randf_range(-75.0, 75.0), C.LOUNGER_Y - randf_range(150.0, 345.0))
	var col := Color.from_hsv(randf(), 0.8, 1.0)
	for k in 24:
		var vel := Vector2.from_angle(TAU * k / 24.0) * randf_range(180.0, 330.0)
		sparks.append({"pos": center, "vel": vel, "life": 1.0, "color": col})


func _update_effects(delta: float) -> void:
	for sp in sparks:
		sp["pos"] += sp["vel"] * delta
		sp["vel"] += Vector2(0, 300) * delta
		sp["life"] -= delta
	sparks = sparks.filter(func(sp): return sp["life"] > 0.0)
	for f in floaters:
		f["pos"] += Vector2(0, -60) * delta
		f["life"] -= delta
	floaters = floaters.filter(func(f): return f["life"] > 0.0)


func _update_coins_label() -> void:
	coins_label.text = "Монеты: %d" % coins


func _load_coins() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://save.cfg") == OK:
		coins = cf.get_value("player", "coins", 0)


func _save_coins() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "coins", coins)
	cf.save("user://save.cfg")


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


# ---------------- Рисование (заглушки вместо спрайтов) ----------------

## Режим «expand»: на длинном телефоне или широком экране видимая область больше 1080×1920.
## Поле ставим по центру по горизонтали и прижимаем к низу (пляж внизу),
## а лишнее место сверху и по бокам занимают вал, вода и песок (рисуются с запасом EXTRA).
const EXTRA := 3000.0


## Камера: поле выше экрана, поэтому вид сдвигается вверх за игроком (cam_scroll — на сколько px).
## Пока игрок на пляже, на лежаке или погиб — камера внизу, у пляжа.
func _fit_to_screen(delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	var base_y := vp.y - C.H  # смещение, при котором низ поля совпадает с низом экрана
	var max_scroll := maxf(-(wall_y - C.CAM_WALL_MARGIN) - base_y, 0.0)  # выше вала с запасом не поднимаемся
	if aiming and aim_shown:
		# прицел у края экрана — камера едет туда сама
		var push := 0.0
		if aim_screen.y < C.AIM_EDGE_TOP:
			push = 1.0 - aim_screen.y / C.AIM_EDGE_TOP
		elif aim_screen.y > vp.y - C.AIM_EDGE_BOTTOM:
			push = -(aim_screen.y - (vp.y - C.AIM_EDGE_BOTTOM)) / C.AIM_EDGE_BOTTOM
		cam_scroll = clampf(cam_scroll + clampf(push, -1.0, 1.0) * C.AIM_SCROLL_SPEED * delta, 0.0, max_scroll)
	elif bombs.any(func(b): return b["thrower"] == player):
		# бомба игрока ещё летит — камера ждёт на месте броска, чтобы был виден взрыв
		cam_scroll = clampf(cam_scroll, 0.0, max_scroll)
	else:
		var target := 0.0
		if state == State.PLAYING and player.in_water():
			target = vp.y * C.CAM_PLAYER_AT - player.position.y - base_y
		target = clampf(target, 0.0, max_scroll)
		cam_scroll = lerpf(cam_scroll, target, 1.0 - exp(-C.CAM_SMOOTH * delta))
	var offset := Vector2((vp.x - C.W) * 0.5, base_y + cam_scroll)
	get_viewport().canvas_transform = Transform2D(0.0, offset)
	view_top = -offset.y  # верх экрана в координатах поля
	if aiming:
		aim_pos = aim_screen - offset  # прицел остаётся под пальцем, а поле едет под ним


## Пляж «прилипает» к низу экрана: когда камера поднята, полоса пляжа с лежаками
## рисуется выше на cam_scroll и накрывает нижний край моря. Берег в игре при этом не двигается.
func beach_dy() -> float:
	return -cam_scroll


func _draw() -> void:
	# зоны доходности
	for i in C.ZONES:
		var y_bottom: float = zone_y[i]
		var y_top: float = zone_y[i + 1]
		if y_bottom - y_top < 1.0:
			continue  # зону полностью вытеснили
		draw_rect(Rect2(-EXTRA, y_top, C.W + EXTRA * 2.0, y_bottom - y_top), C.ZONE_COLORS[i])
		var mid := (y_top + y_bottom) * 0.5
		if y_bottom - y_top < 45.0:
			continue  # зона сжалась валом — подпись не влезает
		draw_circle(Vector2(45, mid), 33, Color(1, 1, 1, 0.25))
		var label_size := 33 if C.ZONE_POINTS[i] < 100 else 26  # «x128» шире — шрифт поменьше
		draw_string(font, Vector2(12, mid + 10), "x%d" % C.ZONE_POINTS[i], HORIZONTAL_ALIGNMENT_CENTER, 66, label_size, Color.WHITE)

	# золотая зона x256 (мигает в последние 2 секунды)
	if gold_active() and (gold_timer > 2.0 or int(gold_timer * 6.0) % 2 == 0):
		var span := gold_span()
		var shimmer := 0.5 + 0.1 * sin(time_passed * 6.0)
		draw_rect(Rect2(0, span.x, C.W, span.y - span.x), Color(C.GOLD_COLOR, shimmer))
		draw_rect(Rect2(0, span.x, C.W, span.y - span.x), Color(1, 0.95, 0.6), false, 4.5)
		var gmid := (span.x + span.y) * 0.5
		draw_circle(Vector2(45, gmid), 33, Color(0.55, 0.35, 0.0, 0.8))
		draw_string(font, Vector2(12, gmid + 10), "x%d" % C.GOLD_POINTS, HORIZONTAL_ALIGNMENT_CENTER, 66, 26, Color.WHITE)
		draw_string(font, Vector2(C.W - 105, gmid + 15), "%d" % ceili(gold_timer), HORIZONTAL_ALIGNMENT_CENTER, 75, 42, Color.WHITE)

	# красная полоса торнадо на границе x32 и x64
	if tornado_band_alive():
		var ty := tornado_y()
		var band := Rect2(-EXTRA, ty - C.TORNADO_BAND * 0.5, C.W + EXTRA * 2.0, C.TORNADO_BAND)
		draw_rect(band, Color(0.95, 0.1, 0.1, 0.35 + 0.1 * sin(time_passed * 4.0)))
		draw_line(Vector2(-EXTRA, band.position.y), Vector2(C.W + EXTRA, band.position.y), Color(1, 0.35, 0.35, 0.9), 3.0)
		draw_line(Vector2(-EXTRA, band.end.y), Vector2(C.W + EXTRA, band.end.y), Color(1, 0.35, 0.35, 0.9), 3.0)

	# полоса игрока
	draw_rect(Rect2(C.LANE_W * C.PLAYER_LANE, wall_y, C.LANE_W, C.SHORE_Y - wall_y), Color(1, 1, 1, 0.08))

	# рябь на воде
	var y := wall_y + 90.0
	while y < C.SHORE_Y - 30.0:
		_draw_wave_line(self, y, 6.0, Color(1, 1, 1, 0.18), 3.0, y * 0.067)
		y += 105.0

	# вал волн
	draw_rect(Rect2(-EXTRA, -EXTRA, C.W + EXTRA * 2.0, wall_y + EXTRA), Color(0.87, 0.95, 0.98))
	for k in 5:
		_draw_wave_line(self, wall_y - k * 33.0, 15.0 + k * 3.0, Color(0.5, 0.71, 0.8), 4.5, k * 1.3)

	# места гибели
	for d in death_marks:
		var m := Vector2(d["x"], wall_y + d["off"])
		if m.y > C.SHORE_Y - 15.0:
			continue  # вал вытолкнул метку на берег — не рисуем
		draw_circle(m, 24, Color(1, 0.3, 0.2, 0.8))
		draw_line(m + Vector2(-13.5, -13.5), m + Vector2(13.5, 13.5), Color.WHITE, 6.0)
		draw_line(m + Vector2(-13.5, 13.5), m + Vector2(13.5, -13.5), Color.WHITE, 6.0)


## Пляж с лежаками — отдельный слой поверх моря, акул и плывущих серферов.
## Сдвинут на beach_dy(), чтобы всегда оставаться внизу экрана.
func _draw_beach() -> void:
	var b := beach_layer
	var dy := beach_dy()
	var shore := C.SHORE_Y + dy
	var ly := C.LOUNGER_Y + dy
	# песок и линия прибоя
	b.draw_rect(Rect2(-EXTRA, shore, C.W + EXTRA * 2.0, C.H - C.SHORE_Y + EXTRA), Color(0.95, 0.86, 0.65))
	_draw_wave_line(b, shore, 9.0, Color(1, 1, 1, 0.85), 6.0, 0.0)

	# лежаки со счётом
	for s in surfers:
		var cx := C.lane_x(s.lane)
		var r := Rect2(cx - 78, ly + 15, 156, 105)
		b.draw_rect(r, Color(0.9, 0.62, 0.23) if s == player else Color(0.79, 0.42, 0.23))
		b.draw_rect(r, Color(0, 0, 0, 0.5), false, 4.5)
		b.draw_string(font, Vector2(cx - 78, ly + 78), str(int(s.score)), HORIZONTAL_ALIGNMENT_CENTER, 156, 45, Color.WHITE)
		b.draw_string(font, Vector2(cx - 78, ly + 111), s.display_name, HORIZONTAL_ALIGNMENT_CENTER, 156, 24, Color(0.15, 0.1, 0.05))
		# временные очки: набраны в воде, но ещё не сохранены на лежаке
		if s.unsaved >= 1.0:
			var tag := Rect2(cx - 60, ly - 39, 120, 51)
			b.draw_rect(tag, Color(0, 0, 0, 0.55))
			b.draw_string(font, Vector2(cx - 60, ly), "+%d" % int(s.unsaved), HORIZONTAL_ALIGNMENT_CENTER, 120, 39, Color(1, 0.95, 0.3))
		# жизни: красные точки — оставшиеся, серые — потерянные
		for i in C.LIVES:
			var dot_col := Color(0.9, 0.15, 0.15) if i < s.lives else Color(0.3, 0.3, 0.3, 0.6)
			b.draw_circle(Vector2(cx - 63 + i * 21, ly + 30), 7.5, dot_col)
		if s.respawn_timer > 0.0:
			# отсчёт до возвращения на лежак
			b.draw_circle(Vector2(cx, ly - 12), 33, Color(0, 0, 0, 0.6))
			b.draw_string(font, Vector2(cx - 33, ly + 3), str(ceili(s.respawn_timer)), HORIZONTAL_ALIGNMENT_CENTER, 66, 42, Color.WHITE)
		elif s.is_out():
			b.draw_rect(r, Color(0, 0, 0, 0.45))  # выбыл — лежак затемнён


func _draw_wave_line(ci: CanvasItem, y: float, amp: float, col: Color, width: float, phase: float) -> void:
	var pts := PackedVector2Array()
	var x := -EXTRA
	while x <= C.W + EXTRA:
		pts.append(Vector2(x, y + sin(x * 0.02 + time_passed * 2.0 + phase) * amp))
		x += 18.0
	ci.draw_polyline(pts, col, width, true)


## Летящие бомбы: тонкий круг — зона взрыва, а толстое кольцо сжимается к центру —
## когда оно сойдётся в точку, бомба взорвётся. Сверху падает сама бомба.
func _draw_bombs() -> void:
	for b in bombs:
		var target: Vector2 = b["target"]
		var k: float = b["t"] / C.BOMB_FALL_TIME
		overlay.draw_circle(target, C.BOMB_RADIUS, Color(1, 0.15, 0.1, 0.12))
		overlay.draw_arc(target, C.BOMB_RADIUS, 0, TAU, 40, Color(1, 0.2, 0.15, 0.7), 3.0)
		var ring := lerpf(C.BOMB_RADIUS * 1.8, 0.0, k)
		if ring > 3.0:
			overlay.draw_arc(target, ring, 0, TAU, 40, Color(1, 0.1, 0.05, 0.6 + 0.4 * k), 6.0)
		overlay.draw_circle(target, 6, Color(1, 0.2, 0.1))
		var pos := Vector2(target.x, lerpf(-60.0, target.y, k * k))
		overlay.draw_circle(pos, 18, Color(0.1, 0.1, 0.1))
		overlay.draw_circle(pos + Vector2(9, -18), 4.5, Color(1, 0.7, 0.1))


## Подсказка в режиме прицеливания: пляж затемнён, сверху надпись.
func _draw_aiming() -> void:
	overlay.draw_rect(Rect2(0, C.SHORE_Y + beach_dy(), C.W, C.LOUNGER_Y - C.SHORE_Y - 45.0), Color(0, 0, 0, 0.25))
	var y := maxf(wall_y, view_top + 160.0) + 45.0  # под верхней панелью, даже если вал выше экрана
	overlay.draw_rect(Rect2(165, y - 42, 750, 60), Color(0, 0, 0, 0.55))
	overlay.draw_string(font, Vector2(165, y), "Наведи и отпусти — туда упадёт бомба", HORIZONTAL_ALIGNMENT_CENTER, 750, 36, Color(1, 0.85, 0.4))
	if not aim_shown:
		return
	# круг взрыва под прицелом: оранжевый — можно бросить, серый с крестом — нельзя (пляж)
	if _aim_ok(aim_pos):
		overlay.draw_circle(aim_pos, C.BOMB_RADIUS, Color(1, 0.45, 0.1, 0.25))
		overlay.draw_arc(aim_pos, C.BOMB_RADIUS, 0, TAU, 40, Color(1, 0.55, 0.15, 0.95), 4.5)
		overlay.draw_line(aim_pos + Vector2(-18, 0), aim_pos + Vector2(18, 0), Color.WHITE, 3.0)
		overlay.draw_line(aim_pos + Vector2(0, -18), aim_pos + Vector2(0, 18), Color.WHITE, 3.0)
	else:
		overlay.draw_arc(aim_pos, C.BOMB_RADIUS, 0, TAU, 40, Color(0.7, 0.7, 0.7, 0.8), 3.0)
		overlay.draw_line(aim_pos + Vector2(-21, -21), aim_pos + Vector2(21, 21), Color(0.9, 0.2, 0.2), 6.0)
		overlay.draw_line(aim_pos + Vector2(-21, 21), aim_pos + Vector2(21, -21), Color(0.9, 0.2, 0.2), 6.0)


## Торнадо: перед вылетом у края полосы мигает красная стрелка, потом летит воронка
## (стопка вращающихся колец, сужающихся книзу).
func _draw_tornadoes() -> void:
	var ty := tornado_y()
	for t in tornadoes:
		var dir: float = t["dir"]
		if t["warn"] > 0.0:
			if int(t["warn"] * 10.0) % 2 == 0:
				var edge := 30.0 if dir > 0.0 else C.W - 30.0
				var tip := Vector2(edge + dir * 40.0, ty)
				overlay.draw_colored_polygon(PackedVector2Array([
					tip, Vector2(edge - dir * 10.0, ty - 30.0), Vector2(edge - dir * 10.0, ty + 30.0)]), Color(1, 0.15, 0.1, 0.95))
			continue
		var base := Vector2(t["x"], ty + C.TORNADO_BAND * 0.5)
		for i in 7:
			var k := i / 6.0
			var r := lerpf(12.0, C.TORNADO_RADIUS + 9.0, k)
			var c := base + Vector2(sin(time_passed * 9.0 + i) * 9.0 * k, -i * 18.0)
			overlay.draw_arc(c, r, time_passed * 8.0 + i, time_passed * 8.0 + i + PI * 1.5, 16, Color(0.85, 0.85, 0.9, 0.9 - k * 0.3), 6.0)
			overlay.draw_arc(c, r * 0.6, -time_passed * 6.0, -time_passed * 6.0 + PI, 12, Color(0.6, 0.6, 0.7, 0.85), 4.5)


## Молния: светящийся круг с кольцом, сжимающимся к центру, а в момент удара —
## ломаная молния с неба и вспышка.
func _draw_lightning() -> void:
	var col := C.LIGHTNING_COLOR
	for st in strikes:
		var target: Vector2 = st["target"]
		var k: float = st["t"] / C.LIGHTNING_WARN
		overlay.draw_circle(target, C.LIGHTNING_RADIUS, Color(col, 0.12 + 0.08 * sin(time_passed * 20.0)))
		overlay.draw_arc(target, C.LIGHTNING_RADIUS, 0, TAU, 40, Color(col, 0.8), 3.0)
		var ring := lerpf(C.LIGHTNING_RADIUS * 1.8, 0.0, k)
		if ring > 3.0:
			overlay.draw_arc(target, ring, 0, TAU, 40, Color(1, 1, 0.7, 0.6 + 0.4 * k), 6.0)
	for f in flashes:
		var target: Vector2 = f["target"]
		var a: float = f["life"] / 0.3
		# ломаная от верха экрана до места удара
		var pts := PackedVector2Array()
		var top := view_top - 50.0
		var steps := 9
		for i in steps + 1:
			var y := lerpf(top, target.y, float(i) / steps)
			var jitter := 0.0 if i == 0 or i == steps else randf_range(-45.0, 45.0)
			pts.append(Vector2(target.x + jitter, y))
		overlay.draw_polyline(pts, Color(1, 1, 0.85, a), 12.0)
		overlay.draw_polyline(pts, Color(1, 1, 1, a), 4.0)
		overlay.draw_circle(target, C.LIGHTNING_RADIUS * (1.2 - a * 0.4), Color(1, 1, 0.8, a * 0.6))


## Ракеты: корпус с носом и огнём из сопла.
func _draw_rockets() -> void:
	for r in rocket_shots:
		var p: Vector2 = r["pos"]
		var d: float = r["dir"]
		overlay.draw_rect(Rect2(p.x - 22.0, p.y - 8.0, 44.0, 16.0), Color(0.85, 0.85, 0.9))
		overlay.draw_colored_polygon(PackedVector2Array([Vector2(p.x + d * 22.0, p.y - 8.0), Vector2(p.x + d * 40.0, p.y), Vector2(p.x + d * 22.0, p.y + 8.0)]), Color(0.9, 0.2, 0.15))
		var flame := 18.0 + randf() * 14.0
		overlay.draw_colored_polygon(PackedVector2Array([Vector2(p.x - d * 22.0, p.y - 7.0), Vector2(p.x - d * (22.0 + flame), p.y), Vector2(p.x - d * 22.0, p.y + 7.0)]), Color(1, 0.6, 0.1, 0.9))


func _draw_overlay() -> void:
	_draw_tornadoes()
	_draw_rockets()
	_draw_lightning()
	_draw_bombs()
	if aiming:
		_draw_aiming()
	for sp in sparks:
		var c: Color = sp["color"]
		c.a = clampf(sp["life"], 0.0, 1.0)
		overlay.draw_circle(sp["pos"], 6.0, c)
	for f in floaters:
		var c: Color = f["color"]
		c.a = clampf(f["life"], 0.0, 1.0)
		overlay.draw_string(font, f["pos"] - Vector2(300, 0), f["text"], HORIZONTAL_ALIGNMENT_CENTER, 600, 42, c)
