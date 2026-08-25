# Y1-2 placeholder — duduclaw-sysd cargo recipe

Not implemented yet. Task's "第二里程（時間允許才做）" — deferred until the
Y1-1 base image (this directory's sibling under `recipes-core/images/`)
actually boots to a login prompt under QEMU; a Rust recipe added on top of
an unverified base wouldn't count as done under this project's
verify-before-claiming convention.

## What Y1-2 needs (not started)

- `meta-rust` layer (or oe-core's own Rust support — needs checking against
  the pinned Yocto 6.0 commit; `cargo-bitbake` is reportedly abandoned
  upstream per `research/native-os-2026-08/base-os-routes-2026-08.md` §3.1,
  so a recipe likely needs to be hand-written rather than generated).
- A recipe for `duduclaw-sysd` specifically (smallest of the five
  `duduclaw-*` binaries, per the task's own suggestion for "minimal" first
  target) pointing `SRC_URI` at the workspace source
  (`crates/duduclaw-sysd/`) — needs a decision on whether this recipe
  vendors crates.io deps offline (`cargo-package`-style, matches the "自組"
  route's approach in the base-route research) or fetches at build time
  (network-dependent, worse for reproducibility).
- A systemd unit + `IMAGE_INSTALL:append` wiring into
  `duduclaw-image-minimal.bb` (or a new `duduclaw-image-y1-2.bb` on top of
  it, to keep the Y1-1 image recipe's verified-minimal contract intact)
  so the binary actually starts on boot — the task's actual bar is "開機自
  啟", not just "builds".
