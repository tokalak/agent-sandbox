# Sandbox image for running coding agents (claude-code, command-code, pi.dev)
# with full file-edit permission against a bind-mounted project directory,
# without ever running as root inside the container.
FROM node:22-bookworm-slim

ARG HOST_UID=1000
ARG HOST_GID=1000

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash git curl ca-certificates ripgrep jq less procps openssh-client unzip vim \
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

RUN npm install -g \
      @anthropic-ai/claude-code \
      command-code@latest \
      opencode-ai \
      @earendil-works/pi-coding-agent \
    && npm cache clean --force

USER agent
WORKDIR /workspace
ENV HOME=/home/agent

CMD ["bash"]
