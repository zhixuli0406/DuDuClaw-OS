# AI runtimes and local models on DuDuClaw OS

DuDuClaw OS ships the AI coding CLIs in the image. A factory-fresh box can
be handed an API key and put to work without installing anything: `claude`,
`codex`, `gemini`, `qwen`, `kimi`, `copilot`, `grok`, `agent` (Cursor),
`opencode` and `vibe` are all on `PATH` at first boot, and `llama-server`
is there for running a model locally with no network at all.

The list matches the platform release the image embeds (1.63.0 in v0.2.0).
The platform deprecated its Gemini CLI runtime in v1.67.0 and plans to
remove it in v1.71.0; the Gemini API provider is not affected. `gemini`
stays in this image until the OS syncs to a platform release without that
runtime.

This guide covers where that payload comes from, how to refresh it, where
credentials are stored, and what the image deliberately does *not* carry.
For the product-side view of multi-runtime task delegation, see
`docs/features/13-multi-runtime.md` in the platform repo.

## What is installed

| Command | Package | Source | Licence |
|---------|---------|--------|---------|
| `claude` | `@anthropic-ai/claude-code` | npm | Proprietary (Anthropic Commercial ToS) |
| `codex` | `@openai/codex` | npm | Apache-2.0 |
| `gemini` | `@google/gemini-cli` | npm | Apache-2.0 |
| `qwen` | `@qwen-code/qwen-code` | npm | Apache-2.0 (by the LICENSE file in the package; its npm metadata publishes no `license` field) |
| `kimi` | `@moonshot-ai/kimi-code` | npm | MIT |
| `copilot` | `@github/copilot` | npm | Proprietary (GitHub Copilot terms) |
| `grok` | Grok Build | `x.ai/cli` | Proprietary (xAI ToS) |
| `agent` / `cursor-agent` | Cursor agent | `downloads.cursor.com` | Proprietary (Anysphere ToS) |
| `opencode` | OpenCode | GitHub releases | MIT |
| `vibe` | `mistral-vibe` | PyPI | Apache-2.0 |
| `llama-server`, `llama-cli` | llama.cpp v0.4.0 | GitHub, built from source | MIT |

Everything except llama.cpp lives under `/opt/duduclaw/runtimes/`, and every
`/usr/bin` name above is a symlink to one dispatcher,
`/usr/libexec/duduclaw/duduclaw-runtime-exec`, which sets `NODE_PATH`,
`PATH` and `PYTHONPATH` into that tree before exec'ing the real entry point.

`/opt/duduclaw/runtimes/MANIFEST.txt` on the running image is the
authoritative record: exact version, source URL and sha256 for every
component, plus a `skipped:` line for anything that is not there.
`/opt/duduclaw/runtimes/LICENSES/` holds each upstream's own licence text.

### Not installed

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

The directory is created mode **0700, owner root** by
`duduclaw-firstboot-provision.sh`. It holds ten vendors' live API tokens;
`duduclaw-kiosk`, the only other real local account, must not be able to
read them.

The one file under that home another account used to read — the Windows RemoteApp registry the kiosk shell turns into Launcher tiles — no longer lives there: `duduclaw compat windows-vm app-add` writes it to `/data/system/windows-vm/apps.toml` (root-owned, world-readable, created by `duduclaw-data-binds`), because the gateway unit and root's profile set `DUDUCLAW_WINDOWS_VM_APPS_DIR=/data/system/windows-vm`. Migration `1788717600` moves an existing registry on machines provisioned before this change.

The dispatcher applies the same default for interactive use: a human
running `claude` over SSH as root gets `HOME=/data/duduclaw` too, rather
than scattering tokens into `/root`.

### Subscription logins vs API keys

API keys are the supported path and the default recommendation. Signing a
consumer subscription (Claude Pro/Max, ChatGPT, Google, Copilot, …) into a
third-party product is a vendor-terms question, not a technical one:
Anthropic and Google have blocked consumer subscription tokens from
third-party products server-side since March 2026, and accounts have been
suspended for it. The OOBE shows that risk and requires an explicit
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

Known gap: the service runs as root. A dedicated account would be correct,
but `/data/duduclaw` is 0700 root (it holds the credentials above), and a
0700 parent blocks traversal for any other uid no matter what mode
`models/` has. Fixing it means either moving the model store out from
under the credentials tree or giving `/data/duduclaw` a group and mode
0710 — both touch the firstboot provisioner and the gateway's path
constants together, so they belong with the local-model RPC work rather
than with this payload.

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
