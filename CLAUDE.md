# CLAUDE.md – OpenClaw Setup auf Hetzner VPS

Du arbeitest remote per SSH auf einem neuen Hetzner VPS. Deine Aufgabe: OpenClaw ("Kai") sicher einrichten, gemäss den Entscheidungen in diesem Dokument.

## Kontext

- **Auftraggeber:** Andreas
- **Ziel-VPS:** 89.167.21.32 (Hetzner CX33, Ubuntu 24.04)
- **SSH-Zugang:** Funktioniert bereits vom Claude-Code-VPS aus (Key hinterlegt)
- **Zweck:** Persönlicher KI-Assistent "Kai" via Telegram + Web-Dashboard
- **Telegram-Bot:** @Kai_Hambot – bereits angelegt, Token existiert
- **Vorgeschichte:** Gestern fehlgeschlagene OpenClaw-Installation → wird in Schritt 0 aufgeräumt
- **Referenzdokument:** `open_claw_vps_anleitung_v2.md` (liegt bei Andreas, nicht auf dem Server)

## CSW-Policy – LIES DAS ZUERST

Du darfst Vorschläge machen, aber **Systemänderungen nur nach explizitem OK von Andreas**.

**CSW-pflichtig (immer fragen):**
- Installation/Deinstallation von Paketen (apt/brew/pip/npm)
- Änderungen an Docker Compose, Volumes, Ports
- Änderungen an Firewall (UFW), Nginx, SSH-Config
- Erstmaliges Starten von Containern
- Skill-Installation

**Frei (darfst du selbst):**
- Dateien lesen, inspizieren, diagnostizieren
- Config-Dateien schreiben/vorbereiten (aber nicht aktivieren)
- Logs lesen und analysieren
- Verifikations-Checks ausführen

**CSW-Format bei Rückfragen:**
```
CSW: <Titel>
Ziel: <warum>
Änderung: <was genau>
Risiko: <kurz>
Rollback: <wie zurück>
Befehl(e): <exakt>
```

Dann warten auf **OK** oder **NO**.

## Architektur-Entscheidungen (feststehend, nicht ändern)

1. **Kein Cloudflare Tunnel** – Nginx + IP-Whitelist (fixe IP: 82.136.108.178 von datazug.ch)
2. **Docker-Socket-Proxy** (Tecnativa) statt direktem docker.sock Mount
3. **Telegram Long Polling** – kein Webhook, kein offener Port
4. **E-Mail via IMAPS Pull** – kein SMTP-Port auf dem VPS
5. **`OPENCLAW_GATEWAY_BIND=lan`** – Pflicht, sonst 502 via Nginx
6. **Onboarding immer als `-u node`** – nie als root
7. **Skills nur nach CSW + OK** – kein blindes Installieren

## Ausgangslage

Auf dem Ziel-VPS existiert bereits:
- **SSH-Zugang funktioniert** (Key vom Claude-Code-VPS ist hinterlegt)
- **Docker ist vermutlich installiert** (von gestern)
- **Telegram-Bot (@Kai_Hambot) ist angelegt** und Token existiert
- **Eine fehlgeschlagene OpenClaw-Installation** von gestern – muss zuerst sauber entfernt werden

## Setup-Reihenfolge

Arbeite diese Schritte der Reihe nach ab. Jeder Schritt endet mit einer Verifikation.

### Schritt 0: Inventar + Aufräumen (alte Installation demontieren)

