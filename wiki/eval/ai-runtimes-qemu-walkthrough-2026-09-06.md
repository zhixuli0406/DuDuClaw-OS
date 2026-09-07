# AI runtimes / 本地模型 / 微調 — QEMU 走查（2026-09-06）

> L2 internal evidence log. Round 1 of the roadmap in the platform repo's
> `docs/todo/TODO-ai-runtimes-2026-09.md`（WP-A～WP-F）. Image under test:
> `duduclaw-image-appliance-test`（root serial autologin），bake "fix9"
> (wic 20260906043147) booted on the Mac QEMU TCG demo VM
> (`-cpu Skylake-Client -smp 6 -m 4096`, slirp NAT, PS/2 keyboard + QMP
> `send-key`, screenshots via QMP `screendump`). Host-side RPC through
> `appliance/tests/wifi-hwsim/ws_rpc.py` on the 18794→18789 hostfwd after
> `POST /api/login`（admin@local + OOBE 密碼）.
>
> Bake history this round: fix9 = first image with the whole WP-F payload;
> fix10 = /lib64 loader + kiro stub removal + `linux-container` (aborted for
> fix11); fix11 = fix10 + `openai_compat` wire-name fix — baking at the time
> of writing, re-verification of the fixed items is in §5.

## 1. Guest-side facts（serial）

| Item | Result |
|---|---|
| root slot | `vda2 root-a 8G`, `vda3 root-b 8G`, `vda4 duduclaw-data 8G`; `/` 6.5 G used of 7.7 G（748 MB free） |
| `/data/duduclaw` | `0700 root`（credential home）；`/data/system/windows-vm` `0755 root` |
| gateway unit env | `DUDUCLAW_HOME=/data/duduclaw HOME=/data/duduclaw DUDUCLAW_WINDOWS_VM_APPS_DIR=/data/system/windows-vm` |
| node / npm | v22.23.2 / 10.9.8 |
| llama-server | `version: 0.4.0-dev (build 10809, commit 5266f24da7)`；unit enabled, `ConditionResult=no` until a model exists（no restart loop） |
| bundled CLIs（fix9 image, before the /lib64 fix） | codex-cli 0.153.4 ✓, gemini 0.58.0 ✓, qwen 0.23.0 ✓, kimi 0.41.0 ✓, grok 1.0.13 ✓, vibe 2.25.0 ✓; **claude / opencode / cursor-agent "cannot execute: required file not found", copilot "no platform package found"** |
| root cause | every prebuilt vendor ELF has `PT_INTERP /lib64/ld-linux-x86-64.so.2`; the image is not usrmerge'd and only has `/lib/ld-linux-x86-64.so.2`, no `/lib64` |
| live fix (remount rw + `ln -s ../lib/ld-linux-x86-64.so.2 /lib64/`) | claude **2.1.261 (Claude Code)** ✓, copilot **1.0.83** ✓, cursor-agent **2026.09.02-c22c1a3** ✓, opencode **1.18.29** ✓ → baked into `duduclaw-ai-runtimes` do_install (fix10+) |
| kiro-cli | absent（expected；stub removed so `runtime.detect` cannot report it as installed） |
| `duduclaw compat list` | bottles / waydroid / windows-vm `ready`; **llamafactory rejected as malformed: `unknown variant linux-gpu`** → platform `FromOs::LinuxContainer` + declaration `from_os = "linux-container"`（fix10+） |
| `/lib64` note | `timeout` is not on the image (busybox without it) — test scripts must not rely on it |

## 2. OOBE（shell, WP-C）

Screens: `artifacts/demo/screens/rt-*.png`（copied from the scratchpad frames）.

