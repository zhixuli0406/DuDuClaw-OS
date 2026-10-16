# Maintenance SSH image acceptance — 2026-10-17

Status: PARTIAL / NO-GO for merge. No image build or new boot acceptance has run in this continuation.

The owner authorized GCP resources, actual image installation, acceptance and merge of OS PR #26 after its gates pass. This is not release authorization. Do not publish or sign an image as part of this task.

## Source baseline

- OS #26: `69033fc82c799f8070a4062cee58e3713639fe57`, based on #25 (`feat/maint-account`).
- Integration branch: `feat/maint-ssh-ready-20261017`, created from fetched `origin/main` (`77da682`). It includes #25, #27 and #28, then #26's reviewed fallback-path repair. All precursor heads remain separately traceable.
- Platform source selected for synchronization: `c7068c508ae9ab5afc4392b58237cf86afdb9f2c` (1.74.0), the exact reviewed and CI-tested maintenance dashboard head. This commit is included in platform main.
- Final integration SHA, generated snapshots, layer SHAs, builder image digest and artifact hashes: pending source freeze. A version string alone is not a source identity.

## Blockers

| ID | Type | Evidence / completion condition | Status |
|---|---|---|---|
| OS26-GCP | External environment | The configured deployment SA cannot list Compute instances in the configured GCP project. Obtain an already-authorized Compute SA or owner-managed IAM configuration; never change IAM or switch identity to evade a refusal. | BLOCKED_ENV |
| OS26-SOURCE | Integration | Pure #26 still embeds platform 1.73.4 and lacks maintenance tools/readiness. Generate snapshots through the supported refresh scripts, install the tools/helper units/marker, verify dependency closure, then freeze the full candidate. | IN_PROGRESS |
| OS26-BUILD | Build | Actual kas builds of base and desktop disk images plus both installer ISOs; rootfs and kernel assertions pass. Keep logs, exit codes, layer identities, manifests and SHA-256. | OPEN |
| OS26-BOOT | Platform | Actual cold boot and reboot of both editions; persistent host fingerprint and effective unit/firewall settings verified. | OPEN |
| OS26-INSTALL | Formal flow | Boot each production installer ISO, identify a newly created blank target disk, execute the shipped installer, remove ISO and boot the installed disk. Check ESP/A/B/data and first-boot behavior. | OPEN |
| OS26-GCE | Cloud installation | Import a source-bound installed disk and boot it as a dedicated GCE guest if supported. GCP-hosted QEMU installation is separate evidence and must not be described as native GCE boot. | OPEN |
| OS26-SSH | Formal flow / security | Actual Admin open, maintenance-key login, menu/log filtering, forbidden identities/passwords/forwarding/commands, close and independent deadline/crash paths, audit and source-address controls. | OPEN |
| OS26-RESET-ORDER | Correctness / privacy | Independent review found factory reset was not ordered before sysd state replay or host-key generation. Add ordering only, preserve failure behavior and prove graph regression; verify actual boot later. | FIXED_PENDING_VERIFY |
| OS26-READY-GATE | Acceptance gate | Require exact executable/marker modes and exact marker bytes; existing relaxed fixtures accepted unsafe variants. Exact modes/bytes regressions and independent static recheck passed; actual guest remains pending. | FIXED_PENDING_VERIFY |
| OS26-CHECKER | Independent review | Review actual candidate diff, harness and evidence. No unresolved blocking findings; required checks pass on the final head. | OPEN |
| OS26-MERGE | Integration | Merge prerequisites in order and #26 only after its source-bound build/boot/install/behavior evidence and independent review pass. An integration candidate's result does not retroactively identify a different standalone image. | OPEN |

## Acceptance contracts

1. Build and boot are different gates. `release-os.sh smoke` reaching `login:` does not prove installation or SSH behavior.
2. Test-login images are never shipping artifacts. Root inspection in a test variant is recorded separately from real installation of the shipping ISO.
3. The shipping maintenance RPC accepts whole hours, with a minimum of one hour. Prove that actual deadline, or clearly label a shorter independent sysd harness; editing a gateway database timestamp does not prove sysd's own monotonic deadline.
4. A slirp host forward rewrites the peer source. Validate LAN/CGNAT/global-address rules with preserved-source netns/veth/tap traffic. Real external IPv6 reachability remains separately identified.
5. Fallback close must remove key/session/port but preserve its persistent window for sysd replay. Normal close and fallback have different state assertions.
6. A single `kill -9` restart and `systemctl stop` are separate cases. A manually invoked fallback script is not evidence that the pre-existing timer fired.
7. Verify existing sessions have ended, not just that new connections fail. Verify the gateway process actually restarted, not just that a helper accepted a request.
8. No production provider credentials or signing keys enter the builder/guest. Test Admin credentials and SSH keys belong only to the disposable acceptance environment and must be redacted from evidence.

