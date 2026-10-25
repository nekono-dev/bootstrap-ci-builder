---
type: llm
focus: trace
weight: 1
---

app_install が notes-sync を ~/.local/bin から使えるようにし、unit を ~/.config/systemd/user へ置いて systemctl --user daemon-reload と notes-sync.timer の有効化・起動を行う
