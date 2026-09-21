extends SceneTree

var frames := 0
var main: Node = null
var bot: XorRng = null
var shots := 0
var want := 4
var since := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")

func _process(_d: float) -> bool:
	frames += 1
	if main == null:
		if root.get_child_count() > 0:
			main = root.get_child(root.get_child_count() - 1)
			bot = XorRng.new(4242)
			main.sim.level_override = 5   # 16分グリッド・5色でテスト
		return false
	var sim = main.sim
	# 適当に列を掴んで動かすボット（浮上と氷の状態を作るため）
	if sim.frame % 6 == 0:
		var col := bot.next_int(Cfg.COLS)
		var cands := []
		for st in sim.stacks:
			if st.cols.has(col) and st.cols[col].size() > 1:
				cands.append(st.cols)
		if sim.ground[col].size() > 1:
			cands.append({col: sim.ground[col]})
		if not cands.is_empty():
			var cd: Dictionary = cands[bot.next_int(cands.size())]
			var n: int = cd[col].size()
			sim.move_in_column(cd, col, bot.next_int(n), bot.next_int(n))
	since += 1
	# 浮上中のスタックがあるときだけ撮る
	if shots < want and sim.stacks.size() > 0 and since > 90:
		var has_ice := false
		for st in sim.stacks:
			if st.total_buoyancy(sim.frame) > 0.0:
				has_ice = true
		if has_ice:
			root.get_texture().get_image().save_png("user://act_%d.png" % shots)
			print("act shot %d: frame=%d stacks=%d chain=%d score=%d" % [shots, sim.frame, sim.stacks.size(), sim.chain, int(sim.score)])
			shots += 1
			since = 0
	return shots >= want or frames > 20000
