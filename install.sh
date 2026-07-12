#!/bin/bash
echo "🚀 V5.7.2: Google Drive Union Bootloader (Isolated JSON File Path)"

# 1. Tools
sudo curl https://rclone.org/install.sh | sudo bash
sudo apt-get update && sudo apt-get install -y jq micro htop ncdu openssh-server

# 2. Cloudflared & SSH
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb && rm cloudflared.deb
sudo service ssh start
echo "runner:runner" | sudo chpasswd

# Tunnel Token
sudo cloudflared service install eyJhIjoiNDAwNmMxYTcwNmVhM2Y4NTFiMzViMWMyYTg1MDU5OGEiLCJ0IjoiMmRiZGY3MjctYzYxNC00ZTQ0LThiYTQtOTEzNGJhZjU4ZWI4IiwicyI6IlpURXpOakF3WkRNdE5ESXlZeTAwTURrMkxXSmpZamd0WkROaU5tWmxaakZqTnpBMyJ9

# 3. Dynamic Rclone Google Drive Union Config
mkdir -p ~/.config/rclone

# Safely dump the raw JSON string directly into a separate file.
# This prevents GitHub runner token expansion errors.
echo "$GD_SECRET" > ~/.config/rclone/service_account.json

# Write structural configuration blocks pointing to the file path instead of raw text
cat <<EOF > ~/.config/rclone/rclone.conf
[gdrive_acc1]
type = drive
scope = drive
service_account_file = /home/runner/.config/rclone/service_account.json

[gdrive_acc2]
type = drive
scope = drive
service_account_file = /home/runner/.config/rclone/service_account.json

[vps_union]
type = union
upstreams = gdrive_acc1:storage gdrive_acc2:storage
action_policy = epall
create_policy = mfs
search_policy = ff
EOF

# 4. INITIAL SMART PULL (From the virtual Union pool)
echo "📥 Syncing Home state from Google Drive Union..."
rclone copy vps_union: /home/runner \
    --exclude "actions-runner/**" \
    --exclude "_work/**" \
    --exclude "**/node_modules/**" \
    --exclude ".npm/**" \
    --exclude ".cache/**" \
    --checksum \
    --update \
    --transfers 16 \
    --buffer-size 256M \
    --progress

touch /home/runner/.files_ready

# 5. Dependency Build
echo "📦 Installing project dependencies..."
find /home/runner -maxdepth 4 -name "package.json" \
    -not -path "*/.*/*" \
    -not -path "*/node_modules/*" \
    -execdir npm install --no-audit --no-fund \;

touch /home/runner/.deps_ready

# 6. Persistent Aliases (Updated to target the union remote)
if ! grep -q "ETERNAL_VPS_MARKER" /home/runner/.bashrc; then
    cat <<EOF >> /home/runner/.bashrc

# --- ETERNAL_VPS_MARKER ---
alias save='pm2 save --force'
alias push='rclone sync /home/runner vps_union: --exclude "actions-runner/**" --exclude "_work/**" --exclude "**/node_modules/**" --exclude ".npm/**" --exclude ".cache/**" --checksum --fast-list --progress'
alias status='pm2 status'
# --- END_MARKER ---
EOF
fi
echo "✅ Environment Ready. Google Drive Union linked via clean file mapping."
