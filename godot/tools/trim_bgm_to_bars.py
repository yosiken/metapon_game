#!/usr/bin/env python3
"""BGM の先頭/末尾の無音を検出し、小節の整数倍にトリムして書き出す。

    pip install numpy soundfile
    python godot/tools/trim_bgm_to_bars.py input.ogg output.ogg --bpm 130

やっていること:
  1. 振幅がピークの2%を超える最初/最後のサンプルを無音の境界とする
  2. 「実音区間の長さ ÷ 1小節」を最も近い整数に丸め、目標終端サンプルを決める
  3. 開始・終了点をゼロクロスにスナップ（トリムでクリックノイズが出ないように）
  4. 前後 1ms だけ振幅0への短いフェードをかける
  5. OGG Vorbis で書き出す（soundfile 経由。一括書き込みでエンコーダが
     クラッシュする環境があるため、5秒チャンクでストリーミング書き込みする）

Deep_Underwater.ogg（asetts/sound/bgm/）はこのスクリプトの手順で作成した。
"""
import argparse
import numpy as np
import soundfile as sf


def snap_to_zero_crossing(idx, mono, search=200):
    lo, hi = max(0, idx - search), min(len(mono) - 1, idx + search)
    seg = mono[lo:hi]
    signs = np.sign(seg)
    signs[signs == 0] = 1
    crossings = np.where(np.diff(signs) != 0)[0]
    if len(crossings) == 0:
        return idx
    best = crossings[np.argmin(np.abs(crossings + lo - idx))]
    return lo + best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--bpm", type=float, required=True)
    ap.add_argument("--silence-thresh", type=float, default=0.02,
                    help="ピークに対する無音判定のしきい値（既定 2%）")
    ap.add_argument("--fade-ms", type=float, default=1.0)
    args = ap.parse_args()

    x, sr = sf.read(args.input, always_2d=True, dtype="float32")
    mono = x.mean(axis=1)
    n = len(mono)
    bar = 60.0 / args.bpm * 4.0

    env = np.abs(mono)
    thr = env.max() * args.silence_thresh
    nz = np.nonzero(env > thr)[0]
    lead_smp, tail_smp = int(nz[0]), int(nz[-1])
    real_len_s = (tail_smp - lead_smp) / sr
    print(f"全長 {n/sr:.4f}s  先頭無音 {lead_smp/sr*1000:.1f}ms  "
          f"末尾無音 {(n-1-tail_smp)/sr*1000:.1f}ms  実音区間 {real_len_s:.4f}s "
          f"= {real_len_s/bar:.4f} 小節")

    target_bars = round(real_len_s / bar)
    target_end_smp = lead_smp + int(round(target_bars * bar * sr))
    start = snap_to_zero_crossing(lead_smp, mono)
    end = snap_to_zero_crossing(target_end_smp, mono)
    print(f"-> {target_bars} 小節にトリム。start={start} end={end} "
          f"長さ={(end-start)/sr:.4f}s = {(end-start)/sr/bar:.4f} 小節")

    clip = x[start:end].copy()
    fade_len = int(sr * args.fade_ms / 1000.0)
    if fade_len > 0:
        clip[:fade_len] *= np.linspace(0, 1, fade_len)[:, None]
        clip[-fade_len:] *= np.linspace(1, 0, fade_len)[:, None]

    chunk = sr * 5
    with sf.SoundFile(args.output, "w", samplerate=sr, channels=clip.shape[1],
                       format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(clip), chunk):
            f.write(clip[i:i + chunk])
    print(f"書き出し完了: {args.output}")


if __name__ == "__main__":
    main()
