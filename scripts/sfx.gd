extends Node
## Звуки игры. Файлы лежат в res://assets/sfx/<имя>.wav — чтобы заменить заглушку настоящим звуком,
## достаточно положить файл с тем же именем. Заглушки генерирует tools/gen_sfx.py.

const NAMES := [
	"tick", "go", "tick_final", "end_gong", "win", "lose",
	"dash", "dash_ready", "streak", "respawn", "wall_alarm",
	"bite", "splash", "player_die",
	"big_warn", "big_jump", "tornado_warn", "tornado_hit", "zap", "thunder", "gold",
	"bomb_throw", "explosion", "rocket_launch", "rocket_hit", "no_ammo",
	"coins", "trophy", "leader", "revenge",
	"click", "buy",
]
const VOICES := 12          # сколько звуков может звучать одновременно
const MIN_REPEAT := 0.05    # один и тот же звук не чаще, чем раз в столько секунд
const QUIET_DB := -12.0     # громкость чужих событий (ботов) относительно своих
const MUSIC_PATH := "res://assets/music/main_theme.mp3"
const MUSIC_DB := 0.0       # громкость музыки
const SFX_DB := -8.0        # общая громкость звуков: они тише музыки

var _streams := {}
var _music: AudioStreamPlayer
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played := {}


func _ready() -> void:
	for n in NAMES:
		var path := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	# главная тема играет по кругу всё время, между раундами не прерывается
	if ResourceLoader.exists(MUSIC_PATH):
		var track: AudioStreamMP3 = load(MUSIC_PATH)
		track.loop = true
		_music = AudioStreamPlayer.new()
		_music.stream = track
		_music.volume_db = MUSIC_DB
		add_child(_music)
		_music.play()


## Сыграть звук. volume_db — громкость (0 — обычная, QUIET_DB — тихо), pitch_jitter — разброс высоты,
## чтобы частые звуки не звучали одинаково.
func play(sound: String, volume_db: float = 0.0, pitch_jitter: float = 0.05) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_played.get(sound, -1.0) < MIN_REPEAT:
		return
	_last_played[sound] = now
	# свободный голос, а если все заняты — самый старый по кругу
	var p: AudioStreamPlayer = null
	for q in _players:
		if not q.playing:
			p = q
			break
	if p == null:
		p = _players[_next]
		_next = (_next + 1) % VOICES
	p.stream = stream
	p.volume_db = volume_db + SFX_DB
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## Громкость события: своё — обычная, чужое — тише.
func vol_for(is_player: bool) -> float:
	return 0.0 if is_player else QUIET_DB
