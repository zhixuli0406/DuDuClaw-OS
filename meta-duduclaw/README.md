# meta-duduclaw — DuDuClaw OS Yocto layer

DuDuClaw OS's product layer: distro policy, machine definitions, and (from
Y1-2 onward) recipes for the five `duduclaw-*` Rust binaries. Lives in the
**main repo root** — not a separate repo, not under `commercial/` — per
[`commercial/docs/MAP-agent-native-os-2026-08.md`](../commercial/docs/MAP-agent-native-os-2026-08.md)
decision ⑥ "同版同發＝單 repo＋OS 進主版本流".

This is the **base-OS bring-up line** (Yocto), replacing the Debian
`appliance/` line for the eventual product image. `appliance/` is frozen
(map decision ⑤) as a reference/transition artifact — do not edit it as
part of this line's work.

## Target release

Yocto Project **6.0 "wrynose"**, current LTS as of 2026-08 (supported to
2028-04). Its own default kernel is already **Linux 6.18** — the exact LTS
`research/native-os-2026-08/kernel-self-maintain-2026-08.md` independently
recommended, so bring-up needed no separate kernel-version fight.

## Why three repos, not one "poky" checkout

A real dead end hit during Y1-1 bring-up, worth reading before touching the
pin in `kas/duduclaw-os.yml`: `git.yoctoproject.org/poky` has tags shaped
like `edison-6.0.2`, but `edison` is poky's own internal release-counter
codename from a completely unrelated ~2012-era release — checking it out
and grepping it found zero `uki.bbclass`, zero wic tooling, and the wrong
`meta-yocto` layout, all because the checkout was 14 years stale, not
because Yocto 6.0 lacks these features. No `wrynose-*` tag exists on that
repo at all.

The real release artifacts, per
`https://downloads.yoctoproject.org/releases/yocto/yocto-6.0.2/`, are three
separate repos pinned to exact commits (see `kas/duduclaw-os.yml` header
comment for the full citation trail):

| repo | url | pinned commit |
|---|---|---|
| bitbake | `git.openembedded.org/bitbake` | `acfe02fa38b5da9e6a36c6cedcf91d4fcbefbfbd` |
| openembedded-core | `git.openembedded.org/openembedded-core` | `5d1aa5c806c061a2994f4decb59016610f093213` |
| meta-yocto | `git.yoctoproject.org/meta-yocto` | `24c24cef5d1523fefe43a3e3d34667b37ae551f3` |

`meta-yocto` still contains `meta-poky/` and `meta-yocto-bsp/` as
subdirectories — same two layers Yocto has shipped for years, just no
longer bundled into a "poky" super-repo for this release.

## Why kas

Task called for "kas 或 repo 管理設定（選最簡）". kas wins: one declarative
YAML pins every upstream repo's exact commit, declares the layer set, and
carries build-time local.conf lines — no hand-maintained `bblayers.conf`,
no `oe-init-build-env` ritual to remember per shell. `kas checkout` /
`kas build` / `kas shell` are the only three commands anyone needs.

## Layer layout