**Zuerst inventarisieren, was vorhanden ist:**
```bash
# Was läuft?
docker ps -a
docker compose ls

# Welche Volumes existieren?
docker volume ls

# Wo liegt die alte Installation?
find / -name "docker-compose.yml" -path "*/openclaw*" 2>/dev/null
find / -name "docker-compose.yml" -path "*/moldboard*" 2>/dev/null
find / -name "docker-compose.yml" -path "*/clawdbot*" 2>/dev/null
find / -name ".env" -path "*/openclaw*" 2>/dev/null
ls -la /opt/openclaw/ 2>/dev/null

# Nginx/Certbot bereits eingerichtet?
ls /etc/nginx/sites-enabled/ 2>/dev/null
ls /etc/letsencrypt/live/ 2>/dev/null

# UFW aktiv?
ufw status

# SSH-Härtung bereits gemacht?
sshd -T | grep -E "permitrootlogin|passwordauthentication"

# Homebrew vorhanden?
ls /home/linuxbrew/.linuxbrew/bin/brew 2>/dev/null
id linuxbrew 2>/dev/null

# Offene Ports?
ss -tlnp

# Tailscale vorhanden?
systemctl status tailscaled 2>/dev/null
tailscale status 2>/dev/null
dpkg -l | grep tailscale 2>/dev/null
```

**Ergebnis an Andreas melden** – zeig was du gefunden hast, bevor du etwas löschst.

**Dann aufräumen (CSW-pflichtig – warte auf OK):**
```bash
# Alte Container stoppen und entfernen
cd <alter-installationspfad>
docker compose down --remove-orphans

# Alte Volumes löschen (ACHTUNG: Datenverlust – aber gewollt, da fehlgeschlagen)
docker volume rm <alte-volume-namen>

# Alte Config-Dateien entfernen
rm -rf <alter-installationspfad>

# Verwaiste Docker-Images aufräumen
docker image prune -f

# Tailscale komplett entfernen
tailscale down
systemctl stop tailscaled
systemctl disable tailscaled
apt purge -y tailscale tailscaled 2>/dev/null
rm -rf /var/lib/tailscale
# Falls Tailscale ein eigenes APT-Repo hinterlassen hat:
rm -f /etc/apt/sources.list.d/tailscale*.list
rm -f /usr/share/keyrings/tailscale*.gpg
apt update
```

**Was BEHALTEN:**
- Docker Engine (nicht deinstallieren, nur Container/Volumes aufräumen)
- SSH-Keys und SSH-Config
- UFW-Regeln (falls bereits gesetzt und korrekt)
- Telegram-Bot-Token (aus alter .env sichern, bevor gelöscht wird!)
- Nginx + Certbot (falls bereits installiert und funktional)
- Homebrew (falls bereits installiert)

**Was ENTFERNEN:**
- **Tailscale** komplett (Dienst, Paket, Repo, State) – wird nicht gebraucht, Zugang läuft über fixe IP + Nginx
- Alle alten OpenClaw/Moldboard/Clawdbot Container und Volumes
- Alte docker-compose.yml und .env (nach Token-Sicherung)
- Alte openclaw.json / Config-Volumes
- Eventuelle docker.sock Mounts

**Verifikation:**
```bash
docker ps -a          # Keine openclaw-Container mehr
docker volume ls      # Keine openclaw-Volumes mehr
ss -tlnp              # Nur SSH (22) sollte lauschen, evtl. 443 falls Nginx bleibt
systemctl status tailscaled 2>/dev/null  # Sollte "not found" oder "inactive" zeigen
```

### Schritt 1: Basis-Härtung (prüfen + ergänzen)

Vieles davon ist möglicherweise schon von gestern vorhanden. Prüfe zuerst, ergänze nur was fehlt.

```bash
# Prüfen was schon da ist
ufw status verbose
sshd -T | grep -E "permitrootlogin|passwordauthentication|pubkeyauthentication"
```

**Falls noch nicht gemacht:**
```bash
# Updates
apt update && apt upgrade -y

# UFW Firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow from 82.136.108.178 to any port 22   # SSH von Andreas' fixer IP
# WICHTIG: Auch die IP des Claude-Code-VPS erlauben, sonst sperrst du dich selbst aus!
# Eigene IP ermitteln (auf dem Claude-Code-VPS ausführen):
# curl -4 ifconfig.me
ufw allow from <CLAUDE_CODE_VPS_IP> to any port 22
ufw allow 443/tcp                                # HTTPS für Web-Frontend
ufw enable

# SSH härten (in /etc/ssh/sshd_config):
# PermitRootLogin prohibit-password  (oder "no" nach Anlegen eines Admin-Users)
# PasswordAuthentication no
# PubkeyAuthentication yes
systemctl restart sshd
```

