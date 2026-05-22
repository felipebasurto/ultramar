# ADR-004 — Híbrido Apple Intelligence + modelos edge

**Estado:** APROBADO  
**Fecha:** 2026-05-22  
**Relacionado:** [ADR-001 LLM stack](./001-llm-stack-locked.md), [ADR-002 Negocio](./002-product-business-decisions.md), [11-ios-llm-frameworks](../research/11-ios-llm-frameworks.md), [llm-routing](../architecture/llm-routing.md)

---

## Contexto

Ultramar AI promete un **asistente de viaje offline-first** con motores propios (Qwen3.5 + Gemma 4). iOS 26 introduce **Foundation Models** (Apple Intelligence) on-device: modelo ~3B del sistema, tool calling nativo, `@Generable`, sin coste ni descarga.

Pregunta: ¿ofrecer Apple Intelligence **además** de los modelos edge?

---

## Decisión

**Sí — capas complementarias, no sustitutivas.**

| Capa | Rol | Obligatorio |
|------|-----|-------------|
| **Edge (Qwen + Gemma)** | Cerebro offline, tools P0, RAG, visión, 201 idiomas | **Sí** — promesa de producto |
| **Apple Intelligence (FM)** | Acelerador cuando disponible: resúmenes, `@Generable`, polish UX | **No** — bonus |

**Principio de producto:** *Offline-first con bonus Apple Intelligence.*  
El claim “tus prompts no salen del iPhone” sigue siendo verificable — FM también corre on-device.

---

## Por qué no es mucho problema (si se acota)

| Esfuerzo | Alcance | Estimación |
|----------|---------|------------|
| **Bajo** | `LLMProvider` + backend FM; toggle Settings; routing por tipo de tarea | ~2–3 días código |
| **Alto (evitar MVP)** | FM como cerebro principal; dos agent loops; FM en temas médicos/legales | Semanas + riesgo legal |

**Riesgo principal:** fragmentación UX (usuario sin Apple Intelligence vs con).  
**Mitigación:** edge siempre funciona; FM mejora tareas acotadas; fallback transparente a Qwen.

---

## Routing por tarea

| Tarea | Motor | FM permitido | Motivo |
|-------|-------|--------------|--------|
| Chat agente + tools P0 | Qwen | **No** | 4K ctx FM; parser tools propio; multilingüe Qwen |
| `searchTravelKB` + síntesis con citas | Qwen + RAG | **No** en médico/fauna/agua | RAG obligatorio; acceptable use FM |
| Resumen itinerario / packing list | FM o Qwen | **Sí** | `@Generable`; no crítico |
| Traducción frase SOS | Phrasebook | **No** | Frases curadas — invariant |
| Foto cartel / menú / planta | Gemma | **No** | FM sin visión |
| Audio básico | Gemma | **No** | FM sin audio |
| Modo Safety / mayday | Qwen + templates | **No** | Contenido crítico |
| Onboarding copy / tips UX | FM o Qwen | **Sí** | No safety-critical |

Detalle de implementación: [llm-routing.md](../architecture/llm-routing.md).

---

## Gates de disponibilidad FM

Foundation Models solo se usa si **todas** se cumplen:

1. iOS 26+
2. Dispositivo compatible (iPhone 15 Pro+, iPhone 16+, etc.)
3. Apple Intelligence **activado** por el usuario
4. Locale/idioma soportado por el modelo del sistema
5. Toggle app “Usar Apple Intelligence” = ON (default ON si gates 1–4 OK)
6. Tarea clasificada como FM-eligible en routing table

Si cualquier gate falla → **Qwen sin error visible al usuario**.

---

## Fallback

```
FM.request(task)
  → success: return
  → unavailable / error / timeout / exceededContextWindow
    → log (debug)
    → Qwen.request(same task)  // transparente
```

Nunca mostrar “Apple Intelligence no disponible” como bloqueo de feature core.

---

## Invariants que no cambian

1. **RAG obligatorio** en temas médicos, fauna, agua — FM no genera respuesta parametric en críticos
2. **Frases SOS curadas** — `translatePhrase` no usa FM ni LLM libre
3. **Un motor GGUF cargado a la vez** — Qwen XOR Gemma; FM no cuenta (modelo OS)
4. **Sin API cloud** — FM + edge = 100 % on-device
5. **Acceptable use FM** — no posicionar FM como asesor médico/legal/financiero

---

## Implementación (siguiente PR)

| Componente | Ubicación | Notas |
|------------|-----------|-------|
| `InferenceRouter` | `Packages/UltramarLLM/` | Clasifica tarea → backend |
| `FoundationModelsProvider` | `Packages/UltramarLLM/` | Conforme a `LLMProvider` |
| `AppleIntelligenceSettings` | `UltramarAI/Settings/` | Toggle + estado gates |
| Referencia unificada | [LocalLLMClient](https://github.com/tattn/LocalLLMClient) | Ya expone FM + llama.cpp + MLX |

Runtime edge sigue siendo **swift-llama** o **LocalLLMClient** sobre llama.cpp ([ADR-001](./001-llm-stack-locked.md)).

---

## Alcance MVP (Tailandia)

| | |
|---|---|
| **Obligatorio MVP** | Qwen3.5 + Gemma E2B + RAG + tools P0 |
| **Opcional MVP (bonus)** | Capa FM para resúmenes/`@Generable` si hay tiempo |
| **No bloqueante** | App funciona 100 % sin Apple Intelligence |

Actualiza [ADR-002 §6](./002-product-business-decisions.md): FM pasa de “Excluye” a “Opcional (bonus)”.

---

## Testing

Matriz mínima antes de ship:

| Escenario | Dispositivo | Esperado |
|-----------|-------------|----------|
| Modo avión 8h, sin FM | iPhone 17 8 GB | Todo core OK |
| Con FM ON | iPhone 17 Pro | Resúmenes más rápidos; tools P0 igual en Qwen |
| FM OFF (toggle) | Cualquier | Idéntico a sin FM |
| FM unavailable (sim) | Simulator sin AI | Fallback Qwen transparente |
| Tema médico | Con FM ON | Solo RAG+Qwen; FM nunca responde directo |

---

## Consecuencias

### Positivas

- UX premium en dispositivos con Apple Intelligence sin coste API
- Diferenciación vs apps solo-GGUF (“offline + Apple Intelligence cuando puedas”)
- Cero bytes extra en bundle para capa FM

### Negativas

- Matriz de test duplicada (with/without AI)
- Documentación y soporte deben explicar dos “modos” sin confundir al usuario
- FM 4K context limita usos; no simplifica agent loop

---

## Alternativas descartadas

| Alternativa | Por qué no |
|-------------|------------|
| FM como único motor | Gate dispositivo; 4K ctx; sin visión; acceptable use |
| Solo edge, sin FM | Pierde bonus gratis iOS 26; Northstar ya lo ofrece |
| vLLM en iPhone | No existe runtime iOS embebible |

---

## Referencias

- [11 — Frameworks iOS LLM](../research/11-ios-llm-frameworks.md)
- [Foundation Models docs](https://developer.apple.com/documentation/FoundationModels)
- [Acceptable use FM](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/)
- [TN3193 context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
