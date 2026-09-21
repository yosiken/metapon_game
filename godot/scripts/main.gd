## モック本体。描画・入力・デバッグUI。ロジックは Sim に閉じている（12.2）。
extends Node2D

const VW := 540.0
const VH := 960.0
const HUD_H := 96.0
const THUMB_H := 115.0

var sim: Sim
var seed_value: int = 20260921
var paused := false
var step_once := false
var slow := false
var _accum := 0.0

# 画面ジオメトリ
var cell: float
var origin: Vector2   # 盤面の左下（row 0 の下辺）

# 入力ポインタ
var pointers := {}    # id -> Dictionary

# 演出の減衰
var flash := 0.0
var shake := 0.0
var chain_pop := 0.0
var beat_pulse := 0.0
var _last_grid := -1

var font: Font
var audio: GameAudio
var _ice_tick := -1

func _ready() -> void:
	font = ThemeDB.fallback_font
	_recalc_geometry()
	sim = Sim.new(seed_value)
	audio = GameAudio.new()
	add_child(audio)
	audio.start_bgm()
	_build_debug_ui()
	set_process_unhandled_input(true)

func _recalc_geometry() -> void:
	cell = minf(VW * 0.94 / float(Cfg.COLS), (VH * 0.78) / float(Cfg.ROWS))
	var bw := cell * float(Cfg.COLS)
	origin = Vector2((VW - bw) * 0.5, VH - THUMB_H)

# ---------------------------------------------------------------- ループ

func _physics_process(_delta: float) -> void:
	var steps := 0
	if step_once:
		steps = 1
		step_once = false
	elif not paused:
		if slow:
			_accum += 0.25
			while _accum >= 1.0:
				_accum -= 1.0
				steps += 1
		else:
			steps = 1
	for i in range(steps):
		sim.step()
		_consume_events()
	audio.sync_bgm(sim.elapsed())

func _consume_events() -> void:
	_ice_tick = audio.consume(sim, _ice_tick)
	for e: Dictionary in sim.ev_freeze:
		chain_pop = 1.0
		if e["kiwa"]:
			flash = maxf(flash, 0.45)
			shake = maxf(shake, 4.0)
	for e: Dictionary in sim.ev_surface:
		flash = maxf(flash, 0.7)
		shake = maxf(shake, 7.0)
	var gf := sim.grid_frames()
	var g := int(sim.frame / gf)
	if g != _last_grid:
		_last_grid = g
		beat_pulse = 1.0

func _process(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 2.2)
	shake = maxf(0.0, shake - delta * 28.0)
	chain_pop = maxf(0.0, chain_pop - delta * 2.5)
	beat_pulse = maxf(0.0, beat_pulse - delta * 5.0)
	_update_readout()
	queue_redraw()

# ---------------------------------------------------------------- 座標変換

func cell_rect(col: int, row: float) -> Rect2:
	return Rect2(origin.x + float(col) * cell, origin.y - (row + 1.0) * cell, cell, cell)

func row_at_y(py: float) -> float:
	return (origin.y - py) / cell

func col_at_x(px: float) -> int:
	return int(floor((px - origin.x) / cell))

# ---------------------------------------------------------------- 入力 (6.1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: paused = not paused
			KEY_PERIOD: step_once = true
			KEY_S: slow = not slow
			KEY_R: _reset()
			KEY_D: _toggle_debug()
			KEY_M: audio.enabled = not audio.enabled
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_grab(event.index, event.position)
		else:
			pointers.erase(event.index)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_grab(100, event.position)
		else:
			pointers.erase(100)
	elif event is InputEventMouseMotion and pointers.has(100):
		_drag(100, event.position)

func _grab(id: int, pos: Vector2) -> void:
	if pointers.size() >= 2 and not pointers.has(id):
		return
	var col := col_at_x(pos.x)
	if col < 0 or col >= Cfg.COLS:
		return
	var rf := row_at_y(pos.y)
	# 水中スタックを優先して掴む
	for s: AirStack in sim.stacks:
		if not s.cols.has(col):
			continue
		var local := rf - (float(s.base_row) + s.y)
		var idx := int(floor(local))
		if idx >= 0 and idx < s.cols[col].size():
			if s.cols[col][idx].state == MBlock.State.ICE:
				return
			pointers[id] = {"stack": s, "col": col, "idx": idx, "start_idx": idx, "start_y": pos.y}
			return
	var gi := int(floor(rf))
	if gi >= 0 and gi < sim.ground[col].size():
		if sim.ground[col][gi].state == MBlock.State.ICE:
			return
		pointers[id] = {"stack": null, "col": col, "idx": gi, "start_idx": gi, "start_y": pos.y}
		audio.play("grab", 1.0, -6.0)