```
meta-duduclaw/
├── conf/
│   ├── layer.conf
│   ├── distro/duduclaw-os.conf          # INIT_MANAGER=systemd, EFI+systemd-boot
│   └── machine/
│       ├── duduclaw-qemux86-64.conf     # QEMU dev/test machine (Y1-1 verified)
│       └── duduclaw-genericx86-64.conf  # real-HW target (N305/8845HS), DEFAULTTUNE
│                                         # pinned to x86-64-v3 (Y2-3), KMACHINE=
│                                         # common-pc-64, kernel fragments applied
├── recipes-core/images/
│   ├── duduclaw-image-minimal.bb        # console-only bring-up image, UKI+systemd-boot
│   ├── duduclaw-image.bb                # + duduclaw-sysd/duduclaw-cli/duduclaw-comp/
│   │                                     # duduclaw-shell payload — "開機即殼" (Y3-1/Y4-0):
│   │                                     # qemux86-64 boots straight into duduclaw-kiosk.
│   │                                     # service (comp+shell), real DRM/udev backend,
│   │                                     # real Wayland socket in /run/duduclaw-kiosk/
│   │                                     # (Y4-0 QEMU-verified after the libegl-mesa fix
│   │                                     # below — before that fix, comp always panicked
│   │                                     # on missing libEGL.so.1 and the kiosk service
│   │                                     # crash-looped to a permanent StartLimitBurst
│   │                                     # failure)
│   └── duduclaw-image-flatpak.bb        # + flatpak/bubblewrap/ostree/polkit chain (Y3-2,
│                                         # Y4-0 PASS: duduclaw-flatpak-kiosk-verify.service
│                                         # OVERALL PASS — real Flathub install of Chromium
│                                         # + 6 runtimes, --kiosk --dump-dom against the
│                                         # real gateway dashboard returns real DOM content)
├── recipes-kernel/linux/
│   ├── linux-yocto_6.18.bbappend        # COMPATIBLE_MACHINE alias fix (both machines)
│   └── linux-yocto/                     # duduclaw-{n305,8845hs,gaming}.cfg driver
│                                         # fragments, real-HW only, Y2-2 written / Y2-3
│                                         # build-verified via kernel_configme
├── recipes-duduclaw/                    # all five duduclaw-* binaries now build-verified:
│                                         # duduclaw-sysd/duduclaw-cli (Y2-1/Y2-3),
│                                         # duduclaw-comp/duduclaw-shell (Y4-0, first-ever
│                                         # successful build — see duduclaw-shell's own
│                                         # gen-git-manifests.sh header comment for the
│                                         # zed-monorepo workspace-inheritance fix this
│                                         # needed). duduclaw-cli-worker still has no
│                                         # recipe (zero work done on it).
├── kas/
│   ├── duduclaw-os.yml                  # build config — start here (qemux86-64)
│   └── duduclaw-os-genericx86-64.yml    # overlay for the real-HW machine (Y2-2/Y2-3)
├── docker/Dockerfile.yocto-builder      # Linux build container for macOS hosts
└── scripts/                             # (reserved)
```

## UKI 接通紀錄 (how the UKI + systemd-boot chain was actually verified)

`uki.bbclass` (`meta/classes-recipe/uki.bbclass` at the pinned oe-core
commit) is real and current — its own header comment documents the exact
distro/machine/image config needed. The config in this layer is lifted
**verbatim** from oe-core's own CI selftest for this precise scenario
(`meta/lib/oeqa/selftest/cases/uki.py::UkiTest.test_uki_boot_systemd`,
`core-image-minimal` + UEFI/OVMF + systemd-boot + QEMU x86_64), not guessed:

- Distro (`duduclaw-os.conf`): `INIT_MANAGER = "systemd"`,
  `EFI_PROVIDER = "systemd-boot"`,
  `PREFERRED_PROVIDER_virtual/bootloader = "systemd-boot"`.
- Machine (`duduclaw-qemux86-64.conf`): `MACHINE_FEATURES:append = " efi"`
  (qemux86-64's stock feature set is just `"x86 pci"` — efi is not on by
  default), `QB_KERNEL_ROOT = ""`, `QB_DEFAULT_KERNEL = "none"` (the kernel
  lives inside the signed UKI, not loaded separately by runqemu),
  `QEMU_USE_KVM = ""` (the selftest itself disables KVM with the comment
  "breaks boot" — moot here anyway since the Apple Silicon Docker Desktop
  host has no x86 KVM to offer).
- Image (`duduclaw-image-minimal.bb`): `require core-image-minimal.bb`,
  `IMAGE_FSTYPES:append = " wic"`, `WKS_FILE = "efi-uki-bootdisk.wks.in"`
  (found at `meta/files/wic/efi-uki-bootdisk.wks.in` — not `meta/wic/`,
  another path that moved since older Yocto docs/tutorials were written),
  `INITRAMFS_IMAGE = "core-image-minimal-initramfs"`,
  `IMAGE_CLASSES:append = " uki"`, `UKI_CMDLINE = "rootwait root=LABEL=root
  console=${KERNEL_CONSOLE}"`.

