SUMMARY = "llama.cpp -- llama-server / llama-cli, local GGUF inference for the appliance"
DESCRIPTION = "${SUMMARY}. WP-F of the platform repo's docs/todo/TODO-ai-runtimes-2026-09.md \
(§1 決策 3A: '映像內建 llama.cpp llama-server（MIT、Vulkan）；模型權重不進映像'). \
The image ships the engine; GGUF weights are downloaded at runtime by the \
dashboard/OOBE into /data/duduclaw/models and served by \
duduclaw-llama-server.service (recipes-duduclaw/duduclaw-llama-server/). \
Only llama-server and llama-cli are installed -- see do_install:append for \
what upstream's own install step produces and why the rest is dropped. \
\
No existing recipe was reused because there is none: checked \
openembedded-core, meta-openembedded and meta-virtualization at this kas \
config's pinned revisions (find -iname '*llama*' across all three: zero \
hits) before writing one from scratch."
HOMEPAGE = "https://github.com/ggml-org/llama.cpp"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=223b26b3c1143120c87e2b13111d3e99"

# v0.4.0 -- the newest SEMVER tag as of 2026-09-05, resolved through the
# GitHub API (repos/ggml-org/llama.cpp/releases + /tags), not guessed.
# Upstream publishes TWO kinds of tag: rolling per-CI build tags (b10819,
# b10818, ... several a day) and, newly, semver releases. v0.4.0's own tag
# commit is "llama.cpp : bump version to 0.4.0 (#28386)" (2026-09-04), and
# a versioned release is the right thing for a pinned appliance recipe --
# a b#### tag would encode "whichever CI build we happened to bake on".
SRCREV = "5266f24da75dc449bd56cbed7addb9c8e4a6a73e"
SRC_URI = "git://github.com/ggml-org/llama.cpp.git;protocol=https;nobranch=1"

# nobranch=1: release tags on this repo are not always reachable from the
# branch tip; same escape hatch, and same reason, as recipes-security/
# gitleaks' own SRC_URI comment. No `S = "${WORKDIR}/git"` assignment --
# wrynose's do_unpack hard-errors on that idiom (bitbake.conf sets the git
# default itself; live bake error 2026-09-01, recorded in gitleaks' header).

inherit cmake pkgconfig

# openssl: LLAMA_OPENSSL defaults ON at this tag (top-level CMakeLists) and
# llama-server's HTTPS/model-download path links it. Listed rather than
# switched off -- the server is reachable from the dashboard over
# 127.0.0.1 today, but the same binary is what a future TLS-terminated
# deployment would use, and openssl is already on this image.
DEPENDS = "openssl"

# --- Vulkan: PACKAGECONFIG, defaulted OFF for this build, deliberately ----
#
# The design decision (TODO §1 決策 3A) is Vulkan, and every knob it needs
# is wired below. It is NOT enabled in this round's default build, and the
# reason is a cross-compilation fact, not a preference:
#
# ggml/src/ggml-vulkan/CMakeLists.txt builds `vulkan-shaders-gen` as a HOST
# tool through ExternalProject_Add and then RUNS it during do_compile to
# generate the SPIR-V for several thousand shader variants. When
# CMAKE_CROSSCOMPILING is true (always, here: this layer's builder is
# aarch64 and MACHINE is x86-64) it auto-detects a host compiler and
# synthesises its own toolchain file -- reaching outside the recipe's
# sysroot for a compiler bitbake did not provide, which is exactly the kind
# of build-host leak do_package_qa's buildpaths check exists to catch, and
# the kind of thing that builds on one machine and not the next.
# GGML_VULKAN_SHADERS_GEN_TOOLCHAIN is the documented override for that,
# and PACKAGECONFIG[vulkan] below passes it -- but making it correct needs
# a generated toolchain file pointing at OE's own -native toolchain plus a
# verified run, and the honest state today is that this has NOT been built
# and booted. On top of that, the SPIR-V generation itself is thousands of
# glslc invocations on a 4-core aarch64 builder.
#
# What ships instead this round: a CPU build with the distro's own
# x86-64-v3 tune (AVX2/FMA/BMI2 -- see conf/machine/duduclaw-genericx86-64
# .conf's DEFAULTTUNE), which is the level llama.cpp's own CPU backend gets
# most of its throughput from anyway on this class of machine (N305 /
# 8845HS integrated graphics, where the Vulkan win over an AVX2 CPU path is
# real but not order-of-magnitude). This is a stated gap, tracked in
# docs/guides/ai-runtimes.md, not a silent substitution: anyone reading
# "Vulkan" in the design doc must be able to find out from this file that
# the shipped binary does not have it.
#
# To turn it on: PACKAGECONFIG:append = " vulkan" (plus the toolchain-file
# work above), then verify with `llama-server --list-devices` on real
# hardware -- a Vulkan build that silently falls back to CPU at runtime
# looks identical to this one from the outside, which is precisely why it
# needs a live check rather than a green bitbake.
PACKAGECONFIG ??= ""
PACKAGECONFIG[vulkan] = "-DGGML_VULKAN=ON -DVulkan_GLSLC_EXECUTABLE=${STAGING_BINDIR_NATIVE}/glslc,-DGGML_VULKAN=OFF,shaderc-native vulkan-headers vulkan-loader"

