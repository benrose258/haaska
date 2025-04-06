#!/bin/bash
set -e

# Start Tailscale
echo "Starting Tailscale..."
tailscaled &

# Wait a little for tailscaled to be ready
sleep 2

# Authenticate Tailscale
echo "Authenticating to Tailscale..."
tailscale up --authkey ${TAILSCALE_AUTHKEY}

# Run your actual app or keep container alive
echo "Tailscale started, container ready."
tail -f /dev/null
