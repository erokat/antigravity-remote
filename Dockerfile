FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/usr/local/bin:/root/.local/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    bash \
    tar \
    gzip \
    python3 \
    python3-pip \
    dbus \
    dbus-x11 \
    libsecret-1-0 \
    gnome-keyring \
    rclone \
    && rm -rf /var/lib/apt/lists/*

# Install official Antigravity CLI flat binary
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- -d /usr/local/bin || true
RUN if [ ! -f /usr/local/bin/agy ] && [ -f /root/.local/bin/agy ]; then cp /root/.local/bin/agy /usr/local/bin/agy; fi || true
RUN chmod +x /usr/local/bin/agy 2>/dev/null || true

# Preinstall userbot Python dependencies
RUN pip3 install --no-cache-dir telethon pillow cryptg requests

WORKDIR /workspace

COPY entrypoint.sh /entrypoint.sh
COPY server.py /server.py
RUN chmod +x /entrypoint.sh /server.py

EXPOSE 10000

CMD ["/entrypoint.sh"]
