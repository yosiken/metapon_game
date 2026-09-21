## 音の再生。仕様書 §11.1 に対応。
##
## 重要な原則（§11.1 / §12.2）:
##   **BGM の再生位置は sim 時刻に従わせる。sim が真であり、音が追従する。**
##   逆にすると（音を時計にすると）決定性が壊れ、リプレイが再現しなくなる。
##
## ファイルが無い場合は黙ってスキップするので、音源が未配置でもゲームは動く。
class_name GameAudio
extends Node

const BGM_PATH := "res://asetts/sound/bgm/Deep_Underwater.ogg"

## イベント -> { path, pitch, db, lead, max_dur }
##   lead    : ファイル先頭の無音をスキップする秒数。
##             実測でどの wav にも 42〜44ms の無音が入っている。16分音符が 117ms
##             なので、補正しないと打楽器が常に拍の 36% 遅れて鳴る（§4.6 が壊れる）。
##   max_dur : この秒数でフェードアウトさせる。0 なら最後まで鳴らす。
##             融解音は 16分グリッドで連打されうるため、短く切らないと団子になる。
##
## 手持ちの音が足りないイベントは、既存の音のピッチ/音量を振って代用している。
## 専用の音が用意できたら path を差し替えるだけでよい。
const SE := {
	"grab":    {"path": "res://asetts/sound/se/click.wav",    "pitch": 1.00, "db":  -9.0, "lead": 0.042, "max_dur": 0.15},
	"freeze":  {"path": "res://asetts/sound/se/Freezing.wav", "pitch": 1.00, "db":   0.0, "lead": 0.043, "max_dur": 0.45},
	# 際結氷（§5.8）は専用音が無いので Freezing を1オクターブ上げて代用
	"kiwa":    {"path": "res://asetts/sound/se/Freezing.wav", "pitch": 2.00, "db":   2.0, "lead": 0.043, "max_dur": 0.35},
	# 融解。これが拍グリッド上で鳴り、ゲームのパーカッションになる（§4.6）
	"melt":    {"path": "res://asetts/sound/se/Melting.wav",  "pitch": 1.00, "db":  -1.0, "lead": 0.042, "max_dur": 0.22},
	"surface": {"path": "res://asetts/sound/se/floatup.wav",  "pitch": 1.00, "db":   2.0, "lead": 0.044, "max_dur": 0.0},
	# 沈降して着地。専用音が無いので Melting を低く鈍く
	"land":    {"path": "res://asetts/sound/se/Melting.wav",  "pitch": 0.62, "db":  -4.0, "lead": 0.042, "max_dur": 0.50},
	# 際窓のグリッド頭で鳴る小さなチック（§6.4.1）
	"tick":    {"path": "res://asetts/sound/se/click.wav",    "pitch": 2.20, "db": -16.0, "lead": 0.042, "max_dur": 0.10},
}

## 連鎖数 → 半音。メジャースケールで上がっていく（§11.1）
const CHAIN_SEMITONES := [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24]

const SE_VOICES := 12
const DRIFT_TOLERANCE := 0.08        # これ以上ズレたら BGM をシークして sim に合わせる
const DRIFT_CHECK_INTERVAL := 1.0

## BGM の先頭無音ぶんのオフセット [s]。耳で合わせて詰める。
const BGM_LEAD := 0.0
## ループ長 [s]。0 ならファイル長をそのまま使う。
## 実測では Breathing Spaces.mp3 は 229.85s = 122.59 小節（BPM128）で、
## 小節の整数倍になっていない。ループの継ぎ目で拍が 0.41 小節ぶんずれる。
## 122 小節ぶん（228.75s）を指定すれば拍を保ったままループできる。
const BGM_LOOP_SEC := 0.0

var bgm: AudioStreamPlayer
var _voices: Array = []
var _next_voice := 0
var _voice_tweens: Array = []
var _streams := {}                   # path -> AudioStream（同じファイルは1回だけ読む）
var _last_drift_check := -99.0
var _missing: Array = []

var bgm_volume_db := -9.0
var se_volume_db := -4.0
var enabled := true

func _ready() -> void:
	bgm = AudioStreamPlayer.new()
	bgm.volume_db = bgm_volume_db
	add_child(bgm)
	for i in range(SE_VOICES):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
		_voice_tweens.append(null)
	_load_all()

