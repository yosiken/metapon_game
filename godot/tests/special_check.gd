## 特別チップ (7.2.1 / 8.2.1) の供給と発動を実測する。
##
## 見たいのは3つ。
##   1. 1プレイに何個降り、何個が実際に発動したか（降っても使われなければ意味がない）
##   2. 共鳴石が「追い詰められている時」に届いているか
##   3. 発動が連鎖に繋がっているか（救済として機能しているか）
extends SceneTree

const SEEDS := [20260921, 777, 31415, 2718]
const MINUTES := 3.0

## 操作が無いとマッチが起きないので、headless_check と同じボットで動かす
func _bot(s: Sim, r: XorRng) -> void:
	if s.frame % 11 != 0:
		return
	var col := r.next_int(Cfg.COLS)
	var bodies := []
	for st: AirStack in s.stacks:
		if st.cols.has(col) and st.cols[col].size() > 1:
			bodies.append(st.cols)
	if s.ground[col].size() > 1:
		bodies.append({col: s.ground[col]})
	if bodies.is_empty():
		return
	var cd: Dictionary = bodies[r.next_int(bodies.size())]
	var n: int = cd[col].size()
	s.move_in_column(cd, col, r.next_int(n), r.next_int(n))

func _initialize() -> void:
	var ok := true
	print("")
	print("%-10s %7s %7s %7s %7s %7s %7s" % ["seed", "浮上", "共鳴降", "共鳴発", "渦降", "渦発", "最大連鎖"])
	var tot := {"rs": 0, "rf": 0, "vs": 0, "vf": 0, "cells": 0}
	for sd in SEEDS:
		var sim := Sim.new(sd)
		var bot := XorRng.new(sd ^ 0x5bd1e995)
		for i in range(int(Cfg.TICKS * MINUTES * 60.0)):
			_bot(sim, bot)
			sim.step()
			if sim.game_over:
				break
			for e: Dictionary in sim.ev_special:
				tot["cells"] += int(e["cells"])
			sim.ev_special.clear()
			sim.ev_freeze.clear()
			sim.ev_melt.clear()
			sim.ev_surface.clear()
			sim.ev_land.clear()
		tot["rs"] += sim.stat_special_spawned[0]
		tot["rf"] += sim.stat_special_fired[0]
		tot["vs"] += sim.stat_special_spawned[1]
		tot["vf"] += sim.stat_special_fired[1]
		print("%-10d %7d %7d %7d %7d %7d %7d" % [sd, sim.stat_surfaced,
			sim.stat_special_spawned[0], sim.stat_special_fired[0],
			sim.stat_special_spawned[1], sim.stat_special_fired[1], sim.stat_max_chain])
	print("")
	print("合計: 共鳴 %d降 / %d発 (%.0f%%)、渦 %d降 / %d発 (%.0f%%)、書き換えたセル %d" % [
		tot["rs"], tot["rf"], 100.0 * float(tot["rf"]) / maxf(1.0, float(tot["rs"])),
		tot["vs"], tot["vf"], 100.0 * float(tot["vf"]) / maxf(1.0, float(tot["vs"])),
		tot["cells"]])

	ok = _check_resonance() and ok
	ok = _check_vortex_is_permutation() and ok
	ok = _check_one_shot() and ok
	ok = _check_prefill() and ok
	ok = _check_determinism() and ok
	print("")
	print("SPECIAL CHECK PASSED" if ok else "SPECIAL CHECK FAILED")
	quit(0 if ok else 1)

## 検証用の最小盤面をつくる。
##
##   row1:  [1][2][3]            <- 書き換えの対象。互いに違う色なのでマッチしない
##   row0:  [0][S][0]            <- S が特別チップ。色0の3マッチで結氷する
##
## 列3-5は空。盤面に他のマッチを作らないことが大事で、作ると `_ignite` の
## 「1列1スタック」制約でどちらが先に着火するか次第になり、何を測ったのか
## 分からないテストになる（最初にこれで取りこぼした）。
## 戻り値: { "sim", "chip", "row1" }。row1 は書き換え対象のブロック参照。
## **位置ではなく参照で検証する**こと。海底のマッチは min_row 以上を丸ごと
## 持ち上げるので (_lift_from_ground)、検証時にはもう海底に無い。
func _fixture(sd: int, kind: int) -> Dictionary:
	var sim := Sim.new(sd, false)
	var row0 := [0, 0, 0]
	var row1 := [1, 2, 3]
	for c in range(3):
		for r in range(2):
			var b := MBlock.new()
			b.id = 3000 + c * 10 + r
			b.color = row0[c] if r == 0 else row1[c]
			sim.ground[c].append(b)
	sim.ground[1][0].kind = kind
	# 供給を止める。降ってくる瓦礫が盤面を変えると検証にならない
	sim.speed_mult = 0.0
	return {"sim": sim, "chip": sim.ground[1][0],
		"row1": [sim.ground[0][1], sim.ground[1][1], sim.ground[2][1]]}

## 共鳴石: 周囲がマッチの色に統一されること
func _check_resonance() -> bool:
	var fx := _fixture(1, MBlock.Kind.RESONANCE)
	var sim: Sim = fx["sim"]
	for i in range(Cfg.FREEZE_DELAY_FRAMES + 2):
		sim.step()
	var got := []
	for b: MBlock in fx["row1"]:
		got.append(b.color)
	var ok: bool = got == [0, 0, 0] and sim.stat_special_fired[0] == 1
	print("  %s 共鳴石: 隣接がマッチ色(0)に統一される -> %s" % ["OK  " if ok else "FAIL", got])
	return ok

