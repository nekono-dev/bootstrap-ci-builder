---
tags: [skill-creator]
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

このリポジトリの server.py を、Ubuntu サーバへ curl 1行でインストールできるようにしたいです。アプリ名は tinyapi で、root で /opt に入れて systemd で常駐させます。設定はポート（PORT、既定 8080）と API トークン（API_TOKEN、必須）の2つです。タグ（v*）を打ったら GitHub Release に install.sh を付けて、開発中のブランチも導入先で切り替えて試せるようにしてください。既存の ci.yml の検査は、install.sh を出す前にも通したいです。必要な情報はこれで全部なので、質問せずに進めてください。
