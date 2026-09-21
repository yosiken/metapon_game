extends SceneTree
func _bot(s: Sim, r: XorRng) -> void:
	if s.frame % 11 != 0: return
	var col := r.next_int(Cfg.COLS)
	var bodies := []
	for st: AirStack in s.stacks:
		if st.cols.has(col) and st.cols[col].size() > 1: bodies.append(st.cols)
	if s.ground[col].size() > 1: bodies.append({col: s.ground[col]})
	if bodies.is_empty(): return
	var cd: Dictionary = bodies[r.next_int(bodies.size())]
	var n: int = cd[col].size()
	s.move_in_column(cd, col, r.next_int(n), r.next_int(n))

func _initialize() -> void:
	var sim := Sim.new(777)
	var bot := XorRng.new(777 ^ 0x5bd1e995)
	var fires := {}
	for i in range(Cfg.TICKS * 180):
		_bot(sim, bot)
		sim.step()
		for e: Dictionary in sim.ev_special:
			var bid: int = e["bid"]
			fires[bid] = int(fires.get(bid, 0)) + 1
			print("F%-6d kind=%d bid=%-5d col=%d cells=%d  (この bid の発動回数 %d)" % [
				sim.frame, e["kind"], bid, e["col"], e["cells"], fires[bid]])
		sim.ev_special.clear()
	print("降った: 共鳴%d 渦%d / 発動: 共鳴%d 渦%d" % [
		sim.stat_special_spawned[0], sim.stat_special_spawned[1],
		sim.stat_special_fired[0], sim.stat_special_fired[1]])
	quit()
