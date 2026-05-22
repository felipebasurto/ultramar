# ADR-006 — Qwen final-only por defecto + thinking debug

**Estado:** APROBADO  
**Fecha:** 2026-05-22 (actualizado 2026-05-22 — final-only, sampler y quality gate)  
**Relacionado:** [ADR-001](./001-llm-stack-locked.md), [ADR-002](./002-product-business-decisions.md), [ADR-007](./007-cli-inference-harness.md), [chat-inference-harness](../architecture/chat-inference-harness.md)

---

## Contexto

Qwen3.5 puede emitir razonamiento interno en bloques *think* del tokenizer (marcadores `think` / `/think`, y variante `redacted_thinking`). En la práctica también aparece texto plano tipo **“Thinking Process:”** con listas numeradas, sobre todo bajo `/no_think` o cuando el presupuesto de tokens se agota antes del cierre del think block.

Sin separar thinking de respuesta:

- El usuario vería razonamiento mezclado con consejos de viaje.
- La generación puede terminar en meta (“Review Constraints”) o repetir la pregunta del usuario.
- Respuestas de 1–2 frases cumplían el prompt antiguo (“1–3 sentences”) pero eran insuficientes para viaje offline.

Ultramar debe priorizar **fiabilidad**: Qwen corre en modo final-only por defecto, thinking queda reservado para depuración explícita y las salidas malas se rechazan antes de mostrarse. Los logs no deben filtrar prompts, respuestas completas ni thinking ([AGENTS.md](../../AGENTS.md) #8).

---

## Decisión

### Producto

| Aspect | Choice |
|--------|--------|
| Modelo Qwen (app / CLI default) | Final-only con `/no_think`; thinking solo en debug explícito |
| Longitud respuesta visible | **Sustantiva:** ~5–8 frases o 5–7 viñetas prácticas; no 1–2 frases salvo petición explícita de brevedad |
| UI app | Solo `answer` por defecto; toggle *Show model thinking* muestra sección Thinking |
| CLI | `ultramar chat --engine qwen` = REPL final-only; `--thinking` activa debug y `--show-thinking` decide si se muestra |
| Modo thinking | `qwenReasoningMode = .thinking` + `/think`; debug, no producto default |
| Supresión explícita | `qwenReasoningMode = .finalOnly` |

Reemplaza la fila histórica en ADR-002 (“Thinking off por latencia”) y el límite antiguo de “1–3 frases” en este ADR.

### Técnica

| Componente | Rol |
|------------|-----|
| `TravelChatPrompts` | System prompts por motor/variante; ver [chat-inference-harness](../architecture/chat-inference-harness.md) |
| `QwenThinkingPolicy` | `GenerationFilter`, `visibleAnswer`, `finalizeGeneration`, anti-eco, `extractPlannedReplyFromThinking` |
| `SamplingPreset` | Presets Qwen reproducibles: final-only `0.7/0.8/20`, thinking `1.0/0.95/20`, presence penalty `1.5` |
| `ChatOutputQualityGate` | Bloquea thinking/template leaks, eco de system/user, vacío y salidas triviales; un retry final-only |
| `QwenStructuredOutput` | `answer`, `thinking`, `tokensGenerated` |
| `ChatPresentation` | `showThinking`, `qwenReasoningMode`, `systemPromptOverride` |
| `InferenceChatHarness.SendResult` | Metadatos + `displayText(showThinking:)` |
| `LlamaLoadPolicy.maxGenerationTokens` | Dispositivo: **512** (final-only), **1536** (thinking); simulador: **96** |

**Recuperación de respuesta** (orden en `finalizeGeneration`):

1. `sanitizeFinalAnswer` sobre texto visible.
2. Cierre sintético de think truncado + `visibleAnswer`.
3. `fallbackAnswerFromThinking` (citas en thinking, sin meta).
4. `extractPlannedReplyFromThinking` si la respuesta no es sustantiva (&lt;140 caracteres útiles).
5. Mensaje fijo en español si sigue vacío.

**Streaming:** apagado por defecto en `ProductChatProfile.standard`; los deltas debug pasan por el mismo filtro visible.

### Logging

- Permitido: contadores (`thinking_chars`, `answer_chars`, `tokens_generated`, `duration_ms`).
- Prohibido: cuerpo de thinking, prompts, KB.

---

## Consecuencias

1. App y CLI comparten política vía harness ([ADR-007](./007-cli-inference-harness.md)).
2. Tests: presets de sampling, defaults de producto, quality gate, thinking policy e integración Tailandia (GGUF opcional).
3. Gemma / FM sin thinking en este ADR.
4. Ajustar longitud o recuperación → cambiar `TravelChatPrompts` + `QwenThinkingPolicy`, no el CLI salvo flags.

---

## Referencias

- Código: `QwenThinkingPolicy.swift`, `TravelChatPrompts.swift`, `Qwen35Engine.swift`
- UI: `UltramarAI/ContentView.swift`
- CLI: `ultramar chat` (ver ADR-007)
- Arquitectura detallada: [chat-inference-harness.md](../architecture/chat-inference-harness.md)
