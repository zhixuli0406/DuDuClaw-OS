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
export DUDUCLAW_HOME=/data/duduclaw
