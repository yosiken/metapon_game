## 付録B「上に5個/8個」相当の局面を組んで、氷と浮上予測ラインの描画を確認する。
extends SceneTree

const LAYOUT := [
	[1,2,3,1,2],
	[2,3,0,1,2,3],
	[3,1,0,2,3],
	[1,2,0,3,1,2],
	[2,3,1,2],
	[3,1,2,3,1],
]
var main: Node = null
var built := false
var ignite_frame := -1
var at := [8, 34, 64, 110]
var idx := 0
var fr := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")

func _process(_d: float) -> bool:
	fr += 1
	if main == null:
		if root.get_child_count() > 0:
			main = root.get_child(root.get_child_count() - 1)
		return false
	var sim = main.sim
	if not built:
		sim.reset(1)
		sim.speed_mult = 0.0
		sim.level_override = 3
		for c in range(LAYOUT.size()):
			for color in LAYOUT[c]:
				var b := MBlock.new()
				b.color = int(color)
				sim.ground[c].append(b)
		built = true
		return false
	if ignite_frame < 0:
		if sim.stacks.size() > 0:
			ignite_frame = sim.frame
			print("ignite at frame %d: Wt=%.1f Ft=%.1f v0=%.2f a=%.2f" % [
				sim.frame, sim.stacks[0].total_weight(), sim.stacks[0].total_buoyancy(sim.frame),
				sim.stacks[0].v,
				(sim.stacks[0].total_buoyancy(sim.frame) / sim.stacks[0].total_weight() - sim.gravity()) * Cfg.BASE_ACCEL])
		return false
	var since: int = sim.frame - ignite_frame
	if idx < at.size() and since >= int(at[idx]):
		root.get_texture().get_image().save_png("user://sc_%d.png" % idx)
		var st_n: int = sim.stacks.size()
		var yy := 0.0
		var vv := 0.0
		if st_n > 0:
			yy = sim.stacks[0].y
			vv = sim.stacks[0].v
		print("sc_%d: +%dF y=%.2f v=%.2f stacks=%d" % [idx, since, yy, vv, st_n])
		idx += 1
	return idx >= at.size() or fr > 4000
