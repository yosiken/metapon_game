## xorshift128。決定性のため Godot 組み込みの乱数は sim 層で使わない（12.2）。
class_name XorRng
extends RefCounted

var _a: int
var _b: int
var _c: int
var _d: int

const MASK := 0xFFFFFFFF

func _init(seed_value: int = 1) -> void:
	reseed(seed_value)

func reseed(seed_value: int) -> void:
	var s := seed_value & MASK
	if s == 0:
		s = 0x9E3779B9
	_a = s
	_b = (s ^ 0x6C8E9CF5) & MASK
	_c = (s + 0x9E3779B9) & MASK
	_d = (s * 1812433253 + 1) & MASK
	for i in range(8):
		next_u32()

func next_u32() -> int:
	var t := _d
	var s := _a
	_d = _c
	_c = _b
	_b = s
	t = (t ^ (t << 11)) & MASK
	t = t ^ (t >> 8)
	_a = (t ^ s ^ (s >> 19)) & MASK
	return _a

## [0, n) の整数
func next_int(n: int) -> int:
	if n <= 0:
		return 0
	return next_u32() % n

## [0, 1) の実数
func next_float() -> float:
	return float(next_u32()) / 4294967296.0
