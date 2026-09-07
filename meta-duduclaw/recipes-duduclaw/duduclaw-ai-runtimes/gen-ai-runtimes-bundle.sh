#!/usr/bin/env bash
# Host-side generator for duduclaw-ai-runtimes-<YYYYMMDD>.tar.zst — the
# vendor AI-coding-CLI payload duduclaw-ai-runtimes.bb unpacks into
# /opt/duduclaw/runtimes/.
#
# SAME CONVENTION AS gen-flatpak-offline-repo.sh (this layer's other big
# vendored blob): this file lives NEXT TO the .bb, deliberately NOT under
# files/ — bitbake never runs it. It needs live network access to three
# registries (npmjs.org, PyPI, and four vendor CDNs) and apt-installs its
# own tooling, none of which belongs inside a do_fetch/do_compile sandbox.
# It is kept in-tree for reproducibility and for the periodic refresh
# these upstreams need (every one of them ships multiple releases a week).
#
# HOW TO RUN (from the repo root, on any host with Docker):
#
#   docker run --rm --platform linux/amd64 \
#     -v "$PWD/meta-duduclaw/recipes-duduclaw/duduclaw-ai-runtimes:/gen" \
#     -v "$PWD/meta-duduclaw/recipes-duduclaw/duduclaw-ai-runtimes/files:/out" \
#     -w /gen node:22-bookworm \
#     bash /gen/gen-ai-runtimes-bundle.sh 2>&1 | tee gen-ai-runtimes-bundle-$(date +%F).log
#
# `--platform linux/amd64` is load-bearing and not a convenience: half of
# this payload is prebuilt native code (npm optionalDependencies resolve
# per `process.platform`/`process.arch`; the four vendor binaries are
# fetched by an explicit linux-x86_64 URL; the Python wheels are pinned to
# manylinux_2_28_x86_64). Running this on an arm64 host WITHOUT that flag
# silently produces an arm64 node_modules tree that installs fine and then
# fails at exec time on the appliance. The image is `node:22-bookworm`
# because the appliance's own Node is meta-oe's nodejs_22.23.2 — same
# major, so anything npm resolves here (engines fields, N-API ABI 127)
# also resolves there.
#
# WHAT IT PRODUCES  (bundle root = /opt/duduclaw/runtimes on the image):
#   node_modules/   npm --omit=dev tree for the six Node CLIs
#   package.json    + package-lock.json (the exact resolution, for refresh)
#   bin/            vendor linux-x64 binaries (grok, cursor-agent, opencode)
#   python/         `pip install --target` tree for mistral-vibe (cp314 /
#                   manylinux_2_28_x86_64 wheels, matching the image's own
#                   python3 3.14.5 from oe-core) + python/bin/vibe with a
#                   rewritten `#!/usr/bin/python3` shebang
#   LICENSES/       one file per component, what LIC_FILES_CHKSUM points at
#   MANIFEST.txt    versions, source URLs, sha256, sizes, and an explicit
#                   `skipped:` line for anything NOT in the bundle
#
# HONESTY RULE (the reason MANIFEST.txt exists at all): a component that
# could not be fetched, or that was deliberately left out, is written into
# MANIFEST.txt as `skipped: <name> — <reason>` and gets an /usr/bin wrapper
# that prints the official install command instead of a "command not
# found". Silently shipping five of six runtimes and calling it six is the
# failure mode this file is written to prevent.
set -euo pipefail

DATE_TAG="${DATE_TAG:-$(date +%Y%m%d)}"
OUT_DIR="${OUT_DIR:-/out}"
WORK="${WORK:-/srv/bundle}"
ROOT="$WORK/duduclaw-ai-runtimes"
TARBALL="$OUT_DIR/duduclaw-ai-runtimes-${DATE_TAG}.tar.zst"

