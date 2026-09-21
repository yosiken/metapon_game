#!/usr/bin/env python3
"""チップのシート画像を切り出し、透過PNGにして重複を除く。

    pip install numpy Pillow
    python godot/tools/slice_chips.py <シート画像> --out godot/asetts/chips

やっていること:
  1. 暗い区切り線を検出してセル境界を求める（等分割ではない。実測で切る）
  2. 各セルの黒背景を輝度でアルファに変換し、宝石の外接矩形で正方形に整える
  3. **ゲーム中の実サイズまで縮めてから**比較して重複を統合する

重複判定について:
  このシートにはピクセル完全一致の重複は無く、すべて微妙に異なるスプライトだった。
  そのため「盤面の実サイズ（約60px）で見分けがつくか」を基準にしている。
  --play-size と --threshold で調整できる。
"""
import argparse
import itertools
import os

import numpy as np
from PIL import Image, ImageFilter


def separators(profile, dark_below=30, merge_gap=16):
    """暗い帯（区切り線）の区間を返す。近接した帯はまとめる。"""
    dark = profile < dark_below
    groups, cur = [], None
    for i, d in enumerate(dark):
        if d and cur is None:
            cur = i
        elif not d and cur is not None:
            groups.append([cur, i - 1])
            cur = None
    if cur is not None:
        groups.append([cur, len(dark) - 1])
    merged = []
    for g in groups:
        if merged and g[0] - merged[-1][1] <= merge_gap:
            merged[-1][1] = g[1]
        else:
            merged.append(g)
    return merged


def make_chip(crop, tile):
    """黒背景を透過にし、外接矩形で正方形に整えて tile px に揃える。"""
    a = np.asarray(crop).astype(float)
    alpha = np.clip((a.mean(axis=2) - 22.0) / 26.0, 0.0, 1.0)
    ys, xs = np.where(alpha > 0.35)
    if len(xs) == 0:
        return None
    rgba = np.dstack([a, alpha * 255]).astype(np.uint8)
    chip = Image.fromarray(rgba, "RGBA").crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    s = max(chip.size)
    sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(chip, ((s - chip.width) // 2, (s - chip.height) // 2))
    return sq.resize((tile, tile), Image.LANCZOS)


def play_signature(chip, play_size):
    """実プレイ時の見え方。ここまで縮めてから比べるのが重要。"""
    small = chip.convert("RGB").resize((play_size, play_size), Image.LANCZOS)
    return np.asarray(small.resize((48, 48), Image.LANCZOS)
                      .filter(ImageFilter.GaussianBlur(0.8))).astype(float)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("--out", default="asetts/chips")
    ap.add_argument("--tile", type=int, default=128, help="書き出すチップの解像度")
    ap.add_argument("--play-size", type=int, default=60, help="盤面でのセルサイズ")
    ap.add_argument("--threshold", type=float, default=25.0, help="重複とみなす距離")
    args = ap.parse_args()

    im = Image.open(args.sheet).convert("RGB")
    lum = np.asarray(im).astype(int).mean(axis=2)
    rs = separators(lum.mean(axis=1))
    cs = separators(lum.mean(axis=0))
    rows = [(rs[i][1] + 1, rs[i + 1][0] - 1) for i in range(len(rs) - 1)]
    cols = [(cs[i][1] + 1, cs[i + 1][0] - 1) for i in range(len(cs) - 1)]
    print(f"グリッド検出: {len(rows)} 行 x {len(cols)} 列")

    os.makedirs(f"{args.out}/all", exist_ok=True)
    os.makedirs(f"{args.out}/unique", exist_ok=True)

    chips = {}
    for ri, (y0, y1) in enumerate(rows):
        for ci, (x0, x1) in enumerate(cols):
            chip = make_chip(im.crop((x0, y0, x1 + 1, y1 + 1)), args.tile)
            if chip is None:
                continue
            name = f"r{ri}c{ci}"
            chip.save(f"{args.out}/all/{name}.png")
            chips[name] = chip
    print(f"切り出し: {len(chips)} 枚 -> {args.out}/all/")

    sigs = {n: play_signature(c, args.play_size) for n, c in chips.items()}
    names = list(chips)
    parent = {n: n for n in names}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    pairs = sorted((np.abs(sigs[a] - sigs[b]).mean(), a, b)
                   for a, b in itertools.combinations(names, 2))
    for d, a, b in pairs:
        if d > args.threshold:
            break
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    groups = {}
    for n in names:
        groups.setdefault(find(n), []).append(n)
    for g in groups.values():
        rep = sorted(g)[0]
        chips[rep].save(f"{args.out}/unique/{rep}.png")
    print(f"重複を統合: {len(chips)} -> {len(groups)} 種 -> {args.out}/unique/")


if __name__ == "__main__":
    main()
