## 仕様書 docs/game-design.md 第7章のパラメータ定義。
## 数値はすべてここに集約する（sim / view 側に直書きしない）。
class_name Cfg
extends RefCounted

# --- 盤面 (7.1) ---
const COLS := 6
const ROWS := 12
const BUFFER_ROWS := 2
const MAX_STACKS := 3

## sim のティックレート。**BPM と同じ値にする**（4.6.3）。
## こうすると 1拍 = 常に 60 ティック、8分 = 30、16分 = 15 になり、
## どんな BPM でもグリッド線が必ずティック境界に乗る。
const TICKS := 130
const OVERFLOW_GRACE_FRAMES := 195  # 1.5s (130 * 1.5)

# --- 物理 (7.3) ---
const MATCH_MIN := 3
const FREEZE_DELAY_FRAMES := 15     # 16分音符1つ ≈ 0.115s（130ティック基準でも15）
const FREEZE_IMPULSE := 12.0
const BASE_ACCEL := 8.0
const V_MAX_UP := 14.0
const V_MAX_DOWN := 18.0
const CHAIN_GRACE_FRAMES := 45      # 16分音符3つ ≈ 0.346s（130ティック基準でも45）
const BUOY_MULT_CAP := 4.0
const FALL_SPEED := 16.0
const KIWA_SCORE_MULT := 1.30
const KIWA_BUOY_MULT := 1.15

# --- 拍 (4.6) ---
const BPM := 130                    # BGM のテンポ。TICKS と同じ値にすること

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

## グリッド1目盛りのティック数。TICKS == BPM なら 1拍=60 / 8分=30 / 16分=15（4.6.3）
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
