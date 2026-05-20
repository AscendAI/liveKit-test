# Production Deployment Guide

This guide walks you through deploying the Garibook voice agent (Arafat) on a live Linux server with a real phone number that callers can dial.

## What you'll need before starting

- A Linux VPS (Ubuntu 22.04 recommended) — DigitalOcean, Hetzner, AWS EC2, etc.
- A **public IPv4 address** on that server (all providers give you one)
- A **VoIP provider account** — this guide uses [Telnyx](https://telnyx.com) (recommended) or Twilio
- All API keys: OpenAI, Soniox, Cartesia

---

## Part 1 — Provision the Server

### Minimum server specs

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 vCPU | 4 vCPU |
| RAM | 4 GB | 8 GB |
| Disk | 20 GB SSD | 40 GB SSD |
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |

> **Important:** You must be on a **dedicated/cloud VPS**, not shared hosting. VoIP requires direct UDP port access.

---

## Part 2 — Initial Server Setup

SSH into your server as root (or a sudo user):

```bash
ssh root@YOUR_SERVER_IP
```

### 2.1 — Update the system

```bash
apt update && apt upgrade -y
apt install -y git curl jq python3
```

### 2.2 — Install Docker

```bash
curl -fsSL https://get.docker.com | sh
# Verify it worked
docker --version
# Should print: Docker version 27.x.x or similar
```

### 2.3 — Install the LiveKit CLI

```bash
curl -sSL https://get.livekit.io/cli | bash
# Verify
lk --version
```

### 2.4 — Open firewall ports

These ports must be open for the stack to work. Run all of these:

```bash
ufw allow 22/tcp        # SSH — do this first or you'll lock yourself out
ufw allow 7880/tcp      # LiveKit API / WebSocket
ufw allow 7881/tcp      # LiveKit WebRTC TCP fallback
ufw allow 5060/udp      # SIP signaling
ufw allow 5060/tcp      # SIP signaling (TCP)
ufw allow 10000:20000/udp   # RTP media (phone audio)
ufw allow 50000:60000/udp   # WebRTC media
ufw --force enable
ufw status
```

> If you are on AWS: also open these same ports in your **EC2 Security Group** (inbound rules) from the AWS console. UFW alone is not enough on AWS.

---

## Part 3 — Deploy the Code

### 3.1 — Upload the project

**Option A — Git (if repo is on GitHub/GitLab):**
```bash
git clone https://github.com/YOUR_ORG/YOUR_REPO.git /opt/garibook
cd /opt/garibook/live-kit
```

**Option B — Copy from your local machine:**
```bash
# Run this on your LOCAL Mac (not the server):
rsync -avz \
  --exclude='.venv' \
  --exclude='__pycache__' \
  --exclude='.git' \
  "/Users/abrar/Office/Ascend ai/Agent/unibox-family/live-kit/" \
  root@YOUR_SERVER_IP:/opt/garibook/
```

Then on the server:
```bash
cd /opt/garibook
```

---

## Part 4 — Configure Environment Variables

### 4.1 — Create your .env file

```bash
cp .env.example .env
nano .env
```

Fill in every value. Here is what each one means:

```bash
# ── LiveKit ────────────────────────────────────────────────────────────────
# For the lk CLI and external connections — use your server's public IP
LIVEKIT_URL=ws://YOUR_SERVER_IP:7880

# Make these up yourself — any random string works, e.g.:
#   openssl rand -hex 16
LIVEKIT_API_KEY=your-random-api-key
LIVEKIT_API_SECRET=your-random-api-secret-longer-is-better

# ── AI providers ───────────────────────────────────────────────────────────
OPENAI_API_KEY=sk-...
SONIOX_API_KEY=...
CARTESIA_API_KEY=...

# ── Cartesia (Bangla voice) ────────────────────────────────────────────────
CARTESIA_MODEL=sonic-3
CARTESIA_VOICE=2ba861ea-7cdc-43d1-8608-4045b5a41de5
CARTESIA_LANG=bn       # bn = Bangla

# ── LLM ───────────────────────────────────────────────────────────────────
LLM_CHOICE=gpt-4.1-mini

# ── Background noise ──────────────────────────────────────────────────────
BG_NOISE_WAV=freesound_community-office-ambience-24734.mp3
```

Save and close (`Ctrl+X`, `Y`, `Enter` in nano).

### 4.2 — Generate secure API key/secret (if you haven't yet)

```bash
echo "API Key:    $(openssl rand -hex 16)"
echo "API Secret: $(openssl rand -hex 32)"
```

Copy those values into your `.env` for `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET`.

---

## Part 5 — Get a Phone Number (VoIP Provider)

### Using Telnyx (recommended)

1. Go to [telnyx.com](https://telnyx.com) and create an account
2. Add credits (minimum $10)
3. Go to **Numbers → Search & Buy** — search for a number in your target country
   - For a Bangladesh-reachable number, buy a US toll-free (+1 800) or a BD number if available
4. Go to **Voice → SIP Trunks → Create SIP Trunk**
   - Name it: `garibook-inbound`
   - Under **Origination** → add an origination URI:
     ```
     sip:YOUR_SERVER_IP:5060
     ```
   - Under **Credentials** → create a username and password (you'll use these next)
   - Save the SIP trunk
5. Go back to your phone number → assign it to this SIP trunk

### Using Twilio (alternative)

1. Buy a phone number in Twilio Console
2. Go to **Elastic SIP Trunking → Trunks → Create**
3. Under **Origination** → add:
   ```
   sip:YOUR_SERVER_IP:5060
   ```
4. Under **Credential Lists** → create a username/password
5. Assign the phone number to this trunk

---

## Part 6 — Start the Stack

### 6.1 — Build and start all containers

```bash
cd /opt/garibook
docker compose up -d --build
```

This starts three containers:
- `garibook-livekit-1` — the LiveKit WebRTC server
- `garibook-livekit-sip-1` — the SIP bridge
- `garibook-agent-1` — your Arafat voice agent

### 6.2 — Verify all containers are running

```bash
docker compose ps
```

Expected output — all three should show `Up`:
```
NAME                      STATUS
garibook-livekit-1        Up 30 seconds
garibook-livekit-sip-1    Up 28 seconds
garibook-agent-1          Up 25 seconds
```

### 6.3 — Check for errors

```bash
# Check LiveKit server
docker compose logs livekit --tail=20

# Check SIP bridge
docker compose logs livekit-sip --tail=20

# Check agent worker
docker compose logs agent --tail=30
```

The agent log should end with something like:
```
Starting worker... connected to LiveKit at ws://livekit:7880
```

---

## Part 7 — Register the SIP Trunk with LiveKit

This is a one-time setup that tells LiveKit how to handle incoming calls.

### 7.1 — Fill in your VoIP credentials

```bash
nano sip-setup/trunk.json
```

Replace the placeholders with the SIP username and password you created in Telnyx/Twilio:

```json
{
  "name": "garibook-inbound",
  "auth_username": "your-telnyx-sip-username",
  "auth_password": "your-telnyx-sip-password"
}
```

Save and close.

### 7.2 — Run the setup script

```bash
# Export credentials so the lk CLI can reach your LiveKit server
export LIVEKIT_URL=ws://localhost:7880
export LIVEKIT_API_KEY=$(grep LIVEKIT_API_KEY .env | cut -d= -f2)
export LIVEKIT_API_SECRET=$(grep LIVEKIT_API_SECRET .env | cut -d= -f2)

bash sip-setup/setup.sh
```

If the script runs successfully you will see:
```
==> Creating SIP inbound trunk from trunk.json ...
{"sipTrunkId": "ST_xxxxxxxxxxxx", ...}
Trunk ID: ST_xxxxxxxxxxxx
==> Creating dispatch rule ...
Done! Incoming calls to your VoIP number will now create a 'call-*' room
and your agent worker will answer automatically.
```

---

## Part 8 — Test the Setup

### 8.1 — Verify SIP trunk is registered

```bash
export LIVEKIT_URL=ws://localhost:7880
export LIVEKIT_API_KEY=$(grep LIVEKIT_API_KEY .env | cut -d= -f2)
export LIVEKIT_API_SECRET=$(grep LIVEKIT_API_SECRET .env | cut -d= -f2)

lk sip inbound list
lk sip dispatch list
```

Both should show one entry each.

### 8.2 — Make a test call

Dial your VoIP number from any phone.

Watch the agent logs in real time:

```bash
docker compose logs agent -f
```

You should see the agent pick up, generate a reply, and start the conversation. Logs look like:

```
[metrics] turn 1: +1823in (0 cached) / +42out tokens
[metrics] turn 2: +2100in (1823 cached) / +65out tokens
```

---

## Part 9 — Keep It Running (Production Hardening)

### 9.1 — Auto-restart on server reboot

Docker Compose with `restart: unless-stopped` already handles container restarts. To also start Docker on boot:

```bash
systemctl enable docker
```

### 9.2 — View logs anytime

```bash
# All containers
docker compose logs -f

# Just the agent
docker compose logs agent -f

# Check metrics
tail -f metrics.jsonl | python3 -m json.tool
```

### 9.3 — Update the agent code

```bash
# Pull latest code (if using git)
git pull

# Rebuild and restart only the agent container (LiveKit + SIP stay up)
docker compose up -d --build agent
```

### 9.4 — Stop everything

```bash
docker compose down
```

---

## Troubleshooting

### Calls ring but agent doesn't answer

```bash
docker compose logs agent --tail=50
```

Most likely cause: the agent crashed on startup. Check for missing API keys in `.env`.

### Caller hears silence / call drops immediately

```bash
docker compose logs livekit-sip --tail=50
```

Most likely cause: RTP ports 10000–20000 are blocked by the firewall. Re-run the UFW commands from Part 2.4.

### SIP trunk setup script fails with "connection refused"

LiveKit isn't running or the API key/secret is wrong. Verify:

```bash
curl http://localhost:7880          # should return 200
docker compose ps                   # livekit should show "Up"
```

### "LIVEKIT_KEYS" error in livekit logs

The `LIVEKIT_API_KEY` or `LIVEKIT_API_SECRET` in your `.env` has a space or special character. Wrap the value in quotes in `.env`:

```bash
LIVEKIT_API_KEY="your-key"
LIVEKIT_API_SECRET="your-secret"
```

### Audio quality is poor on phone

Phone calls are compressed to 8 kHz. This is normal for SIP/PSTN. The agent's Cartesia TTS output is resampled automatically by LiveKit SIP — no code change needed.

### Mac/Windows Docker — SIP bridge can't reach LiveKit

The `network_mode: host` setting only works on Linux. On Mac/Windows, edit `docker-compose.yml` — replace the `livekit-sip` service's `network_mode: host` block with:

```yaml
livekit-sip:
  image: livekit/sip:latest
  ports:
    - "5060:5060/udp"
    - "5060:5060/tcp"
    - "10000-20000:10000-20000/udp"
```

And in `sip.yaml`, change `ws_url` to:

```yaml
ws_url: ws://host.docker.internal:7880
```

---

## Quick Reference — Key Commands

```bash
# Start everything
docker compose up -d --build

# Stop everything
docker compose down

# Live agent logs
docker compose logs agent -f

# Restart just the agent (after code change)
docker compose up -d --build agent

# List SIP trunks
lk sip inbound list

# List dispatch rules
lk sip dispatch list

# Re-run SIP setup (if you need to redo it)
bash sip-setup/setup.sh
```

---

## Architecture Summary

```
Caller dials phone number
        │
        ▼
VoIP Provider (Telnyx/Twilio)
        │  SIP INVITE → port 5060
        ▼
LiveKit SIP Bridge  (livekit/sip container)
        │  creates room "call-xxxx"
        ▼
LiveKit Server  (livekit/livekit-server container, port 7880)
        │  dispatches job to worker
        ▼
Arafat Agent  (your Python container)
        │  Soniox STT → GPT-4.1-mini → Cartesia TTS (Bangla)
        ▼
Audio streams back through LiveKit SIP → Telnyx → caller's phone
```