| Step | Result |
|---|---|
| Steps 1–5 | unchanged from the 2026-09-05 walkthrough（language → input → update → network → account） |
| Step 6「AI Runtime 授權」 | provider list renders（17 rows, scrollable with the wheel）; every row has「輸入 API 金鑰」, rows whose catalog login is not `None` also have「登入帳號」（Qwen Code / Mistral Vibe are key-only） |
| 「登入帳號」on Claude Code | inline risk notice（§1-1 wording: Anthropic/Google server-side block since 2026-03, suspended accounts, OpenAI unclear）+ checkbox; 「開始登入」disabled until acknowledged; after ack the gateway ran the bundled `claude setup-token` and the panel shows the real `https://claude.com/cai/oauth/authorize?...` URL with「用瀏覽器開啟」/「取消登入」. Not completed（needs a real Anthropic account） → cancelled |
| 「輸入 API 金鑰」on Claude Code | field opens; a 17-char placeholder is refused（「這不像 API 金鑰」）; a key-shaped 44-char placeholder is accepted →「已存金鑰」/「已完成授權（第一次交辦時實際驗證）」 |
| second provider（Codex / OpenAI） | same flow →「已存金鑰」; `config.toml` has two `[[accounts]]` with `provider = "anthropic"` / `"openai"`, keys stored as `anthropic_api_key_enc` / `api_key_enc`（WP-A live） |
| Step 7–10 | templates（Express applied → agent「總」）→ finish page shows **「AI Runtime 已授權 2 家」** |
| cosmetic | the key field's placeholder reads `sk-ant-...` for every provider（Codex row too）; 「收起」needs a second click after a save; finish page says「網路 未連線」although the wired link is up（pre-existing, not this round） |

## 3. Host RPC（gateway, WP-A/B/D/E）

| RPC | Result |
|---|---|
| `runtime.detect` | 12 rows; **installed=true** for claude, codex, gemini, grok, qwen, kimi, copilot, cursor(`/usr/bin/cursor-agent`), vibe, opencode; antigravity / kiro `installed=false`; login methods per catalog（cli_login / browser_oauth / device_code / none） |
| `accounts.list` | `oobe-anthropic provider=anthropic`, `oobe-openai provider=openai`, both `auth_method=apikey` |
| `inference.local.status` | `appliance=true llama_server_present=true endpoint=http://127.0.0.1:8080/v1 reachable=false has_model=false`（honest "no model yet"） |
| `inference.local.catalog` | 6 GGUFs; on the 4 GB VM only `qwen3-1.7b (1.11 GB)` is `fit=comfortable`, the rest `too_big` |
| `inference.local.download {id: qwen3-1.7b}` | job 1, 1 107 409 472 bytes, completed in ~8 min over slirp; `installed=[Qwen3-1.7B-Q4_K_M.gguf]` |
| `inference.local.serve {model_file, ctx}` | writes `/data/duduclaw/llama-server.env`（LLAMA_MODEL/CTX/PORT/EXTRA_ARGS）, `restarted=true`; unit active, model loaded, `reachable=true loaded_model=Qwen3-1.7B-Q4_K_M.gguf` |
| `finetune.datasets.create/build` | dataset `ds-…` built（0 rows on a fresh box, files train.jsonl / preference.jsonl / dataset_info.json） |
| `finetune.jobs.create {backend: dry_run}` | job `planned`, artifacts `train.yaml` + `plan.json`, detail「乾跑完成，但 train.jsonl 沒有任何資料列——請先建構資料集」（honest） |
| `system.update_config {inference_mode: "local"}` | written to `[general]`, `applied=false`（needs restart） |

## 4. Delegation chains

