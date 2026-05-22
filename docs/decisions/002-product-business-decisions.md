# Decisiones de producto y negocio — Ultramar AI

**Estado:** APROBADO  
**Fecha:** 2026-05-22  
**Relacionado:** [ADR-001 LLM stack](./001-llm-stack-locked.md), [ADR-003 Marca](./003-brand-ultramar.md), [ADR-004 Híbrido AI](./004-hybrid-apple-intelligence-edge.md), [ADR-006 Qwen final-only + thinking debug](./006-qwen-thinking-visibility.md), [ADR-007 CLI](./007-cli-inference-harness.md)

---

## 1. Qué es el producto (cerrado)

| Decisión | Valor |
|----------|-------|
| **Plataforma** | iOS 100 % (iPhone primero; iPad después si hay demanda) |
| **Conectividad** | Offline-first; red solo para descargar packs/modelos/mapas |
| **Alcance geográfico** | Global; contenido regional = packs descargables |
| **Usuario objetivo** | Viajeros globales: vuelo, layover, destino sin WiFi; traducción, fotos, orientación local |
| **No somos** | Dispositivo médico, sustituto del 112/911, telemedicina |

**Propuesta de valor en una línea:**  
*Compañero de viaje offline con IA local que cita fuentes, actúa con tools y habla tu idioma — sin enviar datos a la nube.*

---

## 2. Posicionamiento competitivo (cerrado)

| Competidor / referencia | Ellos | Nosotros |
|-------------------------|-------|----------|
| Survivalist.AI | GGUF catalog, supervivencia | Travel assistant offline + RAG + dual LLM 2026 |
| Northstar | Apple Intelligence opcional | FM opcional + motores propios obligatorios |
| ChatGPT / Claude app | Requiere red | 100 % local |
| Apple Maps offline | Mapas sin IA | Mapas + agente + KB viaje |

**Moat defendible:**
1. KB curada con citas (RAG obligatorio en temas críticos)
2. Dual engine Qwen3.5 + Gemma4 (agente + multimodal)
3. Regional packs (fauna, emergencias, frases, mapas)
4. Modo **Safety** (secundario): SOS, mayday, ubicación en 2 taps

---

## 3. Modelo de negocio (cerrado fase dogfood)

| Decisión | Valor |
|----------|-------|
| **Monetización v0 → viaje Tailandia** | **Gratis total** — sin IAP, sin suscripción |
| **Revisión post-viaje** | Evaluar freemium + regional packs o pago único |

No implementar StoreKit en MVP. Enfoque 100 % dogfood y validación offline.

---

## 4. Legal y confianza (cerrado)

| Decisión | Acción |
|----------|--------|
| Disclaimer médico | Pantalla first-run + footer en respuestas médicas/fauna |
| ToS | “Información educativa”; no diagnóstico ni prescripción |
| Licencias modelos | Atribución Apache 2.0 en About |
| Contenido KB | Solo PD / CC-BY / CC0 empaquetable; matriz en doc 07 |
| Datos usuario | Todo on-device; sin analytics de prompts por defecto |
| Edad / App Store | 12+ o 17+ según contenido médico gráfico en KB |

**Riesgo Gemma/Qwen:** alucinación en temas críticos → **RAG con `sources[]` obligatorio**; respuesta conservadora si score RAG bajo.

---

## 5. Go-to-market (cerrado para fase 1)

| Fase | Cuándo | Objetivo |
|------|--------|----------|
| **Dogfood** | Antes Tailandia (~2 meses) | Tú solo, iPhone 17, modo avión 24h |
| **TestFlight cerrado** | Semana 6–7 | 5–10 viajeros / outdoor |
| **App Store v1** | Post-viaje o soft launch regional | Global, EN+ES UI |
| **Marketing** | Orgánico | Reddit r/solotravel, r/digitalnomad, r/LocalLLaMA, YouTube “offline AI travel” |

