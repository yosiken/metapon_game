## 特別チップの見た目（標識と発動の衝撃波）を確認する。
extends SceneTree
var main = null
var phase := 0
var t := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")

func _process(_d: float) -> bool:
	if main == null:
		if root.get_child_count() > 0: main = root.get_child(root.get_child_count()-1)
		return false
	var sim = main.sim
	if phase == 0:
		sim.reset(7, false); sim.speed_mult = 0.0
		# 海底を色違いで埋め、2個の特別チップを並べて置く
		for c in range(Cfg.COLS):
			for r in range(5):
				var b := MBlock.new()
				b.id = 500 + c * 10 + r
				b.color = (c * 2 + r) % 5
				sim.ground[c].append(b)
		sim.ground[1][2].kind = MBlock.Kind.RESONANCE
		sim.ground[4][2].kind = MBlock.Kind.VORTEX
		phase = 1
		return false
	t += 1
	if phase == 1 and t > 20:
		root.get_texture().get_image().save_png("user://special_mark.png")
		print("special_mark: 標識（共鳴石=列1 / 渦石=列4）")
		# 渦石を色0の3マッチに巻き込んで発動させる
		sim.ground[3][2].color = sim.ground[4][2].color
		sim.ground[5][2].color = sim.ground[4][2].color
		phase = 2
		t = 0
		return false
	if phase == 2 and t > Cfg.FREEZE_DELAY_FRAMES + 3:
		root.get_texture().get_image().save_png("user://special_burst.png")
		print("special_burst: 発動=%s 書き換え済み" % [sim.stat_special_fired])
		return true
	return false
