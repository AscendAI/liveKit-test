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

```bash
nano sip-setup/trunk.json
```

Replace the placeholders with the Twilio credential list username and password you created in Step 3.2:

```json
{
  "name": "garibook-inbound",
  "auth_username": "your-twilio-credential-username",
  "auth_password": "your-twilio-credential-password"
}
```

Save and close.

### 4.2 — Load your credentials into the terminal

The `setup.sh` script reads your `.env` file automatically, so you don't need to type credentials again. Just run these three lines once in your terminal so that manual `lk` commands (like `lk sip inbound list`) also work:

```bash
export LIVEKIT_URL=$(grep '^LIVEKIT_URL=' .env | cut -d= -f2-)
export LIVEKIT_API_KEY=$(grep '^LIVEKIT_API_KEY=' .env | cut -d= -f2-)
export LIVEKIT_API_SECRET=$(grep '^LIVEKIT_API_SECRET=' .env | cut -d= -f2-)
```

These pull the three values directly from `.env` without trying to parse the whole file.

### 4.3 — Run the setup script

```bash
bash sip-setup/setup.sh
```

You should see:

```
==> Creating SIP inbound trunk from trunk.json ...
{"sipTrunkId": "ST_xxxxxxxxxxxx", ...}
Trunk ID: ST_xxxxxxxxxxxx
==> Creating dispatch rule ...
Done! Incoming calls to your VoIP number will now create a 'call-*' room
and your agent worker will answer automatically.
```

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

In your terminal you should see the agent pick up:

```
[metrics] turn 1: +1823in (0 cached) / +42out tokens
[metrics] turn 2: +2100in (1823 cached) / +65out tokens
```

Arafat will greet the caller in Bangla and the conversation begins.

---

## Troubleshooting

### Agent starts but call never connects

Check that the dispatch rule was created and the trunk ID in it matches the inbound trunk:

```bash
lk sip inbound list
lk sip dispatch list
```

If dispatch list is empty, re-run `bash sip-setup/setup.sh`.

### Caller hears ringing but then silence / call drops

The Twilio Origination URI is wrong. Go back to **Elastic SIP Trunking → Trunks → your trunk → Origination** and confirm the URI is exactly:

```
sip:sip.livekit.cloud
```

No port number, no extra path.

### Agent log shows "authentication failed"

The `auth_username` or `auth_password` in `sip-setup/trunk.json` does not match what you created in Twilio's Credential List. Re-open the file, fix the values, and re-run the setup script:

```bash
# Delete the old trunk first
lk sip inbound list                          # copy the trunk ID
lk sip inbound delete ST_xxxxxxxxxxxx        # delete it

# Then re-run setup
bash sip-setup/setup.sh
```

### "Permission denied" or "unauthorized" from lk CLI

Your exported `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` are wrong or not exported. Double-check with:

```bash
echo $LIVEKIT_URL
echo $LIVEKIT_API_KEY
```

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