EXTRA_OECMAKE = " \
    -DGGML_NATIVE=OFF \
    -DGGML_BACKEND_DL=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLAMA_BUILD_SERVER=ON \
    -DLLAMA_BUILD_TOOLS=ON \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_APP=OFF \
    -DLLAMA_ALL_WARNINGS=OFF \
"

# -DGGML_NATIVE=OFF is mandatory, not tidiness: ggml's default ON runs
# -march=native probes against the BUILD machine (aarch64 here), which
# either fails outright or -- worse on an x86-64 builder -- bakes in
# instructions the target may not have. With it off, ggml takes its ISA
# level from the compiler flags OE already passes, i.e. this distro's own
# x86-64-v3 tune. Nothing extra needs to be appended for AVX2/FMA/BMI2:
# that IS x86-64-v3 (conf/machine/duduclaw-genericx86-64.conf sets
# DEFAULTTUNE = "x86-64-v3" and documents why, and duduclaw-qemux86-64
# already used that tune).
#
# -DBUILD_SHARED_LIBS=OFF: static-links libllama/libggml* into the two
# binaries. The alternative ships unversioned libllama.so/libggml*.so into
# ${libdir}, which trips OE's dev-so QA (an unversioned .so belongs in
# -dev) and would need either a QA skip or a hand-written PACKAGES split,
# for no benefit -- nothing else on this image links llama.
#
# -DGGML_BACKEND_DL=OFF: keep the backend compiled in rather than dlopen'd
# from a .so at runtime. Same reasoning as above plus one more: a dlopen'd
# backend that fails to load degrades silently to CPU, and this image has
# no operator watching a log.

do_install:append() {
    # Upstream's install step lays down every tool it built
    # (llama-quantize, llama-perplexity, llama-imatrix, llama-tokenize,
    # llama-gguf-split, ...). This image needs exactly two: llama-server
    # (what duduclaw-llama-server.service runs) and llama-cli (the manual
    # smoke test a human uses over serial to prove a model loads at all).
    # The rest are model-authoring tools that belong on a workstation, and
    # each one costs multiple MB of statically linked ggml in an 8192 MiB
    # root slot. Removed here rather than switched off at configure time
    # because LLAMA_BUILD_TOOLS is all-or-nothing.
    for f in ${D}${bindir}/*; do
        case "$(basename $f)" in
            llama-server|llama-cli) ;;
            *) rm -rf "$f" ;;
        esac
    done
    # Static build: nothing under ${libdir} is loaded at runtime, and the
    # headers/cmake package files are for building AGAINST llama, which
    # this appliance never does.
    rm -rf ${D}${libdir} ${D}${includedir}
}

FILES:${PN} = "${bindir}/llama-server ${bindir}/llama-cli"

# Only meaningful on the x86-64 machines this layer defines -- the tune
# argument above is x86-specific and the binaries are large. ANCHORED
# (COMPATIBLE_MACHINE is matched with re.match(), and this layer's MACHINE
# values carry the "duduclaw-" prefix; an unanchored alternation silently
# matches nothing -- the failure duduclaw-flatpak-offline-repo.bb's own
# header records).
COMPATIBLE_MACHINE = "^duduclaw-qemux86-64$|^duduclaw-genericx86-64$"
