# Ultramar AI

Offline-first iOS travel assistant. Local LLMs (Qwen 3.5 + Gemma 4) — no network required in the field.

See [AGENTS.md](AGENTS.md) for agent invariants and [docs/README.md](docs/README.md) for architecture.

## Requirements

- macOS with Xcode 26+ (iOS 26 SDK)
- Swift 6.2

## Quick start

```bash
make bootstrap   # generate UltramarAI.xcodeproj
make build       # xcodebuild for iOS Simulator (default: iPhone 17)
make test-run    # unit tests only (manual; make test is a no-op)
make cli-build   # macOS CLI: Packages/UltramarCLI/.build/release/ultramar
make clean       # remove build artifacts
```

### macOS CLI (test models without Simulator)

Non-interactive CLI for agents and local dev. Uses the same model directory as the app (`Application Support/UltramarAI/models/`). Override with `ULTRAMAR_MODELS_DIR` or `--models-dir`.

```bash
make cli-build          # also creates ./bin/ultramar
./bin/ultramar doctor
make qwen-server        # foreground llama-server with Qwen
make chat ENGINE=qwen   # REPL against server; /exit to quit
make batch PROMPTS_FILE=docs/evals/qwen-travel-smoke.txt ENGINE=qwen FORMAT=json
# one-shot smoke against server:
./bin/ultramar chat --backend server \
  --prompt "¿Consejos para viajar a Tailandia sin datos?" --engine qwen
make cli ARGS="route --task generalChat --format json"
```

The CLI defaults to an OpenAI-compatible local server; the app keeps embedded offline inference. Full chat/CLI docs: [chat-inference-harness.md](docs/architecture/chat-inference-harness.md) (flags, prompts, troubleshooting). `ultramar chat --help` for examples.

Regenerate the Xcode project after layout changes:

```bash
python3 Scripts/generate_xcode_project.py
```

## Layout

| Path | Purpose |
|------|---------|
| `UltramarAI/` | SwiftUI app shell |
| `Packages/UltramarCore/` | Shared types (`AppInfo`, `EngineRole`) |
| `Packages/UltramarLLM/` | `LLMProvider`, Qwen/Gemma/Apple FM engines |
| `Packages/UltramarCLI/` | macOS `ultramar` CLI (local inference, downloads) |
| `Scripts/` | Xcode project generator |
| `docs/` | Product specs, ADRs, research |

## Bundle

- **Display name:** Ultramar AI  
- **Subtitle:** Offline travel assistant  
- **Bundle ID:** `com.felipebasurto.ultramar`  
- **Company:** felipebasurto

## AI engines

Three on-device backends — no fake responses:

| Engine | When | Download |
|--------|------|----------|
| **Qwen 3.5** | Brain — chat, agent | Optional (~2.7 GB) |
| **Gemma 4** | Vision — photo/audio analysis | Optional (~3.4 GB) |
| **Apple Intelligence** | Fallback when Qwen is not installed/loaded | Built into iOS 26 (no download) |

Without edge models, chat uses Apple Intelligence when available on the device. Diagnostics go to the Xcode console (`UltramarLog`); the UI stays minimal.

## Brain model (opt-in download)

The Qwen 3.5 brain model is **not** committed to this repository (~2.7 GB). Download is **optional** — chat falls back to Apple Intelligence when Qwen is unavailable.

| Item | Value |
|------|-------|
| File | `Qwen.Qwen3.5-4B.Q4_K_M.gguf` |
| Source | [DevQuasar/Qwen.Qwen3.5-4B-GGUF](https://huggingface.co/DevQuasar/Qwen.Qwen3.5-4B-GGUF) |
| On-device path | `Application Support/UltramarAI/models/Qwen.Qwen3.5-4B.Q4_K_M.gguf` |
| Manifest | `Application Support/UltramarAI/models/manifest.json` |

**In-app install:** Brain Model → **Download brain model**. Downloads use a **background URLSession**, prefer **Wi‑Fi** (toggle “Allow download on cellular” to override), support **cancel/resume**, and verify size + SHA256 when pinned.

**Manual install:** Copy the GGUF into the path above (simulator: `~/Library/Application Support/UltramarAI/models/`).

**Maintainers — pin SHA256 after verifying a release GGUF:**

```bash
shasum -a 256 Qwen.Qwen3.5-4B.Q4_K_M.gguf
# Set ModelCatalog.qwenBrain.sha256 in Packages/UltramarLLM/Sources/UltramarLLM/ModelCatalog.swift
```

See [ADR-005](docs/decisions/005-model-download-workflow.md).

**Verify real inference:** Load Qwen in the **Qwen 3.5** section, type a prompt, tap **Send**. Use a Release build on a physical iPhone 17 for best performance. Without Qwen, verify Apple Intelligence fallback in the console (`provider=appleFM`).

## Debugging logs

Run from **Xcode** (⌘R) and open the **Debug area** console. Filter by subsystem or event name.

| Category | Subsystem | Typical events |
|----------|-----------|------------------|
| `models` | `com.felipebasurto.ultramar` | `download_preflight`, `download_started`, `manifest_reconcile`, `verify_*` |
| `engine` | same | `engine_load_*`, `inference_*` |
| `routing` | same | `route_decision`, `provider_selected` |
| `rag` | same | `rag_search` |
| `fm` | same | `fm_gate` |
| `app` | same | `chat_send`, `chat_completed`, `engine_swap`, `background_session_wakeup` |

Device without Xcode attached:

```bash
log stream --predicate 'subsystem == "com.felipebasurto.ultramar"' --level debug
```

**Privacy:** prompts and KB snippets are **not** logged — only `prompt_chars`, task, backend, and durations. Use these logs to debug stuck downloads, routing fallbacks, and FM gate state.

Logging helpers live in `Packages/UltramarCore/Sources/UltramarCore/UltramarLog.swift`.