**WICHTIG:** Auch den SSH-Key des Claude-Code-VPS berücksichtigen! Nicht aussperren. Prüfe dass der Key in `~/.ssh/authorized_keys` steht, bevor du SSH härtst.

**Verifikation:**
```bash
ufw status verbose
sshd -T | grep -E "permitrootlogin|passwordauthentication|pubkeyauthentication"
```

### Schritt 2: Docker (prüfen, ggf. installieren)

```bash
# Prüfen ob Docker schon da ist
docker --version && docker compose version
```

**Falls nicht installiert:**
```bash
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
```

**Verifikation:**
```bash
docker run --rm hello-world
```

### Schritt 3: Verzeichnisstruktur + .env

```bash
mkdir -p /opt/openclaw
```

Die `.env` Datei in `/opt/openclaw/.env` anlegen mit folgendem Inhalt:

```env
# --- OpenClaw Core ---
PORT=3000
OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_TOKEN=<wird generiert>

# --- LLM Provider (Anthropic) ---
ANTHROPIC_API_KEY=<von Andreas>
MODEL_NAME=claude-opus-4-5-20250514

# --- Telegram ---
TELEGRAM_BOT_TOKEN=<von Andreas>

# --- Working Directory ---
WORKING_DIRECTORY=/work

# --- Logging ---
LOG_LEVEL=info
```

**WICHTIG:** Gateway-Token generieren:
```bash
openssl rand -hex 32
```

Secrets von Andreas erfragen (ANTHROPIC_API_KEY, TELEGRAM_BOT_TOKEN). Den Telegram-Bot-Token aus der alten Installation sichern, falls noch vorhanden. Nicht raten, nicht erfinden.

```bash
chmod 600 /opt/openclaw/.env
```

**Verifikation:**
```bash
grep GATEWAY_BIND /opt/openclaw/.env  # Muss "lan" zeigen
stat -c "%a %U" /opt/openclaw/.env     # Muss "600 root" zeigen
```

### Schritt 4: Docker Compose mit Socket-Proxy

In `/opt/openclaw/docker-compose.yml` anlegen:

```yaml
services:
  # Docker-Socket-Proxy – beschränkt API-Zugriff für Sandbox
  docker-proxy:
    image: tecnativa/docker-socket-proxy
    restart: unless-stopped
    environment:
      CONTAINERS: 1
      IMAGES: 1
      NETWORKS: 1
      POST: 1
      VOLUMES: 0
      SERVICES: 0
      TASKS: 0
      SECRETS: 0
      CONFIGS: 0
      EXEC: 0
      SWARM: 0
      NODES: 0
      BUILD: 0
      SYSTEM: 0
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - openclaw-internal
    expose:
      - "2375"

  openclaw:
    image: ghcr.io/nicepkg/openclaw:latest
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - DOCKER_HOST=tcp://docker-proxy:2375
    ports:
      - "127.0.0.1:${PORT}:${PORT}"
    volumes:
      - openclaw_config:/home/node/.openclaw
      - openclaw_workspace:/home/node/openclaw
      - /home/linuxbrew/.linuxbrew:/home/linuxbrew/.linuxbrew
    networks:
      - openclaw-internal
    deploy:
      resources:
        limits:
          cpus: "3"
          memory: 6G
    depends_on:
      - docker-proxy

volumes:
  openclaw_config:
  openclaw_workspace:

networks:
  openclaw-internal:
    driver: bridge
```

**ACHTUNG:** Das OpenClaw Docker-Image (`ghcr.io/nicepkg/openclaw:latest`) ist ein Platzhalter. Prüfe vor dem Start das korrekte Image:
```bash
# Recherchiere das aktuelle offizielle Image
# OpenClaw/Moldboard/Clawdbot – der Name hat sich mehrfach geändert
# Mögliche Quellen: GitHub Releases, Docker Hub
```

