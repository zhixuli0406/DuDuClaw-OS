# DuDuClaw OS system-wide home (CP-2 wave-2, 2026-08-30). Found live, not
# hypothesized: the gateway UNIT carries Environment=DUDUCLAW_HOME=/data/duduclaw,
# but an interactive login shell (serial console, ssh) had NO such export, so
# `duduclaw compat windows-vm app-add` run by an operator resolved its default
# home and wrote the RemoteApp registry to /root/.duduclaw/windows-vm/apps.toml
# — a file duduclaw-shell's launcher (which reads the FIXED cross-user path
# /data/duduclaw/windows-vm/apps.toml, see apps/windows_vm.rs) never looks at.
# This export makes the three parties — services, interactive CLI, shell —
# agree on one home. profile.d reaches login shells only; the services keep
# their own explicit Environment= lines and do not depend on this file.
#
# Since 2026-10-15 the gateway runs as uid 1000 (`duduclaw`), and its home
# is writable by every AI employee. A root shell must therefore never run
# `duduclaw` as root against this home: the CLI would read config, skills
# and plugin files that uid 1000 controls, with root's rights. The function
# below makes a plain `duduclaw` typed in a root login shell run as the
# gateway account through setpriv (runuser is not available: util-linux
# builds it only with PAM, and this distro has no PAM). Typing the full
# path, /usr/bin/duduclaw, still runs it as root, deliberately and visibly.
# The function only exists in login shells that read /etc/profile.d: a
# `sh -c duduclaw`, a script, sudo-less cron or systemd-run from root runs
# the binary as root. It is a convenience for operators, not a boundary.
#
# Terminal: --no-new-privs, and when stdin is not a terminal the command
# also runs in a new session (setsid -w) with no controlling terminal, so
# nothing it starts can reach the root shell's tty. An interactive run
# keeps the terminal (prompts need it); there the protection is the kernel
# refusing TIOCSTI to non-CAP_SYS_ADMIN callers (CONFIG_LEGACY_TIOCSTI=n,
# dev.tty.legacy_tiocsti=0). Its children can still write to and read from
# that terminal while it runs, like any program started from it.
export DUDUCLAW_HOME=/data/duduclaw
duduclaw() {
    if [ "$(id -u)" = 0 ]; then
        if [ -t 0 ]; then
            setpriv --reuid=duduclaw --regid=duduclaw --init-groups --no-new-privs -- \
                env HOME=/data/duduclaw DUDUCLAW_HOME=/data/duduclaw /usr/bin/duduclaw "$@"
        else
            setsid -w setpriv --reuid=duduclaw --regid=duduclaw --init-groups --no-new-privs -- \
                env HOME=/data/duduclaw DUDUCLAW_HOME=/data/duduclaw /usr/bin/duduclaw "$@"
        fi
    else
        command duduclaw "$@"
    fi
}
# Same value duduclaw-firstboot's 20-home.conf gives the gateway unit: the
# Windows RemoteApp registry lives outside the 0700 gateway home so the
# kiosk shell can read it (see that drop-in's own comment). Without this an
# operator's `duduclaw compat windows-vm app-add` over serial would write to
# /data/duduclaw/windows-vm/apps.toml, a file the Launcher never reads.
export DUDUCLAW_WINDOWS_VM_APPS_DIR=/data/system/windows-vm
