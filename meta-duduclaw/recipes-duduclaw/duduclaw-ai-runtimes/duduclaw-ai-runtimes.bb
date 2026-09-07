SUMMARY = "Vendored AI coding CLIs (Claude Code / Codex / Gemini / Qwen / Kimi / Copilot / Grok / Cursor / OpenCode / Mistral Vibe) under /opt/duduclaw/runtimes"
DESCRIPTION = "${SUMMARY}. WP-F of the platform repo's docs/todo/TODO-ai-runtimes-2026-09.md \
(§1 決策 2 '全部'): the appliance ships every runtime it claims to support, \
so a factory-fresh box can be handed an API key and put to work with no \
network install step. Payload is a single pre-generated tarball -- see \
gen-ai-runtimes-bundle.sh next to this .bb (NOT under files/; same \
convention as duduclaw-flatpak-offline-repo's own generator and \
duduclaw-shell's gen-git-manifests.sh: a host-side helper bitbake never \
executes, because producing it needs live npm/PyPI/vendor-CDN network \
access and an amd64 container, neither of which belongs in a do_fetch \
sandbox). \
\
Installs to /opt/duduclaw/runtimes/{node_modules,bin,cursor-agent,python} \
and drops eleven /usr/bin symlinks covering ten runtimes (claude codex \
gemini qwen kimi copilot \
grok agent cursor-agent opencode vibe) onto one dispatcher, \
files/duduclaw-runtime-exec -- crates/duduclaw-core's which_cli searches \
/usr/bin, so these symlinks are what makes `duduclaw` detect the bundled \
runtimes at all. Credentials land under \$HOME, which the gateway gets as \
/data/duduclaw from duduclaw-firstboot's 20-home.conf drop-in. \
\
NOT EVERYTHING IS IN THE BUNDLE, AND THE GAPS ARE WRITTEN DOWN: \
/opt/duduclaw/runtimes/MANIFEST.txt lists every component with its exact \
source URL, version and sha256, plus a `skipped:` line for each one that \
is not there and why. Kiro CLI is the one deliberate omission this round \
(1039.4 MB uncompressed against ~2.2 GB of total root-slot headroom). It \
gets NO /usr/bin stub on purpose: duduclaw's runtime detection is \
file-existence based, so a stub that exits 127 would still read as \
'installed' in the dashboard and OOBE. The install command lives in the \
platform's runtime catalog (Manual channel, with Kiro's own third-party- \
harness ToS caveat) and lands in \$HOME/.local/bin, which the gateway \
already probes. See docs/guides/ai-runtimes.md."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"

# --- LICENSING -------------------------------------------------------------
# This package is a CARRIER for third-party software with genuinely mixed
# and, in four cases, closed licensing. Stating a single SPDX id here would
# be false, so LICENSE enumerates what is actually inside
# and LIC_FILES_CHKSUM points at files/LICENSE-MANIFEST -- this recipe's
# own per-component licence record, checked into the repo -- rather than at
# a COMMON_LICENSE_DIR copy that would say nothing about this payload.
#
# WHY NOT POINT DIRECTLY AT THE BUNDLE'S OWN LICENSES/ DIRECTORY (the first
# thing tried): the tarball carries `;unpack=0`, so nothing from inside it
# exists under ${S} when do_populate_lic runs -- a
# `file://LICENSES/npm-codex-LICENSE` checksum would reference a path that
# is never created. The upstream texts ARE shipped, on the image, at
# /opt/duduclaw/runtimes/LICENSES/ (the generator copies each npm package's
# own LICENSE out of its tree), and files/LICENSE-MANIFEST is the in-repo
# index of them with the version each statement was read against.
#
#   Apache-2.0   @openai/codex, @google/gemini-cli, mistral-vibe
#   MIT          @moonshot-ai/kimi-code, opencode
#   proprietary  @anthropic-ai/claude-code (Anthropic Commercial ToS -- the
#                package's own `license` field reads "SEE LICENSE IN
#                README.md"), @github/copilot ("SEE LICENSE IN
#                LICENSE.md", GitHub Pre-release/Copilot terms), Grok Build
#                (xAI ToS, closed binary with no license file shipped at
#                all), Cursor `agent` (Anysphere ToS, likewise none)
#   Apache-2.0   @qwen-code/qwen-code -- by the LICENSE file inside the
#                package, NOT by its npm metadata, which publishes no
#                `license` field at all. Checked both, because tooling that
#                reads only the registry sees nothing here.
#
# The four proprietary components are packaged anyway -- that is the
# product decision in the TODO's §1 決策 2, and hiding them would be worse
# than naming them -- but they are named here, in
# docs/guides/ai-runtimes.md, and in MANIFEST.txt, so nobody redistributing
# this image can be surprised by what is in it. LICENSE_FLAGS gates the
# build on an explicit distro-level opt-in for exactly that reason.
LICENSE = "Apache-2.0 & MIT & Proprietary"
LIC_FILES_CHKSUM = "file://LICENSE-MANIFEST;md5=c7dde8f76251a40b53a3b025f839810f"
LICENSE_FLAGS = "duduclaw-ai-runtimes-vendor-terms"

