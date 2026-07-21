#!/usr/bin/env bash
set -e

echo "🚀 Setting up persistent VPS environment..."

# ==========================================
# 1. SSH Server Configuration
# ==========================================
echo "🔑 Ensuring OpenSSH server is active..."
if ! command -v sshd &> /dev/null; then
    sudo apt-get update --fix-missing -y
    sudo apt-get install -y openssh-server
fi

# Ensure SSH daemon is enabled and running on port 22
sudo systemctl enable --now ssh || sudo systemctl enable --now sshd

# ==========================================
# 2. Cloudflare Tunnel Setup via PM2
# ==========================================
echo "🌐 Initializing Cloudflare Tunnel..."

TUNNEL_TOKEN="eyJhIjoiNDAwNmMxYTcwNmVhM2Y4NTFiMzViMWMyYTg1MDU5OGEiLCJ0IjoiMmRiZGY3MjctYzYxNC00ZTQ0LThiYTQtOTEzNGJhZjU4ZWI4IiwicyI6IlpURXpOakF3WkRNdE5ESXlZeTAwTURrMkxXSmpZamd0WkROaU5tWmxaakZqTnpBMyJ9"

# Restart or launch tunnel safely wrapped in quotes to prevent CLI parameter parsing crashes
pm2 delete cf-tunnel 2>/dev/null || true
pm2 start "cloudflared tunnel run --token $TUNNEL_TOKEN" --name "cf-tunnel"

# Save PM2 state across reboots/hand-offs
pm2 save

echo "✅ Setup complete! PM2 process status:"
pm2 status
