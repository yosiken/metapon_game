## モック本体。描画・入力・デバッグUI。ロジックは Sim に閉じている（12.2）。
extends Node2D

const VW := 540.0
const VH := 960.0
const HUD_H := 96.0
## 盤面の下に空ける高さ。ボタン列（56px）と、スマホのブラウザ下部
## ツールバーに食われるぶんの余白を兼ねる。
const THUMB_H := 150.0

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

# 浮上成功を体感させるための演出（view専用。sim状態には影響しない）
var ripples: Array = []   # 水面のリップル: [{x, w, t, dur}]
var popups: Array = []    # 獲得スコアのポップアップ: [{text, x, y, t, dur, size}]
var escapes: Array = []   # 水面を突き破って飛んでいく気泡: [{x, y, vx, vy, t, dur, r}]

var font: Font
var audio: GameAudio
var _ice_tick := -1

# 画面上のボタン（スマホにはキーボードが無いので必須）
var btn_pause := Rect2()
var btn_retry := Rect2()
var btn_debug := Rect2()
var btn_gameover := Rect2()

# 性能の実測値（実機で処理落ちしていないかを見るため）
var fps_shown := 0
var sim_hz_shown := 0
var _sim_steps := 0
var _hz_timer := 0.0

const FONT_PATH := "res://asetts/font/NotoSansJP-subset.woff2"

## 氷のアニメーション用チップ（6.4.1）。拍グリッドごとに1枚ずつ進める。
const ICE_FRAMES := [
	"res://asetts/chips/ice/ice0_r1c0.png",
	"res://asetts/chips/ice/ice1_r2c8.png",
	"res://asetts/chips/ice/ice2_r3c2.png",
]
var ice_tex: Array = []

## 背景の写真。元画像は tools/make_bg.py で 9:16 に切り出して落としてある
const BG_PATH := "res://asetts/bg/underwater.png"
var bg_tex: Texture2D = null

func _ready() -> void:
	# Web書き出しにはOSのフォントが無く、組み込みのフォールバックは日本語の
	# グリフを持たないため、埋め込みフォントを使う（無いと全部 豆腐 になる）。
	# 実際に描画する文字だけをサブセット化してあるので 50KB 程度。
	if ResourceLoader.exists(BG_PATH):
		bg_tex = load(BG_PATH)
	for path in ICE_FRAMES:
		if ResourceLoader.exists(path):
			ice_tex.append(load(path))
	if ice_tex.size() < ICE_FRAMES.size():
		push_warning("氷チップが見つからない。手描きの氷で代替する")
	if ResourceLoader.exists(FONT_PATH):
		font = load(FONT_PATH)
	else:
		push_warning("日本語フォントが見つからない: " + FONT_PATH)
		font = ThemeDB.fallback_font
	_recalc_geometry()
	sim = Sim.new(seed_value)
	audio = GameAudio.new()
	add_child(audio)
	audio.start_bgm()
	_build_debug_ui()
	set_process_unhandled_input(true)

func _recalc_geometry() -> void:
	# 盤面はボタン列より上に収める。THUMB_H はボタンと、スマホのブラウザ
	# 下部ツールバーに食われる余白の両方を兼ねている。
	cell = minf(VW * 0.94 / float(Cfg.COLS), (VH - HUD_H - THUMB_H) / float(Cfg.ROWS))
	var bw := cell * float(Cfg.COLS)
	origin = Vector2((VW - bw) * 0.5, VH - THUMB_H)
	# ボタンを並べる。タップ領域は 44pt 以上を確保する。
	# スマホのブラウザは画面下部にツールバーを重ねてくるため、
	# 画面の一番下には置かない（下端から 70px 以上空ける）。
	# 盤面の下端（VH - THUMB_H）のすぐ下に置く。画面の一番下には置かない
	# （スマホのブラウザは下部にツールバーを重ねてくるため）。
	var bh := 56.0
	var by := VH - THUMB_H + 16.0
	btn_pause = Rect2(24.0, by, 130.0, bh)
	btn_debug = Rect2(VW - 154.0, by, 130.0, bh)
	btn_retry = Rect2(VW * 0.5 - 65.0, by, 130.0, bh)
	btn_gameover = Rect2(VW * 0.5 - 110.0, VH * 0.56, 220.0, 72.0)

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
	_sim_steps += steps
	audio.sync_bgm(sim.elapsed())

