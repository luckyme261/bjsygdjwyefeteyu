#!/bin/bash
echo "🚀 V6.5.0: IDrive e2 Multi-Account Union Bootloader (Priority Tunnel Flow)"

# ==========================================
# 1. IMMEDIATE TUNNEL & SSH SECURE PROVISIONING (Moved to Top)
# ==========================================
echo "🌐 Provisioning Cloudflare Tunnel edge immediately..."
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb && rm cloudflared.deb

# Boot SSH service and authorize credentials
sudo apt-get update && sudo apt-get install -y openssh-server
sudo service ssh start
echo "runner:runner" | sudo chpasswd

# Export and run tunnel instantly to open local vps.sh access
export TUNNEL_TOKEN="eyJhIjoiNDAwNmMxYTcwNmVhM2Y4NTFiMzViMWMyYTg1MDU5OGAiLCJ0IjoiMmRiZGY3MjctYzYxNC00ZTQ0LThiYTQtOTEzNGJhZjU4ZWI4IiwicyI6IlpURXpOakF3WkRNdE5ESXlZeTAwTURrMkxXSmpZamd0WkROaU5tWmxaakZqTnpBMyJ9"
nohup cloudflared tunnel run --token "$TUNNEL_TOKEN" > /tmp/cloudflared.log 2>&1 &

echo "✅ Cloudflare Tunnel background thread established. Gateway open."

# ==========================================
# 2. SYSTEM TOOLS & RUNTIME ENGINE PROVISIONING
# ==========================================
echo "📦 Continuing background system provisioning..."
sudo curl https://rclone.org/install.sh | sudo bash
sudo apt-get install -y jq micro htop ncdu

# Docker Runtime Setup
if ! command -v docker &> /dev/null; then
    echo "🐳 Installing Docker Engine..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker runner
fi

# PM2 Global Path Installation Engine
if ! command -v pm2 &> /dev/null; then
    echo "📦 PM2 missing. Checking npm context..."
    if command -v npm &> /dev/null; then
        echo "⚡ Installing PM2 via current user environment..."
        npm install pm2 -g || sudo npm install pm2 -g --unsafe-perm
        
        if [ -f "$HOME/.npm-global/bin/pm2" ]; then
            sudo ln -sf "$HOME/.npm-global/bin/pm2" /usr/local/bin/pm2
        elif [ -f "$HOME/.nvm/versions/node/$(node -v)/bin/pm2" ]; then
            sudo ln -sf "$HOME/.nvm/versions/node/$(node -v)/bin/pm2" /usr/local/bin/pm2
        fi
    else
        echo "⚠️ Node/NPM not discovered in path yet. Installing system Node..."
        sudo apt-get install -y nodejs npm
        sudo npm install pm2 -g
    fi
fi

# Ensure Bash configuration is present
touch /home/runner/.bashrc

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
# 4. ENHANCED SYSTEM FILTER RULES DEPLOYMENT
# ==========================================
cat << 'EOF' > /home/runner/.config/rclone/filter-rules.txt
# 1. Explicitly protect crucial hidden runtime directories & shell metrics
+ .pm2/**
+ .docker/**
+ .ssh/**
+ .bashrc
+ .bash_history
+ .profile
+ docker_backup/**

# 2. Block heavy system runtimes, caches, and repository workspaces globally
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

# 3. Aggressively drop any unwhitelisted root hidden files/folders
- .*
- .*/**

# 4. Match all visible workspace directories and assets
+ *
+ */**
EOF

# ==========================================
# 5. INITIAL STATE POOLING & RESUME (Rclone -> PM2 & Docker)
# ==========================================
echo "📥 Initializing and Pulling Home state from IDrive e2 Union..."

rclone copy vps_union: /home/runner \
    --filter-from /home/runner/.config/rclone/filter-rules.txt \
    --checksum \
    --update \
    --transfers 16 \
    --buffer-size 256M \
    --contimeout 15s \
    --timeout 30s \
    --retries 2 \
    -v || echo "ℹ ... Skipping initial pull or fresh storage environment encountered."

# 🔄 PM2 RESURRECT SEQUENCE
if command -v pm2 &> /dev/null; then
    if [ -d "/home/runner/.pm2" ]; then
        echo "⚡ Resuming active background processes via PM2..."
        pm2 resurrect || echo "⚠️ Warning: No active PM2 process dump available."
    fi
fi

# 🐳 DOCKER VOLUME RESTORE SEQUENCE
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

# 🐳 DOCKER CONTAINERS RESUME
find /home/runner -name "docker-compose.yml" -o -name "compose.yml" | while read -r compose_file; do
    echo "🐳 Resuming Docker project containers: $compose_file"
    sudo docker compose -f "$compose_file" up -d || true
done

touch /home/runner/.files_ready

# ==========================================
# 6. APPLICATION DEPENDENCY STAGE
# ==========================================
echo "📦 Checking and installing missing project dependencies..."
find /home/runner -maxdepth 4 -name "package.json" \
    -not -path "*/.*/*" \
    -not -path "*/node_modules/*" \
    -execdir npm install --no-audit --no-fund \;

touch /home/runner/.deps_ready

# ==========================================
# 7. GLOBAL PERSISTENT COMMAND INJECTION
# ==========================================
echo "🛠 Overwriting global 'push' execution engine into system path..."

sudo cat << 'EOF' > /usr/local/bin/push
#!/bin/bash
echo "🛑 Saving current PM2 application registry..."
if command -v pm2 &> /dev/null; then
    pm2 save --force || true
fi

echo "🛑 Safely freezing active Docker containers..."
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

# Authorize global system execution
sudo chmod +x /usr/local/bin/push

# Clean old artifacts from interactive config states
sed -i '/# --- ETERNAL_VPS_MARKER ---/,/# --- END_MARKER ---/d' /home/runner/.bashrc

# Append core terminal shortcut aliases directly into standard Bash profile
cat <<EOF >> /home/runner/.bashrc
# --- ETERNAL_VPS_MARKER ---
alias save='pm2 save --force'
alias status='pm2 status'
# --- END_MARKER ---
EOF

echo "✅ Deployment initialization successfully concluded."
