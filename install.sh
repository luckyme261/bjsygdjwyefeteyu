#!/bin/bash
echo "🚀 V5.8.4: Google Drive Union Bootloader (Ordered PM2 Core)"

# 1. Tools & Docker Installation
sudo curl https://rclone.org/install.sh | sudo bash > /dev/null 2>&1
sudo apt-get update && sudo apt-get install -y jq micro htop ncdu openssh-server > /dev/null 2>&1

if ! command -v docker &> /dev/null; then
    echo "🐳 Installing Docker Engine..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh > /dev/null 2>&1
    sudo usermod -aG docker runner
fi

# SSH Server Setup
sudo service ssh start
echo "runner:runner" | sudo chpasswd

# Install cloudflared binary
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb > /dev/null 2>&1
sudo dpkg -i cloudflared.deb && rm cloudflared.deb

# 2. Dynamic Rclone Google Drive Union Config
mkdir -p ~/.config/rclone
echo "$GD_SECRET" > ~/.config/rclone/service_account.json

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

# 3. INITIAL SMART PULL (MUST RUN BEFORE PM2 STARTS)
echo "📥 Initializing and Syncing Home state from Google Drive Union..."
rclone mkdir gdrive_acc1:storage 2>/dev/null || true
rclone mkdir gdrive_acc2:storage 2>/dev/null || true

# Explicitly exclude socket files and runtime lock files from pull
rclone copy vps_union: /home/runner \
    --include "/.bashrc" \
    --include "/.profile" \
    --include "/.opencode/**" \
    --include "/.ssh/**" \
    --include "/.pm2/dump.pm2" \
    --include "/docker_backup/**" \
    --include "*/**" \
    --exclude "**.sock" \
    --exclude "/.pm2/rpc.sock" \
    --exclude "/.pm2/pub.sock" \
    --exclude "/.*/**" \
    --exclude "/.*" \
    --tpslimit 10 \
    --transfers 4 \
    --checksum --update --buffer-size 256M || echo "ℹ️ Note: Clean environment."

# 4. START PM2 AND TUNNEL (AFTER DATA IS RESTORED)
export TUNNEL_TOKEN="eyJhIjoiNDAwNmMxYTcwNmVhM2Y4NTFiMzViMWMyYTg1MDU5OGAiLCJ0IjoiMmRiZGY3MjctYzYxNC00ZTQ0LThiYTQtOTEzNGJhZjU4ZWI4IiwicyI6IlpURXpOakF3WkRNdE5ESXlZeTAwTURrMkxXSmpZamd0WkROaU5tWmxaakZqTnpBMyJ9"

echo "⚡ Booting Tunnel under PM2..."
pm2 start cloudflared --name "cf-tunnel" -- tunnel run --token "$TUNNEL_TOKEN"

# Docker Volume Restore
if [ -d "/home/runner/docker_backup" ]; then
    echo "📦 Restoring local Docker volumes..."
    mkdir -p /var/lib/docker/volumes/
    for archive in /home/runner/docker_backup/*.tar.gz; do
        [ -e "$archive" ] || continue
        vol_name=$(basename "$archive" .tar.gz)
        sudo mkdir -p "/var/lib/docker/volumes/$vol_name/_data"
        sudo tar -xzf "$archive" -C "/var/lib/docker/volumes/$vol_name/_data"
    done
fi

find /home/runner -name "docker-compose.yml" -o -name "compose.yml" | while read -r compose_file; do
    echo "🐳 Starting up Docker project: $compose_file"
    sudo docker compose -f "$compose_file" up -d || true
done

touch /home/runner/.files_ready

# 5. Dependency Build
echo "📦 Installing project dependencies..."
find /home/runner -maxdepth 4 -name "package.json" \
    -not -path "*/.*/*" \
    -not -path "*/node_modules/*" \
    -execdir npm install --no-audit --no-fund \; 2>/dev/null || true

touch /home/runner/.deps_ready

# 6. Persistent Filter Rules & Standalone 'push' Executable
mkdir -p /home/runner/.config/rclone
cat << 'EOF' > /home/runner/.config/rclone/filter-rules.txt
+ /.bashrc
+ /.profile
+ /.opencode/**
+ /.ssh/**
+ /.pm2/dump.pm2
+ /docker_backup/**
+ */**
- /**/*.sock
- /actions-runner/**
- /_work/**
- /**/node_modules/**
- /.*/**
- /.*
EOF

sudo cat << 'EOF' > /usr/local/bin/push
#!/bin/bash
echo "🛑 Safely freezing Docker containers..."
find /home/runner -name "docker-compose.yml" -o -name "compose.yml" | while read -r compose_file; do
    sudo docker compose -f "$compose_file" down || true
done

mkdir -p /home/runner/docker_backup
echo "📦 Compressing active Docker volumes..."
sudo find /var/lib/docker/volumes/ -maxdepth 1 -mindepth 1 -not -name "metadata.db" | while read -r vol; do
    vol_name=$(basename "$vol")
    sudo tar -czf "/home/runner/docker_backup/${vol_name}.tar.gz" -C "$vol/_data" . 2>/dev/null || true
done

echo "📤 Syncing structural workspace state to Google Drive Union..."
rclone sync /home/runner vps_union: \
    --filter-from /home/runner/.config/rclone/filter-rules.txt \
    --checksum \
    --fast-list \
    --transfers 4 \
    --tpslimit 10 \
    --low-level-retries 10 \
    --ignore-errors \
    --progress
EOF

sudo chmod +x /usr/local/bin/push

if ! grep -q "ETERNAL_VPS_MARKER" /home/runner/.bashrc; then
    cat <<EOF >> /home/runner/.bashrc

# --- ETERNAL_VPS_MARKER ---
alias save='pm2 save --force'
alias status='pm2 status'
# --- END_MARKER ---
EOF
fi

echo "✅ Environment Ready."