func _consume_events() -> void:
	_ice_tick = audio.consume(sim, _ice_tick)
	for e: Dictionary in sim.ev_freeze:
		chain_pop = 1.0
		if e["kiwa"]:
			flash = maxf(flash, 0.45)
			shake = maxf(shake, 4.0)
	for e: Dictionary in sim.ev_surface:
		_on_surface(e)
	var gf := sim.grid_frames()
	var g := int(sim.frame / gf)
	if g != _last_grid:
		_last_grid = g
		beat_pulse = 1.0

## 浮上イベント1件を、演出3点（リップル・スコアポップアップ・脱出気泡）に変換する。
## 「消える」ではなく「突き破って出ていく」ことが伝わるようにする。
func _on_surface(e: Dictionary) -> void:
	flash = maxf(flash, 0.5)
	shake = maxf(shake, 6.0)
	var cols: Array = e.get("cols", [])
	if cols.is_empty():
		cols = [int(Cfg.COLS / 2)]
	var cmin: int = cols.min()
	var cmax: int = cols.max()
	var cx: float = origin.x + (float(cmin) + float(cmax) + 1.0) * 0.5 * cell
	var surf_y: float = origin.y - float(Cfg.ROWS) * cell

	# ① 水面のリップル: 「どこで」成功したかを空間的に示す
	ripples.append({"x": cx, "w": (float(cmax - cmin) + 1.0) * cell, "t": 0.0, "dur": 0.55})

	# ② 獲得スコアのポップアップ: 「どれだけ」の価値だったかを数字で示す
	popups.append({
		"text": "+%d" % int(round(float(e.get("gained", 0.0)))),
		"x": cx, "y": surf_y, "t": 0.0, "dur": 1.1,
		"size": 20.0 + minf(float(e["chain"]) * 2.0, 16.0),
	})

	# ③ 脱出する気泡: 消滅ではなく「画面の外へ飛び出していく」ことを見せる
	for c in cols:
		for k in range(5):
			escapes.append({
				"x": origin.x + (float(c) + 0.5) * cell + randf_range(-cell * 0.15, cell * 0.15),
				"y": surf_y, "t": 0.0, "dur": randf_range(0.5, 0.85),
				"vy": randf_range(220.0, 340.0), "vx": randf_range(-30.0, 30.0),
				"r": randf_range(2.5, 5.0),
			})

func _process(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 2.2)
	shake = maxf(0.0, shake - delta * 28.0)
	chain_pop = maxf(0.0, chain_pop - delta * 2.5)
	beat_pulse = maxf(0.0, beat_pulse - delta * 5.0)
	for r: Dictionary in ripples:
		r["t"] += delta
	ripples = ripples.filter(func(r): return r["t"] < r["dur"])
	for p: Dictionary in popups:
		p["t"] += delta
	popups = popups.filter(func(p): return p["t"] < p["dur"])
	for g: Dictionary in escapes:
		g["t"] += delta
	escapes = escapes.filter(func(g): return g["t"] < g["dur"])
	_hz_timer += delta
	if _hz_timer >= 1.0:
		sim_hz_shown = int(round(float(_sim_steps) / _hz_timer))
		fps_shown = int(Engine.get_frames_per_second())
		_sim_steps = 0
		_hz_timer = 0.0
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
			if _handle_ui_tap(event.position):
				return
			_grab(event.index, event.position)
		else:
			pointers.erase(event.index)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _handle_ui_tap(event.position):
				return
			_grab(100, event.position)
		else:
			pointers.erase(100)
	elif event is InputEventMouseMotion and pointers.has(100):
		_drag(100, event.position)

## 画面上のボタンのタップを処理する。処理したら true。
## スマホにはキーボードが無いため、リトライ・一時停止・デバッグ表示は
## すべて画面から触れる必要がある。
func _handle_ui_tap(pos: Vector2) -> bool:
	if sim.game_over:
		# 埋没中はどこを触ってもリトライ（最速でやり直せるように。11.3）
		_reset()
		return true
	if btn_pause.has_point(pos):
		paused = not paused
		return true
	if btn_retry.has_point(pos):
		_reset()
		return true
	if btn_debug.has_point(pos):
		_toggle_debug()
		return true
	return false

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
	_draw_ripples()
	_draw_escapes()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_popups()
	_draw_hud()
	if flash > 0.01:
		draw_rect(Rect2(0, 0, VW, VH), Color(1, 1, 1, flash * 0.35))
	if sim.game_over:
		_draw_gameover()

