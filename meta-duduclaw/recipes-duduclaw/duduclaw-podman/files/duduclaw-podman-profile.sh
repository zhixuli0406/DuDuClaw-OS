# Root shells on DuDuClaw OS talk to the gateway's rootless Podman
# (2026-10-15). Without this, `podman pull` or `docker pull` typed by an
# operator would run rootful Podman with a separate store the gateway never
# sees (and on the read-only-root edition could not even write it).
# CONTAINER_HOST puts the podman CLI (and its `docker` shim) in remote
# mode against the same socket the gateway uses, so images an operator
# pulls are the ones the sandboxes run. Unset it for a one-off local
# command: `env -u CONTAINER_HOST -u DOCKER_HOST podman ...`.
export CONTAINER_HOST=unix:///run/duduclaw-gateway/podman/podman.sock
export DOCKER_HOST=unix:///run/duduclaw-gateway/podman/podman.sock
