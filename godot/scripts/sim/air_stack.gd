## 水中にある剛体（浮上中 or 沈降中）。5.1
class_name AirStack
extends RefCounted

var id: int = 0
var cols: Dictionary = {}      # col:int -> Array[MBlock]（index 0 が local row 0）
var base_row: int = 0          # 結氷した瞬間の最下段の行
var y: float = 0.0             # base_row からのオフセット [cell]
var v: float = 0.0             # 速度 [cell/s]
var groups: Array = []         # [{ "id": int, "buoy": float, "melt_at": int }]
var max_chain: int = 0
var reboosted: bool = false    # リフリーズ成立済み (5.5)
var ever_sank: bool = false

func total_weight() -> float:
	var w := 0.0
	for c in cols:
		for b in cols[c]:
			w += b.weight()
	return maxf(w, 0.0001)

func total_buoyancy(frame: int) -> float:
	var f := 0.0
	for g in groups:
		if g["melt_at"] > frame:
			f += g["buoy"]
	return f

func block_count() -> int:
	var n := 0
	for c in cols:
		n += cols[c].size()
	return n

func is_empty() -> bool:
	return block_count() == 0

## 最も早く融ける氷までの残りフレーム。氷が無ければ -1
func soonest_melt(frame: int) -> int:
	var best := -1
	for g in groups:
		var rem: int = g["melt_at"] - frame
		if rem > 0 and (best < 0 or rem < best):
			best = rem
	return best
