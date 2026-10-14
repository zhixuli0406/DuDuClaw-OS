# Rootless gateway + rootless Podman — QEMU verification checklist (2026-10)

> L2 internal checklist, not yet run. Maps the V1–V25 acceptance checks of
> the rootless-gateway design (`commercial/docs/specs/DESIGN-os-rootless-gateway-2026-10.md`,
> r2.2, in the platform maintainers' private tree) to concrete commands for
> the first real bake + boot on the GCP builder
> ([`../impl/gcp-builder-2026-10.md`](../impl/gcp-builder-2026-10.md)), plus
> the extra checks the OS-side implementation (branch `feat/os-rootless`)
> added. Record results in a dated evidence file under
> `wiki/reports/<kind>/` and link it from here.

## 0. Preconditions

- **Platform snapshot.** The OS side alone is not functional: the vendored
  platform v1.73.1 still probes Docker with `docker info --format
  {{.ServerVersion}}` (fails against Podman), wipes the home itself on
  factory reset, calls `systemctl` for llama-server, and its sysd does not
  know `--require-main-pid-of`. Bake only after `scripts/sync-platform.sh`
  has moved the four snapshots to the platform release that carries P1–P12
  (planned v1.73.4 or the next 1.73.x), and in that same change append
  `--require-main-pid-of duduclaw-gateway.service` to
  `duduclaw-sysd.service`'s `ExecStart` (TODO in that unit's header).
- **Image.** `duduclaw-image-appliance-test` (root serial autologin) on
  `duduclaw-qemux86-64`, booted by `release-os.sh smoke`'s runqemu
  invocation (TCG, slirp, no KVM). The base edition
  (`duduclaw-image-ab`) needs V1–V4, V12, V13 and V21 repeated once; it has
  no container stack.
- **Helper.** `runuser` is not in the image (util-linux builds it only with
  PAM). Use:

  ```sh
  as_gw()    { setpriv --reuid=duduclaw --regid=duduclaw --init-groups -- "$@"; }
  as_kiosk() { setpriv --reuid=duduclaw-kiosk --regid=duduclaw-kiosk --init-groups -- "$@"; }
  ```

- **A/B rounds.** V13 needs two images: v0.3.0 (root gateway) installed
  first, then the new image through the normal update path.

## 1. Design checks V1–V25

