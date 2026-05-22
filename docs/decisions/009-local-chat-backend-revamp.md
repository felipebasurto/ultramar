# ADR-009 — Local chat backend revamp

**Estado:** APROBADO  
**Fecha:** 2026-05-22  
**Relacionado:** [ADR-001](./001-llm-stack-locked.md), [ADR-006](./006-qwen-thinking-visibility.md), [ADR-007](./007-cli-inference-harness.md), [ADR-008](./008-product-chat-session-parity.md), [chat-inference-harness](../architecture/chat-inference-harness.md)

---

## Contexto

El harness original mezclaba ownership de engines, routing, prompts, quality gate y parsing específico de Qwen/Gemma en una sola superficie. Eso servía para llegar rápido a una app y CLI funcionales, pero hacía que el CLI macOS recargara llama.cpp en proceso y que cada cambio de prompt/backend tocara demasiado código.

Hanlin confirma una dirección útil: modelos con capacidades declarativas y servicios separados de la UI. Ultramar adopta esa separación, pero no copia el `APIManager` monolítico de Hanlin.

---

## Decisión

`UltramarLLM` expone un contrato común:

- `ChatBackend`
- `ChatRequest`
- `ChatResponse`
- `ChatEvent`
- `ModelProfile`
- `ModelCapabilities`
- `ChatOrchestrator`

Backends:

| Backend | Uso | Notas |
|---------|-----|-------|
| `OpenAICompatibleLocalBackend` | Default CLI/macOS | Habla con `llama-server` en `http://127.0.0.1:8080/v1` |
| `EmbeddedLlamaBackend` | App iOS y debug | Envuelve `InferenceChatHarness`, `Qwen35Engine` y `Gemma4Engine` |
| Apple FM | Bonus futuro bajo el mismo contrato | No sustituye Qwen/Gemma en agente, visión o RAG crítico |

El CLI usa server mode por defecto:

```bash
make qwen-server
make chat ENGINE=qwen
make batch PROMPTS_FILE=docs/evals/qwen-travel-smoke.txt ENGINE=qwen FORMAT=json
```

El backend embebido queda explícito:

```bash
ultramar chat --backend embedded --engine qwen --interactive
```

---

## Quality Gate

`ChatOrchestrator` aplica `ChatOutputQualityGate` sobre la respuesta visible de cualquier backend. El reasoning oculto no falla el gate si no se muestra. Si la salida visible falla, el orquestador hace un retry final-only antes de propagar `ChatOutputQualityError`.

---

## Consecuencias

1. El prompt lab de macOS ya no carga llama.cpp dentro del proceso `ultramar`.
2. La app iOS mantiene inferencia offline embebida y el invariant de un motor pesado a la vez.
3. `make chat` requiere `make qwen-server` o un server compatible ya escuchando en `--base-url`.
4. No hay auto-instalación de `llama-server`; los errores explican el siguiente comando/acción.
5. RAG, tools y visión quedan fuera de esta fase; primero chat estable.
