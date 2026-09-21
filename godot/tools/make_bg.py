#!/usr/bin/env python3
"""背景画像を縦持ち(9:16)に切り出して、ゲーム用に落ち着かせる。

元画像は宝石が密に散った高コントラストの絵で、そのまま敷くと盤面の
ブロックと同じ「小さくて色の濃い塊」として読めてしまう（仕様書 §11.2）。
背景に退かせるため、彩度・明度を落として軽くぼかす。

  python3 tools/make_bg.py <入力画像> [出力先]

奥行きの階調と危険域の赤染めは実行時に main.gd が上から重ねる（§3.1 / §4.5）
ので、ここでは焼き込まない。
"""
import sys
from PIL import Image, ImageEnhance, ImageFilter

# 仮想解像度 540x960 の 1.5 倍。高DPIの端末でも輪郭が溶けない範囲で最小
OUT_W, OUT_H = 810, 1440

SATURATION = 0.68   # 宝石の色がブロックの色と競合しない程度まで下げる
BRIGHTNESS = 0.58   # ブロックと HUD の白文字が確実に浮く暗さ
BLUR_PX    = 1.4    # 被写界深度。きらめきは残し、輪郭だけ甘くする


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    src = Image.open(sys.argv[1]).convert("RGB")
    dst_path = sys.argv[2] if len(sys.argv) > 2 else "asetts/bg/underwater.png"

    w, h = src.size
    # 高さいっぱいを使い、幅を 9:16 に詰める。光条の収束点が画像の中央に
    # あるので、中央切り出しでそのまま画面上部の水面と揃う
    cw = round(h * OUT_W / OUT_H)
    if cw > w:   # 元が縦長すぎる場合は幅基準に切り替える
        ch = round(w * OUT_H / OUT_W)
        box = (0, (h - ch) // 2, w, (h - ch) // 2 + ch)
    else:
        box = ((w - cw) // 2, 0, (w - cw) // 2 + cw, h)
    im = src.crop(box).resize((OUT_W, OUT_H), Image.LANCZOS)

    im = ImageEnhance.Color(im).enhance(SATURATION)
    im = ImageEnhance.Brightness(im).enhance(BRIGHTNESS)
    im = im.filter(ImageFilter.GaussianBlur(BLUR_PX))

    im.save(dst_path)
    print(f"{sys.argv[1]} {src.size} -> crop{box} -> {dst_path} {im.size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
