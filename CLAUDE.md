# OpenClaw - Self-Hosted AI Gateway

**Bot-Name:** Kai (norddeutsch, klingt wie "KI")
**Status:** Produktiv
**Stand:** 2026-02-11

---

## Schnellzugriff

### SSH (via Tailscale)
```bash
# Claude Code:
ssh -i ~/.ssh/kai_openclaw claude@100.123.162.67

# Andreas:
ssh res@100.123.162.67  # PW: 2EMJHTHW75H5F2SZJMWMZ374
```

### WebUI
https://kai.tailaf420e.ts.net

### Telegram
@Kai_Hambot

---

## VPS-Konfiguration

| Eigenschaft | Wert |
|-------------|------|
| Server-ID | #120673496 |
| Hostname | Kai |
| IPv4 (öffentlich) | 89.167.21.32 (Port 22 geschlossen) |
| IPv4 (Tailscale) | 100.123.162.67 |
| Standort | Helsinki |
| OS | Ubuntu 24.04 LTS |
| Specs | CX33: 4 vCPU, 8 GB RAM, 80 GB SSD |
| Backups | Täglich (Hetzner) |
| Kosten | ~6 EUR/Monat |

---

## Kai Konfiguration

### AI-Modell
- **Provider:** OpenAI
- **Modell:** gpt-4o
- **Spending-Limit:** $20/Monat (OpenAI Dashboard)

### Telegram
- **Username:** @Kai_Hambot
- **Zugriff:** Nur Andreas (ID: 1097992747)
- **DM-Policy:** allowlist

### Berechtigungen (wichtig!)

Kai braucht drei Dinge, um autonom zu arbeiten:

1. **tools.elevated.allowFrom.telegram** - erlaubt sudo/privilegierte Befehle
2. **exec-approvals allowlist** - vorab-genehmigte Befehle ohne Nachfrage
3. **gateway.trustedProxies** - erlaubt WebUI-Zugriff via Tailscale

```bash
# Aktuelle Allowlist anzeigen:
openclaw approvals get

# Befehl hinzufügen:
openclaw approvals allowlist add --agent "*" "befehl *"
```

### Installierte Tools
- Node.js v22, OpenClaw v2026.2.9
- ffmpeg, pip/pip3, curl
- openai-whisper (lokal, für Sprachnachrichten)

---

## Gateway-Befehle

```bash
# Status
systemctl --user status openclaw-gateway
openclaw channels status

# Neustart
systemctl --user restart openclaw-gateway

# Logs
journalctl --user -u openclaw-gateway -f

# Config
openclaw config get <pfad>
openclaw config set '<pfad>' '<wert>'

# Sandbox/Berechtigungen prüfen
openclaw sandbox explain
```

---

## Sicherheit

| Ebene | Massnahme |
|-------|-----------|
| Netzwerk | Port 22 nur via Tailscale erreichbar |
| SSH | Key-only (claude), Passwort (res) |
| Telegram | Allowlist: nur Andreas |
| Gateway | bind: loopback, trustedProxies: Tailscale |
| fail2ban | Aktiv |

**Konzept:** Der VPS ist isoliert. Kai hat volle Rechte auf seinem System.
Schlimmstenfalls macht er den VPS kaputt - dann Backup einspielen oder neu aufsetzen.

---

## Troubleshooting

### "Genehmigung erforderlich"
```bash
openclaw approvals allowlist add --agent "*" "befehl *"
```

### "kann sudo nicht nutzen"
```bash
openclaw config set 'tools.elevated.allowFrom.telegram' '["1097992747"]'
```

### WebUI zeigt "disconnected"
```bash
openclaw config set 'gateway.trustedProxies' '["100.0.0.0/8", "127.0.0.1"]'
systemctl --user restart openclaw-gateway
```

### Sprachnachrichten funktionieren nicht
- Whisper ist installiert in `~/.local/bin/whisper`
- PATH muss in systemd-Service enthalten sein
- Skill `openai-whisper` sollte "Ready" zeigen

---

## Wartung

```bash
# OpenClaw updaten
npm update -g openclaw

# Backup
tar -czf ~/openclaw-backup-$(date +%Y%m%d).tar.gz ~/.openclaw/

# Notfall: Gateway stoppen
systemctl --user stop openclaw-gateway
```

---

## Links

- OpenClaw Docs: https://docs.openclaw.ai/
- Telegram Bot: https://t.me/Kai_Hambot
- Tailscale Admin: https://login.tailscale.com/admin
- OpenAI Usage: https://platform.openai.com/usage
- Hetzner Console: https://console.hetzner.cloud/
