#!/bin/bash
echo "🚀 V6.5.1: High-Speed Bootloader"

# ==========================================
# 1. IMMEDIATE TUNNEL & SSH SECURE PROVISIONING
# ==========================================
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb && rm cloudflared.deb

sudo apt-get update && sudo apt-get install -y jq micro htop ncdu openssh-server > /dev/null 2>&1
sudo service ssh start
echo "runner:runner" | sudo chpasswd

# Fire tunnel exactly as a stable background process routing logs to /tmp
export TUNNEL_TOKEN="eyJhIjoiNDAwNmMxYTcwNmVhM2Y4NTFiMzViMWMyYTg1MDU5OGAiLCJ0IjoiMmRiZGY3MjctYzYxNC00ZTQ0LThiYTQtOTEzNGJhZjU4ZWI4IiwicyI6IlpURXpOakF3WkRNdE5ESXlZeTAwTURrMkxXSmpZamd0WkROaU5tWmxaakZqTnpBMyJ9"
nohup cloudflared tunnel run --token "$TUNNEL_TOKEN" > /tmp/cloudflared.log 2>&1 &

# ==========================================
# 2. DYNAMIC RCLONE MULTI-ACCOUNT UNION CONFIG
# ==========================================
mkdir -p /home/runner/.config/rclone
sudo curl https://rclone.org/install.sh | sudo bash > /dev/null 2>&1

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
# 4. INITIAL SMART PULL
# ==========================================
echo "📥 Syncing Home state from IDrive e2 Union..."
rclone copy vps_union: /home/runner \
    --filter-from /home/runner/.config/rclone/filter-rules.txt \
    --checksum \
    --update \
    --transfers 16 \
    --buffer-size 256M \
    --progress

touch /home/runner/.files_ready

# ==========================================
# 5. DEPENDENCY STAGE
# ==========================================
echo "📦 Checking and installing missing project dependencies..."
find /home/runner -maxdepth 4 -name "package.json" \
    -not -path "*/.*/*" \
    -not -path "*/node_modules/*" \
    -execdir npm install --no-audit --no-fund \;

touch /home/runner/.deps_ready

# ==========================================
# 6. GLOBAL PERSISTENT COMMAND INJECTION
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

echo "✅ Environment Ready. Initial pull complete."