# Native zstd, not the build host's tar: same reasoning as
# duduclaw-flatpak-offline-repo.bb ("don't assume a host tool capability,
# DEPENDS the exact tool" -- `tar --zstd` support varies by tar version).
DEPENDS = "zstd-native"

# Regenerate with gen-ai-runtimes-bundle.sh and bump the date here. The
# tarball itself is gitignored (see .gitignore's own entry, same treatment
# as duduclaw-flatpak-offline-repo's): ~2 GB of third-party binaries does
# not belong in git history, and it is reproducible from the generator plus
# the pinned versions in MANIFEST.txt.
DUDUCLAW_AI_RUNTIMES_DATE ?= "20260905"
SRC_URI = "file://duduclaw-ai-runtimes-${DUDUCLAW_AI_RUNTIMES_DATE}.tar.zst;unpack=0 \
           file://duduclaw-runtime-exec \
           file://LICENSE-MANIFEST \
"
# LICENSE-MANIFEST is in SRC_URI, not just sitting in files/, because
# LIC_FILES_CHKSUM resolves its `file://` entries against ${S} -- a licence
# file that is never unpacked makes do_populate_lic fail with "LIC_FILES_
# CHKSUM points to an invalid file". It is a licence record, not payload,
# so it is deliberately NOT installed into the image (the upstream texts
# ride inside the bundle at /opt/duduclaw/runtimes/LICENSES/ instead).

# SRC_URI_STRICT_CHECKSUMS is deliberately unset, exactly as on
# duduclaw-flatpak-offline-repo: this is a local file:// blob whose whole
# point is "whatever the generator most recently produced", not a byte-
# pinned external download. The per-component sha256s that DO matter (the
# vendor binaries fetched over the network) are recorded inside
# MANIFEST.txt at generation time, where they can be re-verified against
# the upstream URLs later.

S = "${UNPACKDIR}"

# --- QA POSTURE ------------------------------------------------------------
# Byte-for-byte passthrough of prebuilt third-party binaries, same class of
# payload as duduclaw-flatpak-offline-repo and handled with the same skip
# set. Concretely, this bundle contains: Node single-executable-application
# blobs (cursor-agent/node, the claude/copilot/codex platform binaries --
# a SEA appends its payload to the end of a node binary, and ANY strip or
# rewrite invalidates the appended blob's own offsets), static-pie Rust
# binaries (grok), N-API .node addons, and manylinux wheels' .so's. None of
# it was compiled here, none of it can be usefully debug-split, and the
# already-stripped/arch/ldflags/textrel checks are all reporting on
# upstream release-build choices this recipe has no ability to satisfy.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INHIBIT_SYSROOT_STRIP = "1"
INSANE_SKIP:${PN} += "already-stripped arch ldflags textrel build-deps file-rdeps dev-so libdir staticdev split-strip"
# Auto file-dependency scanning would walk ~2 GB of vendor-internal .so's
# and .node addons and manufacture RDEPENDS/RPROVIDES from SONAMEs no
# package manager on this image has any business tracking -- they are
# dlopen'd from inside their own bundle, never linked by anything else on
# the rootfs.
SKIP_FILEDEPS:${PN} = "1"
PRIVATE_LIBS:${PN} = "*"

# Genuinely x86_64-only content (every vendor artifact was fetched by an
# explicit linux-x64 URL; the npm tree resolved its optionalDependencies
# inside a linux/amd64 container). ANCHORED, and the anchors are
# load-bearing: COMPATIBLE_MACHINE is matched with re.match() (start of
# string only) and this layer's real MACHINE values carry the "duduclaw-"
# prefix -- an unanchored "qemux86-64|genericx86-64" does NOT match
# "duduclaw-genericx86-64". That exact mistake cost
# duduclaw-flatpak-offline-repo a failed bake; see its own header.
COMPATIBLE_MACHINE = "^duduclaw-qemux86-64$|^duduclaw-genericx86-64$"
PACKAGE_ARCH = "${MACHINE_ARCH}"

AI_RUNTIMES_DIR = "/opt/duduclaw/runtimes"

# The eleven /usr/bin names -- ten runtimes, because `agent` and
# `cursor-agent` are the same tool and both point at Cursor (its installer
# creates both). No `kiro-cli`: see the DESCRIPTION -- a stub would be
# detected as an installed runtime.
AI_RUNTIME_CLIS = "claude codex gemini qwen kimi copilot grok opencode agent cursor-agent vibe"

