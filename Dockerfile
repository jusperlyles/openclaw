FROM node:22-slim

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install only lightweight Linux tools without heavy recommended packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git python3 jq procps net-tools \
    && rm -rf /var/lib/apt/lists/*

# Limit Node memory during install so Render's 512MB RAM doesn't crash
ENV NODE_OPTIONS="--max-old-space-size=384"

# Install OpenClaw globally
RUN npm install -g openclaw --no-audit --no-fund && npm cache clean --force

# Create workspace and config directory
RUN mkdir -p /root/.openclaw/workspace
WORKDIR /root/.openclaw/workspace

# Expose Render's HTTP port and start OpenClaw
EXPOSE 10000
CMD ["sh", "-c", "mkdir -p /root/.openclaw && printf '{\"tools\":{\"profile\":\"full\",\"exec\":{\"ask\":\"off\"}}}' > /root/.openclaw/openclaw.json && openclaw start --port ${PORT:-10000} --host 0.0.0.0"]
