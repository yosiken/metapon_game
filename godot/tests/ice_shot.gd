## 氷の見た目とアニメーション（拍ごとのコマ送り）を確認する。
extends SceneTree
const LAYOUT := [[1,2,3,1,2],[2,3,0,1,2,3],[3,1,0,2,3],[1,2,0,3,1,2],[2,3,1,2],[3,1,2,3,1]]
var main = null
var built := false
var ig := -1
var at := [3, 12, 21, 30]
var idx := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")

func _process(_d: float) -> bool:
	if main == null:
		if root.get_child_count() > 0: main = root.get_child(root.get_child_count()-1)
		return false
	var sim = main.sim
	if not built:
		sim.reset(1); sim.speed_mult = 0.0; sim.level_override = 1
		for c in range(LAYOUT.size()):
			for col in LAYOUT[c]:
				var b := MBlock.new(); b.color = int(col); sim.ground[c].append(b)
		built = true
		return false
	if ig < 0:
		if sim.stacks.size() > 0: ig = sim.frame
		return false
	var since: int = sim.frame - ig
	if idx < at.size() and since >= int(at[idx]):
		root.get_texture().get_image().save_png("user://ice_%d.png" % idx)
		var g: int = sim.grid_frames()
		print("ice_%d: +%dF  グリッド番号=%d（コマ送りの基準）" % [idx, since, int(sim.frame/g)])
		idx += 1
	return idx >= at.size() or sim.frame > 3000