func _drag(id: int, pos: Vector2) -> void:
	if not pointers.has(id):
		return
	var pt: Dictionary = pointers[id]
	var dy: float = pt["start_y"] - pos.y
	if absf(dy) < cell * 0.35:   # DRAG_THRESHOLD
		return
	var target: int = int(pt["start_idx"]) + int(round(dy / cell))
	var col: int = pt["col"]
	var s: AirStack = pt["stack"]
	var cols_dict: Dictionary
	if s == null:
		cols_dict = {col: sim.ground[col]}
	else:
		if not s.cols.has(col) or sim.stacks.find(s) < 0:
			pointers.erase(id)
			return
		cols_dict = s.cols
	pt["idx"] = sim.move_in_column(cols_dict, col, int(pt["idx"]), target)

# ---------------------------------------------------------------- 描画

func _draw() -> void:
	var off := Vector2(0, 0)
	if shake > 0.01:
		off = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	draw_set_transform(off, 0.0, Vector2.ONE)

	_draw_water()
	_draw_board_frame()
	_draw_ground()
	_draw_stacks()
	_draw_falling()
	_draw_prediction()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hud()
	if flash > 0.01:
		draw_rect(Rect2(0, 0, VW, VH), Color(1, 1, 1, flash * 0.35))
	if sim.game_over:
		draw_rect(Rect2(0, 0, VW, VH), Color(0.02, 0.04, 0.09, 0.72))
		draw_string(font, Vector2(0, VH * 0.46), "埋没", HORIZONTAL_ALIGNMENT_CENTER, VW, 56, Color(0.8, 0.86, 0.95))
		draw_string(font, Vector2(0, VH * 0.52), "R でリトライ", HORIZONTAL_ALIGNMENT_CENTER, VW, 22, Color(0.6, 0.68, 0.8))

## 水中: 上ほど明るく、海底ほど暗い。危険域では全体が暗くなる（3.1 / 4.5）
func _draw_water() -> void:
	var danger: float = clampf(float(sim.ground_height() - (Cfg.ROWS - 2)) / 3.0, 0.0, 1.0)
	var bands := 64
	var bh := VH / float(bands)
	for i in range(bands):
		var t := float(i) / float(bands - 1)
		var top := Color(0.10, 0.32, 0.47)
		var bot := Color(0.015, 0.04, 0.10)
		var c := bot.lerp(top, t * t * 0.6 + t * 0.4)
		c = c.lerp(Color(0.10, 0.02, 0.04), danger * 0.45)
		draw_rect(Rect2(0, VH - (float(i) + 1.0) * bh, VW, bh + 1.5), c)
	# 差し込む光条
	var surf := origin.y - float(Cfg.ROWS) * cell
	for i in range(4):
		var x := 60.0 + float(i) * 130.0
		var pts := PackedVector2Array([
			Vector2(x, surf), Vector2(x + 40.0, surf),
			Vector2(x + 130.0, VH), Vector2(x - 20.0, VH)])
		draw_colored_polygon(pts, Color(0.55, 0.85, 1.0, 0.045 * (1.0 - danger)))

func _draw_board_frame() -> void:
	var bw := cell * float(Cfg.COLS)
	var surf := origin.y - float(Cfg.ROWS) * cell
	# 水面
	draw_line(Vector2(origin.x - 14, surf), Vector2(origin.x + bw + 14, surf), Color(0.75, 0.95, 1.0, 0.85), 3.0)
	draw_string(font, Vector2(origin.x + bw + 18, surf + 6), "水面", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.9, 1.0, 0.8))
	# 列の区切り
	for c in range(Cfg.COLS + 1):
		var x := origin.x + float(c) * cell
		draw_line(Vector2(x, surf), Vector2(x, origin.y), Color(1, 1, 1, 0.045), 1.0)
	# 危険域
	var dy := origin.y - float(Cfg.ROWS - 2) * cell
	draw_line(Vector2(origin.x, dy), Vector2(origin.x + bw, dy), Color(1.0, 0.35, 0.3, 0.35), 1.0)
	# 海底
	draw_rect(Rect2(origin.x - 14, origin.y, bw + 28, 16), Color(0.06, 0.07, 0.10))

func _draw_ground() -> void:
	for c in range(Cfg.COLS):
		var arr: Array = sim.ground[c]
		for r in range(arr.size()):
			_draw_block(arr[r], c, float(r), 1.0)

