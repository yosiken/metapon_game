## 音の再生。仕様書 §11.1 に対応。
##
## 重要な原則（§11.1 / §12.2）:
##   **BGM の再生位置は sim 時刻に従わせる。sim が真であり、音が追従する。**
##   逆にすると（音を時計にすると）決定性が壊れ、リプレイが再現しなくなる。
##
## ファイルが無い場合は黙ってスキップするので、音源が未配置でもゲームは動く。
class_name GameAudio
extends Node

const BGM_PATH := "res://asetts/sound/bgm/Breathing Spaces.mp3"

## イベント -> { path, pitch, db }
## 手持ちの音が足りないイベントは、既存の音のピッチ/音量を振って代用している。
## 専用の音が用意できたら path を差し替えるだけでよい。
const SE := {
	"grab":    {"path": "res://asetts/sound/se/click.wav",    "pitch": 1.00, "db":  -9.0},
	"freeze":  {"path": "res://asetts/sound/se/Freezing.wav", "pitch": 1.00, "db":   0.0},
	# 際結氷（§5.8）は専用音が無いので Freezing を1オクターブ上げて代用
	"kiwa":    {"path": "res://asetts/sound/se/Freezing.wav", "pitch": 2.00, "db":   2.0},
	# 融解。これが拍グリッド上で鳴り、ゲームのパーカッションになる（§4.6）
	"melt":    {"path": "res://asetts/sound/se/Melting.wav",  "pitch": 1.00, "db":  -1.0},
	"surface": {"path": "res://asetts/sound/se/floatup.wav",  "pitch": 1.00, "db":   2.0},
	# 沈降して着地。専用音が無いので Melting を低く鈍く
	"land":    {"path": "res://asetts/sound/se/Melting.wav",  "pitch": 0.62, "db":  -4.0},
	# 際窓のグリッド頭で鳴る小さなチック（§6.4.1）
	"tick":    {"path": "res://asetts/sound/se/click.wav",    "pitch": 2.20, "db": -16.0},
}

## 連鎖数 → 半音。メジャースケールで上がっていく（§11.1）
const CHAIN_SEMITONES := [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24]

const SE_VOICES := 12
const DRIFT_TOLERANCE := 0.08        # これ以上ズレたら BGM をシークして sim に合わせる
const DRIFT_CHECK_INTERVAL := 1.0

var bgm: AudioStreamPlayer
var _voices: Array = []
var _next_voice := 0
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
	var length := bgm.stream.get_length()
	if length <= 0.0:
		return
	var want: float = fposmod(sim_seconds, length)
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
	var p: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = stream
	p.pitch_scale = clampf(float(cfg["pitch"]) * pitch_mult, 0.25, 4.0)
	p.volume_db = se_volume_db + float(cfg["db"]) + db_offset
	p.play()

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
