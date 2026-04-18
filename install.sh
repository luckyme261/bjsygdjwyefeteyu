#!/bin/bash
echo "🚀 V5.2.2: Native Home Persistence"

# 1. Install Core Tools
sudo curl https://rclone.org/install.sh | sudo bash
sudo apt-get update && sudo apt-get install -y jq micro htop ncdu btop tmate openssh-server

# 2. Cloudflared & SSH Setup
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb && rm cloudflared.deb
sudo service ssh start
echo "runner:runner" | sudo chpasswd
sudo cloudflared service install eyJhIjoiNDAwNmMxYTcwNmVhM2Y4NTFiMzViMWMyYTg1MDU5OGEiLCJ0IjoiMmRiZGY3MjctYzYxNC00ZTQ0LThiYTQtOTEzNGJhZjU4ZWI4IiwicyI6IlpURXpOakF3WkRNdE5ESXlZeTAwTURrMkxXSmpZamd0WkROaU5tWmxaakZqTnpBMyJ9

# 3. Rclone Configuration
mkdir -p ~/.config/rclone
cat <<EOF > ~/.config/rclone/rclone.conf
[idrive]
type = s3
provider = Other
access_key_id = $IDRIVE_ACCESS_KEY
secret_access_key = $IDRIVE_SECRET_KEY
endpoint = $IDRIVE_ENDPOINT
region = us-west-2
EOF

# 4. INITIAL PULL: Pull the entire home directory state
echo "📥 Syncing state from iDrive..."
rclone copy idrive:$BUCKET_NAME /home/runner \
    --exclude "actions-runner/**" \
    --exclude "**/node_modules/**" \
    --exclude ".pm2/*.sock" \
    --exclude ".pm2/*.pid" \
    --exclude ".cache/**" \
    --progress

# Signal that files are now on disk
touch /home/runner/.files_ready

# 5. Dependency Installation
echo "📦 Refreshing dependencies..."
find /home/runner -name "package.json" -not -path "*/node_modules/*" -execdir npm install --no-audit --no-fund \;

# Signal that dependencies are ready
touch /home/runner/.deps_ready

# 6. Native .bashrc Update (Persistence for your session)
if ! grep -q "ETERNAL_VPS_MARKER" /home/runner/.bashrc; then
    cat <<EOF >> /home/runner/.bashrc

# --- ETERNAL_VPS_MARKER ---
alias save='pm2 save --force'
alias push='rclone sync /home/runner idrive:\$BUCKET_NAME --exclude "actions-runner/**" --exclude "**/node_modules/**" --exclude ".pm2/*.sock" --exclude ".pm2/*.pid" --exclude ".cache/**" --progress'
alias status='pm2 status'
alias logs='pm2 logs'
# --- END_MARKER ---
EOF
fi

echo "Ready."
