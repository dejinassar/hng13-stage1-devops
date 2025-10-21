#!/usr/bin/env bash
set -euo pipefail
_timestamp() { date +"%Y%m%d_%H%M%S"; }
LOGFILE="deploy_$(_timestamp).log"

log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*" | tee -a "$LOGFILE"
}

err_exit() {
  echo "ERROR: $*" | tee -a "$LOGFILE" >&2
  exit "${2:-1}"
}

trap 'err_exit "Unexpected error occurred. Check $LOGFILE for details."' ERR

log "=== Deploy script started ==="

is_valid_url() {
  case "$1" in
    http*://*|git@*|ssh://*|*github.com*) return 0 ;;
    *) return 1 ;;
  esac
}

is_number() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

file_exists_readable() {
  [ -f "$1" ] && [ -r "$1" ]
}

prompt() {
  local varname="$1"; shift
  local prompt_text="$*"
  local val=""
  printf "%s: " "$prompt_text" >&2
  if [ -t 0 ]; then
    read -r val
  else
    read -r val
  fi
  eval "$varname=\"\$val\""
}

log "Collecting parameters from user..."

prompt GIT_REPO_URL "Git repository URL (HTTPS or SSH)"
if ! is_valid_url "$GIT_REPO_URL"; then
  err_exit "Invalid Git repository URL: $GIT_REPO_URL"
fi
log "Repo URL: $GIT_REPO_URL"

prompt GIT_PAT "Personal Access Token (PAT) — paste or leave blank to use SSH key (input visible)"
if [ -n "$GIT_PAT" ]; then
  if [ "${#GIT_PAT}" -lt 8 ]; then
    err_exit "PAT looks too short. Aborting."
  fi
  log "PAT provided (length ${#GIT_PAT})"
else
  log "No PAT provided (assuming SSH key auth or public repo)"
fi

prompt BRANCH "Branch name (press Enter for 'main')"
: "${BRANCH:=main}"
log "Branch: $BRANCH"

prompt SSH_USER "Remote SSH username (e.g., ubuntu)"
if [ -z "$SSH_USER" ]; then err_exit "SSH username is required"; fi
log "SSH user: $SSH_USER"

prompt SSH_HOST "Remote server IP or hostname (e.g., 203.0.113.10)"
if [ -z "$SSH_HOST" ]; then err_exit "Remote server IP/hostname is required"; fi
log "SSH host: $SSH_HOST"

prompt SSH_KEY_PATH "Path to SSH private key file (e.g., ~/.ssh/id_rsa)"
: "${SSH_KEY_PATH:=$HOME/.ssh/id_rsa}"
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

if ! file_exists_readable "$SSH_KEY_PATH"; then
  err_exit "SSH key not found or not readable at: $SSH_KEY_PATH"
fi
log "SSH key path: $SSH_KEY_PATH"

prompt APP_PORT "Application internal port (container port, e.g., 5000)"
if ! is_number "$APP_PORT"; then err_exit "Application port must be a number"; fi
log "Application port: $APP_PORT"

log "----- Configuration Summary -----"
log "Repository: $GIT_REPO_URL"
log "Branch: $BRANCH"
log "SSH: ${SSH_USER}@${SSH_HOST}"
log "SSH key: $SSH_KEY_PATH"
log "App port: $APP_PORT"
log "Log file: $LOGFILE"
log "---------------------------------"

log "Step 1 complete: parameters collected and validated."

log "=== STEP 2: Cloning repository ==="

REPO_NAME=$(basename -s .git "$GIT_REPO_URL")
[ -z "$REPO_NAME" ] && err_exit "Could not determine repository name from URL."

if [ -d "$REPO_NAME" ]; then
  log "Repository already exists locally. Pulling latest changes..."
  cd "$REPO_NAME" || err_exit "Cannot cd into $REPO_NAME"
  git fetch origin "$BRANCH" || err_exit "Failed to fetch branch $BRANCH"
  git checkout "$BRANCH" || err_exit "Failed to switch to branch $BRANCH"
  git pull origin "$BRANCH" || err_exit "Failed to pull latest changes"
else
  if [ -n "$GIT_PAT" ]; then
    log "Cloning via HTTPS with PAT..."
    AUTH_URL="${GIT_REPO_URL/https:\/\//https:\/\/${GIT_PAT}@}"
    git clone -b "$BRANCH" "$AUTH_URL" || err_exit "Git clone failed (PAT)"
  else
    log "Cloning via SSH/HTTPS (no PAT provided)..."
    git clone -b "$BRANCH" "$GIT_REPO_URL" || err_exit "Git clone failed"
  fi
  cd "$REPO_NAME" || err_exit "Cannot cd into $REPO_NAME after clone"
fi

if [ -f "Dockerfile" ]; then
  log "Dockerfile found"
elif [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
  log "docker-compose file found"
else
  err_exit "No Dockerfile or docker-compose.yml found in the repository!"
fi

log "STEP 2 complete: Repository cloned and validated."

log "=== STEP 3: Testing SSH connectivity to remote host ==="

SSH_TARGET="${SSH_USER}@${SSH_HOST}"


if ssh -i "$SSH_KEY_PATH" -o BatchMode=yes -o ConnectTimeout=10 "$SSH_TARGET" "echo SSH_OK" >>"$LOGFILE" 2>&1; then
  log "SSH connection to $SSH_TARGET successful."
else
  err_exit "Unable to SSH into $SSH_TARGET. Please check your key path or security group."
fi

log "STEP 3 complete: SSH verified."
