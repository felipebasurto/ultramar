# Ultramar AI

**Ultramar AI** is an offline-first iOS travel assistant. Ask questions, translate phrases, and analyze photos on the plane, at the gate, or abroad — without cellular data or Wi‑Fi. Local LLMs run on your device; when edge models are not loaded, Apple Intelligence can fill in on supported hardware.

Built with SwiftUI. Bundle ID: `com.felipebasurto.ultramar`.

![Ultramar AI chat on iPhone — offline travel assistant](screenshots/Simulator%20Screenshot%20-%20iPhone%2017%20-%202026-05-22%20at%2013.59.27.png)

## Why offline

Travel breaks connectivity at the worst moments: long flights, roaming gaps, crowded airports, new cities. Ultramar keeps a useful assistant in your pocket when the network does not — no cloud round-trip, no “check your connection” dead ends.

## AI engines

Three on-device backends. Only one heavy edge model (Qwen **or** Gemma) runs at a time.

| Engine | Role | Download |
|--------|------|----------|
| **Qwen 3.5** | Chat and travel agent | Optional (~2.7 GB) |
| **Gemma 4** | Vision — photos and basic audio | Optional (~3.4 GB) |
| **Apple Intelligence** | Fallback when Qwen is not installed or loaded | Built into iOS 26 |

Without edge models, chat uses Apple Intelligence when the device supports it.

## Quick start

Requires macOS with Xcode 26+ (iOS 26 SDK) and Swift 6.2.

```bash
make bootstrap   # generate UltramarAI.xcodeproj
make build       # xcodebuild for iOS Simulator
make test-run    # unit tests (manual; make test is a no-op)
```

Open `UltramarAI.xcodeproj` in Xcode and run on Simulator or a physical device.

Regenerate the Xcode project after layout changes:

```bash
python3 Scripts/generate_xcode_project.py
```

---

## macOS CLI

A headless macOS CLI (`ultramar`) runs local inference without the Simulator — useful for smoke tests and batch evals. It reads models from the same directory as the app (`Application Support/UltramarAI/models/`). Override with `ULTRAMAR_MODELS_DIR` or `--models-dir`.

```bash
make cli-build          # also creates ./bin/ultramar
./bin/ultramar doctor
make qwen-server        # foreground llama-server with Qwen
make chat ENGINE=qwen   # REPL against server; /exit to quit
make batch PROMPTS_FILE=docs/evals/qwen-travel-smoke.txt ENGINE=qwen FORMAT=json
```

The CLI defaults to an OpenAI-compatible local server; the iOS app keeps embedded offline inference. Details: [chat-inference-harness.md](docs/architecture/chat-inference-harness.md). `ultramar chat --help` for examples.

## Project layout

| Path | Purpose |
|------|---------|
| `UltramarAI/` | SwiftUI app shell |
| `Packages/UltramarCore/` | Shared types (`AppInfo`, `EngineRole`) |
| `Packages/UltramarLLM/` | `LLMProvider`, Qwen/Gemma/Apple FM engines |
| `Packages/UltramarCLI/` | macOS `ultramar` CLI (local inference, downloads) |
| `Scripts/` | Xcode project generator |
| `docs/` | Product specs, ADRs, research |

## Brain model (opt-in download)

The Qwen 3.5 brain model is **not** in this repository (~2.7 GB). Download is optional — chat falls back to Apple Intelligence when Qwen is unavailable.

| Item | Value |
|------|-------|
| File | `Qwen.Qwen3.5-4B.Q4_K_M.gguf` |
| Source | [DevQuasar/Qwen.Qwen3.5-4B-GGUF](https://huggingface.co/DevQuasar/Qwen.Qwen3.5-4B-GGUF) |
| On-device path | `Application Support/UltramarAI/models/Qwen.Qwen3.5-4B.Q4_K_M.gguf` |
| Manifest | `Application Support/UltramarAI/models/manifest.json` |

**In-app:** Brain Model → **Download brain model**. Background download, Wi‑Fi preferred (toggle cellular override), cancel/resume, size + SHA256 verify when pinned.

**Manual:** Copy the GGUF into the path above (simulator: `~/Library/Application Support/UltramarAI/models/`).

**Maintainers — pin SHA256 after verifying a release GGUF:**

```bash
shasum -a 256 Qwen.Qwen3.5-4B.Q4_K_M.gguf
# Set ModelCatalog.qwenBrain.sha256 in Packages/UltramarLLM/Sources/UltramarLLM/ModelCatalog.swift
```

See [ADR-005](docs/decisions/005-model-download-workflow.md).

## Debugging logs

Run from Xcode (⌘R) and open the Debug area console. Filter by subsystem or event name.

| Category | Subsystem | Typical events |
|----------|-----------|----------------|
| `models` | `com.felipebasurto.ultramar` | `download_preflight`, `download_started`, `manifest_reconcile`, `verify_*` |
| `engine` | same | `engine_load_*`, `inference_*` |
| `routing` | same | `route_decision`, `provider_selected` |
| `rag` | same | `rag_search` |
| `fm` | same | `fm_gate` |
| `app` | same | `chat_send`, `chat_completed`, `engine_swap`, `background_session_wakeup` |

On device without Xcode:

```bash
log stream --predicate 'subsystem == "com.felipebasurto.ultramar"' --level debug
```

Prompts and KB snippets are not logged — only lengths, task, backend, and durations.

## Further reading

- [AGENTS.md](AGENTS.md) — agent invariants and command reference
- [docs/README.md](docs/README.md) — architecture, ADRs, and research
