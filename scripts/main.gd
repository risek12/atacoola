extends Node2D
## Главный скрипт прототипа: раунд, вал волн, зоны очков, акулы, сундук и итоги.

const C = preload("res://scripts/cfg.gd")
const SurferScript = preload("res://scripts/surfer.gd")
const SharkScript = preload("res://scripts/shark.gd")
const ChestScript = preload("res://scripts/chest.gd")

enum State { COUNTDOWN, PLAYING, RESULTS }

var state: int = State.COUNTDOWN
var countdown := 3.0
var message_timer := 0.0
var round_time := 0.0
var difficulty := 0.0  # 0 — начало раунда, 1 — пик (см. DIFFICULTY_PEAK_TIME)
var points_rate := 1.0  # базовая ставка очков/с, растёт за матч (см. POINTS_RATE)
var aiming := false         # игрок нажал «Бомба» и выбирает, куда её сбросить
var aim_pos := Vector2.ZERO # куда сейчас наведён прицел
var aim_shown := false      # прицел уже наводили (мышью или пальцем) — можно рисовать круг
var aim_held := false       # палец на экране: бомба упадёт, когда его отпустят
var bombs: Array = []       # летящие бомбы: {target: Vector2, t: float}
var gold_times: Array = []  # когда (секунда раунда) появятся золотые зоны
var gold_timer := 0.0       # > 0 — золотая зона активна, столько секунд ей осталось
var gold_off := 0.0         # верх золотой зоны: на сколько пикселей ниже вала
var wall_y := C.WALL_START_Y
var zone_y: Array = []  # границы зон по Y (см. _update_zones)
var time_passed := 0.0
var surfers: Array = []
var sharks: Array = []
var chest: Node2D = null
var chest_timer := 12.0
var shark_timer := 1.5
var death_marks: Array = []  # метки гибели: {lane, x, off} — off = на сколько ниже вала (едут вместе с ним)
var floaters: Array = []  # всплывающие надписи "+30", "Ам!"
var sparks: Array = []    # искры салюта
var firework_timer := 0.0
var winner_lane := -1
var coins := 0
var player: Node2D
var overlay: Node2D
var font: Font

@onready var countdown_label: Label = $UI/CountdownLabel
@onready var timer_label: Label = $HUD/TimerLabel
@onready var coins_label: Label = $HUD/CoinsLabel
@onready var rate_label: Label = $HUD/RateLabel
@onready var bomb_button: Button = $UI/BombButton
@onready var result_panel: Control = $UI/ResultPanel
@onready var result_label: Label = $UI/ResultPanel/ResultLabel
@onready var restart_button: Button = $UI/ResultPanel/RestartButton


func _ready() -> void:
	font = ThemeDB.fallback_font
	overlay = Node2D.new()
	overlay.z_index = 10
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	restart_button.pressed.connect(start_round)
	bomb_button.pressed.connect(_on_bomb_button)
	_load_coins()
	start_round()


func start_round() -> void:
	for s in surfers:
		s.queue_free()
	for sh in sharks:
		sh.queue_free()
	if chest:
		chest.queue_free()
		chest = null
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
	wall_y = C.WALL_START_Y
	_update_zones()
	shark_timer = 0.3
	chest_timer = randf_range(C.CHEST_FIRST_DELAY[0], C.CHEST_FIRST_DELAY[1])
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

	_fit_to_screen()
	_update_effects(delta)
	timer_label.text = "%d" % ceili(C.ROUND_TIME - round_time)
	rate_label.text = "Очки ×%.1f" % points_rate
	_update_bomb_button()
	queue_redraw()
	overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if state != State.PLAYING:
		return
	if aiming:
		_aim_input(event)  # прицеливание работает и после гибели
		return
	if not player.is_alive():
		return
	# На телефоне касание пальцем приходит как нажатие левой кнопки мыши.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var p: Vector2 = (make_input_local(event) as InputEventMouseButton).position
			if chest and chest.visible and p.distance_to(chest.position) < 90.0:
				_give_chest(player)
				return
			player.press()
		else:
			player.release()
	elif event is InputEventKey and event.keycode == KEY_SPACE and not event.echo:
		# пробел — для проверки на компьютере
		if event.pressed:
			player.press()
		else:
			player.release()


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
	_update_bombs(delta)
	_spawn_sharks(delta)
	_check_bites()
	_update_chest(delta)

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
		var start_height: float = (C.SHORE_Y - C.WALL_START_Y) * (C.ZONE_BOUNDS[i + 1] - C.ZONE_BOUNDS[i])
		y = minf(y + start_height, C.SHORE_Y)
		zone_y[i] = y
	zone_y[0] = C.SHORE_Y


