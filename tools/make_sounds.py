"""程序生成音效和背景音乐（M8）。输出 CAF（16 位 PCM），iOS 原生支持，体积小。

用法：python3 tools/make_sounds.py
"""
import os
import subprocess
import wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "LunHui", "Resources", "Sounds")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def t(d):
    return np.linspace(0, d, int(SR * d), endpoint=False)


def env(n, a=0.005, r=None, curve=4.0):
    """起音 a 秒，之后指数衰减。"""
    x = np.ones(n)
    k = max(1, int(SR * a))
    x[:k] = np.linspace(0, 1, k)
    rest = n - k
    if rest > 0:
        x[k:] = np.exp(-curve * np.linspace(0, 1, rest))
    if r:
        rr = min(n, int(SR * r))
        x[-rr:] *= np.linspace(1, 0, rr)
    return x


def noise(n):
    return rng.uniform(-1, 1, n)


def lowpass(x, cutoff):
    """一阶低通。有 scipy 就用 lfilter，没有就用 FFT 近似。"""
    a = np.exp(-2 * np.pi * cutoff / SR)
    try:
        from scipy.signal import lfilter
        return lfilter([1 - a], [1, -a], x)
    except ImportError:
        n = len(x)
        f = np.fft.rfftfreq(n, 1 / SR)
        h = 1 / np.sqrt(1 + (f / cutoff) ** 2)
        return np.fft.irfft(np.fft.rfft(x) * h, n)


def sweep(f0, f1, d):
    tt = t(d)
    f = np.geomspace(f0, f1, len(tt))
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def tone(f, d, harmonics=(1.0,)):
    tt = t(d)
    s = np.zeros_like(tt)
    for k, a in enumerate(harmonics):
        s += a * np.sin(2 * np.pi * f * (k + 1) * tt)
    return s


def bell(f, d):
    """金属感的钟声：非整数倍泛音。"""
    tt = t(d)
    parts = [(1, 1), (2.76, 0.5), (5.4, 0.25), (8.93, 0.12)]
    s = sum(a * np.sin(2 * np.pi * f * m * tt) * np.exp(-tt * (2 + m)) for m, a in parts)
    return s


def save(name, x, gain=0.8):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1
    x = x / peak * gain
    pcm = (x * 32767).astype(np.int16)
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    caf = os.path.join(OUT, name + ".caf")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "pcm_s16le", "-f", "caf", caf], check=True)
    os.remove(wav)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


# ---------- 音效 ----------

# 命中：短促的噗
n = int(SR * 0.06)
save("hit", lowpass(noise(n), 2500) * env(n, 0.001, curve=9), 0.5)

# 暴击：命中 + 高频金属
d = 0.12
save("crit", mix(lowpass(noise(int(SR * d)), 4000) * env(int(SR * d), 0.001, curve=8),
                 bell(1800, d) * 0.6), 0.6)

# 击杀：低沉的碎裂
d = 0.14
n = int(SR * d)
save("kill", mix(lowpass(noise(n), 1200) * env(n, 0.002, curve=6), sweep(300, 90, d) * env(n, 0.002, curve=5) * 0.6), 0.55)

# 飞剑：嗖
d = 0.16
n = int(SR * d)
x = noise(n) * np.sin(np.linspace(0, np.pi, n)) ** 2
save("sword", lowpass(x, 5000) * 0.7 + sweep(900, 1800, d) * 0.08 * np.sin(np.linspace(0, np.pi, n)), 0.35)

# 法术：柔和的嗡
d = 0.22
n = int(SR * d)
save("spell", sweep(500, 260, d) * env(n, 0.01, curve=4) + tone(780, d) * 0.2 * env(n, 0.01, curve=6), 0.4)

# 爆炸
d = 0.5
n = int(SR * d)
save("boom", mix(lowpass(noise(n), 700) * env(n, 0.002, curve=5), sweep(120, 40, d) * env(n, 0.002, curve=4)), 0.8)

# 雷
d = 0.45
n = int(SR * d)
crack = noise(n) * env(n, 0.0005, curve=10)
save("thunder", mix(crack, lowpass(noise(n), 400) * env(n, 0.02, curve=3) * 0.8), 0.8)

# 拾取修为珠：清脆的叮
save("pickup", bell(1320, 0.18), 0.35)

# 升级：上行琶音
notes = [523.25, 659.25, 783.99, 1046.5]
seq = np.concatenate([bell(f, 0.12) for f in notes] + [bell(1318.5, 0.6)])
save("levelup", seq, 0.7)

# 掉落：按品质分档
save("drop_low", bell(880, 0.25), 0.4)
save("drop_xian", mix(bell(988, 0.6), bell(1480, 0.6) * 0.6), 0.6)
shen = mix(np.concatenate([bell(f, 0.09) for f in [784, 988, 1175, 1568, 1976]] + [np.zeros(1)]),
           np.pad(bell(1568, 1.4), (int(SR * 0.45), 0)) * 0.9)
save("drop_shen", shen, 0.8)
hundun = mix(lowpass(noise(int(SR * 0.8)), 500) * env(int(SR * 0.8), 0.01, curve=3),
             np.pad(np.concatenate([bell(f, 0.1) for f in [440, 554, 659, 880, 1109, 1319]]), (int(SR * 0.15), 0)),
             np.pad(bell(1760, 1.6), (int(SR * 0.75), 0)))
save("drop_hundun", hundun, 0.85)