| Chain | Result |
|---|---|
| Cloud（bundled Claude CLI + placeholder key） | composer → task「ng」排隊中 → goal loop dispatched → `claude_runner: Calling Claude CLI (SDK primary)`, account `oobe-anthropic method=ApiKey` → **`claude CLI assistant error: authentication_failed`** after ~3.5 min under TCG（honest failure; a real key is the last mile） |
| Local（llama-server） | first attempt: `Failed to deserialize inference.toml: unknown variant openai_compat, expected llama_cpp / open_ai_compat / mistral_rs` → engine "no available backend" → **platform bug**, fixed in `duduclaw-inference::types::BackendType`（`rename = "openai_compat"`, alias `open_ai_compat`）. Re-tested on the same VM with a hand-written `inference.toml` in the legacy spelling: the gateway's request reached llama-server（first `HTTP 400 … 3522 tokens exceeds … 2048` with the ctx I had picked; after re-serving with ctx 8192 the local **tool loop** sent a **33 657-token** request → 400 again → `local tool loop failed — falling back to bare completion`; the bare completion（~3.5k tokens）was still being prompt-processed by llama-server 15 min later under TCG, past the gateway's 300 s HTTP timeout）. **Verdict: wiring verified（engine reachable, request routed through `openai_compat`）, completion NOT observed — TCG is too slow; needs real hardware.** |
| Windows RemoteApp registry | `duduclaw compat windows-vm app-add --name Notepad 'C:\Windows\notepad.exe'` wrote `/data/system/windows-vm/apps.toml`（0644）; the kiosk shell's next scan logged `[app-icon] windows-vm:C:\Windows\notepad.exe` and a tile appeared in the dock |

### Findings outside this round's scope（platform）
- **Local tool loop prompt is ~33 k tokens**, four times the 8192 context the appliance serves by default（and any GGUF the 4 GB / 8 GB reference boxes can hold with a bigger KV cache）: on real hardware it fails with the same 400 and falls back to bare completion（no tools）. Either trim the tool-loop prompt for the local path or serve a larger `LLAMA_CTX` when RAM allows.
- **Goal loop after a dispatch failure or gateway restart**: the Personal edition cap（`personal_max_concurrent = 2`）counts the two tasks whose work message failed as still in flight, so every later goal task is「edition concurrency cap reached, deferring」until the no-progress escalation; a restart does not clear it either. Reproduced twice on this VM. Suggested fix: release the slot（and lease）when the dispatcher reports `message dispatch failed` for a goal task, and drop `todo` tasks from the in-flight set on restart.
- `system.update_config {log_level}` writes `logging.level`, but the gateway reads `[general] log_level`.

## 5. Re-verification on the fixed image（fix11, wic 20260906071600）

| Item | Result |
|---|---|
| `/lib64/ld-linux-x86-64.so.2` | present（symlink → `../lib/ld-linux-x86-64.so.2`, shipped by `duduclaw-ai-runtimes`） |
| all ten bundled CLIs `--version` | claude 2.1.261 ✓ codex-cli 0.153.4 ✓ gemini 0.58.0 ✓ qwen 0.23.0 ✓ kimi 0.41.0 ✓ copilot 1.0.83 ✓ grok 1.0.13 ✓ cursor-agent 2026.09.02-c22c1a3 ✓ opencode 1.18.29 ✓ vibe 2.25.0 ✓ |
| kiro-cli | absent（no stub） |
| `duduclaw compat list` | 4 runners, all `ready`: bottles, **llamafactory（`linux-container`）**, waydroid, windows-vm |
| OOBE → home | account / skip runtime / Express / finish; `runtime.detect` installed = claude codex copilot cursor gemini grok kimi opencode qwen vibe |
| `inference.local.status` | `appliance=true llama_server_present=true reachable=false has_model=false`（fresh box） |
| inference default config parse | after `inference_mode = "local"` + restart + a goal task: gateway log has **0** `unknown variant` / `Failed to deserialize` lines（fix9 had them）; before a model is served the engine honestly reports "no available backend" |
| served-model run | `inference.local.download` (1.1 GB, ~60 s this time) → `serve` ctx 8192 → `reachable=true loaded_model=Qwen3-1.7B-Q4_K_M.gguf`; gateway restart in local mode: **`deserialize 0 / unknown-variant 0 / no-available-backend 0 / disabled 0`** — the engine initialised through the image's own default config and the goal task was dispatched to llama-server（completion again not awaited: TCG） |
| `runtime_models` probes | `copilot`, `cursor-agent`, `vibe`, `opencode` model probes time out after 5 s under TCG（cosmetic WARN; Node/SEA start-up is slower than the probe budget on emulated CPUs） |
| `/data/duduclaw` / `/data/system/windows-vm` | 0700 root / 0755 root |

## 6. Installer ISO smoke（fix11, `duduclaw-image-live-desktop` 2026-09-06 08:19, 2.66 GB）

