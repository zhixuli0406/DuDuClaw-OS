# AI runtimes and local models on DuDuClaw OS

DuDuClaw OS ships the AI coding CLIs in the image. A factory-fresh box can
be handed an API key and put to work without installing anything: `claude`,
`codex`, `gemini`, `qwen`, `kimi`, `copilot`, `grok`, `agent` (Cursor),
`opencode` and `vibe` are all on `PATH` at first boot, and `llama-server`
is there for running a model locally with no network at all.

The payload is the bundle generated on 2026-09-05
(`DUDUCLAW_AI_RUNTIMES_DATE = "20260905"` in the recipe). v0.2.0, v0.3.0
and v0.4.0 ship the same bundle, so the CLI versions below did not change
when v0.3.0 moved the embedded platform from 1.63.0 to 1.73.1, or when
v0.4.0 moved it to 1.73.4. Every bundled CLI is a runtime in platform
1.73.4's runtime catalog
(`crates/duduclaw-core/src/runtime_catalog.rs` in the platform repo). The
catalog also lists Kiro CLI and Google Antigravity, which the image does
not bundle (see [Not installed](#not-installed)).

The platform deprecated its Gemini CLI runtime in v1.67.0. Platform 1.73.4
(embedded in v0.4.0) still carries it and has moved the removal to v1.74.0 (Antigravity is the
named replacement); the Gemini API provider is not affected. `gemini` stays
in this image until the OS syncs to a platform release without that
runtime.

This guide covers where that payload comes from, how to refresh it, where
credentials are stored, and what the image deliberately does *not* carry.
For the product-side view of multi-runtime task delegation, see
`docs/features/13-multi-runtime.md` in the platform repo.

## What is installed

| Command | Package | Version (2026-09-05 bundle) | Source | Licence |
|---------|---------|---------|--------|---------|
| `claude` | `@anthropic-ai/claude-code` | 2.1.261 | npm | Proprietary (Anthropic Commercial ToS) |
| `codex` | `@openai/codex` | 0.153.4 | npm | Apache-2.0 |
| `gemini` | `@google/gemini-cli` | 0.58.0 | npm | Apache-2.0 |
| `qwen` | `@qwen-code/qwen-code` | 0.23.0 | npm | Apache-2.0 (by the LICENSE file in the package; its npm metadata publishes no `license` field) |
| `kimi` | `@moonshot-ai/kimi-code` | 0.41.0 | npm | MIT |
| `copilot` | `@github/copilot` | 1.0.83 | npm | Proprietary (GitHub Copilot terms) |
| `grok` | Grok Build | 1.0.13 | `x.ai/cli` | Proprietary (xAI ToS) |
| `agent` / `cursor-agent` | Cursor agent | build 2026.09.02-c22c1a3 | `downloads.cursor.com` | Proprietary (Anysphere ToS) |
| `opencode` | OpenCode | 1.18.29 | GitHub releases | MIT |
| `vibe` | `mistral-vibe` | 2.25.0 | PyPI | Apache-2.0 |
| `llama-server`, `llama-cli` | llama.cpp | recipe `llama-cpp_0.4.0.bb` | GitHub, built from source | MIT |

The versions are read from the bundle's own `MANIFEST.txt` (Grok resolves
its stable channel and Cursor its current build at generation time, so
neither has a pin in the generator).

Everything except llama.cpp lives under `/opt/duduclaw/runtimes/`, and every
`/usr/bin` name above is a symlink to one dispatcher,
`/usr/libexec/duduclaw/duduclaw-runtime-exec`, which sets `NODE_PATH`,
`PATH` and `PYTHONPATH` into that tree before exec'ing the real entry point.

`/opt/duduclaw/runtimes/MANIFEST.txt` on the running image is the
authoritative record: exact version, source URL and sha256 for every
component, plus a `skipped:` line for anything that is not there.
`/opt/duduclaw/runtimes/LICENSES/` holds each upstream's own licence text.

### Not installed

**Google Antigravity (`agy`).** The platform's catalog lists it (already in
the 1.63.0 snapshot v0.2.0 embedded, and the named replacement for the
deprecated Gemini CLI since 1.73.1), but the 2026-09-05 bundle does not contain
it. The catalog installs it with the vendor script
(`https://antigravity.google/cli/install.sh`), which drops `agy` in
`$HOME/.local/bin`; on this image that is `/data/duduclaw/.local/bin`, a path
the gateway probes. Installing it on a running v0.4.0 image has not been
tested.