func _load_all() -> void:
	if ResourceLoader.exists(BGM_PATH):
		bgm.stream = load(BGM_PATH)
		# .import の設定に依存せず、コード側でループを保証する
		if "loop" in bgm.stream:
			bgm.stream.loop = true
	else:
		_missing.append(BGM_PATH)
	for key in SE.keys():
		var path: String = SE[key]["path"]
		if _streams.has(path):
			continue
		if ResourceLoader.exists(path):
			_streams[path] = load(path)
		elif not _missing.has(path):
			_missing.append(path)
	if _missing.is_empty():
		print("[audio] 読み込み完了")
	else:
		print("[audio] 未配置のため該当イベントは無音: %s" % ", ".join(_missing))

func has_any() -> bool:
	return bgm.stream != null or not _streams.is_empty()

func start_bgm() -> void:
	if bgm.stream != null and not bgm.playing:
		bgm.play()

func stop_bgm() -> void:
	bgm.stop()

## sim 時刻に BGM を追従させる。ズレが閾値を超えたときだけシークする。
func sync_bgm(sim_seconds: float) -> void:
	if not enabled or bgm.stream == null:
		return
	if not bgm.playing:
		bgm.play()   # mp3 のループ設定が効いていない場合の保険
		return
	if sim_seconds - _last_drift_check < DRIFT_CHECK_INTERVAL:
		return
	_last_drift_check = sim_seconds
	var length := BGM_LOOP_SEC if BGM_LOOP_SEC > 0.0 else bgm.stream.get_length()
	if length <= 0.0:
		return
	var want: float = fposmod(sim_seconds + BGM_LEAD, length)
	var have: float = bgm.get_playback_position()
	var diff: float = want - have
	if diff > length * 0.5:
		diff -= length
	elif diff < -length * 0.5:
		diff += length
	if absf(diff) > DRIFT_TOLERANCE:
		bgm.seek(want)

func play(key: String, pitch_mult: float = 1.0, db_offset: float = 0.0) -> void:
	if not enabled or not SE.has(key):
		return
	var cfg: Dictionary = SE[key]
	var stream = _streams.get(cfg["path"])
	if stream == null:
		return
	var idx := _next_voice
	_next_voice = (_next_voice + 1) % _voices.size()
	var p: AudioStreamPlayer = _voices[idx]
	# 前回のフェードが残っていると新しい音を止めてしまうので破棄する
	var old_tw = _voice_tweens[idx]
	if old_tw != null and old_tw.is_valid():
		old_tw.kill()
	_voice_tweens[idx] = null

	p.stream = stream
	p.pitch_scale = clampf(float(cfg["pitch"]) * pitch_mult, 0.25, 4.0)
	var vol := se_volume_db + float(cfg["db"]) + db_offset
	p.volume_db = vol
	# 先頭の無音を飛ばして鳴らす。これをしないと拍から 42ms 遅れる
	p.play(float(cfg.get("lead", 0.0)))

	var max_dur := float(cfg.get("max_dur", 0.0))
	if max_dur > 0.0:
		var tw := create_tween()
		tw.tween_interval(max_dur * 0.6)
		tw.tween_property(p, "volume_db", vol - 36.0, max_dur * 0.4)
		tw.tween_callback(p.stop)
		_voice_tweens[idx] = tw

## 連鎖数に応じて音階を上げる（§11.1）
func play_freeze(chain: int) -> void:
	var idx: int = clampi(chain - 1, 0, CHAIN_SEMITONES.size() - 1)
	var semi: float = float(CHAIN_SEMITONES[idx])
	play("freeze", pow(2.0, semi / 12.0))

## sim が 1 ティック進むたびに呼ぶ。イベントを音に変換する。
func consume(sim: Sim, prev_ice_tick: int) -> int:
	if not enabled:
		return prev_ice_tick
	for e: Dictionary in sim.ev_freeze:
		if e["kiwa"]:
			play("kiwa")
		play_freeze(int(e["chain"]))
	# 融解は拍グリッド上でしか起きないので、そのまま打楽器になる（§4.6）。
	# 同一ティックに複数融けても 1 回にまとめ、数で音量を上げる。
	if not sim.ev_melt.is_empty():
		play("melt", 1.0, minf(float(sim.ev_melt.size() - 1) * 1.5, 4.0))
	for e: Dictionary in sim.ev_surface:
		play("surface")
	if not sim.ev_land.is_empty():
		play("land")
	# 際窓に入っている氷があるとき、グリッドの頭で小さくチックを鳴らす
	var gf := sim.grid_frames()
	var tick_id := int(sim.frame / gf)
	if tick_id != prev_ice_tick:
		for s: AirStack in sim.stacks:
			var soon := s.soonest_melt(sim.frame)
			if soon > 0 and soon <= gf:
				play("tick")
				break
		return tick_id
	return prev_ice_tick

func _exit_tree() -> void:
	bgm.stream = null
	for p: AudioStreamPlayer in _voices:
		p.stream = null
	_streams.clear()
