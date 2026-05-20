FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for audio processing (pydub/ffmpeg)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Install uv
RUN pip install uv

# Copy dependency files first for layer caching
COPY pyproject.toml uv.lock ./

# Install dependencies
RUN uv sync --frozen --no-dev

# Pre-download Silero VAD model to avoid cold-start delay
RUN uv run python -c "from livekit.plugins import silero; silero.VAD.load()"

# Copy application code
COPY livekit_basic_agent.py ./
COPY freesound_community-office-ambience-24734.mp3 ./

CMD ["uv", "run", "python", "livekit_basic_agent.py", "start"]