func _draw_stacks() -> void:
	for s: AirStack in sim.stacks:
		for c in s.cols.keys():
			var arr: Array = s.cols[c]
			for i in range(arr.size()):
				_draw_block(arr[i], c, float(s.base_row) + s.y + float(i), 1.0)
		# 氷塊の輪郭（海底スタックと区別する）
		for c in s.cols.keys():
			var n: int = s.cols[c].size()
			if n == 0:
				continue
			var r0 := float(s.base_row) + s.y
			var rc := cell_rect(c, r0 + float(n) - 1.0)
			var box := Rect2(rc.position.x, rc.position.y, cell, cell * float(n))
			draw_rect(box, Color(0.6, 0.95, 1.0, 0.5), false, 2.0)
		# 気泡の尾
		if s.v > 0.1:
			for c in s.cols.keys():
				var rb := cell_rect(c, float(s.base_row) + s.y)
				for k in range(3):
					var yy: float = rb.position.y + cell + 10.0 + float(k) * 16.0
					draw_circle(Vector2(rb.position.x + cell * 0.5, yy), 3.0 - float(k) * 0.6,
						Color(0.8, 0.95, 1.0, 0.35 - float(k) * 0.1))

func _draw_falling() -> void:
	for f: Dictionary in sim.falling:
		if f["y"] > float(Cfg.ROWS):
			continue
		_draw_block(f["block"], f["col"], f["y"], 0.55)

func _draw_block(b: MBlock, col: int, row: float, alpha: float) -> void:
	var r := cell_rect(col, row)
	var pad := cell * 0.06
	var box := Rect2(r.position + Vector2(pad, pad), Vector2(cell - pad * 2.0, cell - pad * 2.0))
	var base: Color = Cfg.COLORS[b.color % Cfg.COLORS.size()]
	if b.kind == MBlock.Kind.ROCK:
		base = Color(0.42, 0.40, 0.38)
	elif b.kind == MBlock.Kind.HEAVY:
		base = base.darkened(0.35)
	base.a = alpha
	draw_rect(box, base)

	if b.kind == MBlock.Kind.HEAVY:
		draw_rect(box, Color(1, 1, 1, 0.5 * alpha), false, 2.0)
	if b.kind != MBlock.Kind.ROCK:
		_draw_symbol(b.color, box, alpha)

	match b.state:
		MBlock.State.FREEZING:
			var k: float = 0.5 + 0.5 * sin(sim.elapsed() * 36.0)
			draw_rect(box, Color(1, 1, 1, (0.35 + 0.35 * k) * alpha))
		MBlock.State.ICE:
			_draw_ice(b, box, alpha)

## 氷は残りグリッド数で段階的に変化する（6.4.1）
func _draw_ice(b: MBlock, box: Rect2, alpha: float) -> void:
	var gf := sim.grid_frames()
	var rem: int = maxi(0, b.melt_at - sim.frame)
	var grids: int = int(ceil(float(rem) / float(gf)))
	draw_rect(box, Color(0.88, 0.98, 1.0, 0.74 * alpha))
	# 氷の内側のハイライト（厚みを感じさせる）
	draw_rect(Rect2(box.position + Vector2(3, 3), box.size - Vector2(6, 6)),
		Color(1, 1, 1, 0.22 * alpha), false, 2.0)
	var edge := Color(0.55, 0.95, 1.0, 0.95 * alpha)
	var cracks := 0
	if grids <= 1:
		# 際窓: 強く脈動し、縁がシアンに光る（5.8 / 6.4.1）
		var k: float = 0.5 + 0.5 * sin(sim.elapsed() * 54.0)
		draw_rect(box, Color(0.55, 1.0, 1.0, (0.18 + 0.30 * k) * alpha))
		edge = Color(0.35, 1.0, 1.0, alpha)
		cracks = 3
	elif grids == 2:
		cracks = 1
	draw_rect(box, edge, false, 2.5 if grids <= 1 else 1.5)
	for i in range(cracks):
		var t := 0.25 + 0.25 * float(i)
		draw_line(box.position + Vector2(box.size.x * t, 2),
			box.position + Vector2(box.size.x * (t + 0.22), box.size.y - 2),
			Color(0.13, 0.36, 0.52, 0.9 * alpha), 2.0)

