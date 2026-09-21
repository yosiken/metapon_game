## ゲームロジック本体。DOM/描画/入力に一切依存しない純粋な状態機械（12.2）。
## 更新順は仕様書 12.4 に従う。
class_name Sim
extends RefCounted

const DT := 1.0 / float(Cfg.TICKS)

# --- 状態 ---
var rng: XorRng
var frame: int = 0
var ground: Array = []        # Array[Array[MBlock]]  index 0 = 海底
var falling: Array = []       # [{ "col": int, "y": float, "block": MBlock }]
var stacks: Array = []        # Array[AirStack]
var chain: int = 0
var chain_expire: int = -1    # ここまでは連鎖が繋がる (5.3)
var score: float = 0.0
var level: int = 1
var game_over: bool = false
var overflow_since: int = -1
var drop_accum: float = 0.0
var color_bag: Array = []

var _next_id: int = 1
var _next_group: int = 1

# --- デバッグ用トグル（P0 のコア検証を邪魔しないよう個別に切れる） ---
var speed_mult: float = 1.0      # 速度プリセット (8.3.3)
var g_mult: float = 1.0
var quantize_melt: bool = true   # 4.6 拍量子化
var kiwa_enabled: bool = true    # 5.8 際結氷
var ice_is_wall: bool = true     # 5.6 氷ブロックは壁
var level_override: int = 0      # 0 = 自動

# --- 統計・イベント（view と音が読む。sim は書くだけ） ---
var stat_max_chain: int = 0
var stat_kiwa: int = 0
var stat_freeze_after_first: int = 0
var stat_surfaced: int = 0
var stat_sunk: int = 0
var ev_freeze: Array = []     # [{ "k": int, "chain": int, "kiwa": bool, "col": int, "row": float }]
var ev_melt: Array = []       # [{ "col": int, "row": float }]
var ev_surface: Array = []    # [{ "count", "chain", "gained", "cols", "row" }]
var ev_land: Array = []

func _init(seed_value: int = 12345) -> void:
	reset(seed_value)

func reset(seed_value: int) -> void:
	rng = XorRng.new(seed_value)
	frame = 0
	ground = []
	for c in range(Cfg.COLS):
		ground.append([])
	falling = []
	stacks = []
	chain = 0
	chain_expire = -1
	score = 0.0
	level = 1
	game_over = false
	overflow_since = -1
	drop_accum = 0.0
	color_bag = []
	_next_id = 1
	_next_group = 1
	stat_max_chain = 0
	stat_kiwa = 0
	stat_freeze_after_first = 0
	stat_surfaced = 0
	stat_sunk = 0
	_clear_events()

func _clear_events() -> void:
	ev_freeze = []
	ev_melt = []
	ev_surface = []
	ev_land = []

# ---------------------------------------------------------------- パラメータ

func elapsed() -> float:
	return float(frame) * DT

func params() -> Dictionary:
	return Cfg.level_params(level)

func grid_frames() -> int:
	return Cfg.grid_frames(int(params()["subdiv"]))

func gravity() -> float:
	return float(params()["g"]) * g_mult

# ---------------------------------------------------------------- メインループ

func step() -> void:
	if game_over:
		return
	_clear_events()
	frame += 1
	level = Cfg.level_of(elapsed()) if level_override <= 0 else level_override

	_supply()              # 2. 供給
	_advance_falling()     # 3. 沈降瓦礫の前進
	_integrate_stacks()    # 4. スタックの積分
	_process_melt()        # 5. 融解処理
	_check_surface()       # 6. 浮上判定
	_check_landing()       # 7. 着地判定
	_detect_matches()      # 8. マッチ判定
	_process_freeze()      # 9. 結氷処理
	_check_overflow()      # 10. 危険 / ゲームオーバー判定

# ---------------------------------------------------------------- 2. 供給 (8.2)

func _supply() -> void:
	var p := params()
	drop_accum += float(p["drop"]) * speed_mult * DT
	while drop_accum >= 1.0:
		drop_accum -= 1.0
		_spawn_debris()

func _spawn_debris() -> void:
	var col := _pick_column()
	var color := _pick_color(col)
	var b := MBlock.new()
	b.id = _next_id
	_next_id += 1
	b.color = color
	b.kind = _pick_kind()
	falling.append({"col": col, "y": float(Cfg.ROWS + Cfg.BUFFER_ROWS), "block": b})

