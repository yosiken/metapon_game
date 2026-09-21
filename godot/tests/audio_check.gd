## 音源が拍に乗るかを測る。
##   godot --headless --path godot --script res://tests/audio_check.gd
extends SceneTree

func _init() -> void:
	var beat := 60.0 / float(Cfg.BPM)
	var bar := beat * 4.0
	var g16 := beat / 4.0
	print("BPM %d  1拍 %.4f s  1小節(4/4) %.4f s  16分 %.4f s\n" % [Cfg.BPM, beat, bar, g16])

	print("--- BGM ---")
	if ResourceLoader.exists(GameAudio.BGM_PATH):
		var st: AudioStream = load(GameAudio.BGM_PATH)
		var len_s := st.get_length()
		var beats := len_s / beat
		var bars := len_s / bar
		print("  %s" % GameAudio.BGM_PATH.get_file())
		print("  長さ        : %.4f s" % len_s)
		print("  拍数        : %.4f 拍" % beats)
		print("  小節数      : %.4f 小節" % bars)
		var off_beats: float = absf(beats - round(beats))
		var off_bars: float = absf(bars - round(bars))
		print("  拍からのズレ: %.4f 拍 = %.1f ms" % [off_beats, off_beats * beat * 1000.0])
		print("  小節のズレ  : %.4f 小節 = %.1f ms" % [off_bars, off_bars * bar * 1000.0])
		if off_bars * bar * 1000.0 < 5.0:
			print("  => 小節の整数倍。ループしても拍がずれない")
		elif off_beats * beat * 1000.0 < 5.0:
			print("  => 拍の整数倍だが小節の途中で切れている")
		else:
			print("  => ★拍に乗っていない。ループ継ぎ目で拍がずれる")
		print("  loop 属性   : %s" % ("あり" % [] if "loop" in st else "なし"))
	else:
		print("  未配置")

	print("\n--- SE ---")
	print("  %-14s %10s %10s  %s" % ["ファイル", "長さ", "16分比", "判定"])
	var seen := {}
	for key in GameAudio.SE.keys():
		var path: String = GameAudio.SE[key]["path"]
		if seen.has(path):
			continue
		seen[path] = true
		if not ResourceLoader.exists(path):
			print("  %-14s %10s" % [path.get_file(), "未配置"])
			continue
		var st: AudioStream = load(path)
		var len_s := st.get_length()
		var ratio := len_s / g16
		var verdict := "OK"
		if ratio > 4.0:
			verdict = "★長い（1拍を超える。拍が濁る）"
		elif ratio > 2.0:
			verdict = "やや長い（8分を超える）"
		print("  %-14s %8.3f s %9.2f  %s" % [path.get_file(), len_s, ratio, verdict])
	print("\n  ※ 融解音(Melting)は拍グリッド上で鳴る打楽器なので、短いほどよい（§4.6）")
	quit()
