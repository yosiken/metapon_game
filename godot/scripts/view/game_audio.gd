## 音の再生。仕様書 §11.1 に対応。
##
## 重要な原則（§11.1 / §12.2）:
##   **BGM の再生位置は sim 時刻に従わせる。sim が真であり、音が追従する。**
##   逆にすると（音を時計にすると）決定性が壊れ、リプレイが再現しなくなる。
##
## ファイルが無い場合は黙ってスキップするので、音源が未配置でもゲームは動く。
class_name GameAudio
extends Node

## 音源の配置。ファイル名が違う場合はここだけ直せばよい。
const BGM_PATH := "res://audio/bgm/main.ogg"
const SE_PATHS := {
	"grab":    "res://audio/se/grab.wav",     # ブロックを掴む
	"freeze":  "res://audio/se/freeze.wav",   # 結氷（連鎖数で音階が上がる）
	"kiwa":    "res://audio/se/kiwa.wav",     # 際結氷（§5.8）
	"melt":    "res://audio/se/melt.wav",     # 融解。これがパーカッションの実体（§4.6）
	"surface": "res://audio/se/surface.wav",  # 水面到達
	"land":    "res://audio/se/land.wav",     # 沈降して着地
	"tick":    "res://audio/se/tick.wav",     # 際窓のグリッド頭（§6.4.1）
}

## 連鎖数 → 半音。メジャースケールで上がっていく（§11.1）
const CHAIN_SEMITONES := [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24]

const SE_VOICES := 12
const DRIFT_TOLERANCE := 0.08   # これ以上ズレたら BGM をシークして sim に合わせる
const DRIFT_CHECK_INTERVAL := 1.0

var bgm: AudioStreamPlayer
var _voices: Array = []
var _next_voice := 0
var _streams := {}
var _last_drift_check := -99.0
var _missing: Array = []

var bgm_volume_db := -8.0
var se_volume_db := -4.0
var enabled := true

func _ready() -> void:
	bgm = AudioStreamPlayer.new()
	bgm.volume_db = bgm_volume_db
	add_child(bgm)
	for i in range(SE_VOICES):
		var p := AudioStreamPlayer.new()
		p.volume_db = se_volume_db
		add_child(p)
		_voices.append(p)
	_load_all()

func _load_all() -> void:
	if ResourceLoader.exists(BGM_PATH):
		bgm.stream = load(BGM_PATH)
	else:
		_missing.append(BGM_PATH)
	for key in SE_PATHS.keys():
		var path: String = SE_PATHS[key]
		if ResourceLoader.exists(path):
			_streams[key] = load(path)
		else:
			_missing.append(path)
	if _missing.is_empty():
		print("[audio] 全て読み込み済み")
	else:
		print("[audio] 未配置のため無音: %s" % ", ".join(_missing))

func has_any() -> bool:
	return bgm.stream != null or not _streams.is_empty()

func start_bgm() -> void:
	if bgm.stream != null and not bgm.playing:
		bgm.play()

func stop_bgm() -> void:
	bgm.stop()

## sim 時刻に BGM を追従させる。ズレが閾値を超えたときだけシークする。
func sync_bgm(sim_seconds: float) -> void:
	if not enabled or bgm.stream == null or not bgm.playing:
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
	# 曲の端をまたいだ場合を補正
	if diff > length * 0.5:
		diff -= length
	elif diff < -length * 0.5:
		diff += length
	if absf(diff) > DRIFT_TOLERANCE:
		bgm.seek(want)

func play(key: String, pitch: float = 1.0, volume_offset_db: float = 0.0) -> void:
	if not enabled or not _streams.has(key):
		return
	var p: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = _streams[key]
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.volume_db = se_volume_db + volume_offset_db
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
			play("kiwa", 1.0, 2.0)
		play_freeze(int(e["chain"]))
	# 融解は拍グリッド上でしか起きないので、そのまま打楽器になる（§4.6）。
	# 同一ティックに複数融けても 1 回にまとめ、数で音量を上げる。
	if not sim.ev_melt.is_empty():
		play("melt", 1.0, minf(float(sim.ev_melt.size() - 1) * 1.5, 4.0))
	for e: Dictionary in sim.ev_surface:
		play("surface", 1.0, 2.0)
	if not sim.ev_land.is_empty():
		play("land")
	# 際窓に入っている氷があるとき、グリッドの頭で小さくチックを鳴らす
	var gf := sim.grid_frames()
	var tick_id := int(sim.frame / gf)
	if tick_id != prev_ice_tick:
		for s: AirStack in sim.stacks:
			var soon := s.soonest_melt(sim.frame)
			if soon > 0 and soon <= gf:
				play("tick", 1.0, -8.0)
				break
		return tick_id
	return prev_ice_tick
