---
tags: [skill-creator]
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

bin/notes-sync を、sudo なしで自分のホームに入れられるインストーラを作ってほしいです。curl 1行で入れて、bin/notes-sync を ~/.local/bin から使えるようにし、systemd/ にある user 用のタイマーを有効にしたいです。設定は同期するディレクトリ SYNC_DIR（必須）と、同期先の git リモート SYNC_REMOTE（必須）。アプリ名は notes-sync で、GitHub のタグで Release、ブランチでも試せるようにしてください。質問せずに進めてください。