Frage Andreas nach dem korrekten Image-Namen, falls unklar.

**Verifikation (Syntax):**
```bash
cd /opt/openclaw && docker compose config
```

### Schritt 5: Homebrew für Skills

```bash
# Dependencies
apt-get install -y build-essential procps curl file git

# User anlegen
useradd -m -s /bin/bash linuxbrew

# Homebrew installieren (als linuxbrew-User)
sudo -u linuxbrew NONINTERACTIVE=1 /bin/bash -c \
  "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Berechtigungen
chmod -R g+w /home/linuxbrew/.linuxbrew/
```

**Verifikation:**
```bash
sudo -u linuxbrew /home/linuxbrew/.linuxbrew/bin/brew --version
```

### Schritt 6: Container starten

```bash
cd /opt/openclaw
docker compose pull
docker compose up -d

# Warten auf Startup
sleep 20

# Status prüfen
docker compose ps
docker compose logs --tail=50
```

**Verifikation:**
```bash
# Port nur auf localhost gebunden?
docker port $(docker ps -q --filter name=openclaw) | grep "127.0.0.1"

# Lokal erreichbar?
curl -sI http://127.0.0.1:3000/ | head -5

# Docker-Proxy läuft?
docker compose ps docker-proxy
```

### Schritt 7: OpenClaw Security-Config (openclaw.json)

Config-Volume finden und Security-Settings setzen:

```bash
docker volume inspect openclaw_config | grep Mountpoint
```

Folgende Settings in `openclaw.json` mergen (nicht überschreiben!):

```json
{
  "discovery": {
    "mdns": {
      "mode": "off"
    }
  },
  "gateway": {
    "bind": "lan"
  },
  "logging": {
    "redactSensitive": "tools"
  },
  "channels": {
    "telegram": {
      "dmPolicy": "allowlist"
    }
  },
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "non-main",
        "scope": "session",
        "workspaceAccess": "rw",
        "docker": {
          "network": "bridge"
        }
      }
    }
  },
  "tools": {
    "elevated": {
      "enabled": false
    }
  }
}
```

**WICHTIG:** `dmPolicy` nur für Telegram setzen, NICHT für Discord oder Slack (verursacht Validierungsfehler).

```bash
# Container neu starten nach Config-Änderung
docker compose restart openclaw
sleep 10
docker compose logs --tail=20 openclaw
```

### Schritt 8: Onboarding

```bash
docker exec -it -u node $(docker ps -q --filter name=openclaw) \
  node /app/dist/index.js onboard
```

**ACHTUNG nach Onboarding:**
```bash
# Prüfen ob Wizard gateway.bind auf loopback zurückgesetzt hat
grep -o '"bind": "[^"]*"' $(docker volume inspect openclaw_config --format '{{.Mountpoint}}')/openclaw.json

# Falls "loopback" → zurück auf "lan" ändern und Container restarten
```

**Ab hier: Andreas macht den Rest interaktiv** (API-Key eingeben, Telegram-Bot verknüpfen, Allowlist-ID setzen). Du assistierst bei Fehlern.

### Schritt 9: Nginx + TLS + IP-Whitelist

```bash
apt install -y nginx certbot python3-certbot-nginx

# Certbot für Domain
certbot --nginx -d www.openclaw.andreasmgross.de
```

Nginx-Config in `/etc/nginx/sites-available/openclaw`:

```nginx
server {
    listen 443 ssl;
    server_name www.openclaw.andreasmgross.de;

    ssl_certificate /etc/letsencrypt/live/www.openclaw.andreasmgross.de/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/www.openclaw.andreasmgross.de/privkey.pem;

    location / {
        # Fixe IP von datazug.ch
        allow 82.136.108.178;
        deny all;

        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

server {
    listen 80;
    server_name www.openclaw.andreasmgross.de;
    return 301 https://$host$request_uri;
}
```

```bash
ln -sf /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
```

