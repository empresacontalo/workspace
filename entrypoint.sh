#!/bin/bash
# =============================================================================
# entrypoint.sh — AI Workspace Container Startup (XRDP + Services)
# =============================================================================

set -e

echo "[entrypoint] Setting up RDP User..."
# Default to aiuser/aipassword if not provided
RDP_USER=${RDP_USER:-aiuser}
RDP_PASSWORD=${RDP_PASSWORD:-aipassword}

# Create user if it doesn't exist
if ! id -u "$RDP_USER" > /dev/null 2>&1; then
    useradd -m -s /bin/bash "$RDP_USER"
    echo "$RDP_USER:$RDP_PASSWORD" | chpasswd
    # Add to sudoers without password
    echo "$RDP_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$RDP_USER
    chmod 0440 /etc/sudoers.d/$RDP_USER
fi

# Fix volume permissions
mkdir -p /data/logs
chown -R "$RDP_USER:$RDP_USER" /workspace /data /opt/hermes-agent /opt/hermes /opt/omniroute /opt/hermes-workspace /opt/aionui 2>/dev/null || true

# ---------------------------------------------------------------------------
# Setup Hermes Agent env file
# ---------------------------------------------------------------------------
HERMES_HOME="/data/hermes"
mkdir -p "$HERMES_HOME"
HERMES_ENV_FILE="$HERMES_HOME/.env"

echo "[entrypoint] Bootstrapping hermes-agent config..."
cat > "$HERMES_ENV_FILE" << EOF
OPENAI_BASE_URL=http://localhost:4000/v1
OPENAI_API_KEY=${OMNIROUTE_API_KEY:-${OPENAI_API_KEY:-omniroute-internal}}
${HERMES_LLM_MODEL:+HERMES_MODEL=${HERMES_LLM_MODEL}}
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
$([ -n "${API_SERVER_KEY:-}" ] && echo "API_SERVER_KEY=${API_SERVER_KEY}" || echo "# API_SERVER_KEY not set")
HERMES_DASHBOARD=true
HERMES_DASHBOARD_HOST=0.0.0.0
HERMES_DASHBOARD_PORT=9119
EOF
chown "$RDP_USER:$RDP_USER" "$HERMES_ENV_FILE"

# ---------------------------------------------------------------------------
# Start AI Services in Background (as RDP_USER where appropriate)
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting AI Services..."

# 1. OmniRoute (4000)
cd /opt/omniroute
PORT=4000 HOST=0.0.0.0 npm start > /data/logs/omniroute.log 2>&1 &
echo "OmniRoute started on port 4000"

# Wait for OmniRoute to be up
echo "Waiting for OmniRoute..."
until curl -s http://localhost:4000 > /dev/null 2>&1; do sleep 2; done

# 2. Hermes Agent Gateway & Dashboard (8642, 9119)
cd /opt/hermes-agent
HOME="$HERMES_HOME" /opt/hermes/.venv/bin/hermes gateway run --no-supervise > /data/logs/hermes-gateway.log 2>&1 &
HOME="$HERMES_HOME" /opt/hermes/.venv/bin/hermes dashboard > /data/logs/hermes-dashboard.log 2>&1 &
echo "Hermes Gateway and Dashboard started"

# 3. Hermes Workspace (3000)
cd /opt/hermes-workspace
PORT=3000 HOST=0.0.0.0 \
HERMES_API_URL="http://localhost:8642" \
HERMES_DASHBOARD_URL="http://localhost:9119" \
HERMES_API_TOKEN="${API_SERVER_KEY}" \
node server-entry.js > /data/logs/hermes-workspace.log 2>&1 &
echo "Hermes Workspace started on port 3000"

# 4. Aion UI (3005)
cd /opt/aionui
AIONUI_PORT=3005 PORT=3005 HOST=0.0.0.0 AIONUI_HOST=0.0.0.0 \
AIONUI_ALLOW_REMOTE=true ALLOW_REMOTE=true \
bun run webui:prod --remote --no-build > /data/logs/aionui.log 2>&1 &
echo "Aion UI started on port 3005"

# ---------------------------------------------------------------------------
# Start XRDP in foreground
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting XRDP..."
# Create xrdp key if not exists
if [ ! -f /etc/xrdp/rsakeys.ini ]; then
    xrdp-keygen xrdp auto
fi

# Start sesman and xrdp in nodaemon mode
/usr/sbin/xrdp-sesman -nodaemon &
exec /usr/sbin/xrdp -nodaemon