### COMPATIBLE_MACHINE alias gotcha

`linux-yocto_6.18.bb` hardcodes `COMPATIBLE_MACHINE` as a single anchored
regex literal listing exact upstream qemu machine names
(`^(qemuarm|...|qemux86-64|...)$`) — a custom machine name like
`duduclaw-qemux86-64` fails that regex even though it `require`s
`qemux86-64.conf`, because the check is a textual `MACHINE` match, not
something that flows through the require chain. First `bitbake -e
duduclaw-image-minimal` failed with "Nothing PROVIDES 'virtual/kernel'"
until `recipes-kernel/linux/linux-yocto_6.18.bbappend` extended the regex
via `COMPATIBLE_MACHINE:append = "|^duduclaw-qemux86-64$"`. The equivalent
fix for `duduclaw-genericx86-64` (real hardware) is **not yet done** — real
hardware doesn't use `linux-yocto_6.18.bb`'s qemu-only compat list at all,
it needs its own kernel provider story; tracked in
`commercial/docs/TODO-agent-first-os-2026-08.md` Y1 row.

**Getting past COMPATIBLE_MACHINE is not sufficient on its own** — once the
recipe accepts the machine, `kernel-yocto.bbclass`'s BSP-definition lookup
uses a *separate* variable, `KMACHINE` (defaults to `${MACHINE}`), and fails
with "Could not locate BSP definition for duduclaw-qemux86-64/standard" if
left unset. Fix: `KMACHINE = "qemux86-64"` in `duduclaw-qemux86-64.conf`,
reusing the upstream BSP metadata verbatim — this is the standard mechanism
for aliasing a custom machine name to an existing kernel BSP, not a hack.

## 磁碟策略 (disk strategy)

Two disk constraints collided during bring-up, both host-specific to this
macOS/Apple-Silicon dev machine, not anything the layer itself assumes:

1. **Docker Desktop's own VM disk is small.** `docker run --rm alpine df -h`
   showed only ~17GB free inside the VM's own ~58GB virtual disk at
   bring-up time — far short of the 50-100GB a cold Yocto build can eat.
   Fix: bind-mount the big directories (`DL_DIR`, `SSTATE_DIR`, `TMPDIR`)
   from the HOST filesystem instead of leaving them on the container's own
   layer — bind mounts don't consume the VM's own disk quota, only the
   host's. This repo's `appliance/` line already established this pattern
   (`Dockerfile.mkosi-runner` + `-v host:container` in `build.sh`); this
   layer follows the same convention.

2. **TMPDIR must be on a case-sensitive filesystem, and macOS APFS bind
   mounts default to case-insensitive.** `bitbake -e` failed with `"The
   TMPDIR (...) can't be on a case-insensitive file system"` the first time
   the cache dir was bind-mounted from a normal `appliance/.yocto-cache/`
   path. Fix: created a dedicated case-sensitive APFS volume sharing the
   same container's free-space pool (no fixed-size partition, no data
   copy):
   ```
   diskutil apfs addVolume disk3 "Case-sensitive APFS" DuDuClawYoctoCache
   ```
   mounted automatically at `/Volumes/DuDuClawYoctoCache`, bind-mounted
   into the builder container at `/yocto-cache`. This is the same class of
   trap as the `target/` APFS case-sensitivity issue previously hit on
   Rust builds on this machine — same fix shape, different mount point.
   The volume can be deleted with `diskutil apfs deleteVolume
   DuDuClawYoctoCache` if reclaiming it is ever needed; it shares disk3's
   free pool so it costs nothing while empty.

