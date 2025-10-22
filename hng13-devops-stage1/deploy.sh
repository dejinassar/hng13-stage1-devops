#!/usr/bin/env bash
set -euo pipefail

# ---------- LOGGING ----------
_timestamp() { date +"%Y%m%d_%H%M%S"; }
LOGFILE="deploy_$(_timestamp).log"
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"; }
err_exit() { echo "ERROR: $*" | tee -a "$LOGFILE" >&2; exit "${2:-1}"; }
trap 'err_exit "Unexpected error occurred. Check $LOGFILE for details."' ERR

log "=== Deploy script started ==="

# ---------- HELPERS ----------
is_valid_url() { case "$1" in http*://*|git@*|ssh://*|*github.com*) return 0 ;; *) return 1 ;; esac; }
is_number() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
file_exists_readable() { [ -f "$1" ] && [ -r "$1" ]; }

prompt() {
  local varname="$1"; shift
  printf "%s: " "$*" >&2
  read -r val
  eval "$varname=\"\$val\""
}

# ---------- STEP 1: INPUTS ----------
log "STEP 1: Collecting parameters from user..."
prompt GIT_REPO_URL "Git repository URL (HTTPS or SSH)"
is_valid_url "$GIT_REPO_URL" || err_exit "Invalid Git repository URL"

prompt GIT_PAT "Personal Access Token (optional, press Enter to skip)"
prompt BRANCH "Branch name (default: main)"; : "${BRANCH:=main}"
prompt SSH_USER "Remote SSH username"
prompt SSH_HOST "Remote server IP/hostname"
prompt SSH_KEY_PATH "Path to SSH private key (default: ~/.ssh/id_rsa)"; : "${SSH_KEY_PATH:=$HOME/.ssh/id_rsa}"
prompt APP_PORT "Application port (default: 5000)"; : "${APP_PORT:=5000}"
is_number "$APP_PORT" || err_exit "Application port must be a number"

SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
file_exists_readable "$SSH_KEY_PATH" || err_exit "SSH key not found at $SSH_KEY_PATH"
log "STEP 1 complete: parameters collected"

# ---------- STEP 2: CLONE REPO ----------
REPO_NAME=$(basename -s .git "$GIT_REPO_URL")
if [ -d "$REPO_NAME" ]; then
    log "Repository exists locally. Pulling latest changes..."
    cd "$REPO_NAME" || err_exit "Cannot cd into repo"
    git fetch origin "$BRANCH"
    git reset --hard "origin/$BRANCH"
else
    log "Cloning repository..."
    if [ -n "$GIT_PAT" ]; then
        AUTH_URL="${GIT_REPO_URL/https:\/\//https:\/\/${GIT_PAT}@}"
        git clone -b "$BRANCH" "$AUTH_URL" || err_exit "Git clone failed"
    else
        git clone -b "$BRANCH" "$GIT_REPO_URL" || err_exit "Git clone failed"
    fi
    cd "$REPO_NAME" || err_exit "Cannot cd into repo"
fi
[ -f "Dockerfile" ] || [ -f "docker-compose.yml" ] || err_exit "No Dockerfile or docker-compose.yml found"
log "STEP 2 complete: repository ready"

# ---------- STEP 3: SSH TEST ----------
SSH_TARGET="${SSH_USER}@${SSH_HOST}"
log "STEP 3: Testing SSH connectivity..."
ssh -i "$SSH_KEY_PATH" -o BatchMode=yes -o ConnectTimeout=10 "$SSH_TARGET" "echo SSH_OK" >>"$LOGFILE" 2>&1 || \
  err_exit "SSH connection failed"
log "STEP 3 complete: SSH verified"

# ---------- STEP 4: REMOTE SETUP ----------
log "STEP 4: Preparing remote server..."
ssh -i "$SSH_KEY_PATH" "$SSH_TARGET" bash <<'EOF' >>"$LOGFILE" 2>&1
sudo apt update -y
sudo apt install -y docker.io docker-compose nginx
sudo usermod -aG docker $USER
sudo systemctl enable --now docker
sudo systemctl enable --now nginx
EOF
log "STEP 4 complete: remote server ready"

# ---------- STEP 5: DEPLOY APP ----------
log "STEP 5: Deploying Dockerized application..."
ssh -i "$SSH_KEY_PATH" "$SSH_TARGET" "rm -rf ~/app && mkdir -p ~/app"
scp -i "$SSH_KEY_PATH" -r ./* "$SSH_TARGET:~/app/"

ssh -i "$SSH_KEY_PATH" "$SSH_TARGET" bash <<EOF >>"$LOGFILE" 2>&1
cd ~/app
docker stop myapp || true
docker rm myapp || true
docker build -t myapp .
docker run -d -p ${APP_PORT}:${APP_PORT} --name myapp myapp
EOF
log "STEP 5 complete: Docker app deployed"

# ---------- STEP 6: NGINX CONFIG ----------
log "STEP 6: Configuring Nginx reverse proxy..."
ssh -i "$SSH_KEY_PATH" "$SSH_TARGET" bash >>"$LOGFILE" 2>&1 <<EOF
cat > ~/myapp.nginx <<'NGINXCONF'
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:APP_PORT_PLACEHOLDER;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINXCONF
sed -i "s/APP_PORT_PLACEHOLDER/${APP_PORT}/g" ~/myapp.nginx
sudo mv ~/myapp.nginx /etc/nginx/sites-available/myapp
sudo ln -sf /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
EOF
log "STEP 6 complete: Nginx configured"

# ---------- STEP 7: VALIDATION ----------
log "STEP 7: Validating deployment..."
ssh -i "$SSH_KEY_PATH" "$SSH_TARGET" bash <<EOF >>"$LOGFILE" 2>&1
systemctl is-active --quiet docker && echo "Docker running"
docker ps --filter "name=myapp" --format "{{.Names}}: {{.Status}}"
curl -s --head http://localhost:${APP_PORT} | head -n 1
EOF

APP_URL="http://$SSH_HOST/"
if curl -s --head "$APP_URL" | grep "200 OK" >/dev/null; then
    log "Deployment successful! App accessible at $APP_URL"
else
    err_exit "Deployment validation failed at $APP_URL"
fi

log "=== Deployment script finished successfully! ==="
