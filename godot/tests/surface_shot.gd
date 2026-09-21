## 浮上成功の演出（リップル・ポップアップ・脱出気泡）が実際に描画されるかを確認する。
## 発生直後ではなく、少し時間が経って動きが見えるタイミングで撮る。
extends SceneTree

var main: Node = null
var bot: XorRng = null
var shots := 0
var want := 3
var wait_frames := -1

func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")

func _process(_d: float) -> bool:
	if main == null:
		if root.get_child_count() > 0:
			main = root.get_child(root.get_child_count() - 1)
			bot = XorRng.new(999)
			main.sim.level_override = 2
		return false
	var sim = main.sim
	if sim.frame % 5 == 0:
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
	if wait_frames < 0 and not sim.ev_surface.is_empty():
		wait_frames = 18   # 演出が動き出すまで待つ（約0.3秒ぶんの描画フレーム）
	if wait_frames > 0:
		wait_frames -= 1
		if wait_frames == 0 and shots < want:
			root.get_texture().get_image().save_png("user://surf_%d.png" % shots)
			print("surf shot %d at frame %d (popups=%d ripples=%d escapes=%d)" % [
				shots, sim.frame, main.popups.size(), main.ripples.size(), main.escapes.size()])
			shots += 1
			wait_frames = -1
	return shots >= want or sim.frame > 20000