3. **bitbake refuses to run as root.** OE-core's sanity checker hard-fails
   with "Do not use Bitbake as root" — the builder Dockerfile creates a
   non-root `yocto` user (uid 1000) and `USER yocto` for exactly this
   reason; run `docker exec -u 1000 ...` (or rely on the Dockerfile's
   default `USER yocto`) rather than the container's default root shell.
   **Corollary that actually bit us**: if you patch a *running* container
   with `useradd` instead of rebuilding the image, the fix evaporates the
   next time the container is recreated — `/etc/passwd` has no entry for
   uid 1000, so `docker exec -u 1000` silently resolves its group to
   `gid=0(root)`, which collides with kernel headers' intentional
   `root:root` ownership and trips bitbake's `do_package_qa`
   `host-user-contaminated` check as a false positive, failing the whole
   build. Always `docker build` the image after editing the Dockerfile;
   verify with `docker exec -u 1000 <container> id` — it must print
   `uid=1000(yocto) gid=1000(yocto)`, not `gid=0(root)`.

4. **TMPDIR on a virtiofs bind mount can silently corrupt writes under
   concurrent workers.** Two different native recipes
   (`texinfo-dummy-native`, then `quilt-native`→`gnu-config-native`) each
   failed with a downstream consumer getting "No such file or directory"
   reading a file an *earlier* task had already reported as successfully
   populated — a write-then-read visibility gap. Retrying the exact failed
   task in isolation passed immediately; lowering `PARALLEL_MAKE`/
   `BB_NUMBER_THREADS` did **not** stop a second, different recipe from
   hitting the same class of failure on the next attempt, ruling out "just
   a parallelism race." Fix: put TMPDIR on a **Docker named volume**
   (backed by the Docker Desktop VM's own native filesystem, no virtiofs
   translation) instead of the case-sensitive APFS bind mount — `DL_DIR`/
   `SSTATE_DIR` stay on the host bind mount (fetch-once / populate-then-
   read-much-later access patterns never hit this). Trade-off: the Docker
   Desktop VM's own disk is much smaller than the host's (~59GB vs.
   hundreds of GB) — see "建置耗時與磁碟實耗" in the TODO doc for how tight
   this got and how it was managed (periodic `rm -rf` of TMPDIR, relying on
   SSTATE_DIR for fast catch-up — a standard, sanctioned Yocto pattern for
   disk-constrained build agents, not a hack).

## Usage

Build the Linux build container (macOS has no native bitbake support —
pseudo/fakeroot and various build steps assume Linux syscalls):

```bash
docker build --platform linux/arm64 \
    -f meta-duduclaw/docker/Dockerfile.yocto-builder \
    -t duduclaw-yocto-builder \
    meta-duduclaw/docker
```