do_install() {
    install -d ${D}${AI_RUNTIMES_DIR}
    # --strip-components=1: the tarball's single top-level entry is
    # `duduclaw-ai-runtimes/`, so this lands node_modules/ bin/
    # cursor-agent/ python/ LICENSES/ MANIFEST.txt directly under
    # AI_RUNTIMES_DIR -- the literal prefix files/duduclaw-runtime-exec
    # hardcodes as RT.
    #
    # --no-same-owner: the tarball is built inside a container and a few
    # vendor archives (Cursor's, notably) carry their build machine's own
    # numeric uid/gid -- 2000:2000, an account that does not exist on this
    # image. Without this flag pseudo faithfully reproduces those ids into
    # ${D} and they ship that way. They are not caught by
    # do_package_qa's host-user-contaminated check either, which only looks
    # for the BUILDER's uid, so this would have gone out silently. Under
    # pseudo the flag resolves everything to root:root, which is what every
    # other file in /opt on this image is.
    zstd -dc ${UNPACKDIR}/duduclaw-ai-runtimes-${DUDUCLAW_AI_RUNTIMES_DATE}.tar.zst | \
        tar -xf - --no-same-owner -C ${D}${AI_RUNTIMES_DIR} --strip-components=1

    install -d ${D}${libexecdir}/duduclaw
    install -m 0755 ${UNPACKDIR}/duduclaw-runtime-exec ${D}${libexecdir}/duduclaw/duduclaw-runtime-exec

    # /lib64/ld-linux-x86-64.so.2 (2026-09-06 QEMU walkthrough of the first
    # bake). Every prebuilt vendor ELF in the bundle -- claude's SEA,
    # opencode, Cursor's bundled node (which is what `agent`/`cursor-agent`
    # exec), Copilot's platform binary -- carries PT_INTERP
    # /lib64/ld-linux-x86-64.so.2, the FHS path every glibc x86-64 distro
    # provides. This image is not usrmerge'd and its glibc installs the
    # loader at /lib/ld-linux-x86-64.so.2 only, so all four died with
    # "cannot execute: required file not found" (and Copilot reported it as
    # "no platform package found"). One relative symlink fixes all of them;
    # a live test on the baked image confirmed each answers --version
    # afterwards. Installed by THIS recipe rather than a glibc bbappend
    # because it exists for this payload and nothing else on the image
    # needs it.
    install -d ${D}/lib64
    ln -sf ../lib/ld-linux-x86-64.so.2 ${D}/lib64/ld-linux-x86-64.so.2

    install -d ${D}${bindir}
    for cli in ${AI_RUNTIME_CLIS}; do
        # Relative symlink target: ${libexecdir} is /usr/libexec and
        # ${bindir} is /usr/bin on this distro, so ../libexec/... resolves
        # correctly both in ${D} (where do_package walks it) and on the
        # installed root. The dispatcher reads basename($0), which is
        # preserved through a symlink exec.
        ln -sf ../libexec/duduclaw/duduclaw-runtime-exec ${D}${bindir}/$cli
    done
}

FILES:${PN} += " \
    ${AI_RUNTIMES_DIR} \
    ${libexecdir}/duduclaw/duduclaw-runtime-exec \
    /lib64 \
"

# node: the six npm CLIs' .bin entries are either `#!/usr/bin/env node`
# scripts or ELF binaries that still spawn node for their own workers.
# meta-oe's nodejs_22.23.2 provides both `nodejs` and `nodejs-npm`; only the
# runtime is a hard requirement here (npm is in the image for the user's own
# `npm install`, wired in duduclaw-image-runtimes.inc, not depended on).
#
# python3-core + python3-modules: /usr/bin/vibe execs /usr/bin/python3
# against a pip --target tree resolved for cp314/manylinux. The wheels bring
# their own C extensions but import plenty of stdlib (ssl, sqlite3, asyncio,
# ctypes) -- python3-modules is the umbrella that guarantees those are on
# the image rather than trusting an implicit pull.
#
# bash: files/duduclaw-runtime-exec itself is POSIX sh, but Cursor's shipped
# `cursor-agent` launcher is `#!/usr/bin/env bash` with `set -euo pipefail`.
#
# ca-certificates: every one of these CLIs talks TLS to its vendor API.
# curl: the vendor install scripts the platform's runtime catalog shows for
# components that are NOT in this bundle (Kiro CLI, or a newer Cursor) are
# all `curl -fsSL <url> | bash`; an install hint the image cannot actually
# execute would be no better than the command-not-found it replaces.
RDEPENDS:${PN} += "nodejs python3-core python3-modules bash ca-certificates curl"