## Серфер воскрес — убираем метку его прошлой гибели.
func on_respawn(s: Node2D) -> void:
	death_marks = death_marks.filter(func(d): return d["lane"] != s.lane)


## Серфер вернулся на лежак и сохранил временные очки.
func on_saved(s: Node2D, amount: int) -> void:
	_add_floater(Vector2(C.lane_x(s.lane), C.LOUNGER_Y - 60.0), "+%d" % amount, Color(0.4, 1.0, 0.4))


# ---------------- Золотая зона x32 ----------------

## Заранее выбираем 1–2 момента появления, разнося их по матчу.
func _schedule_gold() -> void:
	gold_times.clear()
	var count := randi_range(C.GOLD_COUNT[0], C.GOLD_COUNT[1])
	var span := (C.ROUND_TIME - 10.0 - C.GOLD_DURATION - 8.0) / count  # от 8 с до конца, минус запас
	for i in count:
		gold_times.append(8.0 + span * i + randf_range(0.0, span - C.GOLD_DURATION))


func gold_height() -> float:
	return (C.SHORE_Y - C.WALL_START_Y) * (C.ZONE_BOUNDS[C.ZONES] - C.ZONE_BOUNDS[C.ZONES - 1])  # как у x16


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
		_add_floater(Vector2(C.W * 0.5, wall_y + gold_off + gold_height() * 0.5), "ЗОЛОТАЯ ЗОНА x32!", C.GOLD_COLOR)


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
		aim_pos = (make_input_local(event) as InputEventMouseMotion).position
		aim_shown = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
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


## Бомбу можно бросить только в море — между валом и линией прибоя.
func _aim_ok(p: Vector2) -> bool:
	return p.y > wall_y and p.y < C.SHORE_Y


## Бросок бомбы любым серфером (игроком или ботом).
func _throw_bomb(thrower: Node2D, target: Vector2) -> void:
	var cost := bomb_cost(thrower)
	var mult: int = C.BOMB_DEAD_REWARD_MULT if not thrower.is_alive() else C.BOMB_REWARD_MULT
	thrower.score -= cost
	thrower.bomb_cd = C.BOMB_COOLDOWN
	bombs.append({"target": target, "t": 0.0, "reward": cost * mult, "thrower": thrower})
	_add_floater(Vector2(C.lane_x(thrower.lane), C.LOUNGER_Y - 60.0), "−%d" % cost, Color(1, 0.6, 0.3))


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
			_add_floater(Vector2(C.lane_x(thrower.lane), C.LOUNGER_Y - 60.0), "Попал! +%d" % reward, Color(0.4, 1.0, 0.4))
		# на месте взрыва — ник того, кто бросил
		_add_floater(pos + Vector2(0, -C.BOMB_RADIUS * 0.6), "Бомба: %s" % thrower.display_name, Color(1, 0.6, 0.2))
		for k in 28:  # вспышка взрыва
			var vel := Vector2.from_angle(TAU * k / 28.0) * randf_range(120.0, 300.0)
			sparks.append({"pos": pos, "vel": vel, "life": 0.6, "color": Color(1.0, randf_range(0.3, 0.7), 0.1)})


