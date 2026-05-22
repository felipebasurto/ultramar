# ADR-007 — macOS CLI and shared inference harness

**Estado:** APROBADO  
**Fecha:** 2026-05-22 (actualizado 2026-05-22 — server backend default)  
**Relacionado:** [ADR-001](./001-llm-stack-locked.md), [ADR-005](./005-model-download-workflow.md), [ADR-006](./006-qwen-thinking-visibility.md), [ADR-009](./009-local-chat-backend-revamp.md), [chat-inference-harness](../architecture/chat-inference-harness.md)

---

## Contexto

Agents and maintainers need to run local inference, downloads, and routing checks on **macOS without the iOS Simulator**. Duplicating `ContentView.sendPrompt()` logic in the CLI would drift from the app. Downloads via CLI initially exited in ~500 ms because `URLSession` completion is asynchronous.

Agents also need a **predictable** chat UX: pregunta → respuesta en stdout, sin flags obligatorios ni ruido de llama.cpp por defecto.

---

## Decisión

### Package and binary

| Aspect | Choice |
|--------|--------|
| Package | `Packages/UltramarCLI/` (SwiftPM executable `ultramar`) |
| Platform | macOS 26+ (Metal via llama.cpp) |
| Build | `make cli-build` → `Packages/UltramarCLI/.build/release/ultramar` |
| CI | `make cli-build` in `.github/workflows/ci.yml` (no full inference in CI by default) |

### Shared chat path

**App product chat** keeps using the embedded path through `InferenceChatHarness` / `EmbeddedLlamaBackend`.

**CLI product chat** now defaults to `OpenAICompatibleLocalBackend`, which talks to `llama-server` at `http://127.0.0.1:8080/v1` through `ChatOrchestrator`:

1. `ChatRequest` + `ModelProfile`
2. `ChatBackend` (`OpenAICompatibleLocalBackend` or `EmbeddedLlamaBackend`)
3. `ChatOrchestrator` quality gate + final-only retry
4. `ChatResponse(answer, hiddenReasoning?)`

Diagram and troubleshooting: [chat-inference-harness.md](../architecture/chat-inference-harness.md).

### Commands (v1)

| Command | Purpose |
|---------|---------|
| `ultramar doctor` | Environment and model directory sanity |
| `ultramar models list` | Catalog artifacts |
| `ultramar models status` | Install/download state per engine |
| `ultramar models download` | Fetch GGUF (Qwen Phase 1) |
| `ultramar models remove` | Remove artifact from disk |
| `ultramar chat` | Product REPL, batch, or one-shot inference via server default / embedded opt-in |
| `ultramar route` | Print routing decision for `--task` |
| `ultramar fm status` | Foundation Models gate status |
| `ultramar rag search` | KB search (no LLM) |

Global options: `--format text|json`, `--models-dir` / env `ULTRAMAR_MODELS_DIR`.

### Model directory

Same default as the app:

`~/Library/Application Support/UltramarAI/models/`

Override only for read/install paths in CLI via `--models-dir` or `ULTRAMAR_MODELS_DIR`.

### Download behavior (CLI)

`CLIModelFacade` calls `ModelDownloadService.download()` then **`waitForInstall()`** — polls manifest/state until `installed` or `failed` (progress on stderr). Avoids reporting success before the background transfer finishes.

### Chat — uso recomendado

```bash
make cli-build
make qwen-server

# Product REPL: conecta al server local; Qwen vive en llama-server.
Packages/UltramarCLI/.build/release/ultramar chat --backend server --engine qwen

# Batch: muchos prompts, una sola carga en llama-server.
Packages/UltramarCLI/.build/release/ultramar chat \
  --backend server \
  --engine qwen \
  --prompts-file docs/evals/qwen-travel-smoke.txt \
  --format json

# Embedded debug/paridad iOS.
GGML_LOG_LEVEL=error Packages/UltramarCLI/.build/release/ultramar chat \
  --backend embedded \
  --engine qwen \
  --interactive
```

| Stream | Default behavior |
|--------|------------------|
| stdout | **Solo** el texto de la respuesta (sin `---`, sin metadata) |
| stderr | REPL banner, errores por turno, línea `Timing:` cuando aplica |

### Chat flags

| Flag | Default | Meaning |
|------|---------|---------|
| `--backend` | `server` | `server` para OpenAI-compatible local; `embedded` para llama.cpp en proceso |
| `--base-url` | `http://127.0.0.1:8080/v1` | Base URL del server local |
| `--engine` | `auto` | `qwen`, `gemma`, or app routing when unloaded |
| `--prompt` / `--stdin` | — | Input (mutually exclusive) |
| `--prompts-file` | — | Batch: un prompt por línea, una sola carga |
| `--task` | `generalChat` | `AgentTask` for routing |
| `--model-path` | — | Explicit GGUF; solo con `--backend embedded` |
| `--system-prompt-file` | — | System prompt UTF-8; REPL acepta `/system <path>` y `/system reset` |
| `--keep-loaded` | off | Alias histórico; usar REPL/batch para evitar recargas |
| `--show-thinking` | off | Include Qwen think blocks in formatted output ([ADR-006](./006-qwen-thinking-visibility.md)) |
| `--stream` | off | Stream visible tokens live (debug; puede mostrar basura) |
| `--verbose` | off | Imprime sección `--- Thinking ---` en stderr (requiere `--show-thinking`) |
| `--progress` | off | Token progress on stderr (debug) |
| `--fast` | off | Alias histórico; final-only `/no_think` ya es el default |
| `--thinking` | off | Activa modo Qwen thinking para debug |

**Presentation default:** `qwenReasoningMode: .finalOnly`. Solo `--thinking` activa reasoning visible/extraíble para debug.

**JSON output** (`--format json`): `ok`, `engine`, `backend`, `task`, `answer`, optional `thinking`, `text`, `prompt_chars`, `show_thinking`, `load_duration_ms`, `duration_ms` (inferencia), `total_duration_ms`, `tokens_generated`, optional `tokens_per_second`. La misma línea `Timing:` también va a stderr.

**Noise:** `GGML_LOG_LEVEL=error` recomendado solo en server/embedded debug. Unload usa `LlamaCppLogging` + silencio stderr en backend embebido.

### Engine load parity with app

- Server REPL / batch: `make qwen-server` owns the single loaded Qwen model; CLI clients do not load llama.cpp.
- Embedded debug: `EmbeddedLlamaBackend` wraps the existing harness and unloads before process exit.
- `--engine gemma`: server mode passes `model=gemma`; embedded mode loads `Gemma4Engine`.
- `--engine auto`: server mode resolves to Qwen; embedded mode keeps legacy routing behavior.

---

## Consecuencias

1. Any change to routing, Qwen structured output, or FM fallback must update **both** `ContentView` and `ChatCommand` only through the harness API.
2. README and AGENTS.md stay short; detail lives in [chat-inference-harness.md](../architecture/chat-inference-harness.md) and ADRs.
3. Interactive product REPL and multi-turn session are **in scope** via `sendInSession` and [ADR-008](./008-product-chat-session-parity.md). Batch uses the same loaded-process discipline.
4. Flag `--stream` como obligatorio está **obsoleto**; documentar solo opt-in.

---

## Referencias

- [README.md](../../README.md) — Quick start CLI
- [AGENTS.md](../../AGENTS.md) — Agent commands and invariants
- [chat-inference-harness.md](../architecture/chat-inference-harness.md) — Flujo completo, prompts, troubleshooting
- Code: `Packages/UltramarCLI/`, `InferenceChatHarness.swift`, `CLIModelFacade.swift`