## 水中: 上ほど明るく、海底ほど暗い。危険域では全体が暗くなる（3.1 / 4.5）
##
## 背景写真を敷いたうえで、奥行きの階調と危険域の赤染めを必ず上から重ねる。
## この2つは装飾ではなく「水面までの距離」と「あと何段で埋没か」を伝える
## ゲーム内の信号なので、写真に任せず実行時に描く。
func _draw_water() -> void:
	var danger: float = clampf(float(sim.ground_height() - (Cfg.ROWS - 2)) / 3.0, 0.0, 1.0)
	var screen := Rect2(0, 0, VW, VH)
	if bg_tex != null:
		draw_texture_rect(bg_tex, screen, false)
	var bands := 64
	var bh := VH / float(bands)
	for i in range(bands):
		var t := float(i) / float(bands - 1)        # 0 = 海底, 1 = 水面
		var depth := t * t * 0.6 + t * 0.4
		var box := Rect2(0, VH - (float(i) + 1.0) * bh, VW, bh + 1.5)
		if bg_tex == null:
			var c := Color(0.015, 0.04, 0.10).lerp(Color(0.10, 0.32, 0.47), depth)
			draw_rect(box, c.lerp(Color(0.10, 0.02, 0.04), danger * 0.45))
		else:
			# 写真に重ねる幕。海底ほど濃くして、積み上がったブロックを浮かせる
			draw_rect(box, Color(0.02, 0.05, 0.12, lerpf(0.74, 0.08, depth)))
	if bg_tex != null and danger > 0.01:
		draw_rect(screen, Color(0.30, 0.03, 0.06, danger * 0.42))
	if bg_tex != null:
		# 上下の帯。写真で一番明るいのが水面付近＝HUDの位置なので、ここを
		# 落とさないとスコアもフレームレートも読めない。下はボタンの座布団。
		_draw_scrim(0.0, HUD_H + 22.0, 0.66, 0.0)
		_draw_scrim(VH - THUMB_H, VH, 0.30, 0.82)
	if bg_tex == null:
		# 差し込む光条（写真がある場合は写真側が持っている）
		var surf := origin.y - float(Cfg.ROWS) * cell
		for i in range(4):
			var x := 60.0 + float(i) * 130.0
			var pts := PackedVector2Array([
				Vector2(x, surf), Vector2(x + 40.0, surf),
				Vector2(x + 130.0, VH), Vector2(x - 20.0, VH)])
			draw_colored_polygon(pts, Color(0.55, 0.85, 1.0, 0.045 * (1.0 - danger)))

## y0 から y1 へ alpha を a0 -> a1 で渡す暗幕。写真の明暗に関係なく
## 文字が読める下地をつくる。
func _draw_scrim(y0: float, y1: float, a0: float, a1: float) -> void:
	var steps := 24
	var sh := (y1 - y0) / float(steps)
	for i in range(steps):
		var t := (float(i) + 0.5) / float(steps)
		draw_rect(Rect2(0, y0 + float(i) * sh, VW, sh + 1.0),
			Color(0.01, 0.03, 0.07, lerpf(a0, a1, t)))

func _draw_board_frame() -> void:
	var bw := cell * float(Cfg.COLS)
	var surf := origin.y - float(Cfg.ROWS) * cell
	# 盤面の下敷き。背景の宝石はブロックと大きさも色域も近いので、盤の中だけ
	# 沈めておかないとどれが操作できる駒なのか判別できない（11.2）
	if bg_tex != null:
		draw_rect(Rect2(origin.x, surf, bw, origin.y - surf), Color(0.01, 0.03, 0.07, 0.42))
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

