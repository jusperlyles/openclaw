
FROM node:22-slim

# Install Linux tools that OpenClaw can execute via chat
RUN apt-get update && apt-get install -y \
    curl wget git python3 python3-pip jq procps net-tools \
    && rm -rf /var/lib/apt/lists/*

# Install OpenClaw globally
RUN npm install -g openclaw

# Create workspace and config directory
RUN mkdir -p /root/.openclaw/workspace
WORKDIR /root/.openclaw/workspace

# Expose Render's HTTP port and start OpenClaw
EXPOSE 10000
CMD ["sh", "-c", "mkdir -p /root/.openclaw && printf '{\"tools\":{\"profile\":\"full\",\"exec\":{\"ask\":\"off\"}}}' > /root/.openclaw/openclaw.json && openclaw start --port ${PORT:-10000} --host 0.0.0.0"]