## 低い列に偏って供給する。weight(c) = (maxH - h(c) + 1) ^ 1.5
func _pick_column() -> int:
	var heights := []
	var max_h := 0
	for c in range(Cfg.COLS):
		var h := _stack_top_row(c)
		heights.append(h)
		max_h = maxi(max_h, int(h))
	var weights := []
	var total := 0.0
	for c in range(Cfg.COLS):
		var w: float = pow(float(max_h) - heights[c] + 1.0, 1.5)
		weights.append(w)
		total += w
	var r := rng.next_float() * total
	for c in range(Cfg.COLS):
		r -= weights[c]
		if r <= 0.0:
			return c
	return Cfg.COLS - 1

## バッグ方式で色枯れを防ぎ、棚ぼた結氷を 90% で引き直す (8.3.4)
func _pick_color(col: int) -> int:
	var n := int(params()["colors"])
	var color := _draw_from_bag(n)
	if _would_instant_match(col, color) and rng.next_float() < 0.90:
		color = _draw_from_bag(n)
	return color

func _draw_from_bag(n: int) -> int:
	if color_bag.is_empty():
		for i in range(n * 2):
			color_bag.append(i % n)
		# Fisher-Yates
		for i in range(color_bag.size() - 1, 0, -1):
			var j := rng.next_int(i + 1)
			var t = color_bag[i]
			color_bag[i] = color_bag[j]
			color_bag[j] = t
	var c: int = color_bag.pop_back()
	return c % n

func _would_instant_match(col: int, color: int) -> bool:
	# 縦: 着地点の下2個が同色か
	var g: Array = ground[col]
	if g.size() >= 2 and g[g.size() - 1].color == color and g[g.size() - 2].color == color:
		return true
	# 横: 着地する行で左右に2連続できるか
	var row := g.size()
	var run := 1
	var c := col - 1
	while c >= 0 and ground[c].size() > row and ground[c][row].color == color:
		run += 1
		c -= 1
	c = col + 1
	while c < Cfg.COLS and ground[c].size() > row and ground[c][row].color == color:
		run += 1
		c += 1
	return run >= Cfg.MATCH_MIN

func _pick_kind() -> int:
	if level >= 4:
		var rock_rate: float = minf(0.05 + 0.01 * float(level - 4), 0.12)
		if rng.next_float() < rock_rate:
			return MBlock.Kind.ROCK
	if level >= 3:
		var heavy_rate: float = minf(0.06 + 0.015 * float(level - 3), 0.15)
		if rng.next_float() < heavy_rate:
			return MBlock.Kind.HEAVY
	return MBlock.Kind.NORMAL

# ---------------------------------------------------------------- 3. 沈降

## 列 col で瓦礫が着地する行（スタックがあればその上端）
func _stack_top_row(col: int) -> float:
	var top := float(ground[col].size())
	var s := _stack_in_column(col)
	if s != null and s.cols.has(col):
		top = maxf(top, float(s.base_row) + s.y + float(s.cols[col].size()))
	return top

func _stack_in_column(col: int) -> AirStack:
	for s: AirStack in stacks:
		if s.cols.has(col):
			return s
	return null

func _advance_falling() -> void:
	var keep := []
	for f: Dictionary in falling:
		f["y"] -= Cfg.FALL_SPEED * DT
		var land := _stack_top_row(f["col"])
		if f["y"] <= land:
			var s := _stack_in_column(f["col"])
			if s != null and s.cols.has(f["col"]) and land > float(ground[f["col"]].size()):
				# 浮上中のスタックに降り積もる (5.7)
				s.cols[f["col"]].append(f["block"])
			else:
				ground[f["col"]].append(f["block"])
		else:
			keep.append(f)
	falling = keep

# ---------------------------------------------------------------- 4. 積分 (4.3)

func _integrate_stacks() -> void:
	var g := gravity()
	for s: AirStack in stacks:
		var ft := s.total_buoyancy(frame)
		var wt := s.total_weight()
		var a := (ft / wt - g) * Cfg.BASE_ACCEL
		var prev_v := s.v
		s.v = clampf(s.v + a * DT, -Cfg.V_MAX_DOWN, Cfg.V_MAX_UP)
		s.y += s.v * DT
		if s.v < 0.0:
			s.ever_sank = true
		# リフリーズ: 沈降から再び浮上に転じた (5.5)
		if s.ever_sank and prev_v <= 0.0 and s.v > 0.0 and not s.reboosted:
			s.reboosted = true

