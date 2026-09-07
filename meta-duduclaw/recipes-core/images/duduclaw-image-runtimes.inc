# DuDuClaw OS — AI runtime payload (WP-F, 2026-09-05).
#
# The platform repo's docs/todo/TODO-ai-runtimes-2026-09.md §3 WP-F. Shared IMAGE_INSTALL data
# file, same shape as duduclaw-image-desktop.inc / -flatpak.inc /
# -compat.inc: pure IMAGE_INSTALL, no `inherit`, no `require`, no WKS_FILE
# opinion — see duduclaw-image-desktop.inc's own header for why these
# payload sets live in .inc files the image recipes `require` rather than
# being pasted per-recipe.
#
# ── WHY A NEW .inc AND NOT duduclaw-image-desktop.inc ────────────────────
# The TODO offers either. desktop.inc is `require`d by BOTH
# duduclaw-image.bb (the production line) AND duduclaw-image-live.bb (the
# throwaway live-installer environment that becomes the ISO's squashfs).
# Putting ~2 GB of vendor AI runtimes there would land every byte of it in
# the INSTALLER ISO as well — an environment whose entire job is to boot,
# ask three questions, and dd a payload image onto a disk. It has no use
# for `claude` or `llama-server`, and the ISO is a download users wait on.
# A separate .inc, `require`d only by duduclaw-image-appliance.bb (the
# shipping convergence target), puts the payload exactly where the product
# decision put it and nowhere else.
#
# ── ROOT SLOT BUDGET — read this before adding anything here ─────────────
# This file is, by a wide margin, the heaviest .inc in the layer. Measured
# on the 2026-09-05 bundle generation run (see
# recipes-duduclaw/duduclaw-ai-runtimes/gen-ai-runtimes-bundle-2026-09-05.log
# for the primary numbers, not a recollection of them):
#
#   duduclaw-ai-runtimes   1.9 GB unpacked  (606 MB as a .tar.zst)
#     node_modules  1.2 GB   bin  335 MB   cursor-agent  252 MB   python  159 MB
#   nodejs + nodejs-npm    ~90 MB
#   llama-cpp              two statically linked binaries
#
# duduclaw-image-appliance.bb raised DUDUCLAW_AB_SLOT_SIZE_MB from 7168 to
# 8192 in the same commit for exactly this payload, and 8192 is a CEILING,
# not a step on a ladder: it equals crates/duduclaw-gateway/src/
# os_update.rs's MAX_ROOT_BYTES, which is being raised to 9 GiB in the same
# wave (WP-B) and cannot usefully go further without redesigning the
# update transfer. There is no room for a second payload of this size.
# Anything added here from now on needs a measured before/after, and the
# generator already carries two documented omissions made on precisely
# these grounds (Kiro CLI, Cursor's two SEA blobs).

# --- Node.js (TODO §2: "meta-oe 有 nodejs_22.23.2（含 nodejs-npm）但映像沒裝") -
# nodejs: the runtime six of the ten bundled CLIs execute under. Package
# name and version verified against this kas config's own pinned
# meta-openembedded checkout, not guessed:
# meta-oe/recipes-devtools/nodejs/nodejs_22.23.2.bb, which splits out
# `nodejs-npm` as its own package.
#
# nodejs-npm: NOT required by duduclaw-ai-runtimes (its tree is
# pre-resolved; nothing on the appliance runs `npm install` to make the
# bundled CLIs work). It ships because the user-facing story needs it —
# `npm install -g` is how a user adds a runtime this bundle does not carry
# (Kiro CLI's on-demand path, a newer Claude Code than the baked one, an
# MCP server distributed on npm), and an appliance that ships node without
# npm turns every one of those into "reflash the image". Listed with that
# reason attached so a future size squeeze knows what it is dropping.
IMAGE_INSTALL:append = " nodejs nodejs-npm"

# --- The bundle itself ---------------------------------------------------
# Eleven /usr/bin entry points onto /opt/duduclaw/runtimes, all backed by
# real payload. Kiro CLI is not among them and gets no stub either (1039 MB;
# a stub would read as "installed" to duduclaw's file-existence detection --
# see the recipe header and MANIFEST.txt). The recipe sets
# LICENSE_FLAGS = "duduclaw-ai-runtimes-vendor-terms" — conf/distro/
# duduclaw-os.conf accepts it explicitly, which is the point: four of the
# components are proprietary or licence-unstated, and this image says so
# in configuration rather than absorbing it silently.
IMAGE_INSTALL:append = " duduclaw-ai-runtimes"

# --- Local inference (TODO §1 決策 3A) -----------------------------------
# llama-cpp ships llama-server + llama-cli; duduclaw-llama-server ships the
# systemd unit that runs the former against /data/duduclaw/models. NO MODEL
# WEIGHTS ARE IN THIS IMAGE and that is the design: a curated GGUF is
# 1-5 GB, the root slot has none of that to spare, and weights belong on
# the durable partition that survives an OS update anyway. The unit
# condition-fails cleanly until the gateway's inference.local.download RPC
# puts a model there — an appliance that only uses cloud runtimes shows it
# as inactive (condition), never as a failed restart loop.
#
# The shipped llama-server is a CPU build, not the Vulkan build the design
# doc names. That gap is real, is this round's, and is written up in
# recipes-ai/llama-cpp/llama-cpp_0.4.0.bb's own PACKAGECONFIG comment plus
# docs/guides/ai-runtimes.md — not papered over here.
IMAGE_INSTALL:append = " llama-cpp duduclaw-llama-server"
