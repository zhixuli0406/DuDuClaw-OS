# Y12 (2026-08-27) — bump Mesa 26.0.5 -> 26.0.8 to fix the masked-gather/
# scatter codegen crash against LLVM 22, WITHOUT touching LLVM (22.1.3 stays
# pinned in openembedded-core/meta/recipes-devtools/clang/common-clang.inc).
#
# Root cause (fully verified by reading source, not guessed — see
# commercial/docs/RESEARCH-mesa-llvm22-gather-fix-2026-08.md): LLVM 22
# dropped the alignment argument from the @llvm.masked.gather/scatter
# intrinsics (4-arg -> 3-arg). LLVM's auto-upgrade only rewrites bitcode/
# textual IR, not in-memory IR built via the C API — and Mesa gallivm's JIT
# (src/gallium/auxiliary/gallivm/lp_bld_gather.c, lp_build_masked_gather()/
# lp_build_masked_scatter()) builds IR via the C API and unconditionally
# emits the old 4-arg call on every LLVM version >= 16. The X86 backend's
# SelectionDAGBuilder then misreads the extra alignment operand as the mask
# and the real mask as the passthru value, producing an illegal DAG node
# that instruction selection can't lower: "Cannot select: ...
# X86ISD::MGATHER<...>" -> report_fatal_error -> SIGABRT. This is what was
# aborting duduclaw-kiosk in an infinite restart loop on both QEMU TCG and
# a real AVX2 GCP nested-KVM VM (confirmed identical crash signature on real
# silicon, so it was never a QEMU/TCG emulation artifact).
#
# Upstream fixed this in Mesa 26.0.7 (2026-05-14, upstream issue #15096,
# "gallivm: fix masked gather/scatter intrinsic calls for LLVM 22+", fix by
# Dave Airlie). We bump to 26.0.8 (2026-05-27) instead of the minimum 26.0.7
# because it's the LAST point release on the 26.0.x stable branch (superseded
# by 26.1.x since), carries two extra weeks of regression soak with no new
# fixes touching gather/scatter, and changes nothing else relevant to
# x86-64/AVX2 codegen — this is pure LLVM-API-compat code, not a tuning knob.
#
# Known residual risk (see research doc §2.4, do not treat as "solved" until
# re-verified live): upstream issue #15489 (a DIFFERENT gallivm/LLVM22 crash,
# in the compute-shader `cs_variant` JIT path rather than our
# `fs_variant_partial` fragment-shader path) is still OPEN against Mesa
# 26.0.6; the only maintainer comment says the fix is "likely" already in
# 26.0.7, with zero follow-up confirmation. If kiosk still aborts after this
# bump but with a NEW crash signature (anything mentioning cs_variant /
# compute shaders), that is #15489 resurfacing, not this fix failing — would
# need 26.1.8 or later, not another 26.0.x point release.
#
# SHA256 cross-checked from THREE independent sources before pinning here
# (host `curl` + container `wget`, two separate network fetches of the same
# archive.mesa3d.org URL, PLUS the official Mesa 26.0.8 release notes at
# docs.mesa3d.org/relnotes/26.0.8.html) — all three agree byte-for-byte.
#
# PE stays at "2" (set in mesa.inc, untouched here — epoch is preserved
# automatically since this bbappend does not override PE).
#
# Deliberately NOT edited in oe-core directly: any upstream oe-core layer
# update would silently revert an in-place edit to mesa.inc. This bbappend
# lives in meta-duduclaw so it survives layer refreshes.
#
# The three existing downstream patches in mesa.inc's SRC_URI
# (mips-clang atomics / freedreno build-path / armhf LLVM22 StringMapIterator)
# are untouched here. They are applied unconditionally at do_patch regardless
# of target machine, so if the armhf-focused
# 0001-gallivm-Fix-armhf-build-against-LLVM-22.patch no longer applies
# cleanly against the 26.0.8 tarball (its upstream fix may already be folded
# into 26.0.7/26.0.8), `bitbake mesa` will fail do_patch with an explicit
# fuzz/reject error — a loud, diagnosable failure, not a silent corruption.

PV = "26.0.8"
SRC_URI[sha256sum] = "caf1c0061a68e88dfa74967a7e780c0e85d65b6c4e334cd69095a5dc54ad78bc"