func _draw_symbol(color_idx: int, box: Rect2, alpha: float) -> void:
	var c := box.get_center()
	var s := box.size.x * 0.22
	var ink := Color(0, 0, 0, 0.30 * alpha)
	match color_idx % 5:
		0: draw_circle(c, s, ink)
		1: draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, s), c + Vector2(-s, s)]), ink)
		2: draw_rect(Rect2(c - Vector2(s, s), Vector2(s * 2, s * 2)), ink)
		3: draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]), ink)
		4:
			draw_rect(Rect2(c - Vector2(s, s * 0.32), Vector2(s * 2, s * 0.64)), ink)
			draw_rect(Rect2(c - Vector2(s * 0.32, s), Vector2(s * 0.64, s * 2)), ink)

## 浮上予測ライン（6.4）。本作最大のオンボーディング装置。
func _draw_prediction() -> void:
	var bw := cell * float(Cfg.COLS)
	for s: AirStack in sim.stacks:
		var apex := _predict_apex(s)
		var reaches := apex >= float(Cfg.ROWS)
		var y: float = origin.y - clampf(apex, 0.0, float(Cfg.ROWS) + 0.5) * cell
		var col := Color(0.45, 1.0, 1.0, 0.9) if reaches else Color(1.0, 0.45, 0.4, 0.8)
		var x := origin.x
		while x < origin.x + bw:
			draw_line(Vector2(x, y), Vector2(x + 9, y), col, 2.0)
			x += 17.0

func _predict_apex(s: AirStack) -> float:
	var gw := {}
	for c: int in s.cols.keys():
		for b: MBlock in s.cols[c]:
			gw[b.group_id] = float(gw.get(b.group_id, 0.0)) + b.weight()
	var wt := s.total_weight()
	var v := s.v
	var y := s.y
	var f := sim.frame
	var g := sim.gravity()
	var best := float(s.base_row) + y
	for i in range(int(Cfg.TICKS * 2.5)):
		var ft := 0.0
		for grp: Dictionary in s.groups:
			if grp["melt_at"] > f:
				ft += grp["buoy"]
		var a := (ft / maxf(wt, 0.0001) - g) * Cfg.BASE_ACCEL
		v = clampf(v + a * Sim.DT, -Cfg.V_MAX_DOWN, Cfg.V_MAX_UP)
		y += v * Sim.DT
		best = maxf(best, float(s.base_row) + y)
		f += 1
		for grp: Dictionary in s.groups:
			if grp["melt_at"] == f:
				wt -= float(gw.get(grp["id"], 0.0))
		if wt <= 0.001:
			break
		if v < 0.0 and float(s.base_row) + y <= 0.0:
			break
	return best

# ---------------------------------------------------------------- HUD

func _draw_hud() -> void:
	var pale := Color(0.78, 0.88, 0.96)
	draw_string(font, Vector2(18, 34), "SCORE %d" % int(sim.score), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, pale)
	draw_string(font, Vector2(VW - 130, 34), "Lv.%d" % sim.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, pale)

	# 浮力ゲージ: Ft / (Wt * G) を 0〜2 で（6.4）
	var ratio := 0.0
	for s: AirStack in sim.stacks:
		ratio = maxf(ratio, s.total_buoyancy(sim.frame) / (s.total_weight() * sim.gravity()))
	draw_string(font, Vector2(18, 62), "BUOY", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, pale)
	var gx := 66.0
	var gwid := 150.0
	draw_rect(Rect2(gx, 50, gwid, 12), Color(1, 1, 1, 0.10))
	var fill: float = clampf(ratio / 2.0, 0.0, 1.0)
	draw_rect(Rect2(gx, 50, gwid * fill, 12), Color(0.45, 1.0, 1.0, 0.8) if ratio >= 1.0 else Color(1.0, 0.5, 0.4, 0.8))
	draw_line(Vector2(gx + gwid * 0.5, 47), Vector2(gx + gwid * 0.5, 65), Color(1, 1, 1, 0.55), 1.5)

	# 拍インジケータ（音の代わり。4.6）
	var subdiv := int(sim.params()["subdiv"])
	for i in range(subdiv * 2):
		var on: bool = (int(sim.frame / sim.grid_frames()) % (subdiv * 2)) == i
		var a: float = 0.85 if on else 0.18
		var rr: float = 5.0 + (beat_pulse * 3.0 if on else 0.0)
		draw_circle(Vector2(VW - 128 + float(i) * 15.0, 57), rr, Color(0.7, 0.95, 1.0, a))

	if sim.chain >= 2:
		var sz: int = 46 + int(chain_pop * 18.0)
		draw_string(font, Vector2(0, VH * 0.42), "%d CHAIN" % sim.chain,
			HORIZONTAL_ALIGNMENT_CENTER, VW, sz, Color(0.7, 1.0, 1.0, 0.45 + chain_pop * 0.55))

	if paused:
		draw_string(font, Vector2(0, VH - 26), "PAUSED  [space]再開 [.]コマ送り [s]スロー [r]リセット [d]デバッグ",
			HORIZONTAL_ALIGNMENT_CENTER, VW, 14, Color(1, 1, 0.6, 0.9))
	elif slow:
		draw_string(font, Vector2(0, VH - 26), "SLOW 0.25x", HORIZONTAL_ALIGNMENT_CENTER, VW, 14, Color(1, 1, 0.6, 0.9))

