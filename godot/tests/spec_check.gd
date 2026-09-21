## 仕様書 付録B「数値の検算シート」との一致を検証する。
##   godot --headless --path godot --script res://tests/spec_check.gd
extends SceneTree

var fails := 0

func _init() -> void:
	_check_chain_mult()
	_check_grid_frames()
	# 付録B の各ケース: [名前, 盤面, G, 期待 Wt, 期待 Ft, 期待 a, 期待 v0]
	_case("最上部で3マッチ",      [[0], [0], [0]],                              1.0, 3.0,  6.0,  8.0,    12.0)
	_case("上に2個",              [[0,1,2], [0], [0]],                          1.0, 5.0,  6.0,  1.6,     7.2)
	_case("上に5個",              [[0,1,2,1,2], [0,1], [0]],                    1.0, 8.0,  6.0, -2.0,     4.5)
	_case("上に5個 + 4マッチ",    [[0,1,2,1,2], [0,2], [0], [0]],               1.0, 9.0, 10.0,  0.8889,  5.3333)
	_case("上に8個（海溝 G=1.6）",[[0,1,2,1,2,1], [0,2,1], [0,1]],              1.6, 11.0, 6.0, -8.4364,  3.2727)
	if fails == 0:
		print("\nSPEC CHECK PASSED")
	else:
		printerr("\n%d SPEC CHECK(S) FAILED" % fails)
	quit(0 if fails == 0 else 1)

func _approx(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func _expect(name: String, got: float, want: float, eps: float = 0.01) -> void:
	if _approx(got, want, eps):
		print("  OK   %-14s = %.4f" % [name, got])
	else:
		printerr("  FAIL %-14s = %.4f (期待 %.4f)" % [name, got, want])
		fails += 1

func _check_chain_mult() -> void:
	print("連鎖倍率 (5.4)")
	var want := [1.00, 1.35, 1.80, 2.35, 3.00, 3.75, 4.60, 5.55]
	for i in range(want.size()):
		_expect("chain %d" % (i + 1), Cfg.chain_mult(i + 1), want[i], 0.001)

func _check_grid_frames() -> void:
	print("拍グリッド (4.6.3) BPM=%d" % Cfg.BPM)
	_expect("8分 frames", float(Cfg.grid_frames(2)), 12.0, 0.001)
	_expect("16分 frames", float(Cfg.grid_frames(4)), 6.0, 0.001)

func _case(name: String, layout: Array, g: float, wt: float, ft: float, a: float, v0: float) -> void:
	print("\n%s" % name)
	var s := Sim.new(1)
	s.speed_mult = 0.0          # 供給を止める
	s.g_mult = g                # params の G は Lv1 で 1.00 なので g_mult がそのまま G になる
	for c in range(layout.size()):
		for color in layout[c]:
			var b := MBlock.new()
			b.color = int(color)
			s.ground[c].append(b)
	var guard := 0
	while s.stacks.is_empty() and guard < 60:
		s.step()
		guard += 1
	if s.stacks.is_empty():
		printerr("  FAIL 結氷しなかった")
		fails += 1
		return
	var st: AirStack = s.stacks[0]
	var got_wt := st.total_weight()
	var got_ft := st.total_buoyancy(s.frame)
	var got_a := (got_ft / got_wt - s.gravity()) * Cfg.BASE_ACCEL
	_expect("重量 Wt", got_wt, wt)
	_expect("浮力 Ft", got_ft, ft)
	_expect("加速度 a", got_a, a)
	_expect("初速 v0", st.v, v0)
	# 融解時刻はグリッド線上に乗っていること (4.6)
	var gf := s.grid_frames()
	_expect("melt_at grid", float(int(st.groups[0]["melt_at"]) % gf), 0.0, 0.001)
