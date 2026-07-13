#!/bin/bash
echo "🚀 V6.2.0: IDrive e2 Multi-Account Union Bootloader & Automation Core"

# ==========================================
# 1. TOOLS & RUNTIME ENGINE PROVISIONING
# ==========================================
sudo curl https://rclone.org/install.sh | sudo bash
sudo apt-get update && sudo apt-get install -y jq micro htop ncdu openssh-server

if ! command -v docker &> /dev/null; then
    echo "🐳 Installing Docker Engine..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker runner
fi

# ==========================================
# 2. PROXY EDGE & SYSTEM SECURE TUNNELING
# ==========================================
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb && rm cloudflared.deb
sudo service ssh start
echo "runner:runner" | sudo chpasswd

# Tunnel Service Integration
sudo cloudflared service install eyJhIjoiNDAwNmMxYTcwNmVhM2Y4NTFiMzViMWMyYTg1MDU5OGAiLCJ0IjoiMmRiZGY3MjctYzYxNC00ZTQ0LThiYTQtOTEzNGJhZjU4ZWI4IiwicyI6IlpURXpOakF3WkRNdE5ESXlZeTAwTURrMkxXSmpZamd0WkROaU5tWmxaakZqTnpBMyJ9

# ==========================================
# 3. DYNAMIC RCLONE MULTI-ACCOUNT UNION CONFIG
# ==========================================
mkdir -p /home/runner/.config/rclone

cat <<EOF > /home/runner/.config/rclone/rclone.conf
[e2_space1]
type = s3
provider = IDrive
access_key_id = $E2_ACCESS_KEY_1
secret_access_key = $E2_SECRET_1
endpoint = $E2_ENDPOINT_1
acl = private

[e2_space2]
type = s3
provider = IDrive
access_key_id = $E2_ACCESS_KEY_2
secret_access_key = $E2_SECRET_2
endpoint = $E2_ENDPOINT_2
acl = private

[vps_union]
type = union
upstreams = e2_space1:$E2_BUCKET_1 e2_space2:$E2_BUCKET_2
action_policy = epall
create_policy = mfs
search_policy = ff
EOF

# ==========================================
# 4. FILTER RULES DEPLOYMENT
# ==========================================
cat << 'EOF' > /home/runner/.config/rclone/filter-rules.txt
# 1. Explicitly allow targeted essential configurations
+ .bashrc
+ .profile
+ .opencode/**
+ .ssh/**
+ .pm2/dump.pm2
+ docker_backup/**

# 2. Block heavy runner, language, and system runtimes/caches globally
- actions-runner/**
- _work/**
- **/node_modules/**
- .npm/**
- .nvm/**
- .cache/**
- .rustup/**
- .cargo/**
- .ghcup/**
- .local/**
- .dotnet/**

# 3. Match all visible web applications & workspace folders
+ *
+ */**

# 4. Aggressively catch and drop any other hidden root items
- .*
- .*/**
EOF

# ==========================================
# 5. INITIAL STATE POOLING & RESUME
# ==========================================
echo "📥 Initializing and Pulling Home state from IDrive e2 Union..."
rclone copy vps_union: /home/runner \
    --filter-from /home/runner/.config/rclone/filter-rules.txt \
    --checksum --update --transfers 16 --buffer-size 256M || echo "ℹ️ Note: Fresh storage environment."

# 🐳 DOCKER RESTORE SEQUENCE
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

find /home/runner -name "docker-compose.yml" -o -name "compose.yml" | while read -r compose_file; do
    echo "🐳 Starting up Docker project: $compose_file"
    sudo docker compose -f "$compose_file" up -d || true
done

touch /home/runner/.files_ready

# ==========================================
# 6. APPLICATION DEPENDENCY STAGE
# ==========================================
echo "📦 Installing project dependencies..."
find /home/runner -maxdepth 4 -name "package.json" \
    -not -path "*/.*/*" \
    -not -path "*/node_modules/*" \
    -execdir npm install --no-audit --no-fund \;

touch /home/runner/.deps_ready

# ==========================================
# 7. GLOBAL PERSISTENT COMMAND INJECTION (Fixes Code 127)
# ==========================================
echo "🛠️ Injecting global 'push' execution engine into system path..."

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

echo "📤 Copying structural workspace state to IDrive e2 Union..."
rclone copy /home/runner vps_union: \
    --filter-from /home/runner/.config/rclone/filter-rules.txt \
    --checksum \
    --fast-list \
    --transfers 16 \
    --ignore-errors \
    --progress
EOF

# Authorize global system execution across non-interactive shell environments
sudo chmod +x /usr/local/bin/push

# Clean old artifacts from interactive .bashrc configs
sed -i '/# --- ETERNAL_VPS_MARKER ---/,/# --- END_MARKER ---/d' /home/runner/.bashrc

# Append core terminal shortcut aliases
cat <<EOF >> /home/runner/.bashrc
alias save='pm2 save --force'
alias status='pm2 status'
EOF

echo "✅ Deployment initialization successfully concluded."
