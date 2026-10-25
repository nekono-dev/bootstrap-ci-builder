---
type: llm
focus: trace
weight: 1
---

installer/app.sh に元のフックの処理（python3 の導入、hello-svc ユーザーの作成、unit の配置・daemon-reload・enable・restart、uninstall での停止・削除、purge での userdel）がすべて残っている
