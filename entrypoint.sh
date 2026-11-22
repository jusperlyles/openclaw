#!/bin/bash
set -e

mkdir -p /root/.openclaw/workspace
cd /root/.openclaw

# Configure Git identity for automated commits
git config --global user.email "openclaw-bot@render.local"
git config --global user.name "OpenClaw Render Backup"

# 1. Restore state from GitHub if token & repo are set
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
  CLEAN_REPO=$(echo "$GITHUB_REPO" | sed 's:/*$::')
  AUTH_REPO=$(echo "$CLEAN_REPO" | sed "s|https://|https://${GITHUB_TOKEN}@|")

  if [ ! -d ".git" ]; then
    git init -q
    git branch -M main
    git remote add origin "$AUTH_REPO"
  else
    git remote set-url origin "$AUTH_REPO"
  fi

  if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
    echo "[Backup] Restoring OpenClaw data from GitHub..."
    git fetch -q origin main
    git reset -q --hard origin/main
  else
    echo "[Backup] Remote repo is empty; starting fresh."
  fi
fi

mkdir -p /root/.openclaw/workspace
cat << 'EOF' > /root/.openclaw/.gitignore
.env
*.tmp
*.log
EOF

# 2. Create default openclaw.json if not restored from GitHub
if [ ! -f "/root/.openclaw/openclaw.json" ]; then
  echo "[Init] Creating default openclaw.json..."
  cat << 'EOF' > /root/.openclaw/openclaw.json
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "trustedProxies": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.1/32"],
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": true
    }
  },
  "tools": {
    "profile": "full",
    "exec": {
      "ask": "off"
    }
  }
}
EOF
fi

# 3. Always ensure trustedProxies & WhatsApp settings are applied even on restored configs
openclaw config set gateway.trustedProxies '["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.1/32"]' >/dev/null 2>&1 || true
openclaw config set gateway.controlUi.enabled true >/dev/null 2>&1 || true
openclaw config set gateway.controlUi.allowInsecureAuth true >/dev/null 2>&1 || true

if [ -n "$WHATSAPP_ALLOW_FROM" ]; then
  openclaw config set channels.whatsapp.enabled true >/dev/null 2>&1 || true
  openclaw config set channels.whatsapp.dmPolicy "allowlist" >/dev/null 2>&1 || true
  openclaw config set channels.whatsapp.allowFrom "[\"$WHATSAPP_ALLOW_FROM\"]" >/dev/null 2>&1 || true
fi

# 4. Define GitHub sync function & background loop
sync_to_github() {
  if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    cd /root/.openclaw
    git add -A >/dev/null 2>&1 || true
    if ! git diff --cached --quiet; then
      git commit -q -m "Render auto-backup $(date -u +'%Y-%m-%d %H:%M:%S UTC')" >/dev/null 2>&1 || true
      git push -q -u origin main --force >/dev/null 2>&1 || true
      echo "[Backup] Synced state to GitHub."
    fi
  fi
}

if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
  sync_to_github
  trap 'echo "[Backup] Shutting down, pushing final backup..."; sync_to_github; kill -TERM "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; exit 0' SIGTERM SIGINT
  (
    while true; do
      sleep 300
      sync_to_github
    done
  ) &
fi

# 5. Print WhatsApp QR code in Render Logs on first run if not paired yet
if [ -n "$WHATSAPP_ALLOW_FROM" ] && [ ! -d "/root/.openclaw/credentials/whatsapp" ]; then
  echo "=========================================="
  echo "[WhatsApp] Not paired yet! Generating QR code in logs..."
  echo "Open WhatsApp -> Linked Devices -> Link a Device and scan below:"
  echo "=========================================="
  timeout 60 openclaw channels login --channel whatsapp || true
  sync_to_github
fi

# 6. Launch OpenClaw gateway
cd /root/.openclaw/workspace
openclaw gateway run --port "${PORT:-10000}" --bind lan &
PID=$!
wait $PID
