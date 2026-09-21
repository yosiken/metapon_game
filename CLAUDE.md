# METAPON リポジトリの作業メモ

スマホのブラウザで遊ぶ海中アクションパズル。企画書とGodotモックが入っている。

## ブランチ運用

| ブランチ | 用途 |
| --- | --- |
| `main` | 本流。作業ブランチから区切りごとに取り込む |
| `claude/mobile-browser-game-design-lqwx0o` | 作業ブランチ。ここで開発する |
| `gh-pages` | **Webビルドの成果物専用**。ソースは入れない |

**`main` への取り込みは確認不要**（ユーザーから許可済み）。区切りがついたら
作業ブランチから fast-forward で取り込んで push してよい。

```
git checkout main && git merge --ff-only claude/mobile-browser-game-design-lqwx0o && git push origin main
```

## ドキュメント

| ファイル | 内容 |
| --- | --- |
| `docs/game-design.md` | 開発仕様書（本体）。数値の根拠はすべてここ |
| `docs/pitch.md` | 企画概要（配布用） |
| `docs/pitch-script.md` / `docs/speech.md` | 口頭説明原稿 |
| `docs/ad-copy.md` | ストア・SNS向けの広告文 |
| `docs/ideas.md` | アイデアプール（採用/未採用の管理） |

仕様を変えたら `docs/game-design.md` の該当箇所も直す。数値は仕様書と
`godot/scripts/sim/cfg.gd` の両方にあるので、片方だけ直さないこと。

## Godot モック

`godot/` に Godot 4.7 のプロジェクト。**4.3 / 4.4.1 / 4.7 で動作確認済み**。

### 設計上の約束

- `scripts/sim/` は描画・入力・エンジンAPIに依存しない純粋なロジック（仕様書 §12.2）。
  ここに `Engine` や `Node` を持ち込まない
- 固定ティックレート。**`TICKS * 15 / BPM` が整数**になる値を使う（§4.6.3）。
  現在 BPM130 / 78Hz（1拍=36 / 8分=18 / 16分=9 ティック）
- 乱数は `XorRng` のみ。`randi()` 等をsim層で使わない（決定性が壊れる）
- 数値は `scripts/sim/cfg.gd` に集約。sim/view側に直書きしない

### テスト

変更したら必ず通すこと。

```
godot --headless --path godot --script res://tests/spec_check.gd      # 仕様書 付録B の数値と一致するか
godot --headless --path godot --script res://tests/headless_check.gd  # スモーク + 決定性 + 拍量子化
godot --headless --path godot --script res://tests/audio_check.gd     # 音源が拍に乗っているか
godot --headless --path godot --script res://tests/special_check.gd   # 特別チップ（7.2.1）と開始時の海底（8.2.2）
```

`spec_check` が落ちたら物理かグリッドが壊れている。`headless_check` の
決定性チェックが落ちたら sim層に非決定的な処理が混入している。

**盤面を自分で組むテストは `Sim.new(seed, false)` / `reset(seed, false)` を使う。**
既定では開始時に2段積まれるので（§8.2.2）、そのまま組むと敷いた分が混ざる。

**盤面を組んで検証するテストでは、意図したマッチ以外を作らないこと。**
`_ignite` には「1列につき水中スタックは1本」という制約があり、複数のマッチが
競合するとどちらが先に着火するか次第になって、何を測ったのか分からなくなる。
また海底のマッチは `min_row` 以上を丸ごと持ち上げるので、**検証は座標ではなく
ブロックの参照で行う**こと（検証時にはもう海底に無い）。

### スクリーンショット（要 xvfb）

```
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a godot --path godot --script res://tests/scenario_shot.gd --resolution 540x960
```

保存先は `~/.local/share/godot/app_userdata/METAPON Mock/`。

### Web書き出し（スマホ確認用）

```
cd godot && godot --headless --path . --export-release "Web" web/index.html
```

- `web/` は `.gitignore` 対象。デプロイは `gh-pages` ブランチへ（手順は `godot/README.md`）
- **スレッド無しテンプレートを使う**こと。スレッド有りは COOP/COEP ヘッダが必要で
  GitHub Pages では配信できない
- **日本語フォントは埋め込み必須**。Web には OS のフォントが無く、組み込みの
  フォールバックは日本語グリフを持たないため全部 豆腐 になる
  （`asetts/font/NotoSansJP-subset.woff2`。使用文字だけサブセット化してある）
- スマホにはキーボードが無い。新しい操作を足すときは**必ず画面から触れるようにする**

## 音源

`godot/asetts/sound/`。割り当てと実測値は同ディレクトリの `README.md`。

- BGM は **BPM 130**、148小節ぴったりにトリム済み（`tools/trim_bgm_to_bars.py`）
- 差し替えたら `tools/analyze_bgm.py` でテンポ・先頭無音・小節整合を実測すること。
  **提供されたBPMを信用しない**（過去に「128 BPM」と言われた曲が実測102.5だった）
- SE には先頭無音が入っていることがある。16分音符は115msしかないので、
  数十msの無音でも打楽器が拍からズレる。`game_audio.gd` の `lead` で補正している

## モバイルWebでの注意

- sim が重いと音が途切れる（シングルスレッドで音声もメインスレッドで混ざるため）。
  画面右上の `fps / sim Hz` が実測値。sim が目標ティックレートを下回ると赤く出る
- **BGM を sim 時刻へ細かく追従させない**。処理落ち時に毎秒巻き戻す不具合になる。
  破綻時（2秒以上のズレ）のみ復帰させる方針にしてある
