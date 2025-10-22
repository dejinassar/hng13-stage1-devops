#!/bin/bash
set -e
trap 'echo "[ERROR] Something went wrong. Exiting..."; exit 1;' ERR

# -------------------------------
# Logging function
# -------------------------------
log() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# -------------------------------
# User input
# -------------------------------
read -p "Enter Git repository URL: " GIT_REPO
read -p "Enter Personal Access Token (if any, leave blank otherwise): " GIT_TOKEN
read -p "Enter SSH user: " SSH_USER
read -p "Enter SSH host: " SSH_HOST
read -p "Enter SSH port (default 22): " SSH_PORT
SSH_PORT=${SSH_PORT:-22}
read -p "Enter application port: " APP_PORT
APP_PORT=${APP_PORT:-5000}

# -------------------------------
# Basic validation
# -------------------------------
[[ -z "$GIT_REPO" ]] && { echo "[ERROR] Git repository URL is required"; exit 1; }
[[ -z "$SSH_USER" || -z "$SSH_HOST" ]] && { echo "[ERROR] SSH details required"; exit 1; }

# -------------------------------
# SSH connectivity check
# -------------------------------
log "Checking SSH connectivity..."
ssh -o BatchMode=yes -o ConnectTimeout=5 -p $SSH_PORT $SSH_USER@$SSH_HOST "echo 'SSH Connection Successful'" || { echo "[ERROR] SSH Failed"; exit 1; }

# -------------------------------
# Server preparation
# -------------------------------
log "Preparing server (update + install Docker + Nginx)..."
ssh -p $SSH_PORT $SSH_USER@$SSH_HOST << 'EOF'
sudo apt update -y
sudo apt install -y docker.io docker-compose nginx
sudo systemctl enable docker
sudo systemctl start docker
sudo systemctl enable nginx
sudo systemctl start nginx
EOF

# -------------------------------
# Clone or update repo
# -------------------------------
APP_DIR="~/app_deploy"
log "Cloning or updating repository..."
ssh -p $SSH_PORT $SSH_USER@$SSH_HOST << EOF
if [ -d "$APP_DIR" ]; then
    cd $APP_DIR
    git reset --hard
    git pull
else
    git clone $GIT_REPO $APP_DIR
fi
EOF

# -------------------------------
# Docker deployment
# -------------------------------
log "Building and running Docker container..."
ssh -p $SSH_PORT $SSH_USER@$SSH_HOST << EOF
cd $APP_DIR
docker build -t myapp:latest .
docker stop myapp || true
docker rm myapp || true
docker run -d --name myapp -p $APP_PORT:5000 myapp:latest
EOF

# -------------------------------
# Nginx configuration
# -------------------------------
log "Setting up Nginx reverse proxy..."
ssh -p $SSH_PORT $SSH_USER@$SSH_HOST << EOF
sudo tee /etc/nginx/sites-available/myapp << 'NGINXCONF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINXCONF

sudo ln -sf /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
EOF

# -------------------------------
# Deployment validation
# -------------------------------
log "Validating deployment..."
ssh -p $SSH_PORT $SSH_USER@$SSH_HOST << EOF
docker ps | grep myapp || { echo "Docker container not running"; exit 1; }
systemctl is-active nginx || { echo "Nginx not running"; exit 1; }
EOF

log "Deployment completed successfully!"
