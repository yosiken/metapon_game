## ブロック1個 (7.2)
class_name MBlock
extends RefCounted

enum Kind { NORMAL, HEAVY, ROCK }
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
