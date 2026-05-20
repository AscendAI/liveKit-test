#!/bin/bash
# One-time SIP trunk + dispatch rule setup.
# Safe to re-run — reuses an existing trunk if one already exists.
#
# Prerequisites:
#   brew install livekit-cli      (Mac)
#   go install github.com/livekit/livekit-cli/cmd/lk@latest   (Linux)
#
# Usage:
#   bash sip-setup/setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

# Load only the three variables the lk CLI needs from .env
# (avoids sourcing the whole file, which breaks on unicode comment characters)
if [ -f "$ROOT_DIR/.env" ]; then
  LIVEKIT_URL=$(grep '^LIVEKIT_URL=' "$ROOT_DIR/.env" | cut -d= -f2-)
  LIVEKIT_API_KEY=$(grep '^LIVEKIT_API_KEY=' "$ROOT_DIR/.env" | cut -d= -f2-)
  LIVEKIT_API_SECRET=$(grep '^LIVEKIT_API_SECRET=' "$ROOT_DIR/.env" | cut -d= -f2-)
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

# ── Step 1: Reuse existing trunk or create a new one ─────────────────────────
EXISTING_TRUNK=$(lk sip inbound list 2>/dev/null | grep -oE 'ST_[A-Za-z0-9]+' | head -1 || true)

if [ -n "$EXISTING_TRUNK" ]; then
  echo "==> Found existing SIP trunk: $EXISTING_TRUNK — skipping creation."
  TRUNK_ID="$EXISTING_TRUNK"
else
  echo "==> Creating SIP inbound trunk from trunk.json ..."
  TRUNK_OUTPUT=$(lk sip inbound create "$SCRIPT_DIR/trunk.json")
  echo "$TRUNK_OUTPUT"
  TRUNK_ID=$(echo "$TRUNK_OUTPUT" | grep -oE 'ST_[A-Za-z0-9]+' | head -1)

  if [ -z "$TRUNK_ID" ]; then
    echo "Could not auto-extract trunk ID."
    echo -n "Please paste the sipTrunkId from the output above and press Enter: "
    read -r TRUNK_ID
  fi
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