# ---------------------------------------------------------------- 5. 融解 (4.6)

func _process_melt() -> void:
	for s: AirStack in stacks:
		var melted := []
		for g: Dictionary in s.groups:
			if g["melt_at"] <= frame:
				melted.append(g)
		if melted.is_empty():
			continue
		for g: Dictionary in melted:
			var gid: int = g["id"]
			for c in s.cols.keys():
				var arr: Array = s.cols[c]
				for i in range(arr.size() - 1, -1, -1):
					if arr[i].group_id == gid:
						ev_melt.append({"col": c, "row": float(s.base_row) + s.y + float(i)})
						arr.remove_at(i)
			s.groups.erase(g)
		chain_expire = frame + Cfg.CHAIN_GRACE_FRAMES
	_prune_empty_stacks()
	if not _chain_is_live():
		chain = 0

func _prune_empty_stacks() -> void:
	for i in range(stacks.size() - 1, -1, -1):
		if stacks[i].is_empty():
			stacks.remove_at(i)

func _has_active_ice() -> bool:
	for s: AirStack in stacks:
		if s.total_buoyancy(frame) > 0.0:
			return true
	return false

func _chain_is_live() -> bool:
	return _has_active_ice() or frame <= chain_expire

# ---------------------------------------------------------------- 6. 浮上 (4.3)

func _check_surface() -> void:
	for i in range(stacks.size() - 1, -1, -1):
		var s: AirStack = stacks[i]
		if float(s.base_row) + s.y >= float(Cfg.ROWS):
			var n := s.block_count()
			var rocks := 0
			for c in s.cols:
				for b in s.cols[c]:
					if b.kind == MBlock.Kind.ROCK:
						rocks += 1
			# 9.2 浮上スコア
			var gained := float(n) * 50.0 * Cfg.chain_mult(s.max_chain) + float(rocks) * 150.0
			score += gained
			stat_surfaced += n
			# view 側で「どこで・いくら」成功したかを表示するためのメタデータ。
			# 判定/スコア計算そのものには使わない（sim の純粋性は保つ）。
			ev_surface.append({
				"count": n, "chain": s.max_chain, "gained": gained,
				"cols": s.cols.keys(), "row": float(Cfg.ROWS),
			})
			stacks.remove_at(i)

# ---------------------------------------------------------------- 7. 着地

func _check_landing() -> void:
	for i in range(stacks.size() - 1, -1, -1):
		var s: AirStack = stacks[i]
		if s.v > 0.0:
			continue
		var floor_row := 0.0
		for c in s.cols.keys():
			floor_row = maxf(floor_row, float(ground[c].size()))
		if float(s.base_row) + s.y <= floor_row:
			for c in s.cols.keys():
				for b in s.cols[c]:
					b.state = MBlock.State.PLAIN
					b.group_id = -1
					ground[c].append(b)
			stat_sunk += 1
			ev_land.append({"count": s.block_count()})
			stacks.remove_at(i)

# ---------------------------------------------------------------- 8. マッチ判定

## 1つの「剛体」を列→ブロック配列の辞書として扱う。ground も stack も同じ関数で処理する。
func _bodies() -> Array:
	var out := [{"kind": "ground", "cols": _ground_as_dict(), "stack": null}]
	for s: AirStack in stacks:
		out.append({"kind": "stack", "cols": s.cols, "stack": s})
	return out

func _ground_as_dict() -> Dictionary:
	var d := {}
	for c in range(Cfg.COLS):
		d[c] = ground[c]
	return d

func _detect_matches() -> void:
	for body in _bodies():
		var comps := _find_components(body["cols"])
		for comp in comps:
			var at := frame + Cfg.FREEZE_DELAY_FRAMES
			# 既に FREEZING のものが混じっていればその時刻を引き継ぐ（結氷猶予の拡張 5.2）
			for cell in comp:
				var b: MBlock = body["cols"][cell.x][cell.y]
				if b.state == MBlock.State.FREEZING:
					at = mini(at, b.freeze_at)
			for cell in comp:
				var b: MBlock = body["cols"][cell.x][cell.y]
				if b.state == MBlock.State.PLAIN:
					b.state = MBlock.State.FREEZING
				b.freeze_at = at