## 氷は残りグリッド数で段階的に変化する（6.4.1）。
##
## 見せるものが2つある:
##   1. 「これは氷だ」        -> 青いチップ3枚を拍グリッドごとに切り替える
##   2. 「あと何目盛り残りか」 -> 亀裂の本数と際窓の脈動（判断材料なので必須）
##
## チップを拍で送るのは §4.6 の「盤面が音楽を刻む」を**目でも見えるように**
## するため。音を消していても氷が8分/16分で表情を変える。
func _draw_ice(b: MBlock, box: Rect2, alpha: float) -> void:
	var gf := sim.grid_frames()
	var rem: int = maxi(0, b.melt_at - sim.frame)
	var grids: int = int(ceil(float(rem) / float(gf)))

	if ice_tex.is_empty():
		draw_rect(box, Color(0.88, 0.98, 1.0, 0.74 * alpha))
	else:
		# 拍グリッドが1つ進むごとにコマを送る。ブロックごとに位相をずらし、
		# 盤面全体が一斉に同じ絵になるのを避ける。
		var idx: int = (int(sim.frame / gf) + b.id) % ice_tex.size()
		# チップは元ブロックより少し大きく描く。凍って膨らんだように見え、
		# セルの隙間も埋まる（凍結時の体積膨張という設定とも合う。4.3）
		var grow := box.size.x * 0.12
		var dst := Rect2(box.position - Vector2(grow, grow) * 0.5,
			box.size + Vector2(grow, grow))
		draw_texture_rect(ice_tex[idx], dst, false, Color(1, 1, 1, 0.97 * alpha))
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
	# 亀裂は残りグリッド数そのもの。氷の絵の上でも読めるよう、
	# 白の芯に濃い縁取りを付けて描く（6.4.1 の判断材料なので潰さない）
	for i in range(cracks):
		var t := 0.22 + 0.26 * float(i)
		var p0 := box.position + Vector2(box.size.x * t, 3)
		var p1 := box.position + Vector2(box.size.x * (t + 0.20), box.size.y - 3)
		draw_line(p0, p1, Color(0.05, 0.22, 0.38, 0.85 * alpha), 4.0)
		draw_line(p0, p1, Color(0.95, 1.0, 1.0, 0.95 * alpha), 1.8)

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

## 水面のリップル: 浮上した「場所」を空間的に示す（成功を体感させる演出 #1）。
func _draw_ripples() -> void:
	var surf_y := origin.y - float(Cfg.ROWS) * cell
	for r: Dictionary in ripples:
		var t: float = clampf(r["t"] / r["dur"], 0.0, 1.0)
		var half_w: float = lerpf(r["w"] * 0.4, r["w"] * 1.7, t)
		var alpha: float = (1.0 - t) * 0.8
		var sink: float = t * 10.0
		draw_line(Vector2(r["x"] - half_w, surf_y + sink), Vector2(r["x"] + half_w, surf_y + sink),
			Color(0.85, 0.98, 1.0, alpha), 3.0 * (1.0 - t) + 1.0)
		draw_line(Vector2(r["x"] - half_w * 0.6, surf_y + sink * 1.6), Vector2(r["x"] + half_w * 0.6, surf_y + sink * 1.6),
			Color(0.85, 0.98, 1.0, alpha * 0.5), 2.0)

## 水面を突き破って画面外へ飛んでいく気泡: 「消える」ではなく
## 「脱出する」ことを見せる演出 #2（成功を体感させる演出 #2）。
func _draw_escapes() -> void:
	for g: Dictionary in escapes:
		var t: float = g["t"]
		var x: float = g["x"] + g["vx"] * t
		var y: float = g["y"] - g["vy"] * t
		var alpha: float = clampf(1.0 - t / g["dur"], 0.0, 1.0)
		draw_circle(Vector2(x, y), g["r"] * (1.0 - t * 0.3), Color(0.85, 0.98, 1.0, alpha * 0.85))
		draw_circle(Vector2(x, y), g["r"] * 0.4, Color(1, 1, 1, alpha))

