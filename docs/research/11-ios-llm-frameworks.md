# Frameworks Apple y runtimes edge para LLM en iOS (2026)

> **Contexto:** Ultramar AI — travel assistant offline-first con dual engine Qwen3.5 + Gemma 4.  
> **Relacionado:** [ADR-001](../decisions/001-llm-stack-locked.md), [ADR-004](../decisions/004-hybrid-apple-intelligence-edge.md), [llm-routing](../architecture/llm-routing.md)

---

## Resumen ejecutivo

| Stack | Rol en Ultramar AI | ¿Reemplaza Qwen/Gemma? |
|-------|-------------------|------------------------|
| **llama.cpp + Metal** | Runtime edge principal (GGUF) | **Sí — motor obligatorio** |
| **Foundation Models** | Bonus Apple Intelligence (iOS 26+) | No — complemento acotado |
| **MLX Swift** | Alternativa / embeddings / VLM fallback | Posible fork, no ADR actual |
| **Core ML + ANE** | Modelos convertidos pequeños, Gemma ANE pilot | Parcial — “Sentidos” futuro |
| **Create ML** | Entrenamiento/export, no inferencia chat | No |
| **vLLM** | Servidor macOS multi-usuario | **Descartado en iPhone** |

**Conclusión:** llama.cpp = runtime edge principal; Foundation Models = capa bonus; vLLM irrelevante para App Store iOS.

---

## 1. Foundation Models framework (iOS 26+)