## 同色3連続以上に属するセルを連結成分としてまとめて返す
func _find_components(cols_dict: Dictionary) -> Array:
	var marked := {}   # Vector2i -> color
	for c in cols_dict.keys():
		var arr: Array = cols_dict[c]
		for r in range(arr.size()):
			var b: MBlock = arr[r]
			if not b.can_freeze() or b.state == MBlock.State.ICE:
				continue
			if _run_len(cols_dict, c, r, 0, 1) >= Cfg.MATCH_MIN or _run_len(cols_dict, c, r, 1, 0) >= Cfg.MATCH_MIN:
				marked[Vector2i(c, r)] = b.color
	if marked.is_empty():
		return []
	var seen := {}
	var comps := []
	for key in marked.keys():
		if seen.has(key):
			continue
		var color: int = marked[key]
		var comp := []
		var queue := [key]
		seen[key] = true
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_back()
			comp.append(cur)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = cur + d
				if seen.has(nb) or not marked.has(nb):
					continue
				if marked[nb] != color:
					continue
				seen[nb] = true
				queue.append(nb)
		comps.append(comp)
	return comps

func _run_len(cols_dict: Dictionary, c: int, r: int, dc: int, dr: int) -> int:
	var b := _at(cols_dict, c, r)
	if b == null:
		return 0
	var n := 1
	for sgn in [1, -1]:
		var i := 1
		while true:
			var o := _at(cols_dict, c + dc * i * sgn, r + dr * i * sgn)
			if o == null or o.color != b.color or not o.can_freeze() or o.state == MBlock.State.ICE:
				break
			n += 1
			i += 1
	return n

func _at(cols_dict: Dictionary, c: int, r: int) -> MBlock:
	if not cols_dict.has(c):
		return null
	var arr: Array = cols_dict[c]
	if r < 0 or r >= arr.size():
		return null
	return arr[r]

# ---------------------------------------------------------------- 9. 結氷 (4.2 / 5.8)

func _process_freeze() -> void:
	for body in _bodies():
		var ready := _ready_components(body["cols"])
		for comp in ready:
			_ignite(body, comp)

## freeze_at に達した FREEZING の連結成分
func _ready_components(cols_dict: Dictionary) -> Array:
	var marked := {}
	for c in cols_dict.keys():
		var arr: Array = cols_dict[c]
		for r in range(arr.size()):
			var b: MBlock = arr[r]
			if b.state == MBlock.State.FREEZING and b.freeze_at <= frame:
				marked[Vector2i(c, r)] = b.color
	if marked.is_empty():
		return []
	var seen := {}
	var comps := []
	for key in marked.keys():
		if seen.has(key):
			continue
		var color: int = marked[key]
		var comp := []
		var queue := [key]
		seen[key] = true
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_back()
			comp.append(cur)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = cur + d
				if seen.has(nb) or not marked.has(nb) or marked[nb] != color:
					continue
				seen[nb] = true
				queue.append(nb)
		comps.append(comp)
	return comps

