FROM node:22-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git python3 jq procps net-tools \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_OPTIONS="--max-old-space-size=384"

RUN npm install -g openclaw --no-audit --no-fund && npm cache clean --force

RUN mkdir -p /root/.openclaw/workspace
WORKDIR /root/.openclaw/workspace

EXPOSE 10000
CMD ["sh", "-c", "mkdir -p /root/.openclaw && printf '{\"gateway\":{\"mode\":\"local\",\"bind\":\"lan\"},\"tools\":{\"profile\":\"full\",\"exec\":{\"ask\":\"off\"}}}' > /root/.openclaw/openclaw.json && openclaw gateway run --port ${PORT:-10000} --bind lan"]