**Docs:** [FoundationModels](https://developer.apple.com/documentation/FoundationModels) · [WWDC25 session 286](https://developer.apple.com/videos/play/wwdc2025/286/) · [TN3193 context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window) · [Acceptable use](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/)

| Dimensión | Evaluación |
|-----------|------------|
| **Chat** | Bueno para tareas cortas y estructuradas; no sesiones agente largas |
| **Embeddings** | Sin API de embeddings — RAG requiere modelo aparte ([TN3193](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)) |
| **Visión** | Modelo de sistema solo texto |
| **Tool calling** | Protocolo `Tool` nativo + `@Generable` ([docs](https://developer.apple.com/documentation/FoundationModels/expanding-generation-with-tool-calling)) |
| **8 GB RAM** | Gestionado por OS; ~0 bytes en bundle app |
| **Offline** | Sí, si Apple Intelligence está activo |
| **Formatos** | Modelo fijo del sistema + `.fmadapter` LoRA opcional — **no GGUF** |
| **Contexto** | **4 096 tokens** por `LanguageModelSession` ([TN3193](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)) |
| **Dispositivos** | iPhone 15 Pro+, iPhone 16+, M1+ Mac; efectivamente 8 GB+ ([Apple Support](https://support.apple.com/en-us/121115)) |

**Límites para Ultramar:**
- Requiere Apple Intelligence ON — no universal
- Acceptable use **prohíbe** servicios regulados (salud/legal/financiero) — FM no puede generar respuestas médicas/fauna sin RAG
- Adapters requieren entitlement y re-entrenamiento por versión OS

---

## 2. Core ML + Neural Engine (ANE)

**Docs:** [Core ML](https://developer.apple.com/machine-learning/core-ml/) · [MLComputeUnits](https://developer.apple.com/documentation/coreml/mlcomputeunits) · [Jetsam](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports)

| Dimensión | Evaluación |
|-----------|------------|
| **Chat** | Sí — transformers convertidos a `.mlpackage` |
| **Embeddings** | Sí — embedder custom o Natural Language |
| **Visión** | Sí — pipelines VLM (encoder GPU + LLM ANE) |
| **Tool calling** | DIY en app — sin protocolo FM |
| **8 GB RAM** | Gemma-class INT4 ~1 GB footprint ([CoreML-LLM](https://github.com/john-rocky/CoreML-LLM)) |
| **Thermal** | Mejor perfil batería con `.cpuAndNeuralEngine` |
| **Formatos** | Core ML — conversión desde PyTorch; **no GGUF nativo** |
| **Ultramar** | Pilot futuro para Gemma 4 “Sentidos” en ANE; no sustituye Qwen agent |

ANE no es API pública standalone — se accede vía Core ML o modelos del sistema.

---

## 3. MLX / mlx-swift / mlx-swift-lm

**Fuentes:** [mlx-swift](https://github.com/ml-explore/mlx-swift) · [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) · [MLXChatExample](https://github.com/ml-explore/mlx-swift-examples/blob/main/Applications/MLXChatExample/README.md) · [WWDC25 360](https://developer.apple.com/videos/play/wwdc2025/360/)

| Dimensión | Evaluación |
|-----------|------------|
| **Chat** | Excelente — `ChatSession`, streaming, iOS 17+ |
| **Embeddings** | **MLXEmbedders** — RAG-friendly |
| **Visión** | **MLXVLM** — imagen/video |
| **Tool calling** | App-implementado |
| **8 GB RAM** | 3–4B Q4 viable; 8B apretado |
| **Thermal** | GPU/Metal-heavy vs ANE-first Core ML |
| **Formatos** | **MLX safetensors** (mlx-community); convertir desde GGUF vía [mlxify](https://github.com/ClintMoody/mlxify) |
| **Ultramar** | Fallback VLM si llama.cpp mtmd falla; duplica pipeline de pesos vs ADR |

---

## 4. llama.cpp + Metal (runtime edge)

**Fuentes:** [llama.cpp](https://github.com/ggml-org/llama.cpp) · [iOS XCFramework b9275](https://github.com/ggml-org/llama.cpp/releases/tag/b9275) · [multimodal docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md) · [Gemma + llama.cpp (Google)](https://ai.google.dev/gemma/docs/integrations/llamacpp)

| Pros | Contras |
|------|---------|
| XCFramework oficial iOS, Metal first-class | Sin Neural Engine — GPU Metal only |
| GGUF — Qwen3.5 + Gemma 4 day-1 | ~60% RAM usable en 8 GB (~4.8 GB) — riesgo jetsam |
| Offline, App Store friendly | Sensibilidad a versión (regresiones entre builds) |
| Multimodal vía `libmtmd` + `mmproj` | API multimodal aún volátil |
| Tool calling Qwen3.5 fuerte | Parser PEG con bugs conocidos ([#20260](https://github.com/ggml-org/llama.cpp/issues/20260)) |

**Wrappers Swift:**

| Paquete | Rol | Madurez |
|---------|-----|---------|
| [mattt/llama.swift](https://github.com/mattt/llama.swift) | Thin SPM sobre XCFramework | Estable — base producción |
| [profclaw/swift-llama](https://github.com/profclaw/swift-llama) | API Swift nativa, tool parser | v0.1.0 — prometedor |
| [tattn/LocalLLMClient](https://github.com/tattn/LocalLLMClient) | llama.cpp + MLX + Foundation Models | Experimental — bueno para híbrido |

**Performance iPhone 17 (extrapolación Q4_K_M, ctx 4–8K):**

| Modelo | iPhone 17 (8 GB) | iPhone 17 Pro (12 GB) |
|--------|------------------|------------------------|
| Qwen3.5-4B (~2.7 GB) | ~20–30 tok/s | ~25–35 tok/s |
| Gemma-4-E2B (~2.6 GB) | Similar; + mmproj para visión | Headroom E4B |

Benchmarks base: [llama.cpp discussion #4508](https://github.com/ggml-org/llama.cpp/discussions/4508).

---

## 5. vLLM — descartado en iOS

| | |
|---|---|
| **On-device iOS** | **No** — motor servidor Linux/macOS ([docs](https://docs.vllm.ai/en/stable/serving/openai_compatible_server/)) |
| **macOS** | [vllm-swift](https://github.com/TheTom/vllm-swift) — servidor OpenAI-compatible, no embebible |
| **Ultramar** | Solo útil si añades tier online post-MVP |

---

## 6. Create ML

Entrenamiento y export a Core ML — **no** runtime LLM. Útil para clasificadores CV y helpers de curación KB, no para chat.

---

## 7. Matriz de formatos

| Formato | Runtime nativo | Modelos Ultramar ADR |
|---------|----------------|----------------------|
| **GGUF** | llama.cpp | ✅ Qwen3.5, Gemma 4 |
| **Core ML** | Core ML | Requiere conversión |
| **MLX safetensors** | mlx-swift-lm | Requiere re-convert |
| **Sistema FM + .fmadapter** | Foundation Models | Adapters only |

---

## 8. Restricciones iPhone 8 GB (cross-cutting)

Fuentes: [TN3193](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window) · [PocketLLM mobile guide](https://pocketllm.app/blog/developer-guide-mobile-llms/) · [PocketPal entitlements](https://github.com/a-ghorbani/pocketpal-ai/pull/651)

| Restricción | Impacto |
|-------------|---------|
| Jetsam ~60% RAM foreground | ~4.8 GB usable en 8 GB |
| Dual model Qwen + Gemma | ~5–6 GB storage; **uno cargado a la vez** |
| KV cache 4–8K ctx | Cientos de MB — liberar en background |
| mmap weights | Obligatorio para GGUF bajo presión |
| `increased-memory-limit` entitlement | ~+1 GB headroom |
| Contexto práctico móvil | 4–8K (256K teórico es marketing) |

---

## 9. Matriz de capacidades

| Capacidad | Foundation Models | Core ML + ANE | MLX Swift | llama.cpp (ADR) |
|-----------|-------------------|---------------|-----------|-----------------|
| Offline chat | ✅ (gated) | ✅ | ✅ | ✅ |
| Contexto largo | ❌ 4K | ~2K mobile | 4–8K | 4–8K mobile |
| Tool/agent loop | ✅ nativo FM | DIY | DIY | ✅ Qwen |
| Embeddings/RAG | modelo aparte | ✅ | ✅ MLXEmbedders | ✅ stack propio |
| Visión/audio | ❌ | ✅ VLM | ✅ VLM | Gemma via mtmd |
| Multilingüe | locale-gated | model-dependent | model-dependent | Qwen 201 langs |
| App size impact | 0 (OS) | +model GB | +model GB | +model GB |

---

## 10. Recomendación para Ultramar AI

**Híbrido acordado** ([ADR-004](../decisions/004-hybrid-apple-intelligence-edge.md)):

1. **Qwen3.5** — llama.cpp Metal (chat, tools, agente, RAG synthesis)
2. **Gemma 4 E2B** — llama.cpp (cámara, audio); pilot Core ML ANE post-MVP
3. **Foundation Models** — bonus iOS 26 para resúmenes/`@Generable`; nunca temas críticos
4. **RAG embeddings** — E5-small propio; benchmark vs MLXEmbedders opcional
5. **vLLM** — no usar en iPhone

---

## Enlaces oficiales (bookmark)

- Foundation Models: https://developer.apple.com/documentation/FoundationModels
- TN3193 (context/RAG): https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window
- Acceptable use FM: https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/
- Core ML: https://developer.apple.com/machine-learning/core-ml/
- MLX Swift: https://github.com/ml-explore/mlx-swift
- llama.cpp: https://github.com/ggml-org/llama.cpp
