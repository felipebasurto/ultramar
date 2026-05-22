# ADR-008 — Product chat profile & session parity (app ↔ CLI)

**Estado:** APROBADO  
**Fecha:** 2026-05-22  
**Relacionado:** [ADR-006](./006-qwen-thinking-visibility.md), [ADR-007](./007-cli-inference-harness.md), [chat-inference-harness](../architecture/chat-inference-harness.md)

---

## Contexto

Travel chat en la app y en la CLI compartían `InferenceChatHarness.send`, pero cada mensaje era **one-shot**: sin historial, sin contrato de producto unificado, y la CLI mezclaba flags de depuración con el flujo del viajero.

Se confirmó el diseño de producto: el usuario **elige y carga un motor una vez** (Qwen o Gemma), luego chatea en **multi-turn** sin recargas entre mensajes. La CLI interactiva es la superficie de diseño; iOS debe usar el mismo harness y defaults.

---

## Decisión

### Perfil de producto congelado

`ProductChatProfile.standard` en `UltramarLLM`:

| Campo | Default |
|-------|---------|
| `task` | `.generalChat` |
| `presentation.showThinking` | `false` ([ADR-006](./006-qwen-thinking-visibility.md)) |
| `presentation.qwenReasoningMode` | `.finalOnly` |
| `requiresLoadedEngine` | `true` — no auto-load silencioso en Send |
| `keepEngineLoadedBetweenTurns` | `true` |
| `streamingEnabled` | `false` |

### Sesión multi-turn

`ChatSession` guarda `[ChatTurn]` con texto **visible** (respuesta del asistente, no bloques think). Truncado por ventana deslizante con presupuesto de tokens (`n_ctx = 4096`, reserva system + generación vía `LlamaLoadPolicy`).

API de harness:

```swift
func sendInSession(
  prompt: String,
  session: inout ChatSession,
  profile: ProductChatProfile = .standard,
  ...
) async throws -> SendResult
```

`Qwen35Engine` aplica template con **N** mensajes user/assistant + system.

### Clientes

| Cliente | Modo | API |
|---------|------|-----|
| `ContentView` (app) | Producto | `sendInSession` + Load explícito + toggle thinking + Clear chat |
| `ultramar chat` (TTY, sin prompts) | Producto | `sendInSession` + `--engine qwen\|gemma` + `/new` `/system` `/exit` |
| `ultramar chat --prompt …` / batch | Dev/harness | `send` one-shot/batch; `--system-prompt-file`, `--task`, `--thinking` |

Producto CLI: carga una vez al inicio y mantiene el motor durante la sesión; al salir del proceso descarga de forma explícita para evitar asserts de Metal. Dev one-shot recarga por proceso; usar REPL o batch para iterar sin recargar.

---

## Consecuencias

1. Cambios en “cómo debe sentirse el chat” → `ProductChatProfile` + esta ADR, no duplicar en app/CLI.
2. [ADR-007](./007-cli-inference-harness.md) documenta la superficie CLI; esta ADR congela el contrato de producto compartido app/REPL.
3. Fuera de alcance inmediato: RAG crítico en hilo, AgentCoordinator tools, persistencia SwiftData, FM como motor principal de sesión.

---

## Referencias

- [chat-inference-harness.md](../architecture/chat-inference-harness.md)
- `ChatSession.swift`, `ProductChatProfile.swift`, `InferenceChatHarness.sendInSession`
- `ChatCommand.swift`, `ChatInteractiveLoop.swift`, `ContentView.swift`
