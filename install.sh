#!/bin/bash
echo "🚀 V6.5.5: High-Speed Bootloader (Data Pull-First Architecture)"

# ==========================================
# 1. CORE NETWORKING & EXTRACTION SETUP
# ==========================================
echo "🌐 Installing Base System Tools & SSH Server..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server jq micro htop ncdu > /dev/null 2>&1

# Ensure SSH service is active and listening
sudo service ssh start
echo "runner:runner" | sudo chpasswd

# Setup Rclone immediately for data extraction step
sudo curl https://rclone.org/install.sh | sudo bash > /dev/null 2>&1
mkdir -p /home/runner/.config/rclone
touch /home/runner/.bashrc

# ==========================================
# 2. DYNAMIC RCLONE MULTI-ACCOUNT UNION CONFIG
# ==========================================
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
# 3. ENHANCED SYSTEM FILTER RULES DEPLOYMENT
# ==========================================
cat << 'EOF' > /home/runner/.config/rclone/filter-rules.txt
+ .pm2/**
+ .docker/**
+ .ssh/**
+ .bashrc
+ .bash_history
+ .profile
- actions-runner/**
- _work/**
- **/node_modules/**
- .npm/**
- .nvm/**
- .cache/**
- .*
- .*/**
+ *
+ */**
EOF

# ==========================================
# 4. CRITICAL: INITIAL SMART PULL (RUNS FIRST)
# ==========================================
echo "📥 Syncing Home state from IDrive e2 Union BEFORE starting runtimes..."
rclone copy vps_union: /home/runner \
    --filter-from /home/runner/.config/rclone/filter-rules.txt \
    --checksum \
    --update \
    --transfers 16 \
    --buffer-size 256M \
    --progress || echo "ℹ️ Note: Clean environment or no existing files detected."

touch /home/runner/.files_ready

# ==========================================
# 5. PM2 RUNTIME ENGINE & TUNNEL INITIALIZATION
# ==========================================
echo "📦 Installing process registry engine..."
sudo npm install pm2 -g --unsafe-perm > /dev/null 2>&1

echo "🌐 Provisioning Cloudflare Tunnel binary..."
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb && rm cloudflared.deb

# Token definition
export TUNNEL_TOKEN="eyJhIjoiNDAwNmMxYTcwNmVhM2Y4NTFiMzViMWMyYTg1MDU5OGAiLCJ0IjoiMmRiZGY3MjctYzYxNC00ZTQ0LThiYTQtOTEzNGJhZjU4ZWI4IiwicyI6IlpURXpOakF3WkRNdE5ESXlZeTAwTURrMkxXSmpZamd0WkROaU5tWmxaakZqTnpBMyJ9"

echo "⚡ Starting Cloudflare Tunnel via PM2..."
pm2 start cloudflared --name "cf-tunnel" -- tunnel run --token "$TUNNEL_TOKEN"

# 🔄 PM2 RESURRECT SEQUENCE (Brings back your pulled apps safely)
if [ -d "/home/runner/.pm2" ]; then
    echo "⚡ Resuming active background processes via pulled PM2 dump..."
    pm2 resurrect || echo "⚠️ Warning: No active PM2 process dump available."
fi

echo "✅ Gateway tunnel verified under PM2 management. SSH Server online."

# ==========================================
# 6. APPLICATION DEPENDENCY STAGE
# ==========================================
echo "📦 Checking and installing missing project dependencies..."
find /home/runner -maxdepth 4 -name "package.json" \
    -not -path "*/.*/*" \
    -not -path "*/node_modules/*" \
    -execdir npm install --no-audit --no-fund \; 2>/dev/null || true

touch /home/runner/.deps_ready

# ==========================================
# 7. GLOBAL PERSISTENT COMMAND INJECTION
# ==========================================
sudo cat << 'EOF' > /usr/local/bin/push
#!/bin/bash
if command -v pm2 &> /dev/null; then
    pm2 save --force || true
fi

echo "📤 Syncing Home state back to IDrive e2 Union..."
rclone copy /home/runner vps_union: \
    --filter-from /home/runner/.config/rclone/filter-rules.txt \
    --checksum \
    --fast-list \
    --transfers 16 \
    --ignore-errors \
    --progress
EOF

sudo chmod +x /usr/local/bin/push

sed -i '/# --- ETERNAL_VPS_MARKER ---/,/# --- END_MARKER ---/d' /home/runner/.bashrc

cat <<EOF >> /home/runner/.bashrc
# --- ETERNAL_VPS_MARKER ---
alias save='pm2 save --force'
alias status='pm2 status'
# --- END_MARKER ---
EOF

echo "✅ Deployment initialization successfully concluded."
