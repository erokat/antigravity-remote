#!/bin/bash
set -e

echo "[RENDER AGY] Starting clean Antigravity CLI Remote Control..."

# 1. Machine ID setup
mkdir -p /var/lib/dbus
if [ ! -f /etc/machine-id ]; then
    dbus-uuidgen > /etc/machine-id 2>/dev/null || echo "c1072a29b2d5477a8df39ab04f3177c8" > /etc/machine-id
fi
cp -f /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true

# 2. D-Bus session
if command -v dbus-launch >/dev/null 2>&1; then
    eval $(dbus-launch --sh-syntax 2>/dev/null || true)
    export DBUS_SESSION_BUS_ADDRESS
    echo "[RENDER AGY] D-Bus session initialized: $DBUS_SESSION_BUS_ADDRESS"
fi

# 3. Keyring daemon
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    eval $(echo "" | gnome-keyring-daemon --unlock 2>/dev/null || true)
    eval $(gnome-keyring-daemon --start 2>/dev/null || true)
    export SSH_AUTH_SOCK
    echo "[RENDER AGY] Keyring daemon started."
fi

# 4. Prepare directories
mkdir -p /root/.gemini/antigravity-cli /root/.config/antigravity /root/.config/antigravity-cli /workspace

# 5. Restore clean OAuth token
if [ -n "$ANTIGRAVITY_TOKEN_BASE64" ]; then
    echo "[RENDER AGY] Restoring OAuth token..."
    echo "$ANTIGRAVITY_TOKEN_BASE64" | base64 -d > /root/.gemini/antigravity-cli/antigravity-oauth-token
    chmod 600 /root/.gemini/antigravity-cli/antigravity-oauth-token
    
    # Mirror token to fallback locations
    for d in /root/.gemini /root/.config/antigravity /root/.config/antigravity-cli; do
        mkdir -p "$d"
        cp -f /root/.gemini/antigravity-cli/antigravity-oauth-token "$d/antigravity-oauth-token"
        cp -f /root/.gemini/antigravity-cli/antigravity-oauth-token "$d/jetski-standalone-oauth-token"
    done
    cp -f /root/.gemini/antigravity-cli/antigravity-oauth-token /root/.gemini/antigravity-cli/jetski-standalone-oauth-token
    echo "[RENDER AGY] OAuth token configured."
else
    echo "[RENDER AGY] ERROR: ANTIGRAVITY_TOKEN_BASE64 is empty!"
fi

# 6. Generate 100% clean settings.json (NO external bot paths!)
cat << 'EOF' > /root/.gemini/antigravity-cli/settings.json
{
  "allowNonWorkspaceAccess": true,
  "artifactReviewPolicy": "always-proceed",
  "model": "Gemini 3.8 Flash (Medium)",
  "toolPermission": "always-proceed",
  "trustedWorkspaces": [
    "/workspace"
  ]
}
EOF
cp -f /root/.gemini/antigravity-cli/settings.json /root/.config/antigravity/settings.json

# 7. Generate clean state files
cat << 'EOF' > /root/.gemini/antigravity-cli/jetski_state.pbtxt
agent_onboarding_completed: AGENT_ONBOARDING_STATE_COMPLETED
last_selected_agent_model: MODEL_PLACEHOLDER_M319
installation_uuid: "e0de5235-b2d5-477a-8df3-9ab04f3177c8"
EOF
cp -f /root/.gemini/antigravity-cli/jetski_state.pbtxt /root/.config/antigravity/jetski_state.pbtxt

echo "34b32c25-9450-483f-9a3e-f10612cbe265" > /root/.gemini/antigravity-cli/installation_id
cp -f /root/.gemini/antigravity-cli/installation_id /root/.config/antigravity/installation_id

export CASCADE_DEFAULT_MODEL_OVERRIDE="Gemini 3.8 Flash (Medium)"
export AGY_MODEL="gemini-3.8-flash-medium"

# 8. Workspace setup
cat << 'EOF' > /workspace/README.md
# Remote Workspace
Cloud Antigravity environment running on Render.
Model: Gemini 3.8 Flash (Medium)
EOF

# 9. Verify CLI
which agy || true
agy --version || true

# 10. Start remote-control daemon
INSTANCE_NAME="${REMOTE_INSTANCE_NAME:-Render-Cloud-AGY}"
echo "[RENDER AGY] Starting remote-control daemon with name: $INSTANCE_NAME..."
agy remote-control start --name "$INSTANCE_NAME" || true
agy remote-control status || true

# 11. Run background server on port 10000 with streaming logs & watchdog
echo "[RENDER AGY] Starting server on port 10000..."
exec python3 /server.py
