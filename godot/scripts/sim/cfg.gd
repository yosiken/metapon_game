## 仕様書 docs/game-design.md 第7章のパラメータ定義。
## 数値はすべてここに集約する（sim / view 側に直書きしない）。
class_name Cfg
extends RefCounted

# --- 盤面 (7.1) ---
const COLS := 6
const ROWS := 12
const BUFFER_ROWS := 2
const MAX_STACKS := 3

## sim のティックレート [Hz]（4.6.3）。
## 条件は「**`TICKS * 15 / BPM` が整数**」であること。こうすると 16分音符が
## 整数ティックに乗り、融解時刻の量子化が誤差なく成立する。
## `TICKS == BPM` は常にこの条件を満たす（1拍=60ティック）が、負荷が高い。
## BPM130 では 26 の倍数が条件を満たすので、60Hz を超える最小の 78 を採る。
##   78Hz -> 1拍=36 / 8分=18 / 16分=9 ティック
## 130Hz から 4割軽くなる。秒で見た挙動は変わらない（モバイルWebでの処理落ち対策）。
const TICKS := 78
const OVERFLOW_GRACE_FRAMES := 117  # 1.5s (78 * 1.5)

# --- 物理 (7.3) ---
const MATCH_MIN := 3
const FREEZE_DELAY_FRAMES := 9      # 16分音符1つ = 0.115s
const FREEZE_IMPULSE := 12.0
const BASE_ACCEL := 8.0
const V_MAX_UP := 14.0
const V_MAX_DOWN := 18.0
const CHAIN_GRACE_FRAMES := 27      # 16分音符3つ = 0.346s
const BUOY_MULT_CAP := 4.0
const FALL_SPEED := 16.0
const KIWA_SCORE_MULT := 1.30
const KIWA_BUOY_MULT := 1.15

# --- 拍 (4.6) ---
const BPM := 130                    # BGM のテンポ。TICKS との関係は上記の条件を満たすこと

# --- レベル進行 (8.1) ---
# BPM128 では 8分=234ms / 16分=117ms。BPM150 のときより氷が約17%長持ちする。
# グリッド数は整数しか取れないため、テンポ差はここでは吸収せず dropRate 側で詰める。
const LEVELS := [
	{"t":   0, "colors": 3, "drop": 1.2, "g": 1.00, "subdiv": 2, "grids": 4},
	{"t":  30, "colors": 4, "drop": 1.5, "g": 1.00, "subdiv": 2, "grids": 4},
	{"t":  75, "colors": 4, "drop": 1.8, "g": 1.05, "subdiv": 2, "grids": 3},
	{"t": 120, "colors": 4, "drop": 2.2, "g": 1.10, "subdiv": 2, "grids": 3},
	{"t": 165, "colors": 5, "drop": 2.6, "g": 1.15, "subdiv": 4, "grids": 5},
	{"t": 225, "colors": 5, "drop": 3.0, "g": 1.20, "subdiv": 4, "grids": 5},
	{"t": 285, "colors": 5, "drop": 3.4, "g": 1.30, "subdiv": 4, "grids": 4},
	{"t": 345, "colors": 5, "drop": 3.8, "g": 1.40, "subdiv": 4, "grids": 4},
]
const DROP_MAX := 4.8
const G_MAX := 1.8
const GRIDS_MIN := 3

# --- 見た目 (11.2: 背景が青なので、ブロックの色相から青系を外す) ---
const COLORS := [
	Color("ff5b4a"), # 珊瑚
	Color("ffc93c"), # 琥珀
	Color("5fd46a"), # 緑
	Color("c36be8"), # 紫
	Color("f0efe6"), # 白
]

## グリッド1目盛りのティック数。TICKS=78 / BPM=130 なら 1拍=36 / 8分=18 / 16分=9（4.6.3）
static func grid_frames(subdiv: int) -> int:
	return int(round(float(TICKS) * 60.0 / float(BPM * subdiv)))

## 連鎖倍率 (5.4)
static func chain_mult(c: int) -> float:
	if c <= 1:
		return 1.0
	var n := float(c - 1)
	return 1.0 + 0.30 * n + 0.05 * n * n

## 経過秒からレベル番号（1始まり）
static func level_of(elapsed: float) -> int:
	var lv := 1
	for i in range(LEVELS.size()):
		if elapsed >= float(LEVELS[i]["t"]):
			lv = i + 1
	if elapsed >= 345.0:
		lv = 8 + int((elapsed - 345.0) / 60.0)
	return lv

## レベル番号からパラメータ（Lv9以降は外挿）
static func level_params(lv: int) -> Dictionary:
	if lv <= LEVELS.size():
		return LEVELS[lv - 1].duplicate()
	var last: Dictionary = LEVELS[LEVELS.size() - 1].duplicate()
	var over := lv - LEVELS.size()
	last["drop"] = minf(last["drop"] + 0.3 * over, DROP_MAX)
	last["g"] = minf(last["g"] + 0.05 * over, G_MAX)
	last["grids"] = GRIDS_MIN
	return last