func _ignite(body: Dictionary, comp: Array) -> void:
	var is_ground: bool = body["kind"] == "ground"
	var stack: AirStack = body["stack"]

	# モックの制約: 1列につき水中スタックは1本まで。
	# 既にスタックが載っている列の海底マッチは、その列が空くまで持ち越す。
	if is_ground:
		for cell in comp:
			if _stack_in_column(cell.x) != null:
				return
		if stacks.size() >= Cfg.MAX_STACKS:
			return

	var k := comp.size()

	# --- 連鎖 (5.3) ---
	if _chain_is_live():
		chain += 1
	else:
		chain = 1
	stat_max_chain = maxi(stat_max_chain, chain)
	if chain >= 2:
		stat_freeze_after_first += 1

	# --- 際結氷 (5.8): 同一スタック内の氷が最後の1グリッドに入っているか ---
	var kiwa := false
	if kiwa_enabled and stack != null:
		var soon := stack.soonest_melt(frame)
		if soon > 0 and soon <= grid_frames():
			kiwa = true
			stat_kiwa += 1

	# --- 浮力とスコア (5.2 / 5.4 / 9.1) ---
	var same_hit: float = 1.0 + 0.25 * float(maxi(0, k - Cfg.MATCH_MIN))
	var cm := Cfg.chain_mult(chain)
	var kiwa_score: float = Cfg.KIWA_SCORE_MULT if kiwa else 1.0
	var kiwa_buoy: float = Cfg.KIWA_BUOY_MULT if kiwa else 1.0
	var reboost: float = 1.5 if (stack != null and stack.reboosted) else 1.0

	var raw_buoy := 0.0
	for cell in comp:
		raw_buoy += (body["cols"][cell.x][cell.y] as MBlock).buoyancy()
	var buoy := raw_buoy * minf(cm, Cfg.BUOY_MULT_CAP) * same_hit * kiwa_buoy
	score += float(k) * 100.0 * cm * same_hit * kiwa_score * reboost

	# --- 融解時刻を拍グリッドへ量子化 (4.6) ---
	var gf := grid_frames()
	var grids := int(params()["grids"])
	var melt_at: int
	if quantize_melt:
		melt_at = int(ceil(float(frame) / float(gf))) * gf + grids * gf
	else:
		melt_at = frame + grids * gf

	var gid := _next_group
	_next_group += 1
	var min_row := 1 << 30
	var involved := {}
	for cell in comp:
		var b: MBlock = body["cols"][cell.x][cell.y]
		b.state = MBlock.State.ICE
		b.group_id = gid
		b.melt_at = melt_at
		min_row = mini(min_row, cell.y)
		involved[cell.x] = true

	var target: AirStack = stack
	if is_ground:
		target = _lift_from_ground(involved.keys(), min_row)
	target.groups.append({"id": gid, "buoy": buoy, "melt_at": melt_at})
	target.max_chain = maxi(target.max_chain, chain)
	# 初速インパルス: 凍結時の体積膨張 (4.3)
	target.v += Cfg.FREEZE_IMPULSE * float(k) / target.total_weight()

	ev_freeze.append({"k": k, "chain": chain, "kiwa": kiwa, "col": comp[0].x,
		"row": float(target.base_row) + target.y + float(comp[0].y - min_row)})

## 海底の min_row 以上を持ち上げて新しいスタックを作る (4.2)
func _lift_from_ground(cols_involved: Array, min_row: int) -> AirStack:
	var s := AirStack.new()
	s.id = _next_id
	_next_id += 1
	s.base_row = min_row
	s.y = 0.0
	s.v = 0.0
	for c in cols_involved:
		var arr: Array = ground[c]
		var lifted := []
		while arr.size() > min_row:
			lifted.append(arr[min_row])
			arr.remove_at(min_row)
		s.cols[c] = lifted
	stacks.append(s)
	return s

# ---------------------------------------------------------------- 10. 埋没 (4.5)

func ground_height() -> int:
	var h := 0
	for c in range(Cfg.COLS):
		h = maxi(h, ground[c].size())
	return h

func _check_overflow() -> void:
	if ground_height() > Cfg.ROWS:
		if overflow_since < 0:
			overflow_since = frame
		elif frame - overflow_since >= Cfg.OVERFLOW_GRACE_FRAMES:
			game_over = true
	else:
		overflow_since = -1

# ---------------------------------------------------------------- 操作 (6.1)

## col 内で idx のブロックを to へ動かす。間のブロックは逆方向に1つずつシフトする。
## 氷ブロックは掴めず、通り抜けもできない (5.6)。戻り値は実際に落ち着いた index。
func move_in_column(cols_dict: Dictionary, col: int, idx: int, to: int) -> int:
	if not cols_dict.has(col):
		return idx
	var arr: Array = cols_dict[col]
	if idx < 0 or idx >= arr.size():
		return idx
	var b: MBlock = arr[idx]
	if b.state == MBlock.State.ICE:
		return idx
	var lo := 0
	var hi := arr.size() - 1
	if ice_is_wall:
		var i := idx - 1
		while i >= 0:
			if arr[i].state == MBlock.State.ICE:
				lo = i + 1
				break
			i -= 1
		i = idx + 1
		while i < arr.size():
			if arr[i].state == MBlock.State.ICE:
				hi = i - 1
				break
			i += 1
	var t := clampi(to, lo, hi)
	if t == idx:
		return idx
	arr.remove_at(idx)
	arr.insert(t, b)
	return t