# Boss 登场：低沉的鼓和铜锣
d = 1.6
n = int(SR * d)
gong = sum(a * np.sin(2 * np.pi * f * t(d)) for f, a in [(98, 1), (147, 0.6), (233, 0.4), (311, 0.25)]) * env(n, 0.01, curve=2.5)
drum = np.concatenate([sweep(140, 50, 0.25) * env(int(SR * 0.25), 0.001, curve=6), np.zeros(int(SR * 0.05))] * 2)
save("boss", mix(gong, drum * 1.2), 0.85)

# 渡劫成功：大和弦
d = 2.2
n = int(SR * d)
chord = sum(tone(f, d, (1, 0.3, 0.15)) for f in [261.63, 329.63, 392.0, 523.25]) * env(n, 0.05, curve=2)
save("victory", mix(chord, np.pad(bell(1046.5, 1.5), (int(SR * 0.2), 0))), 0.8)

# 兵解：下行
seq = np.concatenate([tone(f, 0.28, (1, 0.4)) * env(int(SR * 0.28), 0.01, curve=3) for f in [392, 349.2, 311.1, 261.6]])
save("death", seq, 0.6)

# 按钮
save("click", bell(1600, 0.05), 0.3)

# 绝学：上冲 + 爆
d = 0.9
n = int(SR * d)
save("ultimate", mix(sweep(200, 1600, d) * np.sin(np.linspace(0, np.pi, n)) * 0.6,
                     np.pad(lowpass(noise(int(SR * 0.4)), 900) * env(int(SR * 0.4), 0.002, curve=4), (int(SR * 0.5), 0))), 0.8)


# ---------- 背景音乐（循环） ----------
# 五声音阶（宫商角徵羽），古风感

def pluck(f, d):
    """拨弦：古筝风格的衰减。"""
    tt = t(d)
    s = np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(2 * np.pi * 2 * f * tt) + 0.12 * np.sin(2 * np.pi * 3 * f * tt)
    return s * np.exp(-tt * 3.2)


def pad(freqs, d):
    tt = t(d)
    s = sum(np.sin(2 * np.pi * f * tt + k) for k, f in enumerate(freqs))
    a = np.minimum(1, np.minimum(tt / 0.6, (d - tt) / 0.6))
    return s * a


def track(name, bpm, scale, pattern, bass, bars, pad_chords, drum=False, gain=0.55):
    beat = 60 / bpm
    total = int(SR * beat * 4 * bars)
    out = np.zeros(total + SR * 2)
    step = beat / 2
    for bar in range(bars):
        for i, deg in enumerate(pattern[bar % len(pattern)]):
            if deg is None:
                continue
            pos = int(SR * (bar * 4 * beat + i * step))
            f = scale[deg % len(scale)] * (2 ** (deg // len(scale)))
            note = pluck(f, 1.2) * 0.5
            out[pos: pos + len(note)] += note
        b = bass[bar % len(bass)]
        pos = int(SR * bar * 4 * beat)
        bn = tone(b, beat * 4, (1, 0.25)) * env(int(SR * beat * 4), 0.02, curve=1.5) * 0.35
        out[pos: pos + len(bn)] += bn
        pc = pad(pad_chords[bar % len(pad_chords)], beat * 4) * 0.08
        out[pos: pos + len(pc)] += pc
        if drum:
            for k in range(4):
                p = int(SR * (bar * 4 * beat + k * beat))
                kick = sweep(110, 45, 0.18) * env(int(SR * 0.18), 0.001, curve=6) * (0.9 if k % 2 == 0 else 0.5)
                out[p: p + len(kick)] += kick
                if k % 2 == 1:
                    hn = int(SR * 0.08)
                    out[p: p + hn] += lowpass(noise(hn), 6000) * env(hn, 0.001, curve=10) * 0.25
    # 尾巴叠回开头，循环无缝
    tail = out[total:]
    out = out[:total]
    out[: len(tail)] += tail
    save(name, out, gain)


gong_scale = [293.66, 329.63, 369.99, 440.0, 493.88]  # D 宫调五声
track("bgm_cave", 72, gong_scale,
      [[0, None, 2, None, 4, None, 3, 2], [1, None, 3, None, 5, 4, 3, None],
       [4, None, 3, 2, 1, None, 0, None], [2, None, 1, None, 0, None, None, None]],
      [146.83, 123.47, 110.0, 146.83], 8,
      [[293.66, 440.0], [246.94, 369.99], [220.0, 329.63], [293.66, 369.99]], drum=False, gain=0.5)

yu_scale = [220.0, 261.63, 293.66, 329.63, 392.0]  # A 羽调五声
track("bgm_battle", 128, yu_scale,
      [[0, 2, 4, 2, 5, 4, 2, 1], [0, 2, 4, 5, 7, 5, 4, 2], [3, 4, 3, 2, 1, 2, 0, None], [0, 2, 4, 2, 5, 7, 9, 7]],
      [110.0, 98.0, 87.31, 98.0], 8,
      [[220.0, 329.63], [196.0, 293.66], [174.61, 261.63], [196.0, 293.66]], drum=True, gain=0.5)

track("bgm_boss", 140, [196.0, 233.08, 261.63, 293.66, 349.23],  # G 羽调
      [[0, 0, 3, 2, 0, 0, 4, 3], [5, 4, 3, 2, 3, 2, 0, None], [0, 0, 3, 2, 0, 0, 5, 4], [7, 5, 4, 3, 2, 3, 0, None]],
      [98.0, 87.31, 77.78, 87.31], 8,
      [[196.0, 293.66], [174.61, 261.63], [155.56, 233.08], [174.61, 261.63]], drum=True, gain=0.55)

print("ok:", sorted(os.listdir(OUT)))