Start a long-lived builder container, bind-mounting the repo, a
case-sensitive cache volume for DL_DIR/SSTATE_DIR (create one per "磁碟策略"
point 2 above if you don't have one yet), and a Docker named volume for
TMPDIR (point 4 — created once with `docker volume create
duduclaw-yocto-tmpdir`, no extra setup needed after that):

```bash
docker run -d --name duduclaw-yocto --platform linux/arm64 \
    -v "$(git rev-parse --show-toplevel)":/workspace \
    -v /Volumes/DuDuClawYoctoCache:/yocto-cache \
    -v duduclaw-yocto-tmpdir:/yocto-vmfs \
    -w /workspace \
    duduclaw-yocto-builder -c "sleep infinity"
```

Build (checkout + bitbake in one step; the Y1-1 bring-up took ~2h45m on a
cold-ish cache — 4 vCPU / 12GB Docker Desktop VM — dominated by `llvm-native`,
a transitive dependency of `systemd`'s `efi` PACKAGECONFIG needed to produce
`systemd-boot`'s EFI PE stub):

```bash
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && kas build meta-duduclaw/kas/duduclaw-os.yml"
```

OVMF (UEFI firmware for QEMU) is a separate host-side tool the image recipe
does NOT depend on — build it once before the first boot test (matches
oe-core's own CI selftest, which builds `image + " ovmf"` together):

```bash
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && kas shell meta-duduclaw/kas/duduclaw-os.yml -c 'bitbake ovmf'"
```

Boot the result under QEMU/OVMF (headless serial console — this is the
Y1-1 PASS criterion, a login prompt on serial, not a GTK window). `slirp`
is required inside an unprivileged container — the default tap networking
needs `/dev/net/tun`, which `docker run` doesn't grant by default and this
milestone doesn't need real networking for anyway:

```bash
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && kas shell meta-duduclaw/kas/duduclaw-os.yml -c \
     'runqemu duduclaw-image-minimal nographic serial wic ovmf slirp'"
```

Verified 2026-08-25 — full serial console evidence in
`meta-duduclaw/qemu-boot-y1-1-PASS-evidence-2026-08-25.log`:
`Welcome to DuDuClaw OS 0.1.0-y1-bringup (y1-bringup)!` → systemd boots to
`Multi-User System` → `Started Serial Getty on ttyS0` →
**`duduclaw-qemux86-64 login:`**.

Interactive bitbake shell for ad-hoc debugging:

```bash
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && kas shell meta-duduclaw/kas/duduclaw-os.yml"
```

## 中文輸入（fcitx5-chewing）依賴閉包

四包遞迴自建（OE 生態系完全沒有現成 recipe，逐一驗證過 OpenEmbedded Layer
Index 與 meta-openembedded 皆為零命中）：

```
extra-cmake-modules-native (KDE ECM, 純建置期 CMake find-module 集合，無執行期產物)
        │  find_package(ECM REQUIRED 1.0.0) — fcitx5、fcitx5-chewing 兩者的
        │  頂層 CMakeLists.txt 皆無條件呼叫
        ▼
     fcitx5 (核心框架，DEPENDS: extra-cmake-modules-native fmt gettext-native
     │        zlib dbus util-linux libxkbcommon wayland wayland-native
     │        wayland-protocols iso-codes xkeyboard-config expat cairo
     │        pango gdk-pixbuf json-c；RDEPENDS: iso-codes xkeyboard-config
     │        ——純資料檔案，auto-shlibs 抓不到，手動宣告；Y8-2 新增
     │        RRECOMMENDS: fcitx5-chewing，見下)
        │
        │  DEPENDS（fcitx5-chewing 透過 pkg-config `chewing>=0.5.0` 找
        │  libchewing，NOT CMake find_package——見 libchewing_0.9.1.bb
        │  header comment 的完整調查）
        ▼
   libchewing (Rust cargo crate `chewing_capi`，target 只產生 .so；native
   │           變體額外 DEPENDS sqlite3-native 供 chewing-cli 的
   │           rusqlite feature；target 端 DEPENDS libchewing-native 供
   │           do_install 呼叫 chewing-cli 產生 tsi.dat/word.dat 詞庫)
        │
        ▼
   fcitx5-chewing (fcitx5 addon 外殼；DEPENDS extra-cmake-modules-native
                   fcitx5 libchewing gettext-native；無手動 RDEPENDS——
                   對 fcitx5/libchewing 的 RDEPENDS 皆由 OE shlibs 自動
                   偵測，因為 libchewing.so 這個 addon 真的用一般 ELF
                   NEEDED 連結 libFcitx5Core.so/libFcitx5Utils.so/
                   libchewing.so.3，不是 dlopen，auto-RDEPENDS 抓得到)
```

**image 層黏合（不是 recipe 層依賴）**：`duduclaw-image.bb` 的
`IMAGE_INSTALL:append = " fcitx5 fcitx5-chewing"` 是唯一把兩者綁在一起的地方。
`fcitx5-chewing` 會自動 RDEPENDS 回 `fcitx5`（上圖已標註），但反方向從來沒有
——fcitx5 核心對任何特定輸入法引擎都無強制依賴（純 X11/waylandim 直通鍵盤
是完全合法的 fcitx5 安裝形態，例如日/韓/其他語系）。這代表過去只要有人把
`duduclaw-image.bb` 的 IMAGE_INSTALL 改成單獨列 `fcitx5`、漏了
`fcitx5-chewing`，image 會建置成功、開機也正常，但**零中文輸入引擎、零錯誤
訊息**——與 Y7-3 抓到的 kernel-modules umbrella 同一種「靜默能力遺失」坑。
Y8-2（2026-08-27）已在 `fcitx5_5.1.12.bb` 補上
`RRECOMMENDS:${PN} += "fcitx5-chewing"`（軟依賴，刻意不用 RDEPENDS——那會讓
fcitx5 在沒有任何引擎的合法安裝形態下建置失敗）作為第二道防線。

**外圍、非直接依賴、易混淆的鄰近票**：Y7-1 同一輪順手修掉的
`pipewire_%.bbappend` `sndfile` PACKAGECONFIG 缺漏（讓 `pw-cat` 能建置）
與 fcitx5 本身**沒有依賴關係**——純粹是同一份 `duduclaw-image.bb` 共用建置
路徑上，先卡住的人先修。不要因為兩者常在同一輪 log 出現就誤植成 fcitx5 的
依賴鏈。

**RRECOMMENDS/隱藏 module 稽核結論（Y8-2）**：仿 Y7-3 對 kernel-modules
umbrella 的稽核手法，逐一讀四包 recipe 原始碼（非只看 build log）——除了
上述「fcitx5 → fcitx5-chewing」這一條軟依賴缺口外，其餘鏈路（ECM 建置期
find_package、libchewing 的 cargo/sqlite3-native/libchewing-native 三段
DEPENDS、fcitx5-chewing 對 fcitx5/libchewing 的 auto-shlibs RDEPENDS）
皆已由既有機制正確覆蓋，未發現第二個同類缺口。

**Seed 設定的兩層架構（Y6-1 設計，Y8-2 補上系統預設層）**：
`duduclaw-kiosk-launch.sh` 的 `seed_fcitx5_config()` 寫入
`$HOME/.config/fcitx5`（per-user 層，鍵盤配置：keyboard-us/chewing 順序、
`ActiveByDefault=True` 開機即中文、Ctrl+Space 切換、直式候選字）——但這台
Yocto 線的 `duduclaw-kiosk` 系統使用者 `$HOME=/data/duduclaw-kiosk`
（`duduclaw-shell_1.62.0.bb` 的 `USERADD_PARAM`）目前**永遠不可寫**：
grep 全 `meta-duduclaw/` 確認零 `.mount` 單元、零 `systemd-repart` 設定、
零 `tmpfiles.d` 條目為 `/data` 存在，且 `/` 本身是 `root:root 0755`，非
特權使用者連 `mkdir /data` 都會 `Permission denied`（QEMU 上以
`duduclaw-kiosk` 身分活測重現，非猜測）。Y8-2 因此在
`duduclaw-shell_1.62.0.bb` 的 `do_install` 新增**建置期烤入**的
`${sysconfdir}/xdg/fcitx5/{profile,config,conf/classicui.conf,conf/chewing.conf}`
（root:root 0644，內容與 per-user 層完全一致）——fcitx5 本來就會用標準
XDG_CONFIG_DIRS 層級掃描這個系統預設路徑，只需要「讀」的權限，完全繞開
`/data` 不可寫的問題。兩層關係：`$HOME/.config/fcitx5`（若可寫）永遠贏過
`/etc/xdg/fcitx5`，符合一般 XDG 疊層語意；一旦未來 `/data` 真的掛載成功，
`seed_fcitx5_config()` 的主分支會自動重新開始成功寫入 per-user 層，無需
額外遷移程式碼。**踩坑記錄**：第一版曾嘗試在 `seed_fcitx5_config()`
「執行期」寫入 `/etc/xdg/fcitx5` 作為 fallback，以 `duduclaw-kiosk` 身分
重新活測後發現 `/etc/xdg` 與 `/` 同樣是 root-only、同一個
`Permission denied`——那個修法是死碼，跟原本的坑一樣不會生效。真正的修法
必須是建置期產物，不能是執行期以非特權使用者寫入，這個教訓值得下一棒
牢記：**任何「以 duduclaw-kiosk 身分修 fallback」的方案，套用前務必用
`su -s /bin/sh duduclaw-kiosk -c '...'` 實測寫入權限，不能只用 root shell
測過就當作驗證完成**。

**QEMU headless IME 引擎驗證手法（Y8-2，繞開殼黑屏／AVX2 崩潰迴圈）**：
不啟動 `duduclaw-kiosk.service`（`systemctl mask` 掉），改以
`su -s /bin/sh duduclaw-kiosk -c 'dbus-run-session -- fcitx5 -D ...'`
手動起一個獨立 D-Bus session bus + fcitx5 daemon，完全不需要
comp/wayland/顯示裝置。活測證實：`fcitx5-remote -n` 開機後立即回報
`chewing`（系統預設層生效）、`-s keyboard-us`/`-s chewing` 反覆切換皆
`rc=0` 且狀態正確、`/etc/xdg/fcitx5/conf/{classicui,chewing}.conf` 的
直式候選字設定確認落地。**已知限制（誠實列，未完全達成）**：
`org.fcitx.Fcitx.InputMethod1.CreateInputContext`／`InputContext1.
ProcessKeyEvent` 這組真正的按鍵注入 D-Bus API（`busctl introspect` 已
拿到完整簽章：`CreateInputContext(a(ss)) -> (o,ay)`、
`ProcessKeyEvent(uuubu) -> b`）是**per-connection 生命週期**——fcitx5
會在建立 IC 的那個 D-Bus 連線斷線時銷毀該 IC，而 `busctl call`/
`dbus-send` 每次呼叫都是全新連線，導致「建立→FocusIn→送鍵」這種需要
同一條連線的多步驟流程無法用這台機器上現有的 CLI 工具（無 python3、
無 socat、無 gdbus、busctl 無 batch 模式）直接串起來完整驗證
「su3cl3→你好」的委托組字。曾嘗試起一個 ANONYMOUS 認證的 TCP D-Bus bus
讓 host 端 Python（`dbus_next`）常駐連線驅動，但 fcitx5 的 `dbus` 模組
在這個自建 TCP bus 上穩定回報
`Unable to request dbus name`（連線本身先於此已成功，RequestName 這步
失敗，根因未深入到 libdbus vs sd-bus 傳輸層），列為下一棒可選跟進項
（見 TODO 文件 Y8-2 段落）；`fcitx5-remote` 狀態層級的引擎啟用/切換驗證
已經比 Y7-1（AVX2 崩潰迴圈下連一次穩定查詢都拿不到）更進一步。

## Status

See `commercial/docs/TODO-agent-first-os-2026-08.md` "Y 線" section for the
live status (build/boot evidence, disk/time actuals, what's deferred to
Y1-2).

As of Y4-0 (2026-08-26): `bitbake duduclaw-image-flatpak` builds 100% green
(all 7734 tasks succeed) and boots to a real "開機即殼" — `duduclaw-comp` +
`duduclaw-shell` run under `duduclaw-kiosk.service` with a real udev/DRM
backend and a real Wayland socket in `/run/duduclaw-kiosk/`, and
`duduclaw-flatpak-kiosk-verify.service` proves the Flatpak/Chromium chain
end-to-end (real Flathub network install, real `--kiosk --dump-dom` against
the real gateway dashboard). This took six real bugs to get here — see the
TODO doc's "Y4-0 本輪紀錄" section for the full list (a Yocto Rust version
gap, a zed-monorepo Cargo workspace-inheritance gotcha, a missing runtime
library the image recipe's own comment had misdiagnosed as unnecessary, and
three smaller packaging fixes). One residual finding not yet root-caused:
`duduclaw-kiosk.service` was observed to restart once or twice before
settling into a stable `active`/`running` state on one boot (down from
*always* hitting `StartLimitBurst` permanently before the fix) — tracked as
an open follow-up, not re-claimed as fully stable.
