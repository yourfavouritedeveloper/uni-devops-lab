#!/usr/bin/env bash
# Starts the local lab "app server" (Ubuntu + systemd + SSH, no Docker) and
# authorizes the control node's SSH key for user 'deploy'.
set -euo pipefail
KEY="${KEY:-$HOME/.ssh/id_ed25519_appserver}"
cd "$(dirname "$0")"
[ -f "$KEY" ] || ssh-keygen -t ed25519 -f "$KEY" -N "" -C "ansible-control-node" -q
docker build -q -t uni-app-server app-server
docker rm -f app-server >/dev/null 2>&1 || true
# /var/lib/docker and /var/lib/containerd must be real volumes, not overlayfs,
# otherwise nested image builds fail with "mount source: overlay ... invalid argument".
docker run -d --name app-server --hostname app-server --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v app-server-docker:/var/lib/docker \
  -v app-server-containerd:/var/lib/containerd \
  -p 2222:22 -p 8080:8080 uni-app-server
sleep 5
docker cp "$KEY.pub" app-server:/home/deploy/.ssh/authorized_keys
docker exec app-server bash -c 'chown -R deploy:deploy /home/deploy/.ssh && chmod 600 /home/deploy/.ssh/authorized_keys'
ssh-keygen -R "[127.0.0.1]:2222" >/dev/null 2>&1 || true
ssh-keyscan -p 2222 127.0.0.1 2>/dev/null >> "$HOME/.ssh/known_hosts"
echo "App server ready: ssh -i $KEY -p 2222 deploy@127.0.0.1"
