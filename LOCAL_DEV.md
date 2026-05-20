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
        │  SIP → YOUR-PROJECT-ID.sip.livekit.cloud  (project-specific URI)
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

## Step 1.5 — Find your project-specific SIP URI

**This is the most important step.** LiveKit Cloud gives every project a unique SIP endpoint. You must use this URI — the generic `sip:sip.livekit.cloud` does not work.

1. In your LiveKit Cloud project, go to **Telephony** in the left sidebar
2. Click **SIP trunks**
3. At the top of that page you will see your project SIP URI — it looks like:
   ```
   sip:4erbyiofrjv.sip.livekit.cloud
   ```
   (the prefix is your project ID, different for every project)
4. **Copy this URI exactly** — you will need it in Step 3.2

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
4. Under **Origination** → click **Add new Origination URI** and enter your project-specific URI from Step 1.5:
   ```
   sip:YOUR-PROJECT-ID.sip.livekit.cloud
   ```
   For example: `sip:4erbyiofrjv.sip.livekit.cloud`

   Leave priority and weight at defaults. Save.

5. Save the SIP trunk. No Credential List is needed — LiveKit authenticates calls by phone number.

### 3.3 — Assign your phone number to the trunk

1. Go to **Phone Numbers → Manage → Active Numbers**
2. Click your number
3. Under **Voice Configuration** → set **Configure With** to **SIP Trunk**
4. Select your `garibook-inbound` trunk
5. Save

---

## Step 4 — Register the SIP trunk with LiveKit Cloud

### 4.1 — Fill in your phone number

Open `sip-setup/trunk.json`. The file must list your Twilio phone number in E.164 format:

```json
{
  "trunk": {
    "name": "garibook-inbound",
    "numbers": ["+12088167436"]
  }
}
```

Replace `+12088167436` with the Twilio number you bought in Step 3.1.

The `numbers` field is how LiveKit authenticates inbound calls — it accepts calls from your number and rejects anything else.

### 4.2 — Load your credentials into the terminal

Run these three lines once so the `lk` CLI and the setup script can reach LiveKit Cloud:

```bash
export LIVEKIT_URL=$(grep '^LIVEKIT_URL=' .env | cut -d= -f2-)
export LIVEKIT_API_KEY=$(grep '^LIVEKIT_API_KEY=' .env | cut -d= -f2-)
export LIVEKIT_API_SECRET=$(grep '^LIVEKIT_API_SECRET=' .env | cut -d= -f2-)
```

You only need this when you open a new terminal. The setup script reads `.env` directly, so this step is only needed if you want to run `lk` commands manually.

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

If Cartesia TTS is giving a 402 error (billing), run with OpenAI TTS instead:

```bash
TTS_PROVIDER=openai uv run python livekit_basic_agent.py dev
```

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

1. **Twilio Origination URI** — must be your project-specific URI like `sip:4erbyiofrjv.sip.livekit.cloud` (NOT the generic `sip:sip.livekit.cloud`)
2. **Number assigned to trunk** — go to Phone Numbers → Active Numbers → your number → Voice Configuration must show your SIP trunk, not a webhook
3. **Dispatch rule exists** — run `lk sip dispatch list` and confirm there is one row

### LiveKit Calls tab shows no calls / call just rings forever

The most common cause is using the **wrong Origination URI** in Twilio. Every LiveKit Cloud project has a unique SIP endpoint. Go to your LiveKit Cloud project → **Telephony → SIP trunks** and copy the exact URI shown there (e.g. `sip:4erbyiofrjv.sip.livekit.cloud`). Update the Twilio trunk origination URI to match.

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

### Agent receives job but never answers the call

Make sure `await ctx.connect()` is at the top of the `entrypoint` function. Without it, the worker registers with LiveKit and receives the job but never joins the room, so the call just rings and times out.

### Cartesia TTS returns 402 Payment Required

Your Cartesia account has no credits. Either add credits at [play.cartesia.ai](https://play.cartesia.ai) or switch to OpenAI TTS:

```bash
TTS_PROVIDER=openai uv run python livekit_basic_agent.py dev
```

### lk CLI says "unauthorized"

Your environment variables are not exported. Run the three export lines from Step 4.2 again — they reset when you open a new terminal.

### .env sourcing fails in zsh with parse errors

Do not use `source .env` or `set -a; source .env; set +a` — `.env` files with Unicode characters in comments will break zsh. Use the grep-based extraction method shown in Step 4.2 instead.

---

## Switching between local dev and production server

The only differences between local dev and the self-hosted production setup are three `.env` values and the Twilio Origination URI:

| Setting | Local dev (LiveKit Cloud) | Production (self-hosted) |
|---|---|---|
| `LIVEKIT_URL` | `wss://your-project.livekit.cloud` | `ws://YOUR_SERVER_IP:7880` |
| `LIVEKIT_API_KEY` | LiveKit Cloud key | Your own generated key |
| `LIVEKIT_API_SECRET` | LiveKit Cloud secret | Your own generated secret |
| Twilio Origination URI | `sip:YOUR-PROJECT-ID.sip.livekit.cloud` | `sip:YOUR_SERVER_IP:5060` |
| How to start agent | `uv run python livekit_basic_agent.py dev` | `docker compose up -d` |

When you are ready to go live, follow [DEPLOYMENT.md](DEPLOYMENT.md), swap those four values, and re-run `bash sip-setup/setup.sh` pointing at your server.
