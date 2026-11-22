#!/bin/bash
set -e

mkdir -p /root/.openclaw
cd /root/.openclaw

# Configure Git identity for automated commits
git config --global user.email "openclaw-bot@render.local"
git config --global user.name "OpenClaw Render Backup"

# 1. Restore full state (chat history + WhatsApp session credentials) from GitHub
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
  AUTH_REPO=$(echo "$GITHUB_REPO" | sed "s|https://|https://${GITHUB_TOKEN}@|")

  # Only ignore .env files; allow credentials/ so WhatsApp stays paired across restarts
  cat << 'EOF' > .gitignore
.env
*.tmp
EOF

  if [ ! -d ".git" ]; then
    git init
    git branch -M main
    git remote add origin "$AUTH_REPO"
    git fetch origin main 2>/dev/null || true
    git reset --hard origin/main 2>/dev/null || true
  else
    git remote set-url origin "$AUTH_REPO"
    git fetch origin main 2>/dev/null || true
    git reset --hard origin/main 2>/dev/null || true
  fi

  # 2. Define backup function
  sync_to_github() {
    cd /root/.openclaw
    git add -A 2>/dev/null || true
    if ! git diff --cached --quiet; then
      git commit -m "Render auto-backup $(date -u +'%Y-%m-%d %H:%M:%S UTC')" 2>/dev/null || true
      git push -u origin main --force 2>/dev/null || true
    fi
  }

  # 3. Trap container shutdown (SIGTERM/SIGINT) to save final state before Render stops/redeploys
  trap 'echo "Container stopping, backing up to GitHub..."; sync_to_github; exit 0' SIGTERM SIGINT

  # 4. Background loop to push chat history & updated WhatsApp session keys every 5 minutes
  (
    while true; do
      sleep 300
      sync_to_github
    done
  ) &
fi

# 5. Auto-configure WhatsApp allowlist if provided in Render Environment Variables
if [ -n "$WHATSAPP_ALLOW_FROM" ]; then
  openclaw config set channels.whatsapp.enabled true || true
  openclaw config set channels.whatsapp.dmPolicy "allowlist" || true
  openclaw config set channels.whatsapp.allowFrom "[\"$WHATSAPP_ALLOW_FROM\"]" || true
fi

# 6. Start OpenClaw in foreground and wait (required for SIGTERM trap to work)
openclaw gateway start &
PID=$!
wait $PID