## Множитель очков в точке: золотая зона перекрывает обычные.
func points_mult_at(y: float) -> int:
	if gold_active():
		var span := gold_span()
		if y >= span.x and y <= span.y:
			return C.GOLD_POINTS
	var zone := zone_at(y)
	return 0 if zone < 0 else C.ZONE_POINTS[zone]


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
	death_marks.append({"lane": s.lane, "x": s.position.x, "off": s.position.y - wall_y})
	var lost: float = s.die()
	_add_floater(s.position, "%s −%d" % [floater_text, int(lost)], Color(1, 0.3, 0.3))
	if s == player:
		if s.lives > 0:
			_show_message("%s\nВозврат через %d с" % [player_message, int(C.RESPAWN_DELAY)], 2.0)
		else:
			_show_message("%s\nЖизни кончились" % player_message, 2.5)


func _update_chest(delta: float) -> void:
	if chest == null:
		chest_timer -= delta
		if chest_timer <= 0.0:
			chest = ChestScript.new()
			chest.position = Vector2(randf_range(90.0, C.W - 90.0), randf_range(wall_y + 120.0, C.SHORE_Y - 60.0))
			add_child(chest)
		return
	chest.tick(delta)
	if chest.age >= C.CHEST_LIFE:
		_remove_chest()
	elif chest.age >= chest.bot_time:
		var bots := surfers.filter(func(s): return s.is_bot and s.is_alive())
		if bots.is_empty():
			_remove_chest()
		else:
			_give_chest(bots.pick_random())


func _give_chest(s: Node2D) -> void:
	s.score += C.CHEST_POINTS
	_add_floater(chest.position, "%s +%d" % [s.display_name, C.CHEST_POINTS], Color(1, 0.85, 0.2))
	_remove_chest()


func _remove_chest() -> void:
	chest.queue_free()
	chest = null
	chest_timer = randf_range(C.CHEST_INTERVAL[0], C.CHEST_INTERVAL[1])


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
## Поле ставим по центру по горизонтали и прижимаем к низу (пляж всегда внизу),
## а лишнее место сверху и по бокам занимают вал, вода и песок (рисуются с запасом EXTRA).
const EXTRA := 2000.0


func _fit_to_screen() -> void:
	var vp := get_viewport().get_visible_rect().size
	get_viewport().canvas_transform = Transform2D(0.0, Vector2((vp.x - C.W) * 0.5, vp.y - C.H))


