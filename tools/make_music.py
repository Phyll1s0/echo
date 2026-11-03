# /// script
# dependencies = ["numpy>=2,<3", "soundfile>=0.13,<1"]
# ///
"""Render Stillwater, an original six-beat chamber score. Run: uv run tools/make_music.py"""
from pathlib import Path
import numpy as np
import soundfile as sf

RATE = 32000
BAR = 6.0  # six quarter notes at 60 bpm
# Bass, three bowed notes, then felt-piano entries (beat, MIDI pitch, touch).
# A short high call leaves space for a quieter answer across the stereo field.
SCORE = [
    (38, (53, 57, 64), [(0.70, 77, .74), (2.45, 76, .47), (4.15, 69, .65)]),
    (38, (55, 59, 64), [(2.80, 71, .46)]),
    (36, (53, 57, 64), [(0.40, 72, .62), (3.20, 67, .43)]),
    (33, (52, 55, 62), []),
    (34, (53, 57, 62), [(0.90, 77, .68), (2.66, 76, .44), (4.36, 72, .62)]),
    (41, (52, 57, 60), [(2.25, 69, .56), (4.85, 67, .34)]),
    (43, (53, 58, 62), [(1.55, 70, .55)]),
    (33, (52, 55, 62), [(2.70, 64, .39)]),
    (38, (53, 57, 64), [(1.40, 69, .54), (3.45, 74, .69)]),
    (43, (53, 59, 64), [(0.65, 76, .49), (2.85, 79, .60)]),
    (36, (55, 60, 64), [(1.30, 76, .50), (4.45, 72, .51)]),
    (41, (52, 57, 62), []),
    (34, (53, 57, 62), [(0.80, 74, .66), (3.15, 69, .47)]),
    (43, (53, 58, 62), [(1.25, 70, .51), (4.30, 67, .40)]),
    (33, (52, 57, 62), [(1.65, 64, .51), (3.80, 69, .38)]),
    (38, (52, 57, 62), []),
]
FRAMES = round(len(SCORE) * BAR * RATE)
TAU = 2 * np.pi


def hz(note):
    return 440 * 2 ** ((note - 69) / 12)


def add(mix, voice, seconds, pan, gain):
    """Place the entire note on a ring, including its tail across the loop seam."""
    start = round(seconds * RATE) % FRAMES
    count = min(len(voice), FRAMES - start)
    angle = (pan + 1) * np.pi / 4
    stereo = voice[:, None] * (gain * np.array([np.cos(angle), np.sin(angle)]))
    mix[start:start + count] += stereo[:count]
    if count < len(voice):
        mix[:len(voice) - count] += stereo[count:]


def bow(note, length, rng, bass=False):
    t = np.arange(round(length * RATE)) / RATE
    f = hz(note)
    rate = rng.uniform(3.2, 4.1)
    vibrato = (.0009 if bass else .0019) * f / rate * np.sin(TAU * rate * t)
    phase = TAU * f * t + vibrato + rng.uniform(0, TAU)
    tone = np.zeros_like(t)
    for harmonic, strength in enumerate([1, .33, .23, .10, .09, .045, .026], 1):
        tone += strength * np.sin(harmonic * phase + harmonic * .37)
    attack = 1.00 if bass else 1.65
    release = 1.55
    swell = np.sin(.5*np.pi*np.clip(t/attack, 0, 1))**2
    swell *= np.sin(.5*np.pi*np.clip((length-t)/release, 0, 1))**2
    return tone * swell * (.84 + .16*np.sin(TAU*.18*t + phase[0]))


def felt(note, touch, rng):
    t = np.arange(round(5.8 * RATE)) / RATE
    f = hz(note)
    tone = np.zeros_like(t)
    # The two softly detuned strings beat against one another. Upper modes
    # decay sooner, leaving a round fundamental and a little sympathetic ring.
    for h, strength in enumerate([1, .48, .25, .12, .069, .036], 1):
        omega = TAU * f * h * np.sqrt(1 + .00008*h*h)
        partial = .65*np.sin(omega*t) + .35*np.sin(omega*1.0015*t + .12*h)
        tone += strength * partial * np.exp(-t*(.80 + .32*h + .04*h*h))
    hammer = np.convolve(rng.normal(0, 1, len(t)), np.ones(13)/13, mode="same")
    tone += .095 * hammer * np.exp(-38*t)
    return touch * tone * (1-np.exp(-t/.011)) * np.clip((5.8-t)/.18, 0, 1)


def room_return(source, rng):
    # A dark, diffuse stereo space. Circular convolution means the beginning
    # already contains the reflections of the previous turn through the score.
    n = round(4.8 * RATE)
    t = np.arange(n) / RATE
    smooth = np.hanning(21)
    noise = np.convolve(rng.normal(0, 1, n), smooth/smooth.sum(), mode="same")
    tail = noise * (1-np.exp(-t/.07)) * np.exp(-1.6*t)
    tail *= .48 / np.sqrt(tail @ tail)
    impulse = np.zeros(FRAMES)
    impulse[round(.045*RATE):round(.045*RATE)+n] = tail
    for delay, gain in [(.057, .22), (.097, -.15), (.149, .13), (.223, .08)]:
        impulse[round((delay + rng.uniform(-.007,.007))*RATE)] += gain
    return np.fft.irfft(np.fft.rfft(source) * np.fft.rfft(impulse), n=FRAMES)


def render():
    rng = np.random.default_rng(411)
    mix = np.zeros((FRAMES, 2))
    for bar, (root, chord, melody) in enumerate(SCORE):
        pos = BAR * bar
        add(mix, bow(root, 7.7, rng, bass=True), pos-.80, -.08, .13)
        for note, pan, gain in zip(chord, [-.55, .14, .56], [.063, .052, .041]):
            add(mix, bow(note, 7.95, rng), pos-.90+rng.uniform(-.10,.10), pan, gain)
        for beat, note, touch in melody:
            add(mix, felt(note, touch, rng), pos+beat, -.20, .49)
        if melody and bar in (0, 4, 9, 12):
            beat, pitch, touch = melody[-1]
            add(mix, felt(pitch-12, touch*.65, rng), pos+beat+2.25, .52, .36)
    # A low answering line enters only in the middle and falls away again.
    for bar, beat, note, length in [(4,1.2,50,3.9), (5,.3,52,4.8), (6,.2,53,5.1),
                                    (8,2.5,53,4.0), (9,.9,55,4.2), (10,.3,52,4.8),
                                    (12,2.1,50,4.0), (13,1.1,48,4.3)]:
        add(mix, bow(note, length, rng), bar*BAR+beat, .20, .105)
    send = mix.mean(axis=1)
    for ch in range(2):
        mix[:, ch] += room_return(send, rng)
    mix -= mix.mean(axis=0)
    mix *= min(.077/np.sqrt(np.mean(mix**2)), .73/np.max(np.abs(mix)))
    dest = Path(__file__).resolve().parents[1] / "assets/audio/stillwater.ogg"
    sf.write(dest, mix, RATE, format="OGG", subtype="VORBIS")
    print(f"{dest.name}: {len(mix)/RATE:.0f} s, {dest.stat().st_size//1024} KiB")


if __name__ == "__main__":
    render()
