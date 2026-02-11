#!/bin/bash
# Pip-Pakete in persistentes Volume
export PIP_TARGET=/root/.local/lib/python3
export PYTHONPATH=/root/.local/lib/python3:$PYTHONPATH
export PATH=/root/.local/bin:$PATH

# Nur installieren wenn nicht vorhanden
if [ ! -f /root/.local/bin/whisper ]; then
    echo "[init] Installing whisper to persistent volume..."
    apt-get update -qq
    apt-get install -y -qq python3-pip ffmpeg
    pip3 install --target=/root/.local/lib/python3 openai-whisper
    ln -sf /root/.local/lib/python3/bin/whisper /root/.local/bin/whisper 2>/dev/null || true
    echo "[init] Whisper installed"
else
    echo "[init] Whisper already in volume"
fi

# Starte Gateway
exec node /app/dist/index.js gateway --port 3000 --bind lan
