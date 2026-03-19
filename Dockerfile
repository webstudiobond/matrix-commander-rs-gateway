# Debian Trixie (13) slim: minimum image providing glibc >= 2.38, required by
# current matrix-commander-rs releases. Bookworm ships glibc 2.36 which is
# insufficient.
FROM debian:trixie-slim

# TARGETARCH is injected automatically by BuildKit.
# Mapping:
#   amd64 -> x86_64-unknown-linux-gnu   (standard GNU/Linux x86-64)
#   arm64 -> aarch64-unknown-linux-gnu  (standard GNU/Linux AArch64)
#
# Intentionally omitted: armv7-linux-androideabi — that target links against
# Android's Bionic libc and is entirely incompatible with standard
# Linux/Debian environments. There is no supported armv7 musl or GNU variant
# in the upstream release matrix.
ARG TARGETARCH

# Combine update + install + cleanup in one layer to prevent stale index cache
# from persisting in the image. --no-install-recommends minimises attack
# surface by excluding optional suggested packages.
# netcat-openbsd is retained in the final image for the Docker healthcheck probe.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server \
        curl \
        jq \
        netcat-openbsd \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 10001 -s /bin/bash bot

# All directories bot needs at runtime. /run/sshd is intentionally NOT created
# here — it is mounted as tmpfs at runtime (see docker-compose.yaml) and the
# mount point must be initialised by the entrypoint.
RUN mkdir -p /home/bot/.ssh /home/bot/keys /home/bot/.local/share/matrix-commander-rs \
    && chown -R bot:bot /home/bot

# Resolve target triple from Docker's normalised TARGETARCH value.
# The shell variable is consumed only during this RUN layer; the resulting
# binary is the sole artefact that persists.
# curl and jq have no runtime purpose; purge them but retain netcat-openbsd,
# which is required by the Docker healthcheck probe.
# apt-mark manual protects netcat-openbsd from being swept by --auto-remove,
# since it was installed in the same transaction as curl/jq.
# hadolint ignore=DL4006
RUN set -eu; \
    case "${TARGETARCH}" in \
        amd64) TRIPLE="x86_64-unknown-linux-gnu"   ;; \
        arm64) TRIPLE="aarch64-unknown-linux-gnu"  ;; \
        *)     echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/8go/matrix-commander-rs/releases/latest \
        | jq -r --arg t "${TRIPLE}" '.assets[] | select(.name | endswith($t)) | .browser_download_url'); \
    if [ -z "${DOWNLOAD_URL}" ] || [ "${DOWNLOAD_URL}" = "null" ]; then \
        echo "Error: release asset not found for triple ${TRIPLE}" >&2; exit 1; \
    fi; \
    curl -fsSL "${DOWNLOAD_URL}" -o /usr/local/bin/matrix-commander-rs; \
    chmod 0755 /usr/local/bin/matrix-commander-rs; \
    apt-mark manual netcat-openbsd; \
    apt-get purge -y --auto-remove curl jq \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

EXPOSE 2222
USER bot
ENTRYPOINT ["/entrypoint.sh"]
