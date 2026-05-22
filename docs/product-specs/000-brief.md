# Product brief — Ultramar AI

## Problem

Viajeros en vuelo, aeropuerto o destino sin red no tienen un **asistente offline** que traduzca, lea carteles/fotos, responda con contexto local y cite fuentes — no un chatbot genérico que alucina.

## Primary user

Viajero global (avión, layover, destino nuevo) que necesita utilidad offline: idioma, orientación, foto→texto, frases curadas, packs regionales.

## MVP scope

**Dual engine antes del viaje a Tailandia (~8 semanas):**

- Qwen3.5-4B: chat, AgentCoordinator, tools P0
- Gemma 4-E2B: foto (carteles, menús, plantas) + audio básico
- RAG global core + pack Thailand
- Tools P0: `searchTravelKB`, `getEmergencyContacts`, `translatePhrase`, `getLocation`, `generateMayday`, `getChecklist`
- Modo safety (ubicación, mayday, números locales) — secundario, no hero
- SwiftData inventario + checklists viaje
- UI ES + EN
- Apple Foundation Models opcional (bonus si Apple Intelligence activo — ver [ADR-004](../decisions/004-hybrid-apple-intelligence-edge.md))

## App Store

- **Title:** Ultramar AI
- **Subtitle:** Offline travel assistant

## Non-goals (MVP)

- Pagos / StoreKit
- Mapas MBTiles grandes
- TestFlight público
- Framing “supervivencia / naufragio”
- Diagnóstico médico
- Apple Intelligence como **sustituto** de Qwen/Gemma — FM es bonus; edge es obligatorio

## Success metrics

### Dogfood (Tailandia)

- 8 h modo avión sin crash
- &lt;15 s respuesta media Qwen3.5
- 3 escenarios: traducir frase, leer foto cartel, contacto emergencia offline
- Apple FM: nice-to-have (resumen itinerario más rápido); **no** métrica bloqueante dogfood

## Trust boundaries

| Boundary | Policy |
|----------|--------|
| No dispositivo médico | Disclaimer; temas salud vía RAG + “consulta profesional” |
| Datos on-device | Sin analytics de prompts por defecto |
| Temas críticos | RAG con citas obligatorio |
| Red | Solo descarga modelos/packs |

## V1 quality constraints

1. **Offline reliability** — core funcional en modo avión prolongado
2. **Chat latency** — &lt;15 s media Qwen3.5 en iPhone 17 8 GB

## Assumptions

- ASSUMPTION: iOS 26+, bundle `com.felipebasurto.ultramar`, empresa felipebasurto
- ASSUMPTION: gratis hasta post-viaje
- ASSUMPTION: Tailandia = primer regional pack dogfood
