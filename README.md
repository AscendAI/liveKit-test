# LiveKit voice-agent demo

A minimal website where visitors click a button and have a **live voice conversation**
with an AI agent, backed by your self-hosted LiveKit server.

Two services:

| Service  | What it does                                                                 |
| -------- | ---------------------------------------------------------------------------- |
| `server` | Fastify app. Serves the static page (`public/`) and mints LiveKit tokens at `GET /token`. |
| `agent`  | Node/TS worker (`@livekit/agents`). Joins rooms and runs the voice pipeline. |

```
Browser ──GET /token──► server ──signs JWT──► (returns token + serverUrl)
   └── room.connect() ──► LiveKit server (VPS) ◄── agent worker (dispatched into room)
                                                    STT (Deepgram) → LLM (OpenAI) → TTS (Cartesia)
```

## Prerequisites

- A running LiveKit server reachable over **`wss://` with valid TLS** (browsers reject plain `ws://` from an `https://` page).
- API key/secret matching your server's `livekit.yaml` `keys:` (or LiveKit Cloud credentials).
- API keys for: **Deepgram** (STT), **OpenAI** (LLM), **Cartesia** (TTS).

## Local development

```bash
cp .env.example .env        # fill in all values
```

The agent reads `LIVEKIT_URL` / `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` from the
environment. Export your `.env` into the shell for local runs, e.g. `set -a; source .env; set +a`.

In two terminals:

```bash
# terminal 1 — web server (http://localhost:3000)
cd server && npm install && npm run dev

# terminal 2 — agent worker
cd agent && npm install && npm run dev
```

Open <http://localhost:3000>, click **Start call**, allow the microphone, and the agent
should greet you. The first agent run downloads the Silero VAD model.

## Deploy to Coolify

1. Push this repo to Git and create a Coolify resource from `docker-compose.yml`.
2. Set the env vars (from `.env.example`) in Coolify.
3. Attach your domain (with TLS) to the **`server`** service. The `agent` needs no public port.
4. Deploy, open the domain, and run the voice test again.

## Swapping providers

Each pipeline stage is one plugin in [agent/src/agent.ts](agent/src/agent.ts):

- **STT** — `new deepgram.STT({ model: 'nova-3' })`
- **LLM** — `new openai.LLM({ model: 'gpt-4o-mini' })`
- **TTS** — `new cartesia.TTS()`

Replace any one with another `@livekit/agents-plugin-*` (e.g. ElevenLabs for TTS, Anthropic
for LLM) and update the matching API key.

## Customizing the agent

Edit the `instructions` in [agent/src/agent.ts](agent/src/agent.ts) to change the agent's
persona and behavior.