**Kiro CLI.** Not in the image, and there is deliberately no `/usr/bin/
kiro-cli` stub: `duduclaw` decides "installed" by whether the binary
exists, so a stub would show Kiro as ready in the dashboard and OOBE when
it is not. Kiro's Linux artifact is 1039 MiB unpacked (615 MiB zip:
`kiro-cli-chat` 839 MiB, `kiro-cli` 114 MiB, `kiro-cli-term` 87 MiB) — see
the budget table at the end of this guide for what that costs. Shipping
only the 114 MiB launcher is not an option either: every agent subcommand
execs `kiro-cli-chat`. The dashboard's runtime page shows the vendor
install command from the platform's runtime catalog (`curl -fsSL
https://cli.kiro.dev/install | bash`, marked manual because Kiro's FAQ
disallows use through third-party automation harnesses); run as root it
installs under `/data/duduclaw/.local/bin` (the gateway's `$HOME`), a path
the gateway already probes, on the partition `systemd-repart` grows to the
whole disk.

**Model weights.** No GGUF ships in the image. A curated model is 1–5 GB
and belongs on the durable partition, so the dashboard downloads one into
`/data/duduclaw/models` on request.

**Vulkan acceleration in llama.cpp.** The shipped `llama-server` is a CPU
build against the distro's x86-64-v3 tune (AVX2/FMA/BMI2). The design calls
for `-DGGML_VULKAN=ON`; the recipe wires it as `PACKAGECONFIG[vulkan]` but
leaves it off, because ggml builds and *runs* `vulkan-shaders-gen` as a
host tool during compilation and its cross-compilation path reaches for a
build-host compiler that bitbake did not provide. Turning it on needs a
`GGML_VULKAN_SHADERS_GEN_TOOLCHAIN` file pointing at OE's own native
toolchain plus a real on-hardware check — `llama-server --list-devices`,
because a Vulkan build that silently falls back to CPU looks identical from
the outside. Full reasoning is in the recipe header,
`meta-duduclaw/recipes-ai/llama-cpp/llama-cpp_0.4.0.bb`.

## Where credentials live

Every one of these CLIs resolves its credential directory from `$HOME`:

```
~/.claude/.credentials.json   ~/.codex/auth.json     ~/.gemini/oauth_creds.json
~/.qwen/                      ~/.kimi/               ~/.copilot/
~/.grok/auth.json             ~/.local/share/opencode/
~/.local/share/cursor-agent/  ~/.config/mistral/
```

On this image `$HOME` for the gateway is **`/data/duduclaw`**, set by
`/usr/lib/systemd/system/duduclaw-gateway.service.d/20-home.conf`. That
matters twice over: root is read-only on the shipping image, so a login
writing to `/root` would fail outright; and root is what an A/B update
overwrites wholesale, so anything that *did* land there would vanish on the
next update. `/data` survives both.

The directory is mode **0700, owner `duduclaw`** (uid 1000, the account the
gateway runs as since v0.4.0; before that it was owner root). Ownership is
set at boot by `systemd-tmpfiles` from `duduclaw-home.conf`
(`duduclaw-home-owner.service`), and `duduclaw-firstboot-provision.sh` uses
the same file. It holds ten vendors' live API tokens;
`duduclaw-kiosk`, the only other real local account, must not be able to
read them.

The one file under that home another account used to read — the Windows RemoteApp registry the kiosk shell turns into Launcher tiles — no longer lives there: `duduclaw compat windows-vm app-add` writes it to `/data/system/windows-vm/apps.toml` (owned by `duduclaw` since v0.4.0, world-readable, created by the tmpfiles file in `duduclaw-cli`), because the gateway unit and root's profile set `DUDUCLAW_WINDOWS_VM_APPS_DIR=/data/system/windows-vm`. Migration `1788717600` moves an existing registry on machines provisioned before this change.

The dispatcher applies the same default for interactive use: a human
running `claude` in a root login shell gets `HOME=/data/duduclaw` too,
rather than scattering tokens into `/root`. Since v0.4.0 the dispatcher
then re-executes the CLI as `duduclaw` through `setpriv --no-new-privs`, so
hooks and MCP servers the CLI starts never run as root. (SSH is off by
default, and no account can log in over it yet.)

### Subscription logins vs API keys

API keys are the supported path and the default recommendation. Signing a
consumer subscription (Claude Pro/Max, ChatGPT, Google, Copilot, …) into a
third-party product is a vendor-terms question:
[Anthropic's policy](https://code.claude.com/docs/en/legal-and-compliance)
does not let third-party products route requests through Claude subscription
credentials and may be enforced without notice, and Google's
[Gemini CLI terms](https://geminicli.com/docs/resources/tos-privacy/) and
[Antigravity terms](https://antigravity.google/terms) (section 6) say
third-party software accessing the service through a subscription sign-in may
get the account suspended or terminated. OpenAI's and xAI's positions are
unclear; their terms still apply. The OOBE shows that risk and requires an explicit
acknowledgement before offering a subscription login.

## Local models

`llama-server` runs under `duduclaw-llama-server.service`, which is
**inert until a model exists**:

- `ConditionPathExists=/data/duduclaw/llama-server.env`
- `ConditionPathIsDirectory=/data/duduclaw/models`

A failed condition is not a failure — systemd marks the unit
condition-failed and moves on. An appliance that only ever uses cloud
runtimes never sees a restart loop. Configure it by writing the env file
and restarting:

```sh
install -d -m 0755 /data/duduclaw/models
cat >/data/duduclaw/llama-server.env <<'EOF'
LLAMA_MODEL=/data/duduclaw/models/Qwen3-4B-Q4_K_M.gguf
LLAMA_CTX=8192
LLAMA_PORT=8080
LLAMA_EXTRA_ARGS=
EOF
systemctl restart duduclaw-llama-server
curl -s http://127.0.0.1:8080/v1/models
```

The dashboard's local-models page drives exactly this through the gateway's
`inference.local.*` RPCs. The server binds `127.0.0.1` only: it is an
unauthenticated HTTP API, and the firewall is a second layer, not the
first.

Since v0.4.0 the service runs as `duduclaw`, the same account as the
gateway, and no longer loads `llama-server.env` as an `EnvironmentFile=`
(through v0.3.0 it ran as root and read that file, which the gateway's
account can write). `/usr/libexec/duduclaw/llama-server-run` reads the file
as uid 1000 and accepts only the four `LLAMA_*` keys shown above:
`LLAMA_MODEL` must be under `/data/duduclaw/models`, and `LLAMA_EXTRA_ARGS`
may not contain `--host` or `--port`.

## Fine-tuning

There is no on-device training path, and the image does not pretend
otherwise. Every 2026-era post-training stack (LLaMA-Factory, Unsloth,
Axolotl) assumes CUDA or ROCm, and both reference machines — Intel N305 and
Ryzen 8845HS — have integrated graphics only.

What ships instead is a `compat.d` declaration,
`/usr/share/duduclaw/compat.d/llamafactory.toml`, that gives `duduclaw
compat list` a row explaining the requirement (discrete NVIDIA GPU +
NVIDIA Container Toolkit) and a one-command Docker entry point for anyone
who has one. Dataset export and remote/cloud training are the supported
path for everyone else, from the dashboard's fine-tuning page.

## Refreshing the bundle

The payload is one pre-generated tarball,
`meta-duduclaw/recipes-duduclaw/duduclaw-ai-runtimes/files/duduclaw-ai-runtimes-<YYYYMMDD>.tar.zst`
(606 MB compressed, 1.9 GB unpacked). It is **gitignored** — reproducible
from the generator plus the versions pinned inside it, and 600 MB of vendor
binaries does not belong in git history.

To regenerate, from the repo root:

```sh
docker run --rm --platform linux/amd64 \
  -v "$PWD/meta-duduclaw/recipes-duduclaw/duduclaw-ai-runtimes:/gen" \
  -v "$PWD/meta-duduclaw/recipes-duduclaw/duduclaw-ai-runtimes/files:/out" \
  -w /gen node:22-bookworm \
  bash /gen/gen-ai-runtimes-bundle.sh 2>&1 | tee gen-ai-runtimes-bundle-$(date +%F).log
```

Then bump `DUDUCLAW_AI_RUNTIMES_DATE` in `duduclaw-ai-runtimes.bb` to the
new date stamp.

`--platform linux/amd64` is not optional. Half the payload is prebuilt
native code — npm resolves `optionalDependencies` by `process.platform`,
the vendor binaries come from explicit linux-x86_64 URLs, and the Python
wheels are pinned to `cp314` / `manylinux_2_28_x86_64` to match the image's
own Python 3.14.5. Generating on an arm64 host without that flag produces a
tree that installs cleanly and then fails at exec time on the appliance.

Version pins live at the top of the generator (`V_CLAUDE`, `V_CODEX`, …).
Every one of these upstreams ships several releases a week, so a refresh
means bumping them deliberately and reading the diff, not silently taking
whatever `latest` resolved to on the day someone rebuilt.

Two things to re-check after a version bump:

1. **Cursor's launcher.** The generator prunes `cursor-agent-sea` and
   `cursor-agent-worker-sea` (273 MB) because the shipped `cursor-agent`
   bash launcher execs its bundled `node` against `index.js` and never
   touches either blob. Re-read that launcher after a bump; if it changes,
   the prune becomes a breakage.
2. **The root slot.** See below.

## Root slot budget

`DUDUCLAW_AB_SLOT_SIZE_MB` in `duduclaw-image-appliance.bb` is **8192**
(raised from 7168 for this payload). That number is a ceiling, not a step
on a ladder: it equals `MAX_ROOT_BYTES` in the platform repo's
`crates/duduclaw-gateway/src/os_update.rs`, which the update transfer
enforces against the *full declared partition length*, not against real
content. Root-A and root-B must stay identical (the update writes a
slot-A-sized payload into slot B with no resize step), so one constant
governs both.

Rough costs, measured on the 2026-09-05 generation run:

| Item | Unpacked |
|------|----------|
| `node_modules/` (six npm CLIs, hoisted once) | 1.2 GB |
| `bin/` (grok 166 MB + opencode 185 MB) | 335 MB |
| `cursor-agent/` (after pruning the two SEA blobs) | 252 MB |
| `python/` (mistral-vibe, 97 packages) | 159 MB |
| `nodejs` + `nodejs-npm` | ~90 MB |
| `llama-cpp` (two statically linked binaries) | tens of MB |

Anything added to `duduclaw-image-runtimes.inc` from here needs a measured
before/after against that ceiling.