# Pinned versions. Everything here moves fast (Claude Code alone ships
# multiple builds a day), so a refresh means bumping these deliberately,
# re-running, and re-reading the diff -- not silently taking whatever
# `latest` resolved to on the day someone happened to rebuild.
V_CLAUDE="${V_CLAUDE:-2.1.261}"
V_CODEX="${V_CODEX:-0.153.4}"
V_GEMINI="${V_GEMINI:-0.58.0}"
V_QWEN="${V_QWEN:-0.23.0}"
V_KIMI="${V_KIMI:-0.41.0}"
V_COPILOT="${V_COPILOT:-1.0.83}"
V_VIBE="${V_VIBE:-2.25.0}"
V_OPENCODE="${V_OPENCODE:-1.18.29}"
# Grok Build and Cursor publish a "current version" pointer rather than a
# stable download index; both are resolved live below and recorded.
CURSOR_INSTALLER="https://cursor.com/install"
GROK_CHANNEL_URL="https://x.ai/cli/stable"

MANIFEST="$ROOT/MANIFEST.txt"

log() { printf '\n==> %s\n' "$*"; }
note() { printf '%s\n' "$*" >>"$MANIFEST"; }

sha_of() { sha256sum "$1" | cut -d' ' -f1; }

log "[0/7] tooling"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    ca-certificates curl zstd unzip python3 python3-pip python3-venv >/dev/null
node --version
npm --version
python3 --version

rm -rf "$WORK"
mkdir -p "$ROOT/bin" "$ROOT/LICENSES" "$OUT_DIR"
: >"$MANIFEST"
note "duduclaw-ai-runtimes bundle — generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by gen-ai-runtimes-bundle.sh"
note "host: $(uname -srm) | node $(node --version) | npm $(npm --version) | python $(python3 --version 2>&1)"
note "install prefix on the appliance: /opt/duduclaw/runtimes"
note ""
note "== Node CLIs (npm install --omit=dev) =="

# --------------------------------------------------------------------------
# 1. Node CLIs
# --------------------------------------------------------------------------
# One flat `npm install --prefix` of all six, NOT six separate prefixes:
# they share a very large transitive set (@modelcontextprotocol/sdk, zod,
# undici, react/ink, ...) and npm's hoisting dedupes it once. Measured on
# the 2026-09-05 run this is the difference between one tree and six
# near-copies of the same dependency graph in an 8 GiB root slot.
#
# --omit=dev, --no-audit, --no-fund: no dev deps in a shipped payload; the
# audit/fund calls are extra network round trips with no artifact.
# --ignore-scripts is deliberately NOT passed: @github/copilot and
# @anthropic-ai/claude-code both use a postinstall step to place their
# platform-native helper, and skipping it produces a tree that installs
# clean and then cannot run.
log "[1/7] npm install (six vendor CLIs)"
cd "$ROOT"
cat >package.json <<EOF
{
  "name": "duduclaw-ai-runtimes",
  "version": "0.0.0",
  "private": true,
  "description": "Vendored AI coding CLIs for DuDuClaw OS (/opt/duduclaw/runtimes)",
  "license": "UNLICENSED"
}
EOF
npm install --omit=dev --no-audit --no-fund --loglevel=warn \
    "@anthropic-ai/claude-code@${V_CLAUDE}" \
    "@openai/codex@${V_CODEX}" \
    "@google/gemini-cli@${V_GEMINI}" \
    "@qwen-code/qwen-code@${V_QWEN}" \
    "@moonshot-ai/kimi-code@${V_KIMI}" \
    "@github/copilot@${V_COPILOT}"

for spec in \
    "@anthropic-ai/claude-code:claude" \
    "@openai/codex:codex" \
    "@google/gemini-cli:gemini" \
    "@qwen-code/qwen-code:qwen" \
    "@moonshot-ai/kimi-code:kimi" \
    "@github/copilot:copilot"; do
    pkg="${spec%%:*}"; cli="${spec##*:}"
    ver="$(node -p "require('$ROOT/node_modules/$pkg/package.json').version")"
    lic="$(node -p "require('$ROOT/node_modules/$pkg/package.json').license || 'UNSPECIFIED'")"
    note "npm  $pkg@$ver  cli=$cli  license=$lic  https://registry.npmjs.org/${pkg}/-/$(basename "$pkg")-${ver}.tgz"
    # Carry each package's own license text into LICENSES/ so the recipe's
    # LIC_FILES_CHKSUM can point at a real file inside the bundle rather
    # than at a generic COMMON_LICENSE_DIR copy that says nothing about
    # what this payload actually contains.
    for cand in LICENSE LICENSE.md LICENSE.txt LICENCE License.md license.md README.md; do
        if [ -f "$ROOT/node_modules/$pkg/$cand" ]; then
            cp "$ROOT/node_modules/$pkg/$cand" "$ROOT/LICENSES/npm-${cli}-${cand}"
            break
        fi
    done
