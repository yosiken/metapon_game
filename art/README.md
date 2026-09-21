# 原画

加工前の素材。**Godot プロジェクトの外**に置いてある。`godot/` の下に入れると
エディタがインポートして書き出しにも含まれてしまい、配信サイズが無駄に増えるため。

| ファイル | 加工先 | 加工 |
| --- | --- | --- |
| `underwater-source.jpg` | `godot/asetts/bg/underwater.png` | `godot/tools/make_bg.py` |

```
cd godot && python3 tools/make_bg.py ../art/underwater-source.jpg asetts/bg/underwater.png
```

チップシート（10x10 の宝石）は `godot/tools/slice_chips.py` が
`godot/asetts/chips/` を生成する。こちらは原画も切り出し後も
`godot/asetts/chips/` に入っている（切り出し済みを直接使うため）。
