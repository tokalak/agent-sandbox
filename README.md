# Agent Sandbox

## What problem does this solve?

AI coding assistants like Claude Code, Command Code, opencode and Pi are
most useful
when they can work with full permissions — read, write, delete files and run
commands — without asking for approval at every step.

Granting that much freedom directly on your machine is risky: a bug, a bad
suggestion, or a careless command could touch files far outside the project
you're working on.

This tool runs the assistants inside a Docker container instead:

- Only the current project directory is bind-mounted (read-write at
  `/workspace`). Nothing else on the host is visible to the container.
- The container runs as an unprivileged user with all Linux capabilities
  dropped and `no-new-privileges` set.
- The container is ephemeral (`--rm`): on exit it's removed entirely. Only
  the changes to your project directory persist.

In short: the assistant works freely, but only inside a locked room
containing the one project you handed it.

## Prerequisites

- Docker installed and running, e.g. [Docker Desktop](https://www.docker.com/products/docker-desktop/).
- Your projects live under `~/Projects` (i.e. `~/Projects/your-project`).
  The script refuses to run anywhere else — see "Safety rails" below. If
  your projects live elsewhere, adjust `PROJECTS_ROOT` in the script.
- You've logged into Claude Code, Command Code, opencode and/or Pi at least
  once on the host, so the sandbox can reuse those credentials (see "How
  your logins and configuration are handled"). Alternatively, log in from
  inside the container, e.g. via the `/login` command of the respective
  agent.

## Setup (one-time)

1. Clone or copy this folder somewhere permanent, e.g.
   `~/Projects/agent-sandbox`.
2. Symlink the script into a directory on your `PATH`:
   ```
   ln -s ~/Projects/agent-sandbox/agent-sandbox ~/.local/bin/agent-sandbox
   ```
3. Done — no manual build step. On first run the script builds the image
   automatically (takes a few minutes); subsequent runs start instantly.

## How the shell finds the `agent-sandbox` command

The symlink from setup step 2 lives in `~/.local/bin`, which is on your
`PATH`, and points to the actual script in this repo. The script resolves
its own real location through the symlink, so it always finds the
`Dockerfile` next to it.

Note: if you move this folder later, the symlink breaks — delete it and
create a new one pointing at the new location.

## Usage

1. `cd` into the project you want to work on, e.g. `cd ~/Projects/my-website`.
2. Run `agent-sandbox <agent>` to start an agent directly:
   ```
   agent-sandbox claude      # start Claude Code
   agent-sandbox cmd         # start Command Code (alias: commandcode)
   agent-sandbox opencode    # start opencode
   agent-sandbox pi          # start Pi
   ```
   The agent's configuration and credentials from your host are copied into
   the container, and the agent starts in `/workspace` **with full
   permissions** — no approval prompts, the container is the safety
   boundary (this is the whole point of the project). Concretely: `claude`
   and `commandcode` get `--dangerously-skip-permissions`, `opencode` gets
   `--auto`, and `pi` already runs with full permissions by default.
   Anything after the agent name is passed through to it, e.g.
   `agent-sandbox claude --continue`.
3. Or run plain `agent-sandbox` to get a shell inside the container
   (already in `/workspace`, with the configuration of all agents copied
   in) and start `claude`, `commandcode`, `opencode`, or `pi` yourself —
   started manually like this, they use their normal permission prompts.
4. Exit the agent (or type `exit` in the shell) when done. The container is
   removed automatically; only the changes to your project files remain.

Multiple sandboxes for the same project can run in parallel — each gets its
own container, named after the project folder (`my-website`, `my-website-2`,
`my-website-3`, ...).

## How your logins and configuration are handled

Instead of requiring a fresh login inside the container, the script stages
**copies** of your existing credentials and configuration (Claude Code,
Command Code, opencode, Pi) into a temporary directory, mounts it read-only
at `/agent-config`, and copies it into the container's home on startup. The
assistants work with their own writable copies — token refreshes and
settings changes work normally — while the host originals are never exposed
to the container. The copies vanish with the container, and the staging
directory is deleted (credentials shredded where possible) when the script
exits.

For Claude Code this includes `~/.claude/settings.json`, `CLAUDE.md`, your
`commands`/`agents`/`skills` directories, and `~/.claude.json` — with the
per-project history of your other projects stripped out (requires `jq` on
the host), so only the mounted project is visible to the agent.

On macOS, Claude Code stores its credentials in the login Keychain rather
than in a file, so the script exports them into the staged copy (mode 600)
for the duration of the session.

If an assistant isn't logged in on the host, it's simply unavailable in the
container until you log in from inside it — that login is discarded with
the container.

## Passing API keys and other environment variables

Nothing from your environment is forwarded into the container by default —
notably, a `.env` file in the project is **not** read automatically, since
that would silently hand every secret in it to the assistant.

If the assistant needs specific variables (an API key, a database URL),
whitelist them by name in `AGENT_SANDBOX_ENV`:

```
export OPENAI_API_KEY=sk-...
AGENT_SANDBOX_ENV="OPENAI_API_KEY DATABASE_URL" agent-sandbox
```

Only the listed names are forwarded; their values are read by Docker
directly from your environment, so they never appear on a command line or
in shell history.

## Safety rails built in

- **Only the current project directory is mounted** — never your home
  directory or anything else on the host.
- **The script refuses to run outside `~/Projects`.** This guards against
  accidentally mounting a sensitive directory like `$HOME`, Desktop, or
  Documents.
- **The container runs as a non-root user** whose UID/GID match yours, so
  files created inside the container are owned by you on the host — no
  root-owned leftovers.
- **`.git/config` and `.git/hooks` are mounted read-only.** Git hooks and
  config settings like `core.fsmonitor` execute commands on the *host* the
  next time you run git there — a way for a misbehaving agent to reach
  outside the sandbox after the fact. With these paths read-only, the agent
  can still use git normally (status, diff, log, local commits) but cannot
  plant hooks or reconfigure the repo.
- **No environment variables are forwarded implicitly.** Secrets reach the
  container only if you explicitly list their names in `AGENT_SANDBOX_ENV`.
- **Agent configs are copied, never mounted.** The container only ever sees
  disposable copies of your credentials and settings; the host originals
  cannot be modified or deleted from inside.
- **Nothing persists after exit.** The container is removed (`--rm`), and
  the staged credential copies are shredded/deleted.

## Optional host-side hardening

Independent of this tool, you can tell git on your host to ignore
repo-local hooks entirely, so hooks planted by *anything* (not just a
sandboxed agent) never run:

```
mkdir -p ~/.githooks
git config --global core.hooksPath ~/.githooks
```

Git then only runs hooks from that (empty) directory. Note this disables
legitimate repo-local hooks too (e.g. husky or pre-commit setups) — if you
rely on those in some repos, re-enable per repo with
`git config core.hooksPath .git/hooks`.

## Updating

After editing the `Dockerfile` (e.g. to add another tool), rebuild the
image once:
```
agent-sandbox --rebuild
```
Subsequent runs use the updated image automatically.