func _draw() -> void:
	# песок
	draw_rect(Rect2(-EXTRA, C.SHORE_Y, C.W + EXTRA * 2.0, C.H - C.SHORE_Y + EXTRA), Color(0.95, 0.86, 0.65))

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
		draw_string(font, Vector2(12, mid + 12), "x%d" % C.ZONE_POINTS[i], HORIZONTAL_ALIGNMENT_CENTER, 66, 33, Color.WHITE)

	# золотая зона x32 (мигает в последние 2 секунды)
	if gold_active() and (gold_timer > 2.0 or int(gold_timer * 6.0) % 2 == 0):
		var span := gold_span()
		var shimmer := 0.5 + 0.1 * sin(time_passed * 6.0)
		draw_rect(Rect2(0, span.x, C.W, span.y - span.x), Color(C.GOLD_COLOR, shimmer))
		draw_rect(Rect2(0, span.x, C.W, span.y - span.x), Color(1, 0.95, 0.6), false, 4.5)
		var gmid := (span.x + span.y) * 0.5
		draw_circle(Vector2(45, gmid), 33, Color(0.55, 0.35, 0.0, 0.8))
		draw_string(font, Vector2(12, gmid + 12), "x32", HORIZONTAL_ALIGNMENT_CENTER, 66, 30, Color.WHITE)
		draw_string(font, Vector2(C.W - 105, gmid + 15), "%d" % ceili(gold_timer), HORIZONTAL_ALIGNMENT_CENTER, 75, 42, Color.WHITE)

	# полоса игрока
	draw_rect(Rect2(C.LANE_W * C.PLAYER_LANE, wall_y, C.LANE_W, C.SHORE_Y - wall_y), Color(1, 1, 1, 0.08))

	# рябь на воде
	var y := wall_y + 90.0
	while y < C.SHORE_Y - 30.0:
		_draw_wave_line(y, 6.0, Color(1, 1, 1, 0.18), 3.0, y * 0.067)
		y += 105.0
	_draw_wave_line(C.SHORE_Y, 9.0, Color(1, 1, 1, 0.85), 6.0, 0.0)

	# вал волн
	draw_rect(Rect2(-EXTRA, -EXTRA, C.W + EXTRA * 2.0, wall_y + EXTRA), Color(0.87, 0.95, 0.98))
	for k in 5:
		_draw_wave_line(wall_y - k * 33.0, 15.0 + k * 3.0, Color(0.5, 0.71, 0.8), 4.5, k * 1.3)

	# места гибели
	for d in death_marks:
		var m := Vector2(d["x"], wall_y + d["off"])
		if m.y > C.SHORE_Y - 15.0:
			continue  # вал вытолкнул метку на берег — не рисуем
		draw_circle(m, 24, Color(1, 0.3, 0.2, 0.8))
		draw_line(m + Vector2(-13.5, -13.5), m + Vector2(13.5, 13.5), Color.WHITE, 6.0)
		draw_line(m + Vector2(-13.5, 13.5), m + Vector2(13.5, -13.5), Color.WHITE, 6.0)

	# лежаки со счётом
	for s in surfers:
		var cx := C.lane_x(s.lane)
		var r := Rect2(cx - 78, C.LOUNGER_Y + 15, 156, 105)
		draw_rect(r, Color(0.9, 0.62, 0.23) if s == player else Color(0.79, 0.42, 0.23))
		draw_rect(r, Color(0, 0, 0, 0.5), false, 4.5)
		draw_string(font, Vector2(cx - 78, C.LOUNGER_Y + 78), str(int(s.score)), HORIZONTAL_ALIGNMENT_CENTER, 156, 45, Color.WHITE)
		draw_string(font, Vector2(cx - 78, C.LOUNGER_Y + 111), s.display_name, HORIZONTAL_ALIGNMENT_CENTER, 156, 24, Color(0.15, 0.1, 0.05))
		# временные очки: набраны в воде, но ещё не сохранены на лежаке
		if s.unsaved >= 1.0:
			var tag := Rect2(cx - 60, C.LOUNGER_Y - 39, 120, 51)
			draw_rect(tag, Color(0, 0, 0, 0.55))
			draw_string(font, Vector2(cx - 60, C.LOUNGER_Y), "+%d" % int(s.unsaved), HORIZONTAL_ALIGNMENT_CENTER, 120, 39, Color(1, 0.95, 0.3))
		# жизни: красные точки — оставшиеся, серые — потерянные
		for i in C.LIVES:
			var dot_col := Color(0.9, 0.15, 0.15) if i < s.lives else Color(0.3, 0.3, 0.3, 0.6)
			draw_circle(Vector2(cx - 63 + i * 21, C.LOUNGER_Y + 30), 7.5, dot_col)
		if s.respawn_timer > 0.0:
			# отсчёт до возвращения на лежак
			draw_circle(Vector2(cx, C.LOUNGER_Y - 12), 33, Color(0, 0, 0, 0.6))
			draw_string(font, Vector2(cx - 33, C.LOUNGER_Y + 3), str(ceili(s.respawn_timer)), HORIZONTAL_ALIGNMENT_CENTER, 66, 42, Color.WHITE)
		elif s.is_out():
			draw_rect(r, Color(0, 0, 0, 0.45))  # выбыл — лежак затемнён


func _draw_wave_line(y: float, amp: float, col: Color, width: float, phase: float) -> void:
	var pts := PackedVector2Array()
	var x := -EXTRA
	while x <= C.W + EXTRA:
		pts.append(Vector2(x, y + sin(x * 0.02 + time_passed * 2.0 + phase) * amp))
		x += 18.0
	draw_polyline(pts, col, width, true)


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
	overlay.draw_rect(Rect2(0, C.SHORE_Y, C.W, C.LOUNGER_Y - C.SHORE_Y - 45.0), Color(0, 0, 0, 0.25))
	var y := wall_y + 45.0
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


func _draw_overlay() -> void:
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
