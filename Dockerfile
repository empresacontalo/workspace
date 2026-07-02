# =============================================================================
# Dockerfile — AI Dev Workspace (Debian XFCE + XRDP)
# =============================================================================

FROM debian:bookworm-slim

LABEL maintainer="Bruno <brunomiguel@outsourc-e.com>"
LABEL description="AI Dev Workspace — XFCE + XRDP + CLIs + Web UI"

ENV DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# 1. System Dependencies, XFCE, XRDP, and Python
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-goodies \
    xrdp \
    sudo \
    curl \
    wget \
    ca-certificates \
    gnupg \
    build-essential \
    jq \
    unzip \
    openssh-client \
    git \
    python3 \
    python3-pip \
    python3-venv \
    nano \
    && rm -rf /var/lib/apt/lists/*

# Configure XRDP to use XFCE
RUN echo xfce4-session > /etc/skel/.xsession \
    && cp /etc/skel/.xsession /root/.xsession

# Fix XRDP start bug in some Debian containers
RUN sed -i 's/test -x \/etc\/X11\/Xsession/test -x \/etc\/X11\/Xsession || true/' /etc/xrdp/startwm.sh

# ---------------------------------------------------------------------------
# 2. Node.js 22 & Bun & pnpm
# ---------------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g bun pnpm

# ---------------------------------------------------------------------------
# 3. CLI Tools Installation
# ---------------------------------------------------------------------------
# Some of these packages might not exist in the official NPM registry with these exact names.
# We append `|| true` to prevent the Docker build from failing if a package is not found.
RUN npm install -g \
    @anthropic-ai/claude-code@latest \
    copilot-cli \
    qwen-cli \
    @google/generative-ai-cli \
    gemini-cli \
    goose-cli \
    openclaw \
    augment-code \
    codebuddy \
    kimi-cli \
    opencode-ai@latest \
    factory-droid \
    @githubnext/github-copilot-cli \
    qoder \
    mistral-vibe \
    nanobot \
    aion-cli \
    snow-cli \
    cursor-cli \
    kiro \
    command-code@latest \
    antigravity@latest \
    || true

# ---------------------------------------------------------------------------
# 4. App 1: OmniRoute — AI Gateway (port 4000)
# ---------------------------------------------------------------------------
ARG OMNIROUTE_VERSION=main
RUN git clone --depth 1 --branch ${OMNIROUTE_VERSION} \
    https://github.com/diegosouzapw/OmniRoute.git /opt/omniroute
WORKDIR /opt/omniroute
RUN npm install --production 2>/dev/null || npm install
RUN npm run build

# ---------------------------------------------------------------------------
# 5. App 2: Hermes Workspace (port 3000)
# ---------------------------------------------------------------------------
ARG HERMES_VERSION=main
RUN git clone --depth 1 --branch ${HERMES_VERSION} \
    https://github.com/outsourc-e/hermes-workspace.git /opt/hermes-workspace
WORKDIR /opt/hermes-workspace
RUN pnpm install
RUN pnpm build

# ---------------------------------------------------------------------------
# 6. App 3: Aion UI (port 3005)
# ---------------------------------------------------------------------------
ARG AIONUI_VERSION=main
RUN git clone --depth 1 --branch ${AIONUI_VERSION} \
    https://github.com/iofficeai/aionui.git /opt/aionui
WORKDIR /opt/aionui
RUN jq 'del(.overrides["@codemirror/language"])' package.json > package.json.tmp \
    && mv package.json.tmp package.json
RUN bun install
RUN node scripts/prepareAioncore.js
RUN bun run package

# ---------------------------------------------------------------------------
# 7. App 4: Hermes Agent (port 8642 / 9119)
# ---------------------------------------------------------------------------
# We clone Hermes Agent and install its Python dependencies globally in a venv.
RUN git clone --depth 1 https://github.com/NousResearch/Hermes-Agent.git /opt/hermes-agent
WORKDIR /opt/hermes-agent
RUN python3 -m venv /opt/hermes/.venv \
    && /opt/hermes/.venv/bin/pip install --upgrade pip \
    && /opt/hermes/.venv/bin/pip install -r requirements.txt || true \
    && /opt/hermes/.venv/bin/pip install -e . || true
# Ensure hermes command is in PATH
ENV PATH="/opt/hermes/.venv/bin:${PATH}"

# ---------------------------------------------------------------------------
# 8. Entrypoint and Permissions
# ---------------------------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create the base workspace and data directories
RUN mkdir -p /workspace /data/omniroute /data/hermes-workspace /data/aionui /data/hermes
WORKDIR /workspace

# ---------------------------------------------------------------------------
# Expose Ports
# ---------------------------------------------------------------------------
# 3389 - XRDP (RDP Access)
# 8642 - hermes-agent gateway
# 9119 - hermes-agent dashboard
# 4000 - OmniRoute AI Gateway
# 3000 - Hermes Workspace UI
# 3005 - Aion UI
EXPOSE 3389 8642 9119 4000 3000 3005

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
CMD ["/entrypoint.sh"]
