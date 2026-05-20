# Local Development with Twilio VoIP

This guide lets you run the Garibook agent on your **local machine** and receive real phone calls through Twilio — no server, no ngrok, no port forwarding needed.

---

## Can you use ngrok?

**No — not for VoIP.** Here is why:

- ngrok tunnels **HTTP/TCP only**
- SIP signaling uses **UDP port 5060** — ngrok cannot forward UDP (except on expensive enterprise plans)
- RTP audio (the actual voice stream) uses **UDP ports 10000–20000** — ngrok fundamentally cannot do this
- Even if SIP signaling somehow worked, the audio would never arrive and the call would be silent

---

## The right approach: LiveKit Cloud as your SIP gateway

Instead of exposing your local machine to the internet, you use **LiveKit Cloud** as the public-facing SIP server. Your local agent connects *outbound* to LiveKit Cloud — no inbound ports are needed on your Mac at all.

```
Caller dials Twilio number
        │
        ▼
Twilio SIP Elastic Trunk
        │  SIP → sip.livekit.cloud  (LiveKit's public endpoint)
        ▼
LiveKit Cloud  (handles all public-facing SIP + WebRTC)
        │  dispatches job to any connected worker
        ▼
Your local agent  (connects outbound to LiveKit Cloud)
        │  Soniox STT → GPT-4.1-mini → Cartesia TTS (Bangla)
        ▼
Audio streams back  →  LiveKit Cloud  →  Twilio  →  caller's phone
```

Your Mac never needs a public IP. LiveKit Cloud is the only public-facing piece.

---

## What you need before starting

