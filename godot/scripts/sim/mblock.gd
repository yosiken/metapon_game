## ブロック1個 (7.2)
class_name MBlock
extends RefCounted

## RESONANCE / VORTEX は「特別チップ」(7.2.1)。通常の色を1つ持ち、その色の
## マッチに巻き込まれて**結氷した瞬間**に、隣接セルへ効果を及ぼす。
## 物理特性は NORMAL と同じにしてある。効果だけで特別扱いし、重さや浮力まで
## 同時に変えると、何が効いたのか切り分けられなくなるため。
enum Kind { NORMAL, HEAVY, ROCK, RESONANCE, VORTEX }
enum State { PLAIN, FREEZING, ICE }

var id: int = 0
var kind: int = Kind.NORMAL
var color: int = 0
var state: int = State.PLAIN
var freeze_at: int = 0   # FREEZING -> ICE になるフレーム (5.2)
var melt_at: int = 0     # ICE が消えるフレーム。必ずグリッド線上 (4.6)
var group_id: int = -1

func weight() -> float:
	match kind:
		Kind.HEAVY: return 2.5
		Kind.ROCK: return 1.5
		_: return 1.0

func buoyancy() -> float:
	match kind:
		Kind.HEAVY: return 3.5
		Kind.ROCK: return 0.0
		_: return 2.0

## 岩は凍らない (7.2)
func can_freeze() -> bool:
	return kind != Kind.ROCK

## 特別チップか (7.2.1)
func is_special() -> bool:
	return kind == Kind.RESONANCE or kind == Kind.VORTEX

## 色を書き換えてよいか。岩は色を持たず、結氷判定の済んだものを変えると
## マッチ判定と矛盾するので対象外にする (7.2.1)
func color_is_mutable() -> bool:
	return kind != Kind.ROCK and state == State.PLAIN