done
note ""

# --------------------------------------------------------------------------
# 2. Grok Build (xAI)
# --------------------------------------------------------------------------
# x.ai/cli/install.sh resolves a channel pointer (a bare version string at
# https://x.ai/cli/stable) and then fetches
# https://x.ai/cli/grok-<ver>-linux-x86_64[.zst|.gz]. Reimplemented here
# rather than piping the installer to bash: the installer writes into
# $HOME/.grok, reads ~/.grok/auth.json, and symlinks `agent` (which on this
# image belongs to Cursor) -- none of which is wanted in a build container.
log "[2/7] Grok Build"
note "== Vendor binaries (bin/) =="
if grok_ver="$(curl -fsSL -m 60 "$GROK_CHANNEL_URL" | tr -d '[:space:]')" && [ -n "$grok_ver" ]; then
    grok_url="https://x.ai/cli/grok-${grok_ver}-linux-x86_64"
    if curl -fsSL -m 900 "${grok_url}.zst" -o /tmp/grok.zst 2>/dev/null; then
        zstd -q -d -c /tmp/grok.zst >"$ROOT/bin/grok"
        grok_src="${grok_url}.zst"; grok_dl=/tmp/grok.zst
    elif curl -fsSL -m 900 "$grok_url" -o "$ROOT/bin/grok"; then
        grok_src="$grok_url"; grok_dl="$ROOT/bin/grok"
    else
        grok_src=""
    fi
    if [ -n "${grok_src:-}" ]; then
        chmod 0755 "$ROOT/bin/grok"
        note "bin  grok $grok_ver  license=proprietary (xAI Terms of Service — closed-source binary, no license file shipped by upstream)"
        note "     url=$grok_src"
        note "     sha256(download)=$(sha_of "$grok_dl")  sha256(binary)=$(sha_of "$ROOT/bin/grok")  size=$(stat -c%s "$ROOT/bin/grok")"
    else
        note "skipped: grok — download failed from $grok_url (channel said $grok_ver)"
    fi
else
    note "skipped: grok — could not resolve the stable channel pointer at $GROK_CHANNEL_URL"
fi

# --------------------------------------------------------------------------
# 3. Cursor agent
# --------------------------------------------------------------------------
# The install script embeds its own build id in the download URL
# (https://downloads.cursor.com/lab/<build>/linux/x64/agent-cli-package.tar.gz)
# and there is no separate version index -- so the id is scraped out of
# the installer rather than guessed. The tarball's top level is a versioned
# directory; --strip-components=1 flattens it.
log "[3/7] Cursor agent"
if cursor_sh="$(curl -fsSL -m 60 "$CURSOR_INSTALLER")" \
   && cursor_build="$(printf '%s' "$cursor_sh" | grep -oE 'downloads\.cursor\.com/lab/[^/]+/' | head -1 | cut -d/ -f3)" \
   && [ -n "$cursor_build" ]; then
    cursor_url="https://downloads.cursor.com/lab/${cursor_build}/linux/x64/agent-cli-package.tar.gz"
    if curl -fsSL -m 900 "$cursor_url" -o /tmp/cursor.tgz; then
        mkdir -p "$ROOT/cursor-agent"
        tar --strip-components=1 -xzf /tmp/cursor.tgz -C "$ROOT/cursor-agent"
        # The package is a directory (node runtime + js bundle + native
        # helpers), not a single file -- keep it whole and expose the
        # entrypoint through bin/.
        if [ -f "$ROOT/cursor-agent/cursor-agent" ]; then
            chmod 0755 "$ROOT/cursor-agent/cursor-agent"
            ln -sf ../cursor-agent/cursor-agent "$ROOT/bin/cursor-agent"
        fi
        note "bin  cursor-agent build=$cursor_build  license=proprietary (Cursor/Anysphere Terms of Service — closed-source, no license file in the package)"
        note "     url=$cursor_url"
        note "     sha256(tar.gz)=$(sha_of /tmp/cursor.tgz)  unpacked=$(du -sb "$ROOT/cursor-agent" | cut -f1) bytes"
    else
        note "skipped: cursor-agent — download failed from $cursor_url"
    fi
