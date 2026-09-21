#!/usr/bin/env python3
"""unique/ の中からゲームで使う5色を選ぶ。

制約（仕様書 §11.2）:

1. **青〜青緑を除外**。背景が青い水中であることに加え、氷結演出が青いチップ
   3枚（asetts/chips/ice/）なので、青は「凍っている」の専用色にする。
2. **色覚特性に関わらず区別できること**。正常色覚・1型（P）・2型（D）・3型（T）の
   4通りで CIELAB 距離を測り、**その最悪値**が最大になる組を選ぶ。
   「正常色覚で離れている」だけでは足りない。

形（輪郭）も測って副基準に使うが、主基準にはしない。非青のチップは丸や八角が
多く、5枚すべてを違う輪郭にはできないため。**形の判別はブロックに重ねる
シンボル（●▲■◆★）が担う**という前提で、色の方を最大化する。

    python3 tools/pick_chips.py [--chips asetts/chips]
"""
import argparse, colorsys, glob, itertools, os
import numpy as np
from PIL import Image

# 青〜青緑は氷の色域として空ける
BLUE_LO, BLUE_HI = 150.0, 265.0

def _lin(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((np.maximum(c, 0) + 0.055) / 1.055) ** 2.4)

def _srgb(c):
    c = np.clip(np.asarray(c, float), 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)

# Viénot 1999 の錐体応答と、各型の投影
_M = np.array([[17.8824, 43.5161, 4.11935],
               [3.45565, 27.1554, 3.86714],
               [0.0299566, 0.184309, 1.46709]])
_MI = np.linalg.inv(_M)
_SIM = {
    "正常": np.eye(3),
    "1型(P)": np.array([[0, 2.02344, -2.52581], [0, 1, 0], [0, 0, 1]]),
    "2型(D)": np.array([[1, 0, 0], [0.494207, 0, 1.24827], [0, 0, 1]]),
    "3型(T)": np.array([[1, 0, 0], [0, 1, 0], [-0.395913, 0.801109, 0]]),
}

def _lab(rgb):
    r, g, b = _lin(rgb)
    x = 0.4124 * r + 0.3576 * g + 0.1805 * b
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = 0.0193 * r + 0.1192 * g + 0.9505 * b
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x / 0.95047), f(y), f(z / 1.08883)
    return np.array([116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)])

def labs_under_cvd(rgb):
    return [_lab(_srgb(_MI @ (T @ (_M @ _lin(rgb))))) for T in _SIM.values()]

def silhouette(im, bins=72):
    """輪郭の極座標プロファイル。丸=平坦 / 星=周期的な尖り / カイト=上下に尖る"""
    a = np.asarray(im.convert("RGBA"), float)[..., 3] / 255.0
    ys, xs = np.nonzero(a > 0.5)
    cy, cx = ys.mean(), xs.mean()
    idx = ((np.arctan2(ys - cy, xs - cx) + np.pi) / (2 * np.pi) * bins).astype(int) % bins
    rad = np.hypot(ys - cy, xs - cx)
    p = np.array([rad[idx == i].max() if (idx == i).any() else 0.0 for i in range(bins)])
    return p / p.max()

def load(chips_dir):
    d = {}
    for path in sorted(glob.glob(f"{chips_dir}/unique/*.png")):
        name = os.path.basename(path)[:-4]
        im = Image.open(path)
        a = np.asarray(im.convert("RGBA"), float) / 255.0
        al = a[..., 3]
        rgb = (a[..., :3] * al[..., None]).sum((0, 1)) / al.sum()
        h, s, _ = colorsys.rgb_to_hsv(*rgb)
        d[name] = dict(hue=h * 360, sat=s, rgb=rgb,
                       labs=labs_under_cvd(rgb), prof=silhouette(im))
    return d

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--chips", default="asetts/chips")
    ap.add_argument("--top", type=int, default=8)
    args = ap.parse_args()

    D = load(args.chips)
    pool = [n for n, v in D.items() if not (BLUE_LO <= v["hue"] <= BLUE_HI)]
    col = lambda a, b: min(float(np.linalg.norm(x - y))
                           for x, y in zip(D[a]["labs"], D[b]["labs"]))
    shp = lambda a, b: float(np.abs(D[a]["prof"] - D[b]["prof"]).mean())

    scored = sorted(((min(col(a, b) for a, b in itertools.combinations(c, 2)),
                      min(shp(a, b) for a, b in itertools.combinations(c, 2)), c)
                     for c in itertools.combinations(pool, 5)), reverse=True)
    print(f"候補 {len(pool)} 枚（{len(D)} 枚から青系を除外） / {len(scored)} 通り\n")
    print(f"{'色(最悪)':>8} {'形(最悪)':>8}  構成")
    for cv, sh, c in scored[: args.top]:
        print(f"{cv:8.1f} {sh:8.3f}  " +
              " ".join(f"{n}({D[n]['hue']:.0f}°)" for n in c))

    cv, sh, best = scored[0]
    print(f"\n採用: {' '.join(best)}")
    print(f"{'':16}" + "".join(f"{k:>10}" for k in _SIM) + f"{'形':>8}")
    for a, b in itertools.combinations(best, 2):
        cells = "".join(f"{float(np.linalg.norm(D[a]['labs'][i] - D[b]['labs'][i])):10.1f}"
                        for i in range(len(_SIM)))
        print(f"{a}-{b:8}" + cells + f"{shp(a, b):8.3f}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
