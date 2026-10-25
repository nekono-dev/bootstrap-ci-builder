---
type: llm
focus: trace
weight: 1
---

app_install が tinyapi の systemd unit を /etc/systemd/system に置き、daemon-reload・enable・restart を行い、unit は /etc/tinyapi/tinyapi.env を EnvironmentFile で読む
