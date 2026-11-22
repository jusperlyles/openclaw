#!/bin/bash
set -e

mkdir -p /root/.openclaw/workspace
cd /root/.openclaw

# Configure Git identity for automated commits
git config --global user.email "openclaw-bot@render.local"
git config --global user.name "OpenClaw Render Backup"

# 1. Restore state from GitHub if token & repo are set
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
  # Strip any accidental trailing slash and inject token cleanly
  CLEAN_REPO=$(echo "$GITHUB_REPO" | sed 's:/*$::')
  AUTH_REPO=$(echo "$CLEAN_REPO" | sed "s|https://|https://${GITHUB_TOKEN}@|")

  if [ ! -d ".git" ]; then
    git init -q
    git branch -M main
    git remote add origin "$AUTH_REPO"
  else
    git remote set-url origin "$AUTH_REPO"
  fi

  # Fetch & restore only if remote 'main' branch already exists (prevents error on empty repo)
  if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
    echo "[Backup] Restoring OpenClaw data from GitHub..."
    git fetch -q origin main
    git reset -q --hard origin/main
  else
    echo "[Backup] Remote repo is empty; starting fresh."
  fi
fi

# Ensure workspace and .gitignore always exist after git reset
mkdir -p /root/.openclaw/workspace
cat << 'EOF' > /root/.openclaw/.gitignore
.env
*.tmp
*.log
EOF

# 2. Create default openclaw.json ONLY if not already restored from GitHub
if [ ! -f "/root/.openclaw/openclaw.json" ]; then
  echo "[Init] Creating default openclaw.json..."
  printf '{"gateway":{"mode":"local","bind":"lan"},"tools":{"profile":"full","exec":{"ask":"off"}}}' > /root/.openclaw/openclaw.json
fi

# 3. Apply WhatsApp allowlist if WHATSAPP_ALLOW_FROM is set
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
  # Push initial state right away so empty repos get initialized immediately
  sync_to_github

  # Trap Render container shutdown/redeploy to save final state
  trap 'echo "[Backup] Shutting down, pushing final backup..."; sync_to_github; kill -TERM "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; exit 0' SIGTERM SIGINT

  # Sync every 5 minutes in the background
  (
    while true; do
      sleep 300
      sync_to_github
    done
  ) &
fi

# 5. Launch OpenClaw gateway using your exact original port & bind settings
cd /root/.openclaw/workspace
exec_cmd() {
  openclaw gateway run --port "${PORT:-10000}" --bind lan &
  PID=$!
  wait "$PID"
}
exec_cmd
