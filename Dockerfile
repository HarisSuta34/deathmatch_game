# Dedicated game server: official Godot 4.3 Linux binary running this project headless.
# The host must route WebSocket traffic to $PORT (Render sets PORT automatically).
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
    && wget -q https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /tmp \
    && mv /tmp/Godot_v4.3-stable_linux.x86_64 /usr/local/bin/godot \
    && rm /tmp/godot.zip \
    && apt-get purge -y wget unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY project.godot main.tscn ./
COPY scripts ./scripts

ENV PORT=10000
EXPOSE 10000
CMD ["godot", "--headless", "--path", "/app", "--", "--server"]
