# OpenClaw "Kai" - Produktiv-Setup

**Stand:** 2026-02-11
**Status:** Produktiv
**Bot:** @Kai_Hambot

---

## Schnellzugriff

### SSH
```bash
ssh -i ~/.ssh/kai_openclaw claude@89.167.21.32
```

### WebUI
https://www.openclaw.andreasmgross.de (nur von IP 82.136.108.178)

### Telegram
@Kai_Hambot

---

## VPS-Konfiguration

| Eigenschaft | Wert |
|-------------|------|
| IPv4 (öffentlich) | 89.167.21.32 |
| Standort | Helsinki (Hetzner) |
| OS | Ubuntu 24.04 LTS |
| Specs | CX33: 4 vCPU, 8 GB RAM, 80 GB SSD |
| Kosten | ~6 EUR/Monat |

---

## Architektur

```
Internet
    │
    ▼ (443/tcp, IP-Whitelist: 82.136.108.178)
┌─────────┐
│  Nginx  │ + Let's Encrypt TLS
└────┬────┘
     │ (localhost:3000)
     ▼
┌──────────────────────────────────────────┐
│  Docker: openclaw-openclaw-1             │
│  Image: ghcr.io/phioranex/openclaw-docker│
│  Model: openai/gpt-4.1-nano              │
│  + Whisper (lokal, persistent)           │
└──────────────────────────────────────────┘
     │
     ▼
┌──────────────────────────────────────────┐
│  Docker: openclaw-docker-proxy-1         │
│  (Tecnativa Socket-Proxy)                │
└──────────────────────────────────────────┘
```

---

## Wichtige Befehle

### Container-Management
```bash
cd /opt/openclaw

# ✅ Neustart (behält alles)
sudo docker compose restart openclaw

# ❌ NICHT verwenden (löscht Container, Whisper muss neu installieren)
sudo docker compose down && sudo docker compose up -d

# Logs
sudo docker compose logs -f openclaw

# Status
sudo docker compose ps
```

### Model wechseln
```bash
sudo docker exec openclaw-openclaw-1 /app/packages/clawdbot/node_modules/.bin/openclaw models set <model>

# Beispiele:
# openai/gpt-4.1-nano     (sehr günstig, aktuell)
# openai/gpt-4.1-mini     (günstig)
# anthropic/claude-haiku-4-5  (mittel)
```

---

## Dateien auf dem VPS

| Pfad | Beschreibung |
|------|--------------|
| `/opt/openclaw/docker-compose.yml` | Container-Konfiguration |
| `/opt/openclaw/.env` | Secrets (API-Keys, Tokens) |
| `/opt/openclaw/scripts/init.sh` | Startup-Script (Whisper-Install) |

### Volumes (persistent)
- `openclaw_config` → `/root/.openclaw` (Config, Sessions)
- `openclaw_workspace` → `/root/workspace` (Arbeitsverzeichnis)
- `openclaw_local` → `/root/.local` (Pip-Pakete, Whisper)

---

## Sicherheit

| Ebene | Massnahme |
|-------|-----------|
| SSH | Key-only, nur von 82.136.108.178 + 157.90.148.75 |
| HTTPS | Nginx + Let's Encrypt, IP-Whitelist |
| Telegram | Allowlist: nur Andreas (ID: 1097992747) |
| Container | Root-Zugriff für autonome Installation |
| Tailscale | Entfernt (nicht mehr benötigt) |

---

## Kosten

| Posten | Kosten/Monat |
|--------|--------------|
| Hetzner CX33 | ~6€ |
| OpenAI API (gpt-4.1-nano) | ~1-5€ (je nach Nutzung) |
| **Total** | **~7-11€** |

---

## Troubleshooting

### Kai antwortet nicht
```bash
sudo docker compose ps  # Container läuft?
sudo docker compose logs --tail=50 openclaw  # Fehler?
```

### Whisper fehlt nach Neustart
Bei `docker compose restart` bleibt Whisper erhalten.
Bei `docker compose down/up` wird Whisper automatisch neu installiert (~3-5 Min).

### Model wechseln
```bash
sudo docker exec openclaw-openclaw-1 /app/packages/clawdbot/node_modules/.bin/openclaw models set openai/gpt-4.1-mini
sudo docker compose restart openclaw
```

### API-Guthaben leer
- Anthropic: https://console.anthropic.com/settings/billing
- OpenAI: https://platform.openai.com/settings/organization/billing

---

## Zukunft: GPU-VPS für lokales LLM

Wenn API-Kosten zu hoch werden, Migration zu GPU-VPS möglich:

| Anbieter | GPU | VRAM | Preis |
|----------|-----|------|-------|
| Vast.ai | RTX 3090 | 24GB | ~$0.15-0.30/h |

Mit 24GB VRAM möglich:
- Qwen 2.5 Coder 32B (Q4)
- Mistral Small 3 24B
- Llama 3.2 70B (Q4)
