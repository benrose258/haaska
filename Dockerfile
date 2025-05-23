FROM alpine:3.20

# Install dependencies: iptables, ip6tables, curl, bash, tini, ca-certificates, Python 3 and pip, and requests
RUN apk add --no-cache iptables ip6tables curl bash tini ca-certificates python3 py3-pip py3-requests

# Install Tailscale (version 1.66.4 for Alpine 3.20)
ARG TAILSCALE_VERSION=1.66.4
RUN curl -fsSL https://pkgs.tailscale.com/stable/alpine/v3.20/tailscale_${TAILSCALE_VERSION}-r0.apk -o tailscale.apk \
  && apk add --no-cache --allow-untrusted tailscale.apk \
  && rm tailscale.apk

# Create writable directories for Tailscale (only /tmp is writable in Lambda)
RUN mkdir -p /tmp/tailscale-state /tmp/tailscale-socket

# Set environment variables for Tailscale paths
ENV TS_STATE_DIR=/tmp/tailscale-state
ENV TS_SOCKET_DIR=/tmp/tailscale-socket
ENV TS_SOCKET=$TS_SOCKET_DIR/tailscaled.sock

# Set working directory for your application
WORKDIR /usr/src/app

# Copy your application files (including handler.py, Makefile, etc.)
COPY . /usr/src/app

# Install Python dependencies from requirements.txt, if present
RUN if [ -f requirements.txt ]; then pip install --no-cache-dir --break-system-packages -r requirements.txt; fi

# Embed the entrypoint script directly
RUN cat <<'EOF' > /entrypoint.sh
#!/bin/bash
set -euo pipefail

echo "[entrypoint] Starting tailscaled..."
tailscaled --tun=userspace-networking --statedir="${TS_STATE_DIR}" --socket="${TS_SOCKET}" &

# Wait for the socket to appear (up to 30 seconds)
for i in {1..30}; do
  if [ -S "${TS_SOCKET}" ]; then
    echo "[entrypoint] tailscaled is ready!"
    break
  fi
  echo "[entrypoint] Waiting for tailscaled socket..."
  sleep 1
done

if [ ! -S "${TS_SOCKET}" ]; then
  echo "[entrypoint] ERROR: tailscaled socket not found after timeout"
  exit 1
fi

# Ensure the auth key is provided via the environment
if [ -z "${TAILSCALE_AUTH_KEY:-}" ]; then
  echo "[entrypoint] ERROR: TAILSCALE_AUTH_KEY environment variable is not set"
  exit 1
fi

echo "[entrypoint] Running tailscale up..."
export TAILSCALE_SOCKET="${TS_SOCKET}"
tailscale --socket="${TS_SOCKET}" up --authkey="${TAILSCALE_AUTH_KEY}" --hostname="lambda-node"

echo "[entrypoint] Tailscale is up. Starting Haaska..."
# Run your Haaska code; here we assume the entrypoint for Haaska is handler.py
exec python3 handler.py
EOF

# Make the entrypoint script executable
RUN chmod +x /entrypoint.sh

# Use tini as the init process to handle signals properly
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