| # | Command(s) on the guest | Pass when |
|---|---|---|
| V1 | `id duduclaw`; `getent group duduclaw-flatpak duduclaw-ipc`; `getent passwd 1000; getent group 1000` | `uid=1000(duduclaw) gid=1000(duduclaw) groups=…duduclaw-ipc…duduclaw-kiosk`; `duduclaw-flatpak` lists no members; `duduclaw-ipc` lists `duduclaw,duduclaw-kiosk` (order may differ); nothing else owns 1000 |
| V2 | `systemctl show -p User,MainPID duduclaw-gateway`; `grep -E 'CapEff\|NoNewPrivs' /proc/<MainPID>/status` | `User=duduclaw`; `CapEff: 0000000000000000`; `NoNewPrivs: 1` |
| V3 | `ls -l /run/duduclaw/sysd.sock`; trigger reboot from the dashboard; `as_kiosk curl -sS --http0.9 --unix-socket /run/duduclaw/sysd.sock http://localhost/` | socket `srw------- duduclaw`; reboot works; kiosk gets `Permission denied` (connect refused by mode) |
| V4 | `find /data/duduclaw ! -user duduclaw \| wc -l`; `find /data/system/containers/duduclaw -maxdepth 3 ! -user duduclaw \| head` | `0`; the store has files owned by 100000+ (proves it was never chowned) |
| V5 | `as_gw env -u CONTAINER_HOST -u DOCKER_HOST XDG_RUNTIME_DIR=/run/duduclaw-gateway podman info --format '{{.Host.Security.Rootless}}'`; `as_gw env -u CONTAINER_HOST -u DOCKER_HOST XDG_RUNTIME_DIR=/run/duduclaw-gateway podman unshare cat /proc/self/uid_map` (local mode on purpose; the root shell's profile exports `CONTAINER_HOST`) | `true`; `0 1000 1` and `1 100000 65536` |
| V6 | `curl -sS --unix-socket /run/duduclaw-gateway/podman/podman.sock http://d/_ping`; same with `/v1.47/info` | `OK`; JSON containing `ServerVersion` |
| V7 | `as_gw env CONTAINER_HOST=unix:///run/duduclaw-gateway/podman/podman.sock docker version --format '{{.Server.Version}}'` | `5.8.x` |
| V8 | Run a task-sandbox task from the dashboard (`--network bridge`). In the container: `cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/pids.max /sys/fs/cgroup/cpu.max`; `ip addr`; `curl -sI https://example.com`. Then `--memory 32m` + a python process allocating 80 MB. Host: `systemctl show -p DelegateSubgroup duduclaw-podman`; `journalctl -u duduclaw-podman \| grep -iE 'EPERM\|operation not permitted\|read-only file system\|nftables error'`; `podman ps -a` (through the socket) after the sweep; `lsmod` before/after the first container | limits equal the plan, `cpu.max` not `max`; eth0 present, egress works; 80 MB process OOM-killed (exit 137); `DelegateSubgroup=supervisor`; journal clean (no EPERM from the CAP_SETUID/SETGID bounding set, no EROFS from `ProtectKernelTunables`/`ProtectSystem=strict`, no netavark nft error); no leftover containers. **lsmod diff** goes into `duduclaw-containers-modules.conf` (drop unused names, add missing ones). netavark failure → platform P11 (pasta mode) |
| V8b | `systemctl edit duduclaw-podman` → `[Service]` `DelegateSubgroup=` (empty), restart; run `duduclaw doctor`; try a sandbox task; revert | doctor shows sandbox / computer use "unavailable", task refused; normal after revert |
| V9 | Script sandbox (bollard) run from an agent; inside: `ip -o link` | succeeds; only `lo` (`--network=none`) |
| V10 | Computer-use session with `allowed_domains=["example.com"]`; in the container `curl -sI https://example.com`, `curl -m5 https://1.1.1.1`; masked screenshot; live view | no `[domain-filter]` fatal; example.com works, 1.1.1.1 blocked; live view shows frames |
| V11 | Discovery scoring run; `ls -l /data/duduclaw/tmp/`; `journalctl -u duduclaw-gateway \| grep discovery_score` | `--user 65534` container completes; bind source under `/data/duduclaw/tmp` |
| V12 | Factory reset from the dashboard (with and without "clear network"); after reboot: `ls -la /data/duduclaw/system/`; `stat -c %U /data/duduclaw/config.toml`; `journalctl -b -u duduclaw-factory-reset`; `ls /data/system/factory-reset.pending` | `.provisioned` recreated, `config.toml` owned by duduclaw, journal shows the wipe, marker gone; `/data/system/iwd` empty only for `clear_network=1`; new `/etc/machine-id` |
| V13 | Install v0.3.0, use it (tasks, an agent run), update to the new image; repeat V2/V4; `as_gw sqlite3 /data/duduclaw/tasks.db 'pragma integrity_check'` (or open the task board); roll back to v0.3.0, `touch /data/duduclaw/rollback-root-file` as root there; update again | V2/V4 pass after the first update; tasks readable/writable; after the second update the rollback file is owned by duduclaw; `ls -l /data/system/random-seed /data/system/machine-id /data/system/audit/rescue` exist (relocated) |
| V14 | `systemctl start duduclaw-secaudit-scan`; `ls -l /data/duduclaw/secaudit/reports/` | report written, owned by duduclaw, listed in the dashboard |
| V15 | `as_gw busctl --system call net.connman.iwd / org.freedesktop.DBus.ObjectManager GetManagedObjects`; `cat /usr/share/dbus-1/system.d/iwd-dbus.conf` | no `AccessDenied`; record the upstream policy text |
| V16 | `ls -l /run/duduclaw-kiosk/pipewire-0*`; `as_gw env XDG_RUNTIME_DIR=/run/duduclaw-kiosk wpctl status`; change volume from the dashboard | sockets `srw-rw---- duduclaw-kiosk duduclaw-ipc`; wpctl works; volume changes |
| V17 | `ls -l /run/duduclaw-kiosk/duduclaw-shell.sock /run/duduclaw-kiosk/duduclaw-codrive.sock /run/duduclaw-kiosk/duduclaw-codrive.token`; `journalctl -u duduclaw-kiosk \| grep 'shared with group'`; shell-control audit log after a dashboard display action; `as_gw cat /run/duduclaw-kiosk/duduclaw-codrive.token >/dev/null`; repeat the last one as `duduclaw-flatpak-verify` | sockets `0660 duduclaw-kiosk:duduclaw-ipc`, token `0640`; audit line marks the gateway as `Agent`; display-bridge RPC succeeds; gateway reads the token, flatpak-verify gets `Permission denied` |
| V18 | Restart the local model service from the dashboard with no model file; `journalctl -u duduclaw-gateway -u duduclaw-sysd \| grep -i 'permission denied'` | sysd answers "unit not enabled"-type message; no `Permission denied` |
| V19 | `as_gw systemctl reboot`; `env -u CONTAINER_HOST -u DOCKER_HOST podman ps -a` as root | reboot refused (no polkit grant); root's local podman sees no gateway containers (may also fail on the read-only root, which counts as pass) |
| V20 | `as_gw duduclaw doctor` (or the dashboard doctor page) | Docker / task sandbox / computer use all available |
| V21 | As uid 1000: `ln -s /etc/shadow /data/duduclaw/evil; ln -s /dev/sda /data/duduclaw/evil2; ln /data/system/random-seed /data/duduclaw/seed`; reboot; `stat -c '%U %n' /etc/shadow /dev/sda /data/system/random-seed`; `journalctl -b -u duduclaw-home-owner` | the `ln` fails with `Operation not permitted` (`sysctl fs.protected_hardlinks` = 1); after reboot the three targets keep their owners |
| V22 | In a sandbox container: `curl -m5 http://<host-LAN-IP>:18789/`, `curl -m5 http://169.254.1.2:8080/`, `curl -m5 http://<container-gw>:18789/`; on the host: `curl -s 127.0.0.1:8080/health` as the gateway; `cat /proc/$(pgrep -f pasta \| head -1)/cgroup`; `nft list chain inet filter duduclaw_podman_egress` | all three container connections fail; the gateway's own call works; pasta's cgroup is under `system.slice/duduclaw-podman.service`; the chain holds the three rules and the drop counter increased |
| V23 | `find / -xdev -type f -perm /6000` | only `/usr/bin/newuidmap` and `/usr/bin/newgidmap` (directories with setgid are not counted; the build already asserts this) |
| V24 | Through the libpod API as uid 1000, create a container with `oci_runtime: "/usr/bin/id"` (or `--runtime /usr/bin/id` via `podman --remote`) and read its output | runs as uid 1000 with no new capabilities (`CapEff` 0 except CAP_SETUID/SETGID bounding) — recorded, not blocked |
| V25 | `ls -l /dev/kvm` | record the mode; if not 0666, add the gateway to `kvm` in duduclaw-cli's useradd |

## 2. Extra checks from the implementation

| Check | Command(s) | Pass when |
|---|---|---|
| Kernel config | `zcat /proc/config.gz \| grep -E 'CONFIG_(NFT_SOCKET\|CGROUP_BPF\|SOCK_CGROUP_DATA\|TUN\|NFT_NAT\|NFT_MASQ\|NFT_FIB_INET\|NFT_COMPAT\|SECURITY_YAMA)='`; the kernel-cache audit warnings in the bake log | all present as requested in `duduclaw-rootless.cfg`; no "did not make it into the final configuration" warnings for them |
| Podman unit has no NNP | `grep NoNewPrivs /proc/$(systemctl show -p MainPID --value duduclaw-podman)/status` | `NoNewPrivs: 0` (if 1, a seccomp-based option implied it and newuidmap breaks; V5 would fail too) |
| Loopback guard fails closed | `systemctl stop duduclaw-podman`; temporarily move the guard aside (`mount --bind /bin/false /usr/libexec/duduclaw/podman-egress-guard`); `systemctl start duduclaw-podman`; undo | the unit refuses to start |
| Guard survives a firewall reload | `systemctl restart nftables`; `nft list chain inet filter duduclaw_podman_egress` | rules present again (PartOf restarted podman) |
| sysctl | `sysctl fs.protected_hardlinks fs.protected_symlinks kernel.yama.ptrace_scope` | `1 1 1` |
| Ordering | `systemd-analyze critical-chain duduclaw-gateway.service`; `systemctl show -p After duduclaw-podman.service` | home-owner before podman/gateway; no ordering-cycle messages in `journalctl -b \| grep -i cycle` |
| Relocation | first boot of the new image over v0.3.0: `journalctl -b -u duduclaw-home-owner \| grep relocate`; `dmesg \| grep duduclaw-persist` | seed, machine-id and rescue audit moved to `/data/system`; machine-id unchanged across the update |
| Factory reset fail-safe | write `garbage` to `/data/system/factory-reset.pending`, reboot | nothing wiped, marker kept, `duduclaw-factory-reset.service` failed with the "malformed" line; dashboard still reachable |
| modules-load | `systemctl status systemd-modules-load` | active, no "Failed to find module" |
| AI CLI sandbox | run a Claude Code task with its bubblewrap sandbox enabled (if the platform enables it) | record: expected to fail under `RestrictNamespaces=yes`; decide whether to keep the setting |
| Root shell | in a login shell: `echo $CONTAINER_HOST`; `podman images` | points at the gateway socket; lists the gateway's images |
| setuid strip side effects | in a Flatpak app (Chromium), open a file through the file chooser; `ls -l /run/duduclaw-kiosk/doc 2>&1`; `journalctl -b \| grep -iE 'fusermount\|launch-helper'` | portal file access works, or the failure is recorded and fusermount3 goes on the allowlist with a reason in duduclaw-image-compat.inc |
| Flatpak | `as_gw flatpak install --system …` (any small app from the offline repo) | refused by polkit (no `duduclaw-flatpak` membership); the kiosk Launcher install still works |
