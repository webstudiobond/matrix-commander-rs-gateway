# matrix-commander-rs-gateway

## Containerised Matrix Gateway via SSH Tunnel

[![CI](https://github.com/webstudiobond/matrix-commander-rs-gateway/actions/workflows/ci.yml/badge.svg)](https://github.com/webstudiobond/matrix-commander-rs-gateway/actions/workflows/ci.yml)

A minimal, hardened Docker container running [matrix-commander-rs](https://github.com/8go/matrix-commander-rs) behind an SSH reverse tunnel. Designed to serve as a secure Matrix protocol gateway — in this project specifically used to manage an [OpenWrt-based router](https://github.com/webstudiobond/matrix-bot-openwrt) via a Matrix bot, though the container is general-purpose and can back any matrix-commander-rs workflow.

The container exposes port `2222` bound exclusively to `localhost`, acting as the inbound endpoint for an SSH reverse tunnel originating from a remote client (e.g. a router, an IoT device, or any SSH-capable host).

> **Upstream project:** [https://github.com/8go/matrix-commander-rs](https://github.com/8go/matrix-commander-rs)
> matrix-commander-rs is authored by [8go](https://github.com/8go) and its contributors. This repository provides only the containerisation layer.

---

## Architecture
```
[Remote client — e.g. OpenWrt router]
    |
    | SSH reverse tunnel  (-R 2222:localhost:2222)
    v
[Host: 127.0.0.1:2222]
    |
    | Docker port mapping
    v
[matrix-bot container :2222]
    |
    | sshd — PubkeyAuthentication only, UsePAM=no
    v
[matrix-commander-rs session]
```

The container does not bind to any public interface. All external access is funnelled exclusively through the authenticated SSH tunnel established by the remote client.

---

## Related Projects

- [matrix-bot-openwrt](https://github.com/webstudiobond/matrix-bot-openwrt) — A lightweight, POSIX shell–based Matrix bot for remote router management over the Matrix protocol.

---

## Security Posture

| Control | Status |
|---|---|
| Runs as UID 10001 (non-root) | ✅ |
| `no-new-privileges` | ✅ |
| All Linux capabilities dropped | ✅ |
| Read-only root filesystem | ✅ |
| `/run` and `/tmp` as `noexec`/`nosuid` tmpfs | ✅ |
| PAM disabled (`UsePAM=no`) | ✅ |
| SSH password authentication disabled | ✅ |
| SSH root login disabled | ✅ |
| SSH `MaxAuthTries 3`, `LoginGraceTime 20` | ✅ |
| SSH X11 forwarding, PermitTunnel, GatewayPorts disabled | ✅ |
| Port bound to `127.0.0.1` only | ✅ |
| Multi-arch binary (`amd64` / `arm64`) | ✅ |
| Docker healthcheck | ✅ |

> **Note on `UsePAM=no`:** sshd invokes the PAM helper `unix_chkpwd` (a setuid binary) even when password authentication is disabled. This conflicts with `no-new-privileges:true`. Since PAM provides no value in a pubkey-only, single-user container, it is explicitly disabled, which resolves the conflict without sacrificing any meaningful security control.

---

## Requirements

- Docker Engine ≥ 24.0 with BuildKit enabled
- Docker Compose v2
- Host architecture: `amd64` or `arm64`

---

## Directory Structure
```
.
├── Dockerfile
├── docker-compose.yaml
├── entrypoint.sh
├── authorized_keys        # Remote client's SSH public key
├── bot_data/              # Matrix session persistence
└── host_keys/             # SSH host key persistence
```

---

## Setup

> All paths below use `/home/user/matrix-commander-rs/` as an example. Replace `user` and the directory name with your actual username and preferred path.

### 1. Clone the repository
```bash
git clone git@github.com:webstudiobond/matrix-commander-rs-gateway.git /home/user/matrix-commander-rs
cd /home/user/matrix-commander-rs
```

### 2. Create host directories and set ownership

The container runs exclusively as **UID/GID 10001**. All read-write volume mount points on the host must be owned by that UID, or sshd's `StrictModes` check will refuse to start.
```bash
mkdir -p /home/user/matrix-commander-rs/bot_data \
         /home/user/matrix-commander-rs/host_keys

sudo chown -R 10001:10001 /home/user/matrix-commander-rs/bot_data \
                          /home/user/matrix-commander-rs/host_keys
```

### 3. Install the remote client's public key

Place the **public key of the host** that will establish the reverse SSH tunnel:
```bash
cat /path/to/client_id_ed25519.pub > /home/user/matrix-commander-rs/authorized_keys
sudo chown 10001:10001 /home/user/matrix-commander-rs/authorized_keys
chmod 0600 /home/user/matrix-commander-rs/authorized_keys
```

### 4. Build the image
```bash
docker compose -f /home/user/matrix-commander-rs/docker-compose.yaml build --no-cache
```

### 5. Initial Matrix session login

On first run, `matrix-commander-rs` requires interactive login to create its session database. Start the container and open a shell inside it:
```bash
docker compose -f /home/user/matrix-commander-rs/docker-compose.yaml up -d

docker compose -f /home/user/matrix-commander-rs/docker-compose.yaml exec -it matrix-bot /bin/bash
```

Inside the container ([full CLI reference](https://github.com/8go/matrix-commander-rs?tab=readme-ov-file#usage)):
```bash
# Before running this command:
# 1. Create a dedicated Matrix account for the bot on your homeserver.
#    Do NOT use your personal account — the bot account will be used
#    for automated messaging and device verification.
# 2. Replace every placeholder below with your actual values:
#      --homeserver   your Matrix homeserver URL
#      --user-login   the bot account Matrix ID
#      --device       any human-readable device name
#      --password     the bot account password (use a strong one)
#      --room-default the Matrix room ID the bot will post to by default
matrix-commander-rs --login password \
  --homeserver https://your-homeserver.tld \
  --user-login @your-bot:your-homeserver.tld \
  --device "YourDeviceName" \
  --password "YourStr0ng-Pa$$word" \
  --room-default '!yourRoomId:your-homeserver.tld'
```

Session credentials are written to `/home/user/matrix-commander-rs/bot_data/` on the host.

### 6. Device verification (cross-signing)

After login, verify the bot device and your own device to establish cross-signing trust. Run both commands inside the container:
```bash
# Before running verification commands, ensure both the bot account and your personal
# account are present in the same Matrix room — matrix-commander-rs will list available
# rooms and devices in the console output to guide you through the process.
matrix-commander-rs --verify emoji-req --user @bot:mymatrix.tld --device SGWUDYUMLE
matrix-commander-rs --verify emoji-req --user @me:mymatrix.tld --device PONDAYCPRK
```

For full details, refer to the [upstream verification documentation](https://github.com/8go/matrix-commander-rs?tab=readme-ov-file#usage).

Exit the interactive shell
```bash
exit
```

### 7. Restart the service

Once the session is initialised and verification is complete, restart the container in its normal operating mode — without an interactive shell:

```bash
docker compose -f /home/user/matrix-commander-rs/docker-compose.yaml down
docker compose -f /home/user/matrix-commander-rs/docker-compose.yaml up -d
```

The container will now run as a persistent background service, ready to accept incoming tunnel connections from the remote client.

---

## Volume Reference

| Host path | Container path | Mode | Ownership requirement |
|---|---|---|---|
| `./authorized_keys` | `/home/bot/.ssh/authorized_keys` | `ro` | `chown 10001:10001`, `chmod 0600` |
| `./bot_data/` | `/home/bot/.local/share/matrix-commander-rs` | `rw` | `chown -R 10001:10001` |
| `./host_keys/` | `/home/bot/keys` | `rw` | `chown -R 10001:10001` |

---

## SSH Host Key Persistence

On first startup, the entrypoint generates `/home/bot/keys/ssh_host_ed25519_key` and persists it via the `./host_keys` volume. This prevents host key churn across container restarts, which would otherwise produce `REMOTE HOST IDENTIFICATION HAS CHANGED` warnings on the connecting client.

To rotate the host key intentionally:
```bash
docker compose -f /home/user/matrix-commander-rs/docker-compose.yaml down
rm /home/user/matrix-commander-rs/host_keys/ssh_host_ed25519_key
docker compose -f /home/user/matrix-commander-rs/docker-compose.yaml up -d
```

---

## Multi-Architecture Support

The image resolves the correct upstream binary at build time using Docker's `TARGETARCH` build argument:

| `TARGETARCH` | Upstream binary triple |
|---|---|
| `amd64` | `x86_64-unknown-linux-gnu` |
| `arm64` | `aarch64-unknown-linux-gnu` |

`armv7-linux-androideabi` is explicitly unsupported: that target links against Android's Bionic libc and is incompatible with standard Linux/Debian environments.

To build a multi-platform manifest:
```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag yourregistry/matrix-bot:latest \
  --push .
```

---

## Attribution

**matrix-commander-rs** is developed and maintained by [8go](https://github.com/8go) and contributors.
Source: [https://github.com/8go/matrix-commander-rs](https://github.com/8go/matrix-commander-rs)

This containerisation layer is an independent wrapper and is not affiliated with or endorsed by the upstream project.