**WebSocket-Header** (`Upgrade` + `Connection`) sind wichtig – OpenClaw nutzt WebSockets für das Dashboard.

**Verifikation:**
```bash
# Von aussen (oder curl mit --resolve):
curl -sI https://www.openclaw.andreasmgross.de/ --resolve www.openclaw.andreasmgross.de:443:89.167.21.32

# Certbot-Timer aktiv?
systemctl status certbot.timer
```

### Schritt 10: Abschluss-Check

```bash
echo "=== Sicherheits-Check ==="

echo -n "1. Port nur localhost: "
docker port $(docker ps -q --filter name=openclaw) | grep -q "127.0.0.1" && echo "✔" || echo "✗"

echo -n "2. GATEWAY_BIND=lan: "
grep -q "OPENCLAW_GATEWAY_BIND=lan" /opt/openclaw/.env && echo "✔" || echo "✗"

echo -n "3. UFW aktiv: "
ufw status | grep -q "Status: active" && echo "✔" || echo "✗"

echo -n "4. SSH kein Passwort: "
sshd -T 2>/dev/null | grep -q "passwordauthentication no" && echo "✔" || echo "✗"

echo -n "5. Nginx läuft: "
systemctl is-active nginx >/dev/null && echo "✔" || echo "✗"

echo -n "6. Docker-Proxy läuft: "
docker ps --filter name=docker-proxy --format "{{.Status}}" | grep -q "Up" && echo "✔" || echo "✗"

echo -n "7. Certbot-Timer: "
systemctl is-active certbot.timer >/dev/null && echo "✔" || echo "✗"

echo -n "8. Homebrew verfügbar: "
[ -f /home/linuxbrew/.linuxbrew/bin/brew ] && echo "✔" || echo "✗"

echo -n "9. .env Permissions: "
[ "$(stat -c %a /opt/openclaw/.env)" = "600" ] && echo "✔" || echo "✗"

echo -n "10. Tailscale entfernt: "
! systemctl is-active tailscaled >/dev/null 2>&1 && echo "✔" || echo "✗"

echo "========================="
```

## Troubleshooting

### 502 Bad Gateway
1. `grep GATEWAY_BIND /opt/openclaw/.env` → muss `lan` sein
2. `curl -sI http://127.0.0.1:3000/` → muss antworten
3. `docker compose logs openclaw` → Fehlermeldungen?

### Dashboard zeigt "Pairing required"
- Onboarding wurde als root statt als node ausgeführt.
- Fix: `chown -R 1000:1000 $(docker volume inspect openclaw_config --format '{{.Mountpoint}}')/`
- Dann: Container restarten

### Sandbox "Docker not available"
- Docker-Proxy läuft? `docker compose ps docker-proxy`
- OpenClaw sieht Proxy? `docker exec $(docker ps -q --filter name=openclaw) env | grep DOCKER_HOST`
- Fallback: Falls Proxy-Ansatz nicht kompatibel → CSW an Andreas: direkten Socket-Mount vorschlagen

### Skill-Installation schlägt fehl
- Homebrew gemountet? `docker exec $(docker ps -q --filter name=openclaw) ls /home/linuxbrew/.linuxbrew/bin/brew`
- Berechtigungen? `docker exec $(docker ps -q --filter name=openclaw) id node`

### Container startet nicht
```bash
docker compose logs --tail=100
docker compose config  # Syntax prüfen
```

## Was NICHT tun

- **Kein** direkter `/var/run/docker.sock` Mount in den OpenClaw-Container
- **Keine** Cloudflare-Installation
- **Kein** Tailscale – wurde bewusst entfernt, nicht wieder installieren
- **Keine** Skills installieren ohne CSW + OK
- **Keine** Ports öffnen ausser 22 (SSH, nur fixe IP) und 443 (HTTPS)
- **Keine** Secrets in Logs, Git, oder Chat-Output
- **Kein** Onboarding als root
- **Keine** Änderungen an der `.env` ohne Rückfrage (ausser Generierung des Gateway-Tokens)
