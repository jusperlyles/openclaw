#!/bin/bash
set -e

mkdir -p /root/.openclaw/workspace
cd /root/.openclaw

git config --global user.email "openclaw-bot@render.local"
git config --global user.name "OpenClaw Render Backup"

# 1. Restore state from GitHub
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
  fi
fi

mkdir -p /root/.openclaw/workspace
cat << 'EOF' > /root/.openclaw/.gitignore
.env
*.tmp
*.log
EOF

# 2. Initialize or update openclaw.json instantaneously with jq (saves RAM & 15s boot time)
if [ ! -f "/root/.openclaw/openclaw.json" ]; then
  echo '{}' > /root/.openclaw/openclaw.json
fi

jq '.gateway.mode = "local"
  | .gateway.bind = "lan"
  | .gateway.trustedProxies = ["0.0.0.0/0"]
  | .tools.profile = "full"
  | .tools.exec.ask = "off"' /root/.openclaw/openclaw.json > /root/.openclaw/openclaw.json.tmp \
  && mv /root/.openclaw/openclaw.json.tmp /root/.openclaw/openclaw.json

if [ -n "$WHATSAPP_ALLOW_FROM" ]; then
  jq --arg num "$WHATSAPP_ALLOW_FROM" \
    '.channels.whatsapp.enabled = true
    | .channels.whatsapp.dmPolicy = "allowlist"
    | .channels.whatsapp.allowFrom = [$num]' /root/.openclaw/openclaw.json > /root/.openclaw/openclaw.json.tmp \
    && mv /root/.openclaw/openclaw.json.tmp /root/.openclaw/openclaw.json
fi

# 3. GitHub backup sync function & background loop
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

# 4. Launch OpenClaw gateway directly on 0.0.0.0:$PORT
echo "[Gateway] Starting OpenClaw on port ${PORT:-10000}..."
cd /root/.openclaw/workspace
openclaw gateway run --port "${PORT:-10000}" --bind lan &
PID=$!
wait $PID
