#!/bin/bash
echo "🚀 V5.8: Google Drive Union Bootloader + Docker Persistence Engine"

# 1. Tools & Docker Installation
sudo curl https://rclone.org/install.sh | sudo bash
sudo apt-get update && sudo apt-get install -y jq micro htop ncdu openssh-server

# Install Docker and Docker Compose if not already present
if ! command -v docker &> /dev/null; then
    echo "🐳 Installing Docker Engine..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker runner
fi

# 2. Cloudflared & SSH Setup
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb && rm cloudflared.deb
sudo service ssh start
echo "runner:runner" | sudo chpasswd

# Tunnel Token
sudo cloudflared service install eyJhIjoiNDAwNmMxYTcwNmVhM2Y4NTFiMzViMWMyYTg1MDU5OGEiLCJ0IjoiMmRiZGY3MjctYzYxNC00ZTQ0LThiYTQtOTEzNGJhZjU4ZWI4IiwicyI6IlpURXpOakF3WkRNdE5ESXlZeTAwTURrMkxXSmpZamd0WkROaU5tWmxaakZqTnpBMyJ9

# 3. Dynamic Rclone Google Drive Union Config
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

# 4. INITIAL SMART PULL (State Restoration)
echo "📥 Initializing and Syncing Home state from Google Drive Union..."
rclone mkdir gdrive_acc1:storage 2>/dev/null || true
rclone mkdir gdrive_acc2:storage 2>/dev/null || true

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
    --progress || echo "ℹ️ Note: No existing files found. Proceeding clean."

# 🐳 DOCKER RESUME LOGIC
# Look for any zipped docker volumes that were backed up in the last cycle
if [ -d "/home/runner/docker_backup" ]; then
    echo "📦 Restoring local Docker volumes..."
    mkdir -p /var/lib/docker/volumes/
    for archive in /home/runner/docker_backup/*.tar.gz; do
        [ -e "$archive" ] || continue
        vol_name=$(basename "$archive" .tar.gz)
        echo "🔄 Restoring volume: $vol_name"
        sudo mkdir -p "/var/lib/docker/volumes/$vol_name/_data"
        sudo tar -xzf "$archive" -C "/var/lib/docker/volumes/$vol_name/_data"
    done
fi

# Automatically spin back up any docker-compose projects found in the workspace
find /home/runner -name "docker-compose.yml" -o -name "compose.yml" | while read -r compose_file; do
    echo "🐳 Starting up Docker project: $compose_file"
    sudo docker compose -f "$compose_file" up -d || true
done

touch /home/runner/.files_ready

# 5. Dependency Build (For Node/Next.js/PM2 projects)
echo "📦 Installing project dependencies..."
find /home/runner -maxdepth 4 -name "package.json" \
    -not -path "*/.*/*" \
    -not -path "*/node_modules/*" \
    -execdir npm install --no-audit --no-fund \;

touch /home/runner/.deps_ready

# 6. Persistent Aliases & Global Push Function
if ! grep -q "ETERNAL_VPS_MARKER" /home/runner/.bashrc; then
    cat <<EOF >> /home/runner/.bashrc

# --- ETERNAL_VPS_MARKER ---
alias save='pm2 save --force'
alias status='pm2 status'

# Custom smart push function that safely handles Docker and Rclone
push() {
    echo "🛑 Safely freezing Docker containers..."
    # Find all active compose files and bring them down cleanly to flush database caches to disk
    find /home/runner -name "docker-compose.yml" -o -name "compose.yml" | while read -r compose_file; do
        sudo docker compose -f "\$compose_file" down || true
    done
    
    # Backup named volumes into home directory before upload
    mkdir -p /home/runner/docker_backup
    echo "📦 Compressing active Docker volumes..."
    sudo find /var/lib/docker/volumes/ -maxdepth 1 -mindepth 1 -not -name "metadata.db" | while read -r vol; do
        vol_name=\$(basename "\$vol")
        sudo tar -czf "/home/runner/docker_backup/\${vol_name}.tar.gz" -C "\$vol/_data" . 2>/dev/null || true
    done
    
    echo "📤 Syncing everything up to the Google Drive Union..."
    rclone sync /home/runner vps_union: --exclude "actions-runner/**" --exclude "_work/**" --exclude "**/node_modules/**" --exclude ".npm/**" --exclude ".cache/**" --checksum --fast-list --progress
}
# --- END_MARKER ---
EOF
fi

echo "✅ Environment Ready. Google Drive Union and Docker pipeline established."