- A [LiveKit Cloud](https://cloud.livekit.io) account (free tier)
- A [Twilio](https://console.twilio.com) account with credits (~$5 minimum)
- All existing API keys already in your `.env` (Soniox, Cartesia, OpenAI)
- The LiveKit CLI installed: `brew install livekit-cli`

---

## Step 1 — Create a LiveKit Cloud project

1. Go to [cloud.livekit.io](https://cloud.livekit.io) and sign up or log in
2. Click **New Project** — give it any name (e.g. `garibook-dev`)
3. Go to **Settings → Keys**
4. Copy all three values:
   - **WebSocket URL** — looks like `wss://your-project-abc123.livekit.cloud`
   - **API Key** — looks like `APIxxxxxxxxxxxxxxxxx`
   - **API Secret** — a long random string

---

## Step 2 — Update your .env

Open `.env` and replace the `LIVEKIT_*` lines with your cloud credentials:

```bash
LIVEKIT_URL=wss://your-project-abc123.livekit.cloud
LIVEKIT_API_KEY=APIxxxxxxxxxxxxxxxxx
LIVEKIT_API_SECRET=your-cloud-api-secret
```

Leave all other keys (Soniox, Cartesia, OpenAI) as they are.

---

## Step 3 — Set up Twilio

### 3.1 — Buy a phone number

1. Go to [console.twilio.com](https://console.twilio.com)
2. Navigate to **Phone Numbers → Manage → Buy a Number**
3. Search for a number — pick any country/type you need
4. Click **Buy** and confirm

### 3.2 — Create a SIP Elastic Trunk

1. In the Twilio console go to **Elastic SIP Trunking → Trunks**
2. Click **Create new SIP Trunk**
3. Give it a name: `garibook-inbound`
4. Under **Origination** → click **Add new Origination URI** and enter:
   ```
   sip:sip.livekit.cloud
   ```
   Leave priority and weight at defaults. Save.

5. Under **Authentication → Credential Lists** → click **Create new Credential List**
   - Name it anything (e.g. `garibook-creds`)
   - Add a **username** and **password** — write these down, you will need them in Step 4
   - Save

6. Save the SIP trunk

### 3.3 — Assign your phone number to the trunk

1. Go to **Phone Numbers → Manage → Active Numbers**
2. Click your number
3. Under **Voice Configuration** → set **Configure With** to **SIP Trunk**
4. Select your `garibook-inbound` trunk
5. Save

---

## Step 4 — Register the SIP trunk with LiveKit Cloud

### 4.1 — Fill in your Twilio SIP credentials

Open `sip-setup/trunk.json`. The file must use this exact format (camelCase, wrapped in `"trunk"`):

```json
{
  "trunk": {
    "name": "garibook-inbound",
    "authUsername": "your-twilio-credential-username",
    "authPassword": "your-twilio-credential-password"
  }
}
```

Replace `authUsername` and `authPassword` with the values you created in Twilio's Credential List in Step 3.2.

### 4.2 — Load your credentials into the terminal

Run these three lines once so the `lk` CLI and the setup script can reach LiveKit Cloud:

```bash
export LIVEKIT_URL=$(grep '^LIVEKIT_URL=' .env | cut -d= -f2-)
export LIVEKIT_API_KEY=$(grep '^LIVEKIT_API_KEY=' .env | cut -d= -f2-)
export LIVEKIT_API_SECRET=$(grep '^LIVEKIT_API_SECRET=' .env | cut -d= -f2-)
```

### 4.3 — Run the setup script

```bash
bash sip-setup/setup.sh
```

Expected output:

```
Using LiveKit at: wss://your-project-abc123.livekit.cloud

==> Creating SIP inbound trunk from trunk.json ...
SIPTrunkID: ST_xxxxxxxxxxxx

Trunk ID: ST_xxxxxxxxxxxx

==> Creating dispatch rule ...
SIPDispatchRuleID: SDR_xxxxxxxxxxxx

Done! Incoming calls to your VoIP number will now create a 'call-*' room
and your agent worker will answer automatically.
```

If a trunk already exists from a previous run, the script will reuse it automatically instead of creating a duplicate.

### 4.4 — Verify

```bash
lk sip inbound list
lk sip dispatch list
```

Both should return one entry each.

---

## Step 5 — Run the agent locally

```bash
uv run python livekit_basic_agent.py dev
```

The `dev` command connects **outbound** to LiveKit Cloud and waits for incoming jobs. You will see:

```
Starting worker... connected to wss://your-project-abc123.livekit.cloud
```

Leave this terminal open.

---

## Step 6 — Test

Dial your Twilio number from any phone.

In your terminal you should see the agent pick up and process turns:

```
[metrics] turn 1: +1823in (0 cached) / +42out tokens
[metrics] turn 2: +2100in (1823 cached) / +65out tokens
```

Arafat will greet the caller in Bangla and the conversation begins.

---

## Troubleshooting

### Caller hears "incorrect number" or the call drops immediately

This means the call reached Twilio but couldn't reach LiveKit. Check all three:

1. **Twilio Origination URI** — must be exactly `sip:sip.livekit.cloud` (no port, no `wss://`)
2. **Number assigned to trunk** — go to Phone Numbers → Active Numbers → your number → Voice Configuration must show your SIP trunk, not a webhook
3. **Dispatch rule exists** — run `lk sip dispatch list` and confirm there is one row

### Dispatch list is empty

Create the dispatch rule manually:

```bash
lk sip dispatch create --trunks ST_xxxxxxxxxxxx --individual "call-"
```

Replace `ST_xxxxxxxxxxxx` with your trunk ID from `lk sip inbound list`.

### Agent starts but call never connects / no metrics appear

The dispatch rule trunk ID doesn't match your inbound trunk. Delete the dispatch rule and recreate it:

```bash
lk sip dispatch list                           # copy the SIPDispatchRuleID
lk sip dispatch delete SDR_xxxxxxxxxxxx        # delete it
lk sip dispatch create --trunks ST_xxxxxxxxxxxx --individual "call-"
```

### "Conflicting inbound SIP Trunks" error from setup.sh

A trunk already exists. The script handles this automatically by reusing it. If you see this error running commands manually, just skip trunk creation and go straight to dispatch rule creation.

### Agent log shows "authentication failed"

The `authUsername` or `authPassword` in `sip-setup/trunk.json` does not match the Twilio Credential List. Delete the old trunk and recreate:

```bash
lk sip inbound list                          # copy the SIPTrunkID
lk sip inbound delete ST_xxxxxxxxxxxx        # delete it
# Fix trunk.json, then:
bash sip-setup/setup.sh
```

### lk CLI says "unauthorized"

Your environment variables are not exported. Run the three export lines from Step 4.2 again — they reset when you open a new terminal.

---

## Switching between local dev and production server

The only differences between local dev and the self-hosted production setup are three `.env` values and the Twilio Origination URI:

| Setting | Local dev (LiveKit Cloud) | Production (self-hosted) |
|---|---|---|
| `LIVEKIT_URL` | `wss://your-project.livekit.cloud` | `ws://YOUR_SERVER_IP:7880` |
| `LIVEKIT_API_KEY` | LiveKit Cloud key | Your own generated key |
| `LIVEKIT_API_SECRET` | LiveKit Cloud secret | Your own generated secret |
| Twilio Origination URI | `sip:sip.livekit.cloud` | `sip:YOUR_SERVER_IP:5060` |
| How to start agent | `uv run python livekit_basic_agent.py dev` | `docker compose up -d` |

When you are ready to go live, follow [DEPLOYMENT.md](DEPLOYMENT.md), swap those four values, and re-run `bash sip-setup/setup.sh` pointing at your server.
