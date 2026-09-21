## 開始時の海底を撮る。
extends SceneTree
var main = null
var t := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(_d: float) -> bool:
	if main == null:
		if root.get_child_count() > 0: main = root.get_child(root.get_child_count()-1)
		return false
	var sim = main.sim
	if t == 0:
		sim.reset(20260921)
		sim.speed_mult = 0.0
	t += 1
	if t > 20:
		root.get_texture().get_image().save_png("user://start.png")
		var rows := []
		for r in range(Cfg.INITIAL_ROWS):
			var line := []
			for c in range(Cfg.COLS):
				line.append(sim.ground[c][r].color)
			rows.append(line)
		print("start: 段=%s 山の高さ=%d スコア=%d" % [rows, sim.ground_height(), int(sim.score)])
		return true
	return false
