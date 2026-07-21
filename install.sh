#!/bin/bash
set -eo pipefail

# Print exact line number and command on error
trap 'echo "❌ Error on line $LINENO. Last command was: $BASH_COMMAND"' ERR

echo "🚀 Bootloading VPS Environment with Backblaze B2 S3 Storage..."

# ==========================================
# 0. Validate Backblaze B2 Credentials
# ==========================================
if [ -z "$B2_KEY_ID" ] || [ -z "$B2_APPLICATION_KEY" ] || [ -z "$B2_BUCKET" ]; then
    echo "❌ ERROR: Backblaze environment variables are missing!"
    echo "Please set B2_KEY_ID, B2_APPLICATION_KEY, and B2_BUCKET in GitHub Actions Secrets."
    exit 1
fi

# ==========================================
# 1. System Tools & Docker Installation
# ==========================================
echo "📦 Installing core system tools..."
sudo curl -s https://rclone.org/install.sh | sudo bash > /dev/null 2>&1 || true
sudo apt-get update --fix-missing -y > /dev/null 2>&1
sudo apt-get install -y jq micro htop ncdu openssh-server netcat-openbsd pigz > /dev/null 2>&1

# Direct SSH Configuration & Key Generation (Bypasses systemd/systemctl limits)
echo "🔑 Enabling OpenSSH Server..."
sudo mkdir -p /var/run/sshd
sudo ssh-keygen -A 2>/dev/null || true # Generate host keys if missing
echo "runner:runner" | sudo chpasswd

# Start sshd directly in background if service/systemctl fails
sudo service ssh start 2>/dev/null || sudo /usr/sbin/sshd -D &
sleep 2

# Verify SSH is bound to Port 22
if ! nc -zv 127.0.0.1 22 2>/dev/null; then
    echo "⚠️ SSH failed to start via service. Forcing manual daemon execution..."
    sudo /usr/sbin/sshd
fi

# Docker Engine Setup
if ! command -v docker &> /dev/null; then
    echo "🐳 Installing Docker Engine..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh > /dev/null 2>&1
    sudo usermod -aG docker runner || true
    rm -f get-docker.sh
fi

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
# 2. Configure Rclone for Backblaze B2
# ==========================================
echo "⚙️ Configuring Rclone for Backblaze B2..."
mkdir -p ~/.config/rclone

cat <<EOF > ~/.config/rclone/rclone.conf
[b2_remote]
type = b2
account = $B2_KEY_ID
key = $B2_APPLICATION_KEY
EOF

# Strict Filter Rules (System/cache exclusions + explicit dotfile inclusions)
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

# Exclude temporary & socket files
- /**/*.sock
- /**/*.lock

# Exclude generic dotfiles, EXCEPT critical configuration
+ /.bashrc
+ /.profile
+ /.ssh/**
+ /.opencode/**
+ /.pm2/dump.pm2
+ /docker_backup/**
- /.*/**
- /.*

# --- EXPLICIT INCLUSIONS ---
+ /**
EOF

# Verify B2 Connection
echo "🔍 Testing Backblaze B2 Auth..."
rclone lsd "b2_remote:" > /dev/null 2>&1 || {
  echo "❌ Could not authenticate with Backblaze B2. Double check B2_KEY_ID and B2_APPLICATION_KEY secrets."
  exit 1
}

# ==========================================
# 3. INITIAL SMART PULL (FROM BACKBLAZE)
# ==========================================
echo "📥 Syncing Home state from Backblaze B2 ($B2_BUCKET)..."
rclone mkdir "b2_remote:$B2_BUCKET" || true

rclone copy "b2_remote:$B2_BUCKET" /home/runner \
    --filter-from /home/runner/.config/rclone/filter-rules.txt \
    --skip-links \
    --transfers 8 \
    --checksum \
    --update \
    --verbose || echo "ℹ️ Note: No previous backup found or bucket is empty."

# ==========================================
# 4. PM2 & CLOUDFLARED TUNNEL BOOT
# ==========================================
export TUNNEL_TOKEN="eyJhIjoiNDAwNmMxYTcwNmVhM2Y4NTFiMzViMWMyYTg1MDU5OGEiLCJ0IjoiMmRiZGY3MjctYzYxNC00ZTQ0LThiYTQtOTEzNGJhZjU4ZWI4IiwicyI6IlpURXpOakF3WkRNdE5ESXlZeTAwTURrMkxXSmpZamd0WkROaU5tWmxaakZqTnpBMyJ9"

echo "⚡ Launching Cloudflare Tunnel via PM2..."
pm2 delete cf-tunnel 2>/dev/null || true
pm2 start "cloudflared tunnel run --token $TUNNEL_TOKEN" --name "cf-tunnel"
pm2 save || true

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
find /home/runner -name "docker-compose.yml" -o -name "compose.yml" 2>/dev/null | while read -r compose_file; do
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
    -not -path "*/node_modules/*" 2>/dev/null | while read -r pkg; do
    dir=$(dirname "$pkg")
    (cd "$dir" && npm install --no-audit --no-fund) || true
done

touch /home/runner/.deps_ready

# ==========================================
# 7. STANDALONE 'push' BINARY
# ==========================================
echo "🛠️ Writing '/usr/local/bin/push' executable..."
sudo tee /usr/local/bin/push > /dev/null << EOF
#!/bin/bash
set -e

echo "🛑 [PUSH] Safely freezing Docker containers..."
find /home/runner -name "docker-compose.yml" -o -name "compose.yml" 2>/dev/null | while read -r compose_file; do
    sudo docker compose -f "\$compose_file" down || true
done

mkdir -p /home/runner/docker_backup
echo "📦 [PUSH] Compressing active Docker volumes..."
sudo find /var/lib/docker/volumes/ -maxdepth 1 -mindepth 1 -not -name "metadata.db" 2>/dev/null | while read -r vol; do
    vol_name=\$(basename "\$vol")
    sudo tar -czf "/home/runner/docker_backup/\${vol_name}.tar.gz" -C "\$vol/_data" . 2>/dev/null || true
done

echo "📤 [PUSH] Syncing workspace state to Backblaze B2 ($B2_BUCKET)..."
rclone sync /home/runner "b2_remote:$B2_BUCKET" \
    --filter-from /home/runner/.config/rclone/filter-rules.txt \
    --skip-links \
    --checksum \
    --fast-list \
    --transfers 8 \
    --low-level-retries 10 \
    --ignore-errors \
    --progress

echo "✅ [PUSH] Sync completed successfully."
EOF

sudo chmod +x /usr/local/bin/push

# Shell Aliases Setup
if ! grep -q "ETERNAL_VPS_MARKER" /home/runner/.bashrc 2>/dev/null; then
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
pm2 status || true
