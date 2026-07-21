#!/bin/bash
set -e

echo "🚀 V5.8.6: Google Drive Union Bootloader (Quota & Filter Hotfix)"

# ==========================================
# 1. System Tools & Docker Installation
# ==========================================
echo "📦 Installing core system tools..."
sudo curl https://rclone.org/install.sh | sudo bash > /dev/null 2>&1
sudo apt-get update --fix-missing -y > /dev/null 2>&1
sudo apt-get install -y jq micro htop ncdu openssh-server netcat-openbsd pigz > /dev/null 2>&1

# Docker Engine Setup
if ! command -v docker &> /dev/null; then
    echo "🐳 Installing Docker Engine..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh > /dev/null 2>&1
    sudo usermod -aG docker runner || true
    rm -f get-docker.sh
fi

# OpenSSH Server Initialization
echo "🔑 Enabling OpenSSH Server on Port 22..."
sudo systemctl enable --now ssh 2>/dev/null || sudo service ssh start 2>/dev/null || sudo /usr/sbin/sshd || true
echo "runner:runner" | sudo chpasswd

# Cloudflared Binary Installation
if ! command -v cloudflared &> /dev/null; then
    echo "🌐 Installing Cloudflared..."
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb > /dev/null 2>&1
    sudo dpkg -i cloudflared.deb && rm -f cloudflared.deb
fi

# PM2 Global Setup
if ! command -v pm2 &> /dev/null; then
    echo "⚡ Installing PM2 Process Manager..."
    sudo npm install -g pm2 > /dev/null 2>&1
fi

# ==========================================
# 2. Dynamic Rclone Google Drive Union Config
# ==========================================
echo "⚙️ Configuring Rclone Google Drive Union..."
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

# Write strict filter rules (EXCLUDES MUST COME BEFORE INCLUDES)
cat << 'EOF' > /home/runner/.config/rclone/filter-rules.txt
# --- STRICT EXCLUSIONS FIRST ---
- /.cache/**
- /.local/**
- /.dotnet/**
- /.npm/**
- /.cargo/**
- /.rustup/**
- /**/node_modules/**
- /actions-runner/**
- /_work/**
- /**/*.sock
- /**/*.lock

# Exclude all hidden files/folders by default, except explicitly allowed ones
- /.*/**
- /.*

# --- EXPLICIT INCLUSIONS ---
+ /.bashrc
+ /.profile
+ /.opencode/**
+ /.ssh/**
+ /.pm2/dump.pm2
+ /docker_backup/**
+ /**
EOF

# ==========================================
# 3. INITIAL SMART PULL (FROM DRIVE)
# ==========================================
echo "📥 Syncing Home state from Google Drive Union..."
rclone mkdir gdrive_acc1:storage 2>/dev/null || true
rclone mkdir gdrive_acc2:storage 2>/dev/null || true

rclone copy vps_union: /home/runner \
    --filter-from /home/runner/.config/rclone/filter-rules.txt \
    --skip-links \
    --tpslimit 10 \
    --transfers 4 \
    --checksum --update --buffer-size 256M || echo "ℹ️ Note: First run or clean environment."

# ==========================================
# 4. PM2 & CLOUDFLARED TUNNEL BOOT
# ==========================================
export TUNNEL_TOKEN="eyJhIjoiNDAwNmMxYTcwNmVhM2Y4NTFiMzViMWMyYTg1MDU5OGEiLCJ0IjoiMmRiZGY3MjctYzYxNC00ZTQ0LThiYTQtOTEzNGJhZjU4ZWI4IiwicyI6IlpURXpOakF3WkRNdE5ESXlZeTAwTURrMkxXSmpZamd0WkROaU5tWmxaakZqTnpBMyJ9"

echo "⚡ Launching Cloudflare Tunnel via PM2..."
pm2 delete cf-tunnel 2>/dev/null || true
pm2 start "cloudflared tunnel run --token $TUNNEL_TOKEN" --name "cf-tunnel"
pm2 save

# ==========================================
# 5. DOCKER RESTORE & AUTO-START
# ==========================================
if [ -d "/home/runner/docker_backup" ]; then
    echo "📦 Restoring local Docker volumes..."
    mkdir -p /var/lib/docker/volumes/
    for archive in /home/runner/docker_backup/*.tar.gz; do
        [ -e "$archive" ] || continue
        vol_name=$(basename "$archive" .tar.gz)
        sudo mkdir -p "/var/lib/docker/volumes/$vol_name/_data"
        sudo tar -xzf "$archive" -C "/var/lib/docker/volumes/$vol_name/_data" 2>/dev/null || true
    done
fi

echo "🐳 Spawning Docker compose projects..."
find /home/runner -name "docker-compose.yml" -o -name "compose.yml" | while read -r compose_file; do
    echo "  └─ Starting: $compose_file"
    sudo docker compose -f "$compose_file" up -d || true
done

touch /home/runner/.files_ready

# ==========================================
# 6. DEPENDENCY BUILD
# ==========================================
echo "📦 Installing project dependencies..."
find /home/runner -maxdepth 4 -name "package.json" \
    -not -path "*/.*/*" \
    -not -path "*/node_modules/*" \
    -execdir npm install --no-audit --no-fund \; 2>/dev/null || true

touch /home/runner/.deps_ready

# ==========================================
# 7. STANDALONE 'push' BINARY
# ==========================================
echo "🛠️ Writing '/usr/local/bin/push' executable..."
sudo tee /usr/local/bin/push > /dev/null << 'EOF'
#!/bin/bash
set -e

echo "🛑 [PUSH] Safely freezing Docker containers..."
find /home/runner -name "docker-compose.yml" -o -name "compose.yml" | while read -r compose_file; do
    sudo docker compose -f "$compose_file" down || true
done

mkdir -p /home/runner/docker_backup
echo "📦 [PUSH] Compressing active Docker volumes..."
sudo find /var/lib/docker/volumes/ -maxdepth 1 -mindepth 1 -not -name "metadata.db" | while read -r vol; do
    vol_name=$(basename "$vol")
    sudo tar -czf "/home/runner/docker_backup/${vol_name}.tar.gz" -C "$vol/_data" . 2>/dev/null || true
done

echo "📤 [PUSH] Syncing workspace state to Google Drive Union..."
rclone sync /home/runner vps_union: \
    --filter-from /home/runner/.config/rclone/filter-rules.txt \
    --skip-links \
    --checksum \
    --fast-list \
    --transfers 4 \
    --tpslimit 10 \
    --low-level-retries 10 \
    --ignore-errors \
    --progress

echo "✅ [PUSH] Sync completed successfully."
EOF

sudo chmod +x /usr/local/bin/push

# Shell Aliases Setup
if ! grep -q "ETERNAL_VPS_MARKER" /home/runner/.bashrc; then
    cat <<EOF >> /home/runner/.bashrc

# --- ETERNAL_VPS_MARKER ---
alias save='pm2 save --force'
alias status='pm2 status'
# --- END_MARKER ---
EOF
fi

echo "------------------------------------------------"
echo "✅ Environment Ready! Diagnostics:"
echo "SSH Status (Port 22):"
nc -zv 127.0.0.1 22 || true
echo "PM2 Status:"
pm2 status
