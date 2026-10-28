#!/bin/bash
set -e

echo "[RENDER AGY] Starting clean Antigravity CLI Remote Control..."

# 1. Disable D-Bus and Keyring so agy uses direct file-based storage
unset DBUS_SESSION_BUS_ADDRESS
unset SSH_AUTH_SOCK
export AGY_DISABLE_KEYRING=1
export PYTHONUNBUFFERED=1

# 2. Prepare directories
mkdir -p /root/.gemini/antigravity-cli \
         /root/.gemini/antigravity-cli/presence \
         /root/.config/antigravity \
         /root/.config/antigravity-cli \
         /root/.config/rclone \
         /root/.antigravity \
         /workspace

# 3. Restore OAuth token
if [ -n "$ANTIGRAVITY_TOKEN_BASE64" ]; then
    echo "[RENDER AGY] Restoring fresh OAuth token..."
    echo "$ANTIGRAVITY_TOKEN_BASE64" | base64 -d > /root/.gemini/antigravity-cli/antigravity-oauth-token
    chmod 600 /root/.gemini/antigravity-cli/antigravity-oauth-token
    
    # Mirror token across all possible CLI paths
    for d in /root/.gemini /root/.config/antigravity /root/.config/antigravity-cli /root/.antigravity; do
        mkdir -p "$d"
        cp -f /root/.gemini/antigravity-cli/antigravity-oauth-token "$d/antigravity-oauth-token"
        cp -f /root/.gemini/antigravity-cli/antigravity-oauth-token "$d/jetski-standalone-oauth-token"
    done
    cp -f /root/.gemini/antigravity-cli/antigravity-oauth-token /root/.gemini/antigravity-cli/jetski-standalone-oauth-token
    echo "[RENDER AGY] OAuth token configured in all paths."
else
    echo "[RENDER AGY] ERROR: ANTIGRAVITY_TOKEN_BASE64 is empty!"
fi

# 4. Generate complete settings.json
cat << 'SETTINGS_EOF' > /root/.gemini/antigravity-cli/settings.json
{
  "allowNonWorkspaceAccess": true,
  "artifactReviewPolicy": "always-proceed",
  "model": "Gemini 3.8 Flash (Medium)",
  "toolPermission": "always-proceed",
  "trustedWorkspaces": [
    "/workspace"
  ]
}
SETTINGS_EOF
cp -f /root/.gemini/antigravity-cli/settings.json /root/.config/antigravity/settings.json

# 5. Generate complete jetski_state.pbtxt (Full onboarding bypass)
cat << 'PB_EOF' > /root/.gemini/antigravity-cli/jetski_state.pbtxt
post_onboarding: {
  completed_steps: POST_ONBOARDING_STEP_TYPE_MANAGER_WELCOME
  completed_steps: POST_ONBOARDING_STEP_TYPE_USAGE_MODE
  completed_steps: POST_ONBOARDING_STEP_TYPE_AGENT_CONFIGURATION
  completed_steps: POST_ONBOARDING_STEP_TYPE_ADD_WORKSPACE
}
seen_nuxs: {
  uids: 51
  uids: 48
  uids: 24
}
agent_onboarding_completed: AGENT_ONBOARDING_STATE_COMPLETED
last_selected_agent_model: MODEL_PLACEHOLDER_M319
installation_uuid: "e0de5235-b2d5-477a-8df3-9ab04f3177c8"
migrations: {
  key: 3
  value: MIGRATION_STATUS_COMPLETED
}
migrations: {
  key: 4
  value: MIGRATION_STATUS_COMPLETED
}
migrations: {
  key: 5
  value: MIGRATION_STATUS_COMPLETED
}
PB_EOF
cp -f /root/.gemini/antigravity-cli/jetski_state.pbtxt /root/.config/antigravity/jetski_state.pbtxt

echo "34b32c25-9450-483f-9a3e-f10612cbe265" > /root/.gemini/antigravity-cli/installation_id
cp -f /root/.gemini/antigravity-cli/installation_id /root/.config/antigravity/installation_id

export CASCADE_DEFAULT_MODEL_OVERRIDE="Gemini 3.8 Flash (Medium)"
export AGY_MODEL="gemini-3.8-flash-medium"

# 6. Setup rclone configuration and restore from Google Drive
if [ -n "$RCLONE_CONFIG_BASE64" ]; then
    echo "[RENDER AGY] Restoring rclone config from environment..."
    echo "$RCLONE_CONFIG_BASE64" | base64 -d > /root/.config/rclone/rclone.conf
    chmod 600 /root/.config/rclone/rclone.conf
fi

if [ -f /root/.config/rclone/rclone.conf ]; then
    echo "[RENDER AGY] Google Drive config found. Restoring memory and components..."
    mkdir -p /tmp/bin
    if rclone copy memory:system/restore_and_protect.sh /tmp/bin/ --timeout 30s; then
        chmod +x /tmp/bin/restore_and_protect.sh
        echo "[RENDER AGY] Running restore_and_protect.sh in background..."
        /tmp/bin/restore_and_protect.sh || echo "[RENDER AGY] Warning during restoration (non-fatal)"
    else
        echo "[RENDER AGY] Notice: restore_and_protect.sh copy skipped or failed"
    fi
else
    echo "[RENDER AGY] Notice: rclone.conf not configured, skipping Google Drive restore"
fi

# 7. Workspace setup
cat << 'README_EOF' > /workspace/README.md
# Remote Workspace
Cloud Antigravity environment running on Render.
Model: Gemini 3.8 Flash (Medium)
README_EOF

# 8. Start remote-control daemon
INSTANCE_NAME="${REMOTE_INSTANCE_NAME:-Render-Cloud-AGY}"
echo "[RENDER AGY] Starting remote-control daemon with name: $INSTANCE_NAME..."
agy remote-control start --name "$INSTANCE_NAME" || true
agy remote-control status || true

# 9. Start background healthcheck and watchdog server
echo "[RENDER AGY] Starting server on port 10000..."
exec python3 /server.py