**Nombre público:** **Ultramar AI** — App Store subtitle: *Offline travel assistant* ([ADR-003](./003-brand-ultramar.md)).

---

## 6. Alcance MVP — Tailandia (cerrado)

**Dual engine antes del viaje:** Qwen3.5-4B + Gemma 4-E2B.

| Incluye | Excluye |
|---------|---------|
| Qwen3.5-4B chat + AgentCoordinator + tools P0 | Pagos / StoreKit |
| Gemma 4-E2B: foto (carteles, menús, plantas) + audio básico | Mapas MBTiles grandes |
| RAG global core + pack Thailand | TestFlight público |
| Tools: KB, SOS, frases, ubicación, mayday | 40+ idiomas phrasebook |
| Apple FM opcional (resúmenes, `@Generable` — bonus, no bloqueante) | Suscripciones |
| Modo Safety (secundario) + SwiftData inventario + checklists | |

---

## 7. Decisiones de UX/producto (cerrado)

| Tema | Decisión |
|------|----------|
| Idioma app v1 | Español + English (UI); KB multilingüe vía RAG |
| Onboarding | 3 pasos: disclaimer → descargar Qwen (~2.7 GB) → elegir región opcional |
| Modo Safety | Tab secundario: ubicación, mayday copiable, 112/local, frase TH |
| Citas | Toda respuesta médica/fauna muestra “Fuente: [doc]” |
| Qwen3.5 reasoning | **Final-only por defecto** (`/no_think`); thinking solo en debug explícito con toggle o `--thinking` + `--show-thinking` ([ADR-006](./006-qwen-thinking-visibility.md)) |
| Privacidad marketing | “Tus prompts no salen del iPhone” — claim verificable |

---

## 8. Métricas de éxito (negocio + producto)

### Dogfood (Tailandia)

- [ ] 8h modo avión sin crash térmico
- [ ] <15 s respuesta media Qwen3.5 en chat
- [ ] 3 escenarios reales: traducir frase, leer foto cartel, contacto emergencia offline
- [ ] Ubicación + mayday generado offline

### Post-lanzamiento (si App Store)

- Descargas mes 1
- % usuarios que completan descarga modelo
- Retención D7 (viajeros pre-viaje)
- Conversión regional pack (si freemium)

---

## 9. Costes y recursos (cerrado)

| Partida | Coste |
|---------|-------|
| LLM API cloud | **$0** (local) |
| Apple Developer | $99/año |
| CDN packs (Cloudflare R2 / similar) | ~$5–20/mes inicial |
| Contenido KB curación | Tu tiempo + posible freelancer médico reviewer |
| Legal ToS/privacy | Plantilla + revisión opcional ~$500 |

**No hay coste por token** — el modelo de negocio no depende de márgen API.

---

## 10. Riesgos de negocio

| Riesgo | Mitigación |
|--------|------------|
| Responsabilidad mala consejo médico | Disclaimer + RAG + “consulta profesional” |
| App Store rechazo contenido médico | Categoría Utilities/Travel; no “Medical Diagnosis” |
| Qwen3.5 inestable en iOS day-1 | Fallback Qwen2.5-3B empaquetado como “modo compatible” |
| Tamaño descarga espanta | App lite + progreso descarga; explicar 2.7 GB vs 200 fotos |
| Competidor copia | Moat = KB + regional packs + UX travel offline, no el modelo |

---

## 11. Confirmado

| Pregunta | Respuesta |
|----------|-----------|
| Monetización | **Gratis** hasta post-viaje |
| MVP Tailandia | **Dual:** Qwen3.5 + Gemma 4 E2B |
| Marca | **Ultramar AI** — subtitle *Offline travel assistant* |
| TestFlight | Solo dogfood personal por ahora |

---

## Siguiente paso

Integrar `swift-llama` en `UltramarLLM` + descarga Qwen3.5 Q4.
