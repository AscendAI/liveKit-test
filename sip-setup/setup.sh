#!/bin/bash
# One-time SIP trunk + dispatch rule setup.
# Run this AFTER docker-compose up and AFTER filling in trunk.json credentials.
#
# Prerequisites:
#   brew install livekit-cli      (Mac)
#   go install github.com/livekit/livekit-cli/cmd/lk@latest   (Linux)
#
# Usage:
#   cd sip-setup
#   bash setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

# Load env from project root
if [ -f "$ROOT_DIR/.env" ]; then
  set -a; source "$ROOT_DIR/.env"; set +a
fi

export LIVEKIT_URL="${LIVEKIT_URL:-ws://127.0.0.1:7880}"
export LIVEKIT_API_KEY
export LIVEKIT_API_SECRET

if [ -z "$LIVEKIT_API_KEY" ] || [ -z "$LIVEKIT_API_SECRET" ]; then
  echo "ERROR: LIVEKIT_API_KEY and LIVEKIT_API_SECRET must be set in .env"
  exit 1
fi

echo "Using LiveKit at: $LIVEKIT_URL"
echo ""

# ── Step 1: Create inbound SIP trunk ─────────────────────────────────────────
echo "==> Creating SIP inbound trunk from trunk.json ..."
TRUNK_OUTPUT=$(lk sip inbound create "$SCRIPT_DIR/trunk.json")
echo "$TRUNK_OUTPUT"
echo ""

# Extract trunk ID (works whether lk outputs JSON or plain text)
TRUNK_ID=$(echo "$TRUNK_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # lk may return the trunk object or a wrapper
    tid = data.get('sipTrunkId') or data.get('id') or ''
    print(tid)
except Exception:
    pass
" 2>/dev/null || true)

if [ -z "$TRUNK_ID" ]; then
  echo "Could not auto-extract trunk ID."
  echo -n "Please paste the sipTrunkId from the output above and press Enter: "
  read -r TRUNK_ID
fi

echo "Trunk ID: $TRUNK_ID"
echo ""

# ── Step 2: Create dispatch rule ──────────────────────────────────────────────
TMP=$(mktemp /tmp/dispatch-XXXX.json)
sed "s/REPLACE_WITH_TRUNK_ID/$TRUNK_ID/g" "$SCRIPT_DIR/dispatch.json" > "$TMP"

echo "==> Creating dispatch rule ..."
lk sip dispatch create "$TMP"
rm -f "$TMP"

echo ""
echo "Done! Incoming calls to your VoIP number will now create a 'call-*' room"
echo "and your agent worker will answer automatically."
