# ADR-001 — Stack LLM cerrado: Qwen 3.5 + Gemma 4

**Estado:** APROBADO  
**Fecha:** 2026-05-22  
**Contexto:** App iOS 100 % offline, global, agentic + multimodal.

---

## Decisión

Apostamos por **dos motores descargables**, no uno:

| Rol | Modelo | Quant | Tamaño | Dispositivo |
|-----|--------|-------|--------|-------------|
| **Cerebro** (chat, agente, tools, multilingüe) | `Qwen3.5-4B-Instruct` | Q4_K_M | ~2.7 GB | iPhone 17 8 GB+ |
| **Sentidos** (foto, audio, voz offline) | `Gemma-4-E2B-it` | Q4 / INT4 | ~2.6 GB | iPhone 17 8 GB |
| **Upgrade Pro** | `Gemma-4-E4B-it` | Q4 | ~3.5 GB+ | iPhone 17 Pro 12 GB |
| **Bonus sistema** (opcional) | Apple Foundation Models | — | 0 (sistema) | iOS 26 + Apple Intelligence |

**Descartado como motor principal:** Qwen 2.5, Llama 3.2, Gemma 2/3/3n.  
**Qwen 2.5:** solo fallback de contingencia si Qwen 3.5 falla en Metal en dispositivo real.

### Repos Hugging Face / GGUF

- Qwen: [DevQuasar/Qwen.Qwen3.5-4B-GGUF](https://huggingface.co/DevQuasar/Qwen.Qwen3.5-4B-GGUF) → `Qwen.Qwen3.5-4B.Q4_K_M.gguf`
- Gemma: [ggml-org/gemma-4-E2B-it-GGUF](https://ai.google.dev/gemma/docs/integrations/llamacpp)

### Runtime iOS

- **swift-llama** o **LocalLLMClient** sobre llama.cpp (Metal)
- Un modelo cargado a la vez; swap explícito en UI
- **AgentCoordinator** propio = capa de guardrails (no depender de Forge/Python)

### Por qué dual y no uno solo

| Necesidad producto | Qwen 3.5-4B | Gemma 4 E2B |
|--------------------|-------------|-------------|
| Tool calling / agente | 97.5% eval independiente | τ2 inferior |
| 201 idiomas | ✅ | ✅ 140+ |
| Visión + audio nativo móvil | Texto-first en llama.cpp hoy | ✅ diseño edge |
| Apache 2.0 comercial | ✅ | ✅ |
| Contexto largo situación | 256K teórico, 4–8K práctico móvil | 128K |

**Un solo modelo no cubre agente fuerte + multimodal+audio mobile-first.**

---

## Consecuencias técnicas

1. Dos descargas opcionales en Settings (“Instalar cerebro” / “Instalar visión”)
2. Routing: chat/tools → Qwen; cámara/mic → Gemma (sesión aparte)
3. Validación obligatoria en **iPhone 17 físico** antes de congelar quant
4. llama.cpp reciente (soporte Qwen3.5 dense, feb 2026)
5. **Capa híbrida opcional:** Apple Foundation Models como bonus cuando Apple Intelligence está activo — resúmenes, `@Generable`; nunca sustituye Qwen/Gemma en agente, RAG crítico o visión ([ADR-004](./004-hybrid-apple-intelligence-edge.md), [llm-routing](../architecture/llm-routing.md))

---

## Consecuencias de negocio

1. **Storytelling:** “Dos especialistas offline” — no “un chatbot genérico”
2. **Almacenamiento usuario:** ~5–6 GB si instala ambos + KB + mapas regionales
3. **Licencia:** ambos Apache 2.0 — sin PUP de Gemma 3, App Store friendly
4. **Diferenciación vs Survivalist.AI / similares:** stack 2026 (Qwen3.5 + Gemma4), no GGUF 2024

---

## Referencias

- [ADR-004 — Híbrido Apple Intelligence + edge](./004-hybrid-apple-intelligence-edge.md)
- [11 — Frameworks iOS LLM](../research/11-ios-llm-frameworks.md)
- [llm-routing](../architecture/llm-routing.md)
- [09-comparativa](../research/09-comparativa-detallada-qwen-llama-gemma.md)
- [10-qwen-ecosystem](../research/10-qwen-ecosystem-huggingface.md)
- Eval tool calling: [jdhodges 2026](https://www.jdhodges.com/blog/local-llms-on-tool-calling-2026-pt1-local-lm/)
