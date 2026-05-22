# Agent guide — Ultramar AI

## Purpose

iOS offline-first **travel assistant** (App Store: *Ultramar AI: Offline travel assistant*). Dual LLM local (Qwen3.5 + Gemma 4) + Apple Intelligence opcional. Empresa: **felipebasurto**. Bundle: `com.felipebasurto.ultramar`.

## Commands

- Install / bootstrap: `make bootstrap`
- Build: `make build`
- Test: `make test-run` (unit, manual). `make test` is a no-op. GPU/network: `make test-integration` / `make test-all`.
- CLI (macOS, sin simulador): `make cli-build` → `Packages/UltramarCLI/.build/release/ultramar`
- Regenerar Xcode project: `python3 Scripts/generate_xcode_project.py`
- Clean: `make clean`

CI (`.github/workflows/ci.yml`) ejecuta `make build`, `make test-run` y `make cli-build`.

### CLI para agentes (`ultramar`)

Headless, flags-only (ver skill cli-for-agents). Modelos en `~/Library/Application Support/UltramarAI/models/` (mismo que la app). `ULTRAMAR_MODELS_DIR` o `--models-dir` para overrides de lectura.

**Chat CLI:** usa `llama-server` local OpenAI-compatible por defecto; la app iOS conserva backend embebido offline. Doc: `docs/architecture/chat-inference-harness.md`.

```bash
make cli-build          # solo la primera vez (o tras cambiar código)
make qwen-server        # foreground server: carga Qwen una vez
make chat ENGINE=qwen   # REPL contra server: escribe, Enter, repite; /exit para salir

# 500 prompts de prueba — una sola carga en llama-server:
make batch PROMPTS_FILE=./prompts.txt ENGINE=qwen FORMAT=json

# smoke one-shot contra server:
make chat PROMPT='hola' ENGINE=qwen

# debug/paridad iOS embebida:
bin/ultramar chat --backend embedded --engine qwen --interactive
```

`make chat` sin `PROMPT` = sesión interactiva contra `http://127.0.0.1:8080/v1`. `make batch` = un prompt por línea en el fichero.

Cada subcomando: `ultramar <cmd> --help` incluye Examples.

## Docs map

- Product brief: `docs/product-specs/000-brief.md`
- Brand: `docs/decisions/003-brand-ultramar.md`
- Launch log: `docs/decisions/000-initial.md`
- LLM stack (cerrado): `docs/decisions/001-llm-stack-locked.md`
- Híbrido Apple Intelligence + edge: `docs/decisions/004-hybrid-apple-intelligence-edge.md`
- Qwen final-only default + thinking debug: `docs/decisions/006-qwen-thinking-visibility.md`
- CLI + harness: `docs/decisions/007-cli-inference-harness.md`
- Product chat session: `docs/decisions/008-product-chat-session-parity.md`
- Backend revamp local server + embedded: `docs/decisions/009-local-chat-backend-revamp.md`
- LLM routing: `docs/architecture/llm-routing.md`
- Chat harness (app + CLI, prompts, troubleshooting): `docs/architecture/chat-inference-harness.md`
- Negocio (cerrado): `docs/decisions/002-product-business-decisions.md`
- Arquitectura / roadmap: `docs/README.md`
- Research: `docs/research/01-local-llm-models.md` … `11-ios-llm-frameworks.md`

## Invariants (do not violate)

1. **Secretos fuera del repo** — no API keys; modelos GGUF descargados on-device.
2. **Un motor pesado a la vez** — Qwen XOR Gemma cargado; swap explícito en UI.
3. **Tests en Packages** — nuevo comportamiento en `Packages/*` incluye test unitario mínimo.
4. **No auto-test** — no ejecutar tests salvo petición explícita del usuario. Verificación manual: `make test-run` (unit), `make test-all` (completo).
5. **Apple Intelligence = bonus** — FM no sustituye Qwen/Gemma en agente o visión. Ver [ADR-004](docs/decisions/004-hybrid-apple-intelligence-edge.md).
6. **Logging** — comportamiento crítico nuevo usa `UltramarLog` (`models`, `engine`, `routing`, `app`); no loguear prompts.

## Where to put new knowledge

- Product intent → `docs/product-specs/` (update `index.md`)
- Engineering decisions → `docs/decisions/` (new ADR; link from README index)
- Deep research → `docs/research/`
- Do not grow this file past ~120 lines — detail lives in `docs/`

## Code layout

- `UltramarAI/` — SwiftUI app shell, onboarding, settings
- `Packages/UltramarCore/` — shared types, `AppInfo`, `EngineRole`
- `Packages/UltramarLLM/` — `LLMProvider`, Qwen/Gemma engines
- `Packages/UltramarCLI/` — ejecutable `ultramar` (inferencia y modelos en macOS)

## Verification (manual only)

Do **not** run tests automatically after changes. If the user asks, use `make test-run` (unit) or `make test-all` (includes Qwen GGUF + Hugging Face preflight).

## Skills to prefer

- `project-greenfield-harness` — scaffold, docs, command loop
- `ios-debugger-agent` — build/run on simulator, runtime debug
- `swiftui-ui-patterns` — new SwiftUI screens
