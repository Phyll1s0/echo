"""Generate original small sound effects. Only Python's standard library is used."""
from pathlib import Path
import math, random, struct, wave
ROOT = Path(__file__).resolve().parents[1]
RATE = 44100
for name, notes, duration, volume in [
    ('record', [220, 330, 440], .48, .13),
    ('gate', [660, 990], .22, .08),
    ('complete', [261.63, 329.63, 392, 523.25], .9, .15),
]:
    samples = []
    for i in range(int(duration * RATE)):
        t = i / RATE
        envelope = min(1, t / .008) * math.exp(-t / (duration * .24)) * min(1, (duration-t)/.025)
        signal = sum(math.sin(math.tau*f*t) + .15*math.sin(math.tau*f*2*t) for f in notes) / len(notes)
        samples.append(struct.pack('<h', int(32767 * volume * envelope * signal)))
    path = ROOT / 'assets' / 'audio' / (name + '.wav')
    with wave.open(str(path), 'wb') as out:
        out.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        out.writeframes(b''.join(samples))


# A short contact and a brushed release. The body drops in pitch as it dies
# away; the three small variations keep a long route from sounding metronomic.
for name, seed, base in [('step', 5, 226), ('step_b', 8, 211), ('step_c', 13, 241)]:
    rng = random.Random(seed)
    samples = []
    soft = dark = 0.0
    duration = .118
    for i in range(round(duration * RATE)):
        t = i / RATE
        soft += .12 * (rng.uniform(-1, 1) - soft)
        dark += .028 * (soft - dark)
        grain = (soft-dark) * math.exp(-t/.029)
        phase = math.tau * base * (t + .012 * (1-math.exp(-t/.018)))
        body = (.68*math.sin(phase) + .24*math.sin(1.67*phase+.2)) * math.exp(-t/.017)
        edge = (1-math.exp(-t/.0038)) * min(1, (duration-t)/.014)
        samples.append(struct.pack('<h', round(32767 * .11 * edge * (body + 1.6*grain))))
    with wave.open(str(ROOT / 'assets/audio' / (name + '.wav')), 'wb') as out:
        out.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        out.writeframes(b''.join(samples))
