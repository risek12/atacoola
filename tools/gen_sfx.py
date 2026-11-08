"""Генератор звуков-заглушек для Atacoola.

Синтезирует простые звуки (бипы, взрывы, всплески) и сохраняет их в assets/sfx/*.wav.
Когда появятся настоящие звуки, достаточно положить файлы с теми же именами в assets/sfx.

Запуск: python tools/gen_sfx.py
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'sfx')
random.seed(7)  # одинаковый результат при каждом запуске


# ---------- кирпичики ----------

def silence(dur):
    return [0.0] * int(RATE * dur)


def tone(freq, dur, shape='sine', f_end=None, attack=0.005, decay=None, vol=1.0, vibrato=0.0):
    """Тон с плавным изменением частоты от freq до f_end и огибающей."""
    n = int(RATE * dur)
    f_end = freq if f_end is None else f_end
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        k = i / max(n - 1, 1)
        f = freq + (f_end - freq) * k
        if vibrato:
            f *= 1.0 + vibrato * math.sin(2 * math.pi * 6 * t)
        phase += 2 * math.pi * f / RATE
        if shape == 'sine':
            v = math.sin(phase)
        elif shape == 'square':
            v = 1.0 if math.sin(phase) >= 0 else -1.0
            v *= 0.5
        elif shape == 'saw':
            v = ((phase / math.pi) % 2.0) - 1.0
            v *= 0.6
        else:  # triangle
            v = 2.0 * abs(((phase / math.pi) % 2.0) - 1.0) - 1.0
        out.append(v * vol * env(t, dur, attack, decay))
    return out


def noise(dur, lp=0.3, hp=0.0, attack=0.005, decay=None, vol=1.0, lp_end=None):
    """Шум через простые фильтры: lp — «глухость» (меньше — глуше), hp — срез низов."""
    n = int(RATE * dur)
    out = []
    y1 = y2 = 0.0
    lp_end = lp if lp_end is None else lp_end
    for i in range(n):
        t = i / RATE
        k = i / max(n - 1, 1)
        a = lp + (lp_end - lp) * k
        x = random.uniform(-1, 1)
        y1 += a * (x - y1)
        y2 += hp * (y1 - y2)
        v = y1 - y2 if hp else y1
        out.append(v * vol * env(t, dur, attack, decay))
    return out


def env(t, dur, attack, decay):
    """Огибающая: быстрая атака, дальше экспоненциальное затухание (или линейное до конца)."""
    a = min(1.0, t / attack) if attack > 0 else 1.0
    if decay is None:
        d = max(0.0, 1.0 - t / dur)
    else:
        d = math.exp(-t / decay)
    return a * d


def mix(*parts):
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, v in enumerate(p):
            out[i] += v
    return out


def seq(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def at(offset, part):
    return silence(offset) + part


def save(name, samples, peak=0.8):
    m = max(1e-6, max(abs(v) for v in samples))
    k = peak / m
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v * k)) * 32767)) for v in samples))


# ---------- звуки ----------

def build():
    # раунд
    save('tick', tone(1000, 0.08, decay=0.02))
    save('go', seq(tone(660, 0.12, 'triangle', decay=0.08), tone(990, 0.3, 'triangle', decay=0.12)))
    save('tick_final', tone(1400, 0.07, 'square', decay=0.02), peak=0.6)
    save('end_gong', mix(tone(220, 1.4, decay=0.5), tone(330, 1.4, decay=0.4, vol=0.6), tone(550, 1.4, decay=0.3, vol=0.4)))
    save('win', seq(*[tone(f, 0.12, 'triangle', decay=0.08) for f in (523, 659, 784)], tone(1046, 0.45, 'triangle', decay=0.2)))
    save('lose', seq(*[tone(f, 0.16, 'triangle', decay=0.1) for f in (440, 370, 311)], tone(262, 0.5, 'triangle', decay=0.25)))

    # серфер
    save('dash', mix(noise(0.28, lp=0.08, lp_end=0.5, hp=0.05, decay=0.1), at(0.05, noise(0.2, lp=0.4, decay=0.06, vol=0.5))))
    save('dash_ready', seq(tone(880, 0.05, decay=0.03), tone(1320, 0.09, decay=0.04)), peak=0.5)
    save('streak', tone(600, 0.18, 'triangle', f_end=1200, decay=0.1))
    save('respawn', tone(300, 0.1, f_end=900, decay=0.05))
    save('wall_alarm', seq(tone(1500, 0.07, 'square', decay=0.03), silence(0.04), tone(1500, 0.07, 'square', decay=0.03)), peak=0.5)

    # гибель
    save('bite', mix(noise(0.07, lp=0.25, decay=0.03), at(0.08, noise(0.08, lp=0.2, decay=0.03)), tone(120, 0.2, decay=0.06, vol=0.8)))
    save('splash', noise(0.5, lp=0.35, lp_end=0.08, decay=0.15))
    save('player_die', mix(tone(400, 0.6, 'saw', f_end=90, decay=0.25), noise(0.4, lp=0.15, decay=0.12, vol=0.5)))

    # угрозы и события
    save('big_warn', [v * min(1.0, i / (RATE * 0.6)) for i, v in enumerate(tone(55, 0.75, 'saw', vibrato=0.08, attack=0.01))])
    save('big_jump', mix(tone(95, 0.6, 'saw', vibrato=0.1, decay=0.25), noise(0.7, lp=0.3, lp_end=0.06, decay=0.2, vol=0.9)))
    save('tornado_warn', tone(700, 0.5, f_end=1050, vibrato=0.12), peak=0.45)
    save('tornado_hit', noise(0.7, lp=0.2, hp=0.08, attack=0.05))
    zap = silence(0.35)
    for _ in range(18):
        i = random.randrange(len(zap) - 200)
        for j in range(120):
            zap[i + j] += random.uniform(-1, 1) * (1 - j / 120)
    save('zap', zap, peak=0.4)
    save('thunder', mix(noise(0.08, lp=0.9, decay=0.03), noise(1.3, lp=0.06, decay=0.45, vol=1.2)))
    save('gold', mix(*[at(random.uniform(0, 0.4), tone(random.uniform(1800, 3200), 0.12, decay=0.04, vol=0.6)) for _ in range(9)]))

    # оружие
    save('bomb_throw', tone(1800, 0.9, f_end=600, decay=0.6, attack=0.05), peak=0.45)
    save('explosion', mix(noise(0.8, lp=0.25, lp_end=0.04, decay=0.2), tone(55, 0.5, decay=0.15, vol=1.0)))
    save('rocket_launch', mix(noise(0.35, lp=0.1, lp_end=0.6, hp=0.05, decay=0.15), tone(200, 0.3, 'saw', f_end=600, decay=0.12, vol=0.4)))
    save('rocket_hit', mix(noise(0.45, lp=0.35, lp_end=0.05, decay=0.12), tone(80, 0.3, decay=0.08)))
    save('no_ammo', tone(200, 0.05, 'square', decay=0.015), peak=0.5)

    # бонусы
    save('coins', mix(tone(1318, 0.3, decay=0.08), at(0.07, tone(1760, 0.35, decay=0.1))))
    save('trophy', seq(*[tone(f, 0.09, 'square', decay=0.06) for f in (784, 1046, 1318)], tone(1568, 0.45, 'square', decay=0.2)), peak=0.55)
    save('leader', seq(tone(784, 0.08, 'triangle', decay=0.05), tone(988, 0.08, 'triangle', decay=0.05), tone(1175, 0.3, 'triangle', decay=0.12)))
    save('revenge', mix(tone(220, 0.35, 'saw', decay=0.12), tone(330, 0.35, 'saw', decay=0.12), noise(0.1, lp=0.5, decay=0.03, vol=0.4)))

    # интерфейс
    save('click', tone(2000, 0.02, decay=0.006), peak=0.5)
    save('buy', seq(tone(990, 0.06, decay=0.03), tone(1320, 0.1, decay=0.04)), peak=0.6)


if __name__ == '__main__':
    build()
    print('ok:', sorted(f for f in os.listdir(OUT) if f.endswith('.wav')))