| Step | Result |
|---|---|
| boot from ISO（QEMU, empty 32 GB virtio target） | installer language screen in ~2 min; live root serial autologin present |
| installer walk | language → Wi-Fi（skipped, wired） → account（`M` / 8-digit） → theme → disk（「掃描磁碟」lists `/dev/vda 32G`, excludes the install medium `/dev/vdb`） → confirm（checkbox gate） → 「開始安裝」 |
| install | `duduclaw-install.wic.zst` dd'd to the target;「安裝完成」+「重新開機」within ~8 min under TCG |
| first boot of the installed disk | boots straight to the desktop（「午安，M」, dock without an agent because no template was applied）— the installed payload is the same appliance rootfs verified in §1–§5 |

Artifacts（host, gitignored）: `artifacts/demo/fix11-installer-desktop.iso`, `artifacts/demo/fix11-test.wic.zst`, screens `artifacts/demo/screens/rt-*.png`, `i11-*.png`.

## 7. Round 2 — the "known platform issues" fixed and re-verified（fix12, wic 20260906 late）

| Fix | Live result on fix12 |
|---|---|
| goal loop: failed dispatch held the slot / lease | `inference_mode = "local"` with NO model served; three goal tasks created: t+0 two dispatched（cap 2）, third deferred; **t+30 s `work message failed to dispatch — slot released` ×2 → third task dispatched at once**; back-off 60 s → re-dispatch → fail（2nd）; 120 s → fail（3rd）→ **`escalated to needs_human … reason=goal-loop dispatch failed 3x: Agent 'assistant' …`** for all three within 5 min. No「edition concurrency cap reached」starvation. |
| `system.update_config {log_level}` | `changes: general.log_level = "debug"`; `config.toml` line `log_level = "debug"` under `[general]`; after restart the CLI prints `effective log level: config.toml [general] log_level=debug` |
| OOBE finish page on a wired link | 「網路：有線網路已連線」（was「未連線」） |
| host-disk guard | `release-os.sh check_host_disk_free` — script-level, not exercised by this QEMU round（syntax-checked） |
| local tool loop fitted to the served context | model served（ctx 8192）→ goal task → gateway log **`request trimmed to the served model's context window n_ctx=8192 kept_tools=29 dropped_tools=189 dropped_system_chars=2487`**; llama-server accepted the request（`processing task`, no `send_error … exceeds`）; it was then cancelled by the tool loop's 120 s timeout — TCG prompt-processing speed, not a size error |
| found while doing this: engine unavailability was permanent per process | the first goal task ran before any model was served → `Inference engine … no available backend — disabling local offload for this process`; serving the model later changed nothing until a gateway restart. Fixed（60 s re-probe window + `inference.local.serve/stop` reset the cache）→ fix13 bake for live re-verification（§8） |

## 8. Round 3 — engine re-probe（fix13, 2026-09-07 00:xx）

Scenario on a fresh fix13 boot, `inference_mode = "local"`, gateway restarted once BEFORE any model existed, then never again:

| t | event（gateway log） |
|---|---|
| 00:36:45 | probe task A created; next tick dispatches it → `Inference engine … no available backend — local offload paused, will re-probe` → `message dispatch failed` → goal loop `slot released`（back-off 60 s） |
| +60 s | A re-dispatched → paused again → failed → released（second failure） |
| 00:37:30 → 00:38:45 | `inference.local.download`（45 s）→ `inference.local.serve` ctx 8192 → `reachable` after 30 s（the serve path resets the engine retry window） |
| 00:39:16 | probe task B created; its dispatch **initialises the engine against the live server and sends `request trimmed to the served model's context window`**; llama-server `processing task` — **no gateway restart** |

Verdict: the "first probe failed ⇒ local inference dead for the process" behaviour is gone; local inference recovers within one goal-loop tick of a model being served.

Artifacts: `artifacts/demo/fix13-installer-desktop.iso`（2.66 GB）, `artifacts/demo/fix13-test.wic.zst`（2.4 GB）— these supersede fix11/fix12 copies, which were deleted.

