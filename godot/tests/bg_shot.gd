## 背景写真を敷いた盤面を、通常時と危険域とで撮る。
extends SceneTree
var main = null
var phase := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")

func _process(_d: float) -> bool:
	if main == null:
		if root.get_child_count() > 0: main = root.get_child(root.get_child_count()-1)
		return false
	var sim = main.sim
	if phase == 0:
		sim.reset(20260921); sim.speed_mult = 1.0
		phase = 1
		return false
	if phase == 1 and sim.frame > 900:
		root.get_texture().get_image().save_png("user://bg_normal.png")
		print("bg_normal: 山の高さ=%d" % sim.ground_height())
		# 危険域まで積み上げる
		for c in range(Cfg.COLS):
			while sim.ground[c].size() < Cfg.ROWS - 1:
				var b := MBlock.new(); b.color = (c + sim.ground[c].size()) % 5
				sim.ground[c].append(b)
		phase = 2
		return false
	if phase == 2:
		root.get_texture().get_image().save_png("user://bg_danger.png")
		print("bg_danger: 山の高さ=%d" % sim.ground_height())
		return true
	return false
