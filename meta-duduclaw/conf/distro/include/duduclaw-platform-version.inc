# DuDuClaw platform version — single source of truth mirror.
#
# Y3-3 (2026-08-25), MAP-agent-native-os-2026-08.md 裁決⑥ ("同版同發＝單
# repo＋OS 進主版本流"): the OS image ships on the SAME release train as the
# platform binary — platform vX.Y.Z, OS image vX.Y.Z, one `scripts/release.sh`
# run, one CHANGELOG. This file is the ONE place in the meta-duduclaw layer
# that carries that number; every OS-side version point (DISTRO_VERSION in
# ../duduclaw-os.conf, the duduclaw-cli/duduclaw-sysd/duduclaw-comp recipe
# filenames' PV) derives from it, directly or via the same release.sh step.
#
# Bumped ONLY by `scripts/release.sh <patch|minor|major>` (which shells its
# generic sed-based bump loop over this file exactly like it already does
# for Cargo.toml/pyproject.toml/package.json — see that script's
# `platform_manifests()` / the "yocto_inc" kind). DO NOT hand-edit; a
# manually-edited value is exactly the kind of drift `release.sh audit`
# exists to catch (it enumerates this file too, see the "yocto_inc" audit
# row) — if it disagrees with the root Cargo.toml workspace version, the
# next release run overwrites it back to the real value.
#
# Why a dedicated include instead of sed-ing DISTRO_VERSION in
# duduclaw-os.conf directly: DISTRO_VERSION carries an additional
# human-owned milestone suffix (see that file — "-y1-bringup" as of Y1-1,
# dropped entirely once the OS reaches its first GA release). Splitting the
# machine-owned number from the human-owned suffix into two files means
# release.sh's generic bump mechanism only ever touches the number, never
# risks mangling the suffix with a more fragile regex, and the suffix's
# owner (whoever tracks the Y-line milestones, see
# commercial/docs/TODO-agent-first-os-2026-08.md "Y 線") can rename it
# freely without conflicting with a release-triggered edit to this file.
DUDUCLAW_PLATFORM_VERSION = "1.62.0"
