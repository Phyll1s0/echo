"""Generate original small sound effects. Only Python's standard library is used."""
from pathlib import Path
import math, struct, wave
ROOT = Path(__file__).resolve().parents[1]
RATE = 44100
for name, notes, duration, volume in [
    ('step', [440, 660], .085, .12),
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