## 獲得スコアのポップアップ: 連鎖の価値を数字で示す（成功を体感させる演出 #3）。
## 画面座標系で描く（カメラシェイクの影響を受けない）ため _draw() の
## transform リセット後に呼ぶこと。
func _draw_popups() -> void:
	for p: Dictionary in popups:
		var t: float = p["t"] / p["dur"]
		var y: float = p["y"] - t * 46.0
		var alpha: float = 1.0 - smoothstep(0.6, 1.0, t)
		var pop: float = 1.0 + (1.0 - clampf(t / 0.25, 0.0, 1.0)) * 0.4
		draw_string(font, Vector2(p["x"] - 60.0, y), p["text"], HORIZONTAL_ALIGNMENT_CENTER, 120.0,
			int(p["size"] * pop), Color(1.0, 0.92, 0.5, alpha))

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

## 埋没（ゲームオーバー）。リトライまで最短で戻れるようにする（11.3）。
func _draw_gameover() -> void:
	draw_rect(Rect2(0, 0, VW, VH), Color(0.02, 0.04, 0.09, 0.72))
	draw_string(font, Vector2(0, VH * 0.40), "埋没", HORIZONTAL_ALIGNMENT_CENTER, VW, 56,
		Color(0.8, 0.86, 0.95))
	draw_string(font, Vector2(0, VH * 0.46), "SCORE %d   最大連鎖 %d" % [int(sim.score), sim.stat_max_chain],
		HORIZONTAL_ALIGNMENT_CENTER, VW, 20, Color(0.62, 0.72, 0.85))
	var pulse: float = 0.72 + 0.28 * sin(float(Time.get_ticks_msec()) * 0.004)
	draw_rect(btn_gameover, Color(0.16, 0.55, 0.72, pulse))
	draw_rect(btn_gameover, Color(0.75, 0.95, 1.0, 0.9), false, 2.0)
	draw_string(font, Vector2(btn_gameover.position.x, btn_gameover.position.y + 46.0),
		"もう一度", HORIZONTAL_ALIGNMENT_CENTER, btn_gameover.size.x, 28, Color(1, 1, 1))
	draw_string(font, Vector2(0, VH * 0.70), "画面のどこでもタップでリトライ",
		HORIZONTAL_ALIGNMENT_CENTER, VW, 16, Color(0.55, 0.65, 0.78))

## 画面上のボタン。スマホにはキーボードが無いので常時表示する。
func _draw_buttons() -> void:
	_draw_button(btn_pause, "再開" if paused else "一時停止", paused)
	_draw_button(btn_retry, "リトライ", false)
	_draw_button(btn_debug, "情報", dbg_panel != null and dbg_panel.visible)

func _draw_button(r: Rect2, label: String, active: bool) -> void:
	var bg := Color(0.16, 0.45, 0.60, 0.55) if active else Color(0.10, 0.20, 0.30, 0.55)
	draw_rect(r, bg)
	draw_rect(r, Color(0.6, 0.85, 1.0, 0.45), false, 1.5)
	draw_string(font, Vector2(r.position.x, r.position.y + 36.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color(0.85, 0.94, 1.0))

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

	_draw_buttons()

	# 実測の性能。処理落ちしていると sim が目標ティックレートに届かない。
	# 画面下端はスマホのブラウザUIに隠れるため、上部のHUD内に置く。
	var hz_ok: bool = sim_hz_shown >= Cfg.TICKS - 3
	draw_string(font, Vector2(VW - 158.0, 80.0),
		"%d fps / sim %d Hz" % [fps_shown, sim_hz_shown],
		HORIZONTAL_ALIGNMENT_RIGHT, 150.0, 13,
		Color(0.5, 0.62, 0.72, 0.85) if hz_ok else Color(1.0, 0.55, 0.45, 1.0))
	if slow:
		draw_string(font, Vector2(18.0, 80.0), "SLOW 0.25x", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(1, 1, 0.6, 0.9))

# ---------------------------------------------------------------- デバッグUI

var dbg_panel: PanelContainer
var dbg_readout: Label

func _toggle_debug() -> void:
	dbg_panel.visible = not dbg_panel.visible

func _reset() -> void:
	sim.reset(seed_value)
	pointers.clear()
	_ice_tick = -1
	ripples.clear()
	popups.clear()
	escapes.clear()
	audio.stop_bgm()
	audio.start_bgm()

func _build_debug_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# Control 側にも同じフォントを効かせる（Webでは日本語が豆腐になるため）
	if font != null:
		var theme := Theme.new()
		theme.default_font = font
		theme.default_font_size = 12
		layer.theme = theme
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
