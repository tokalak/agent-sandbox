# Sandbox image for running coding agents (claude-code, command-code, pi.dev)
# with full file-edit permission against a bind-mounted project directory,
# without ever running as root inside the container.
FROM node:22-bookworm-slim

ARG HOST_UID=1000
ARG HOST_GID=1000

# chromium: lets agents verify their own work (load the app they built,
# screenshot it, click through it) via agent-browser. The Debian package
# pulls in all required system libraries and works on arm64, where Chrome
# for Testing (agent-browser's own download) is unavailable.
# fonts-liberation: without it headless screenshots render tofu boxes.
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash git curl ca-certificates ripgrep jq less procps openssh-client unzip vim \
      chromium fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root "agent" user whose UID/GID match the host caller's, so
# files the agents create in the bind-mounted project dir come out owned by
# the host user instead of root. HOST_GID commonly collides with a
# pre-existing Debian system group (e.g. GID 20 = "dialout", the macOS
# "staff" GID), and HOST_UID can likewise collide with an existing system
# user, so rename in place rather than assuming groupadd/useradd will succeed.
RUN set -eux; \
    if getent group "$HOST_GID" > /dev/null 2>&1; then \
        groupmod -n agent "$(getent group "$HOST_GID" | cut -d: -f1)"; \
    else \
        groupadd -g "$HOST_GID" agent; \
    fi; \
    if getent passwd "$HOST_UID" > /dev/null 2>&1; then \
        usermod -l agent -d /home/agent -m -g "$HOST_GID" "$(getent passwd "$HOST_UID" | cut -d: -f1)"; \
    else \
        useradd -u "$HOST_UID" -g "$HOST_GID" -m -s /bin/bash agent; \
    fi

# "@latest" resolves at build time, so Docker would reuse this cached layer
# on rebuilds and pin the agents to their build-day versions forever.
# AGENTS_BUILD_ID changes on every --rebuild, busting the cache for this
# layer only (the apt layer above stays cached).
ARG AGENTS_BUILD_ID=0
RUN echo "Installing coding agents (build $AGENTS_BUILD_ID)" \
    && npm install -g \
      @anthropic-ai/claude-code \
      command-code@latest \
      opencode-ai \
      @earendil-works/pi-coding-agent \
      agent-browser \
    && npm cache clean --force

USER agent
WORKDIR /workspace
ENV HOME=/home/agent

# Point agent-browser at the system Chromium (its own Chrome-for-Testing
# download has no Linux arm64 build and would need --with-deps as root).
# --no-sandbox: Chrome's in-process sandbox needs capabilities/userns that
# this image deliberately drops; the container itself is the sandbox.
# --disable-dev-shm-usage: Docker's default /dev/shm is 64MB, too small
# for Chromium renderers.
ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium \
    AGENT_BROWSER_ARGS="--no-sandbox,--disable-dev-shm-usage"

CMD ["bash"]
