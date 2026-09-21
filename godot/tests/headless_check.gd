## 描画なしで sim を回すスモークテスト。
##   godot --headless --path godot --script res://tests/headless_check.gd
extends SceneTree

const FRAMES := Cfg.TICKS * 180   # 3分

func _init() -> void:
	var fail := 0
	fail += _run_and_check(20260921)
	fail += _run_and_check(777)
	fail += _check_determinism()
	fail += _check_grid_alignment()
	if fail == 0:
		print("\nALL CHECKS PASSED")
	else:
		printerr("\n%d CHECK(S) FAILED" % fail)
	quit(0 if fail == 0 else 1)

func _bot_seed(s: Sim, r: XorRng) -> void:
	# 1秒に数回、適当な列を掴んでランダムに動かす（操作系の経路を通す）
	if s.frame % 11 != 0:
		return
	var col := r.next_int(Cfg.COLS)
	var bodies := []
	for st in s.stacks:
		if st.cols.has(col) and st.cols[col].size() > 1:
			bodies.append(st.cols)
	if s.ground[col].size() > 1:
		bodies.append({col: s.ground[col]})
	if bodies.is_empty():
		return
	var cd: Dictionary = bodies[r.next_int(bodies.size())]
	var n: int = cd[col].size()
	s.move_in_column(cd, col, r.next_int(n), r.next_int(n))

func _run_and_check(seed_value: int) -> int:
	var s := Sim.new(seed_value)
	var bot := XorRng.new(seed_value ^ 0x5bd1e995)
	var fail := 0
	var frames_run := 0
	for i in range(FRAMES):
		if s.game_over:
			break
		_bot_seed(s, bot)
		s.step()
		frames_run += 1
		# 不変条件
		for c in range(Cfg.COLS):
			if s.ground[c].size() > Cfg.ROWS + Cfg.BUFFER_ROWS + 6:
				printerr("[seed %d] 列 %d が異常に高い: %d" % [seed_value, c, s.ground[c].size()])
				fail += 1
				break
		for st in s.stacks:
			if st.is_empty():
				printerr("[seed %d] 空のスタックが残存" % seed_value)
				fail += 1
			if is_nan(st.y) or is_nan(st.v):
				printerr("[seed %d] NaN: y=%f v=%f" % [seed_value, st.y, st.v])
				fail += 1
		# 1列につき水中スタックは1本まで（モックの制約）
		var occupied := {}
		for st in s.stacks:
			for c in st.cols.keys():
				if occupied.has(c):
					printerr("[seed %d] 列 %d に複数のスタック" % [seed_value, c])
					fail += 1
				occupied[c] = true
	var kiwa_rate := 0.0
	if s.stat_freeze_after_first > 0:
		kiwa_rate = 100.0 * float(s.stat_kiwa) / float(s.stat_freeze_after_first)
	print("[seed %d] %dT (%.0fs) Lv%d score=%d 最大連鎖=%d 浮上=%d 沈降=%d 際結氷率=%.0f%% 埋没=%s" % [
		seed_value, frames_run, float(frames_run) / float(Cfg.TICKS), s.level, int(s.score),
		s.stat_max_chain, s.stat_surfaced, s.stat_sunk, kiwa_rate, str(s.game_over)])
	if s.stat_surfaced == 0:
		printerr("[seed %d] 3分回して一度も浮上していない" % seed_value)
		fail += 1
	return fail

## 同じシード・同じ入力なら同じ結果になること（12.2）
func _check_determinism() -> int:
	var res := []
	for t in range(2):
		var s := Sim.new(4242)
		var bot := XorRng.new(99)
		for i in range(Cfg.TICKS * 60):
			_bot_seed(s, bot)
			s.step()
		res.append([int(s.score), s.frame, s.stat_max_chain, s.stat_surfaced, s.ground_height()])
	if res[0] != res[1]:
		printerr("決定性テスト失敗: %s != %s" % [str(res[0]), str(res[1])])
		return 1
	print("決定性OK: %s" % str(res[0]))
	return 0

## 量子化 ON なら、すべての melt_at がグリッド線上に乗ること（4.6）
func _check_grid_alignment() -> int:
	var s := Sim.new(31337)
	var bot := XorRng.new(31337)
	var checked := 0
	var bad := 0
	for i in range(Cfg.TICKS * 90):
		_bot_seed(s, bot)
		s.step()
		var gf := s.grid_frames()
		for st in s.stacks:
			for g in st.groups:
				checked += 1
				if int(g["melt_at"]) % gf != 0:
					bad += 1
	if checked == 0:
		printerr("拍量子化テスト: 氷が1つも生成されなかった")
		return 1
	if bad > 0:
		printerr("拍量子化テスト失敗: %d/%d がグリッド線から外れている" % [bad, checked])
		return 1
	print("拍量子化OK: %d 件すべてグリッド線上" % checked)
	return 0