## Execution plan — not yet run

Use the existing GCP/kas builder convention and `release-linux-builder.yml`, one build at a time. Name every log uniquely and wait for the previous BitBake process to exit before another build. Do not use the kas file's default flatpak target accidentally.

```sh
export DUDUCLAW_OS_KAS_OVERLAY=meta-duduclaw/kas/release-linux-builder.yml
scripts/release-os.sh build --machine duduclaw-qemux86-64 --image duduclaw-image-ab
scripts/release-os.sh build --machine duduclaw-qemux86-64 --image duduclaw-image-appliance
scripts/release-os.sh build --machine duduclaw-qemux86-64 --image duduclaw-image-live
scripts/release-os.sh build --machine duduclaw-qemux86-64 --image duduclaw-image-live-desktop
```

Copy immutable deploy artifacts into a per-run scratch directory. Never boot QEMU on the deploy original. Create a new 48 GiB target for installation, record its identity and blank partition table, then invoke the actual installer inside the live guest:

```sh
lsblk -o NAME,SIZE,TYPE,RO,MOUNTPOINTS
DUDUCLAW_INSTALL_TARGET=vda DUDUCLAW_INSTALL_YES=1 duduclaw-os-install
sync
```

The two installation variables are destructive and may be used only after confirming `vda` is the newly created acceptance disk. Remove the ISO before the verification boot.

Native GCE image import is a separate, initially unverified path. Use a dedicated disposable image/VM/disk without a service account or provider secrets. Preserve the production partition layout and source hashes; record any cloud-specific adaptation as its own diff and artifact. An inaccessible guest, an import success, or a serial login prompt alone is not installation acceptance.

## Evidence and cleanup

Keep raw build/serial/journal/RPC output, source manifests, artifact hashes and per-case results under ignored `artifacts/`. Only sanitized technical results belong in `wiki/`; account keys, credentials, infrastructure inventory and cost estimates stay out of the public tree.

Record every resource created by this run. After exporting evidence, stop its QEMU processes and delete only its own VMs, disks, custom images and temporary objects. Verify deletion through the API; stopping a VM does not remove disk charges. If cleanup is blocked, report the exact resource and outstanding action. Do not delete an existing cache or builder merely because an old runbook names it.

## Current environment evidence

2026-10-17 Asia/Taipei: `gcloud auth list` shows the configured deployment SA active. the configured-project Compute instance inventory command returned a warning that `compute.instances.list` is required; its process exit code was zero, so the warning must not be treated as an empty successful inventory. No Compute resources were created, modified or deleted.

The owner has been asked for a provisioned Compute-capable SA key path or confirmation of owner-managed permission configuration. Local candidate preparation continues independently.

## Local preparation evidence

- Primary ran the new guest validator suite: 9 passed; readiness fixture suite: 6 passed, before review-driven hardening (new final counts pending). These are synthetic host fixtures, not guest acceptance.
- Reset ordering graph regression on the repair branch: original source 2 fail / 2 pass; repaired source 4 pass. This is a structural regression, not a real boot.
- Existing pinned Cargo class installs all produced executables; pinned BitBake DataSmart concatenates repeated `do_install:append` functions. These local checks do not replace actual recipe compilation or package QA.
- Offline runtime/Flatpak input archive sizes and SHA-256 recorded in ignored artifacts; no copies or credentials sent to GCP.

Final local hardening: primary and independent checker each ran 10 guest validator tests and 7 readiness fixture tests, all passed. Exact marker bytes and special permission bits are covered. Reset repair is committed as `27ee4651815f97f32203e6391499d58e52e3a2fd` on PR #26, with four graph regressions and independent static review passed. No kas/guest evidence is implied.

Snapshot whitespace note: the generated upstream dashboard asset `assets/index-DY5iy7OB.js` contains trailing whitespace inside a template-literal message. The full staged diff whitespace check reports it. Preserve byte identity with the tested platform dist; do not hand-edit a generated snapshot. Whitespace validation for authored source excludes only this generated dist tree; full snapshot equality is checked independently.