# ---------------------------------------------------------------- デバッグUI

var dbg_panel: PanelContainer
var dbg_readout: Label

func _toggle_debug() -> void:
	dbg_panel.visible = not dbg_panel.visible

func _reset() -> void:
	sim.reset(seed_value)
	pointers.clear()
	_ice_tick = -1
	audio.stop_bgm()
	audio.start_bgm()

func _build_debug_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	dbg_panel = PanelContainer.new()
	dbg_panel.position = Vector2(8, 96)
	dbg_panel.custom_minimum_size = Vector2(250, 0)
	dbg_panel.visible = false
	layer.add_child(dbg_panel)
	var vb := VBoxContainer.new()
	dbg_panel.add_child(vb)

	dbg_readout = Label.new()
	dbg_readout.add_theme_font_size_override("font_size", 12)
	vb.add_child(dbg_readout)

	_add_slider(vb, "速度 x", 0.3, 2.0, sim.speed_mult, func(v): sim.speed_mult = v)
	_add_slider(vb, "沈降係数 x", 0.5, 2.0, sim.g_mult, func(v): sim.g_mult = v)
	_add_slider(vb, "Lv固定 (0=自動)", 0.0, 12.0, 0.0, func(v): sim.level_override = int(v))
	_add_check(vb, "拍量子化 (4.6)", sim.quantize_melt, func(v): sim.quantize_melt = v)
	_add_check(vb, "際結氷 (5.8)", sim.kiwa_enabled, func(v): sim.kiwa_enabled = v)
	_add_check(vb, "氷は壁 (5.6)", sim.ice_is_wall, func(v): sim.ice_is_wall = v)
	_add_check(vb, "音 (m)", true, func(v): audio.enabled = v)

	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var b1 := Button.new()
	b1.text = "リセット"
	b1.pressed.connect(_reset)
	hb.add_child(b1)
	var b2 := Button.new()
	b2.text = "別シード"
	b2.pressed.connect(func():
		seed_value += 7919
		_reset())
	hb.add_child(b2)

	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 11)
	hint.text = "[space]停止 [.]コマ送り [s]スロー [r]リセット [d]この窓"
	vb.add_child(hint)

func _add_slider(parent: Node, label: String, lo: float, hi: float, val: float, cb: Callable) -> void:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 11)
	l.text = "%s: %.2f" % [label, val]
	parent.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.05
	sl.value = val
	sl.custom_minimum_size = Vector2(230, 16)
	sl.value_changed.connect(func(v):
		l.text = "%s: %.2f" % [label, v]
		cb.call(v))
	parent.add_child(sl)

func _add_check(parent: Node, label: String, val: bool, cb: Callable) -> void:
	var cb_node := CheckBox.new()
	cb_node.text = label
	cb_node.button_pressed = val
	cb_node.add_theme_font_size_override("font_size", 11)
	cb_node.toggled.connect(func(v): cb.call(v))
	parent.add_child(cb_node)

func _update_readout() -> void:
	if dbg_panel == null or not dbg_panel.visible:
		return
	var p := sim.params()
	var kiwa_rate := 0.0
	if sim.stat_freeze_after_first > 0:
		kiwa_rate = 100.0 * float(sim.stat_kiwa) / float(sim.stat_freeze_after_first)
	dbg_readout.text = ("frame %d  t %.1fs\nLv%d  色%d  drop %.2f  G %.2f\nSUBDIV %d  grid %dF  寿命 %dグリッド\n"
		+ "際窓 %.2fs  氷塊 %d  海底高 %d\nchain %d (最大 %d)  際結氷率 %.0f%%\n浮上 %d  沈降 %d") % [
		sim.frame, sim.elapsed(), sim.level, int(p["colors"]), float(p["drop"]) * sim.speed_mult,
		sim.gravity(), int(p["subdiv"]), sim.grid_frames(), int(p["grids"]),
		float(sim.grid_frames()) / 60.0, sim.stacks.size(), sim.ground_height(),
		sim.chain, sim.stat_max_chain, kiwa_rate, sim.stat_surfaced, sim.stat_sunk]
