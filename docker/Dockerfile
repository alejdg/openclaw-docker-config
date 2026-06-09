###############################################################################
# OpenClaw Gateway – Docker Image
#
# IMPORTANT: Runtime installs are lost on container restart. All binaries
# needed by skills MUST be installed here at build time. If you add a skill
# that needs a new binary, update this Dockerfile and rebuild.
###############################################################################

FROM node:22-bookworm-slim

# Install system dependencies as root.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    chromium \
    ca-certificates \
    tini \
    tar \
    jq \
    python3 \
    build-essential \
  && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI (required by github skill).
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && rm -f /etc/apt/sources.list.d/github-cli.list /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && rm -rf /var/lib/apt/lists/*

# Copy skills manifest, workspace templates, and entrypoint.
COPY config/skills-manifest.txt /opt/config/skills-manifest.txt
COPY workspace-templates/ /opt/workspace-templates/
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

# Install Gog CLI (required by gog skill).
ARG GOGCLI_VERSION=v0.12.0
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) gog_arch="amd64" ;; \
      arm64) gog_arch="arm64" ;; \
      *) echo "Unsupported architecture: $arch"; exit 1 ;; \
    esac; \
    version_no_v="${GOGCLI_VERSION#v}"; \
    asset="gogcli_${version_no_v}_linux_${gog_arch}.tar.gz"; \
    base_url="https://github.com/steipete/gogcli/releases/download/${GOGCLI_VERSION}"; \
    curl -fsSL -o /tmp/gogcli.tar.gz "${base_url}/${asset}"; \
    curl -fsSL -o /tmp/checksums.txt "${base_url}/checksums.txt"; \
    expected_sha256="$(awk -v asset="$asset" '$2 == asset {print $1}' /tmp/checksums.txt)"; \
    test -n "$expected_sha256"; \
    echo "$expected_sha256  /tmp/gogcli.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/gogcli.tar.gz -C /tmp gog; \
    install -m 0755 /tmp/gog /usr/local/bin/gog; \
    rm -f /tmp/gogcli.tar.gz /tmp/checksums.txt /tmp/gog; \
    gog --version


# @clawhub/cli is needed to manage skills and workspaces from the command line.
# bun is used to install QMD (memory).
# @mariozechner/pi-coding-agent is a dependency of the pi-coding-agent skill.
# @google/gemini-cli is needed for Gemini-based skills.
# grammy is needed for Telegram plugin.
RUN npm install -g clawhub bun @mariozechner/pi-coding-agent @google/gemini-cli grammy @tobilu/qmd

USER node
WORKDIR /home/node
# Install  @doist/todoist-ai and @doist/todoist-sdk are needed for the todoist-ai-tools plugin.\
RUN npm install @doist/todoist-ai @doist/todoist-sdk

# Pin OpenClaw version for reproducible builds.
USER root
ARG OPENCLAW_VERSION=2026.6.5
RUN npm install -g openclaw@${OPENCLAW_VERSION}

# Create OpenClaw directories owned by node.
RUN mkdir -p /home/node/.openclaw/workspace /.clawhub \
  && chown -R node:node /home/node/.openclaw /.clawhub

USER node

ENTRYPOINT ["tini", "--", "entrypoint.sh"]