## 渦石: 色の**並べ替え**であって、色を増やしも減らしもしないこと
func _check_vortex_is_permutation() -> bool:
	var fx := _fixture(2, MBlock.Kind.VORTEX)
	var sim: Sim = fx["sim"]
	var before := [1, 2, 3]
	for i in range(Cfg.FREEZE_DELAY_FRAMES + 2):
		sim.step()
	var got := []
	for b: MBlock in fx["row1"]:
		got.append(b.color)
	var sorted_got := got.duplicate()
	sorted_got.sort()
	var ok: bool = sorted_got == before and sim.stat_special_fired[1] == 1
	print("  %s 渦石: 色の構成が変わらない（並べ替えのみ） %s -> %s" % [
		"OK  " if ok else "FAIL", before, got])
	return ok

## 発動したチップは使い切りで、通常ブロックへ戻ること (7.2.1)
##
## 結氷は消滅ではない。浮上できなかったスタックは着地して海底へ戻る
## (_check_landing)。使い切りにしないと同じチップが沈むたびに何度でも発動し、
## 実測では1個が3分間に4回発動していた。
func _check_one_shot() -> bool:
	var fx := _fixture(3, MBlock.Kind.VORTEX)
	var sim: Sim = fx["sim"]
	var chip: MBlock = fx["chip"]
	for i in range(Cfg.FREEZE_DELAY_FRAMES + 2):
		sim.step()
	var fired_once: bool = sim.stat_special_fired[1] == 1
	var spent: bool = chip.kind == MBlock.Kind.NORMAL
	# そのまま回し続けても2回目は出ない（沈んで海底へ戻っても再発動しない）
	for i in range(Cfg.TICKS * 120):
		sim.step()
		if sim.game_over:
			break
	var still_one: bool = sim.stat_special_fired[1] == 1
	var ok: bool = fired_once and spent and still_one
	print("  %s 使い切り: 1回だけ発動して通常ブロックへ戻る（発動=%d 種類=%d）" % [
		"OK  " if ok else "FAIL", sim.stat_special_fired[1], chip.kind])
	return ok

## 開始時の海底 (8.2.2) が、どの種でも3並びを含まないこと
##
## 「3つ並ばないように配置する」は目視では確かめられない。5000種ぶん
## 実際に敷いて、縦横すべての極大ランが MATCH_MIN 未満であることを見る。
func _check_prefill() -> bool:
	var bad := 0
	var first := ""
	var seeds := 5000
	for sd in range(1, seeds + 1):
		var sim := Sim.new(sd)
		# 段数と総数
		for c in range(Cfg.COLS):
			if sim.ground[c].size() != Cfg.INITIAL_ROWS:
				bad += 1
				if first == "":
					first = "seed %d: 列%d が %d 段" % [sd, c, sim.ground[c].size()]
				continue
		# 横の並び
		for r in range(Cfg.INITIAL_ROWS):
			var run := 1
			for c in range(1, Cfg.COLS):
				if (sim.ground[c][r] as MBlock).color == (sim.ground[c - 1][r] as MBlock).color:
					run += 1
					if run >= Cfg.MATCH_MIN:
						bad += 1
						if first == "":
							first = "seed %d: 行%d の 列%d で横%d連" % [sd, r, c, run]
				else:
					run = 1
		# 縦の並び
		for c in range(Cfg.COLS):
			var run := 1
			for r in range(1, Cfg.INITIAL_ROWS):
				if (sim.ground[c][r] as MBlock).color == (sim.ground[c][r - 1] as MBlock).color:
					run += 1
					if run >= Cfg.MATCH_MIN:
						bad += 1
						if first == "":
							first = "seed %d: 列%d の 行%d で縦%d連" % [sd, c, r, run]
				else:
					run = 1
		# 何も操作していないのにマッチが走っていないこと
		sim.speed_mult = 0.0
		for i in range(Cfg.FREEZE_DELAY_FRAMES + 3):
			sim.step()
		if not sim.stacks.is_empty() or sim.score > 0.0:
			bad += 1
			if first == "":
				first = "seed %d: 放置で結氷した" % sd
	var ok: bool = bad == 0
	print("  %s 開始時の海底: %d種すべてで %d段 x %d列、3並びなし%s" % [
		"OK  " if ok else "FAIL", seeds, Cfg.INITIAL_ROWS, Cfg.COLS,
		"" if ok else "  （%d件。例: %s）" % [bad, first]])
	return ok

## 特別チップを含めても同じ種から同じ結果が出ること (12.2)
func _check_determinism() -> bool:
	var sig := []
	for rep in range(2):
		var sim := Sim.new(20260921)
		var bot := XorRng.new(20260921 ^ 0x5bd1e995)
		for i in range(Cfg.TICKS * 90):
			_bot(sim, bot)
			sim.step()
		sig.append([int(sim.score), sim.stat_surfaced, sim.stat_max_chain,
			sim.vortex_credit, sim.resonance_credit])
	var ok: bool = sig[0] == sig[1]
	print("  %s 決定性: %s" % ["OK  " if ok else "FAIL", sig[0]])
	return ok
