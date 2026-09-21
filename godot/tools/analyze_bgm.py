#!/usr/bin/env python3
"""BGM のテンポ・拍位相・小節整合を実測する。

    pip install numpy soundfile
    python godot/tools/analyze_bgm.py "godot/asetts/sound/bgm/Breathing Spaces.ogg" --assume-bpm 128

本作は氷の融解タイミングを拍グリッドに量子化している（仕様書 §4.6）ため、
BGM の実テンポと先頭位相が設計に直接効く。数値は必ず実測で確かめること。
"""
import argparse
import numpy as np
import soundfile as sf


def onset_flux(mono, sr, hop=256, win=1024, max_hz=None):
    n = len(mono)
    frames = 1 + (n - win) // hop
    w = np.hanning(win)
    idx = np.arange(win)[None, :] + hop * np.arange(frames)[:, None]
    S = np.abs(np.fft.rfft(mono[idx] * w, axis=1))
    if max_hz:
        S = S[:, : max(1, int(max_hz / (sr / win)))]
    f = np.maximum(0, np.diff(S, axis=0)).sum(axis=1)
    return (f - f.mean()) / (f.std() + 1e-9), sr / hop


def comb_score(flux, fps, dur, bpm, offset):
    beat = 60.0 / bpm
    i = (np.arange(offset, dur, beat) * fps).astype(int)
    i = i[(i >= 0) & (i < len(flux))]
    return flux[i].mean() if len(i) > 8 else -9.0


def best_phase(flux, fps, dur, bpm, step_ms=2):
    beat = 60.0 / bpm
    best = (-9.0, 0)
    for off_ms in range(0, int(beat * 1000), step_ms):
        s = comb_score(flux, fps, dur, bpm, off_ms / 1000.0)
        if s > best[0]:
            best = (s, off_ms)
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--assume-bpm", type=float, default=None,
                    help="想定していたテンポ。実測値と比べる")
    ap.add_argument("--lo", type=float, default=70.0)
    ap.add_argument("--hi", type=float, default=200.0)
    args = ap.parse_args()

    x, sr = sf.read(args.path, always_2d=True)
    mono = x.mean(axis=1)
    dur = len(mono) / sr
    print(f"{args.path}\n  sr={sr}  長さ={dur:.4f}s  ch={x.shape[1]}")

    env = np.abs(mono)
    nz = np.nonzero(env > env.max() * 0.02)[0]
    lead, tail = nz[0] / sr, (len(mono) - 1 - nz[-1]) / sr
    print(f"  先頭無音={lead*1000:.1f} ms  末尾無音={tail*1000:.1f} ms  "
          f"実音区間={(nz[-1]-nz[0])/sr:.4f}s")

    # キックを拾いやすいよう低域に絞る
    flux, fps = onset_flux(mono, sr, max_hz=200)

    cands = []
    for bpm10 in range(int(args.lo * 10), int(args.hi * 10) + 1, 5):
        bpm = bpm10 / 10.0
        s, off = best_phase(flux, fps, dur, bpm, step_ms=5)
        cands.append((s, bpm, off))
    cands.sort(reverse=True)

    print(f"\n  {'順位':>4} {'BPM':>8} {'位相(ms)':>9} {'オンセット強度':>12}")
    for r, (s, bpm, off) in enumerate(cands[:6], 1):
        print(f"  {r:>4} {bpm:>8.2f} {off:>9} {s:>12.3f}")

    top_s, top_bpm, _ = cands[0]
    lo, hi = int((top_bpm - 1.5) * 100), int((top_bpm + 1.5) * 100)
    fine = max(((best_phase(flux, fps, dur, b / 100.0, 2)[0], b / 100.0,
                 best_phase(flux, fps, dur, b / 100.0, 2)[1]) for b in range(lo, hi)))
    print(f"\n  実測テンポ: {fine[1]:.2f} BPM  先頭オフセット {fine[2]} ms  強度 {fine[0]:.3f}")

    if args.assume_bpm:
        s, off = best_phase(flux, fps, dur, args.assume_bpm, 2)
        print(f"  想定 {args.assume_bpm:.2f} BPM: 強度 {s:.3f}（最良位相 {off} ms）")
        ratio = fine[0] / max(s, 1e-6)
        if ratio > 2.0:
            print(f"  => ★実測テンポのほうが {ratio:.1f} 倍強い。想定テンポは疑わしい")
        else:
            print("  => 想定テンポと矛盾しない")

    for label, bpm in [("実測", fine[1])] + ([("想定", args.assume_bpm)] if args.assume_bpm else []):
        beats = dur / (60.0 / bpm)
        print(f"\n  {label} BPM {bpm:.2f} での全長: {beats:.2f} 拍 = {beats/4:.2f} 小節")
        off_bars = abs(beats / 4 - round(beats / 4))
        print(f"    小節からのズレ {off_bars:.3f} 小節 = {off_bars*4*60/bpm*1000:.0f} ms")

    print("\n  ティックレートは BPM に一致させる（§4.6.3）。"
          "\n  BPM が非整数なら 2倍の値を使えば 1拍=120ティックで整数になる。")


if __name__ == "__main__":
    main()