else
    note "skipped: cursor-agent — could not scrape a build id out of $CURSOR_INSTALLER"
fi

# --------------------------------------------------------------------------
# 4. OpenCode
# --------------------------------------------------------------------------
# github.com/sst/opencode 301-redirects to anomalyco/opencode; the release
# assets live under the redirected name, so the URL below uses the real
# one. The plain (glibc, non-baseline) linux-x64 build is correct for this
# image: oe-core glibc 2.43, and every x86-64-v3 machine this layer targets
# has the AVX2 the non-baseline build assumes.
log "[4/7] OpenCode"
oc_url="https://github.com/anomalyco/opencode/releases/download/v${V_OPENCODE}/opencode-linux-x64.tar.gz"
if curl -fsSL -m 900 "$oc_url" -o /tmp/opencode.tgz; then
    mkdir -p /tmp/oc && tar -xzf /tmp/opencode.tgz -C /tmp/oc
    found="$(find /tmp/oc -maxdepth 2 -type f -name opencode | head -1)"
    if [ -n "$found" ]; then
        install -m 0755 "$found" "$ROOT/bin/opencode"
        note "bin  opencode v${V_OPENCODE}  license=MIT (github.com/anomalyco/opencode)"
        note "     url=$oc_url"
        note "     sha256(tar.gz)=$(sha_of /tmp/opencode.tgz)  sha256(binary)=$(sha_of "$ROOT/bin/opencode")  size=$(stat -c%s "$ROOT/bin/opencode")"
        curl -fsSL -m 60 "https://raw.githubusercontent.com/anomalyco/opencode/v${V_OPENCODE}/LICENSE" \
            -o "$ROOT/LICENSES/opencode-LICENSE" || true
    else
        note "skipped: opencode — no 'opencode' binary inside $oc_url"
    fi
else
    note "skipped: opencode — download failed from $oc_url"
fi

# --------------------------------------------------------------------------
# 5. Kiro CLI — DELIBERATELY NOT BUNDLED
# --------------------------------------------------------------------------
# Not a fetch failure: the artifact is reachable and installs fine. It is
# left out on a measured size argument, recorded here so nobody has to
# re-derive it.
#
# https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip
# is 614.9 MB compressed / 1039.4 MB uncompressed (read out of the zip's
# own central directory over HTTP range requests, 2026-09-05):
#   kirocli/bin/kiro-cli-chat   838.6 MB
#   kirocli/bin/kiro-cli        113.9 MB
#   kirocli/bin/kiro-cli-term    86.9 MB
# The 8192 MiB root slot has ~2268 MiB of headroom over this image's
# measured content, and this one runtime would take 46% of it -- more than
# the other ten runtimes plus llama.cpp combined. Shipping only kiro-cli
# (114 MB) is not an option either: it is the launcher, and every agent
# subcommand execs kiro-cli-chat.
#
# Consequence, implemented in the recipe: /usr/bin/kiro-cli is an honest
# wrapper that installs on demand into /data/duduclaw (the persistent
# partition, which systemd-repart grows to the real disk) instead of
# pretending the binary is missing.
log "[5/7] Kiro CLI (skipped by design)"
note "skipped: kiro-cli — 1039.4 MB uncompressed (614.9 MB zip) would consume 46% of the root slot's remaining headroom; /usr/bin/kiro-cli installs it on demand into /data/duduclaw/runtimes-extra instead. Source: https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip (license: proprietary, AWS Customer Agreement / Kiro Service Terms)"
note ""

# --------------------------------------------------------------------------
# 6. Mistral Vibe (Python)
# --------------------------------------------------------------------------
# NOT a venv. A venv records absolute paths in pyvenv.cfg + every console
# script shebang and pins itself to the interpreter that built it -- a
# relocatable-venv dance this bundle does not need, because
# `pip install --target` produces a plain, path-independent import tree
# that only needs PYTHONPATH. The cross-target flags matter:
#   --python-version 3.14   the image's own python3 (oe-core python3_3.14.5)
#   --platform manylinux_2_28_x86_64  image glibc is 2.43, comfortably newer
#   --only-binary=:all:     forced by --platform; also means no compiler and
#                           no build-host leakage into the shipped tree
# mistral-vibe pulls real C extensions (pydantic-core, cryptography, cffi,
# rpds-py, watchfiles, zstandard, tree-sitter, setproctitle,
# textual-speedups), so this ABI/platform pinning is the whole ballgame --
# a cp311 wheel tree would import-error on the appliance's 3.14.
log "[6/7] mistral-vibe (pip --target, cp314/manylinux_2_28_x86_64)"
note "== Python runtime (python/) =="
if pip3 install --break-system-packages --quiet --upgrade pip >/dev/null 2>&1 || true; then :; fi
# --platform is repeatable and MUST be: the resolver only accepts wheels
# whose platform tag is in this set, and the set is NOT "2_28 implies 2_17"
# -- pip treats each tag literally. Real failure from the first run of this
# script (2026-09-05): `cffi==2.0.0` publishes its cp314 build as
# `manylinux2014_x86_64.manylinux_2_17_x86_64` only, so a lone
# `--platform manylinux_2_28_x86_64` resolved cffi to nothing and aborted the
# whole tree with "Could not find a version that satisfies the requirement
# cffi==2.0.0 (from versions: 2.0.0b1)". All three tags below are satisfied
# by the image's glibc 2.43 (oe-core glibc_2.43.bb), so accepting the older
# baselines costs nothing.
if python3 -m pip install \
        --target "$ROOT/python" \
        --platform manylinux_2_17_x86_64 \
        --platform manylinux2014_x86_64 \
        --platform manylinux_2_28_x86_64 \
        --python-version 3.14 \
        --implementation cp \
        --only-binary=:all: \
        --no-warn-script-location \
        --break-system-packages \
        "mistral-vibe==${V_VIBE}" >/tmp/pip.log 2>&1; then
    # pip --target writes console scripts with the BUILD container's
    # interpreter in the shebang; rewrite to the appliance's own path. The
    # wrapper in /usr/bin/vibe sets PYTHONPATH and runs this file.
    if [ -d "$ROOT/python/bin" ]; then
        for f in "$ROOT/python/bin"/*; do
            [ -f "$f" ] || continue
            head -c2 "$f" | grep -q '#!' && sed -i '1s|^#!.*$|#!/usr/bin/python3|' "$f" && chmod 0755 "$f"
        done
    fi
    vibe_entry="$(ls "$ROOT/python/bin" 2>/dev/null | tr '\n' ' ')"
    note "pip  mistral-vibe==${V_VIBE}  license=Apache-2.0  https://pypi.org/project/mistral-vibe/${V_VIBE}/"
    note "     target=/opt/duduclaw/runtimes/python  console-scripts: ${vibe_entry:-<none>}"
    note "     packages=$(find "$ROOT/python" -maxdepth 1 -name '*.dist-info' | wc -l)  size=$(du -sb "$ROOT/python" | cut -f1) bytes"
    for d in "$ROOT/python"/mistral_vibe-*.dist-info; do
        [ -d "$d" ] || continue
        for lf in "$d"/LICENSE*; do
            [ -f "$lf" ] && cp "$lf" "$ROOT/LICENSES/mistral-vibe-$(basename "$lf")"
        done
    done
else
    note "skipped: mistral-vibe — pip install --target failed (see the generator log); /usr/bin/vibe prints the pipx install hint"
    tail -30 /tmp/pip.log >&2 || true
    rm -rf "$ROOT/python"
fi
note ""

# --------------------------------------------------------------------------
# 6b. Prune — remove payload that provably cannot execute on this image
# --------------------------------------------------------------------------
# Every deletion here is justified by reading the shipped launcher, not by
# guessing from a filename. The root A/B slot is 8192 MiB and this bundle
# is the single largest thing ever added to it, so "it's only 273 MB" is
# not an argument for keeping dead weight -- but neither is size an
# argument for deleting something a launcher might exec.
#
#  1. cursor-agent/cursor-agent-{sea,worker-sea} (141 MB + 132 MB): the
#     shipped `cursor-agent` launcher is a bash script that ends in
#     `exec "$SCRIPT_DIR/node" [--use-system-ca] "$SCRIPT_DIR/index.js"`.
#     It never references either SEA (Node single-executable-application)
#     blob on any codepath -- they are the same program packaged for hosts
#     without the bundled node, which this bundle always has. Read out of
#     the launcher itself, quoted here because a future Cursor build could
#     change the launcher and silently turn this prune into a breakage:
#     re-read cursor-agent/cursor-agent after every version bump.
#     The bundled cursor-agent/node (v24.5.0, 124 MB) is deliberately KEPT
#     rather than symlinked to the image's /usr/bin/node -- that is Node
#     22.23.2 (meta-oe), two majors older than what this index.js was built
#     against.
#  2. @img/sharp-wasm32 (8.7 MB): sharp's WASM fallback, used only on
#     platforms with no native binding. @img/sharp-linux-x64 +
#     @img/sharp-libvips-linux-x64 are both present, so the native path is
#     the one that loads.
log "[6b/7] prune non-executable payload"
note "== Pruned (present in npm/vendor output, removed on purpose) =="
for victim in \
    "cursor-agent/cursor-agent-sea" \
    "cursor-agent/cursor-agent-worker-sea" \
    "node_modules/@img/sharp-wasm32"; do
    if [ -e "$ROOT/$victim" ]; then
        sz="$(du -sb "$ROOT/$victim" | cut -f1)"
        rm -rf "$ROOT/$victim"
        note "pruned: $victim ($sz bytes)"
    fi
done
note ""

# --------------------------------------------------------------------------
# 7. Pack
# --------------------------------------------------------------------------
log "[7/7] measure + pack"
note "== Sizes =="
for d in node_modules bin cursor-agent python LICENSES; do
    [ -e "$ROOT/$d" ] || continue
    note "$(du -sh "$ROOT/$d" | sed "s|$ROOT/||")"
done
note "total uncompressed: $(du -sh "$ROOT" | cut -f1)"
du -sh "$ROOT"/* || true

cd "$WORK"
# --no-xattrs: macOS/Docker bind mounts otherwise smuggle com.apple.*
# attributes into the tarball, which do_install's `tar -xf` then warns
# about on every build. -T0 for all cores. Compression level 12, not the
# flatpak offline-repo tarball's -19: this payload is ~2 GB of already-
# incompressible content (Node SEA blobs, static Rust/Go binaries, .node
# addons) and -19 spends roughly an hour of wall clock for a low
# single-digit percentage over -12 on exactly that kind of input.
#
# Hardlinks matter here and tar preserves them: @anthropic-ai/claude-code/
# bin/claude.exe and @anthropic-ai/claude-code-linux-x64/claude are the
# SAME 206 MB inode (link count 2), and npm creates several more such
# pairs. `tar` stores the second and later names as hardlink entries, so
# the bundle -- and the installed rootfs, since do_install untars into
# ${D} -- carries that content once, not twice.
tar --no-xattrs -cf - duduclaw-ai-runtimes | zstd -12 -T0 -f -o "$TARBALL"
# The tarball's own sha256 cannot live inside the tarball it describes.
# It goes to a sidecar next to it and to this log; MANIFEST.txt carries
# every per-component sha256, which is the part that has to be auditable
# from the installed image.
( cd "$OUT_DIR" && sha256sum "$(basename "$TARBALL")" >"$(basename "$TARBALL").sha256" )

log "done"
cat "$MANIFEST"
ls -la "$TARBALL"
cat "${TARBALL}.sha256"
