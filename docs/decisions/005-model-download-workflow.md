# ADR-005 — Model download workflow (Phase 1)

**Estado:** APROBADO  
**Fecha:** 2026-05-22  
**Relacionado:** [ADR-001](./001-llm-stack-locked.md), [ADR-004](./004-hybrid-apple-intelligence-edge.md)

---

## Contexto

Ultramar AI needs optional on-device GGUF downloads (~2.7 GB per brain model). Users must be able to use the app without downloading (Apple Intelligence fallback). Downloads must survive backgrounding and prefer Wi‑Fi.

---

## Decisión

**Phase 1 — Qwen brain only**

| Aspect | Choice |
|--------|--------|
| Onboarding | **Opt-in** — no forced download |
| Network | **Wi‑Fi by default**; cellular via explicit Settings toggle |
| Transport | `URLSession` **background** session + resume data on disk |
| Catalog | `ModelCatalog` with HF resolve URLs |
| Integrity | Minimum size + **SHA256 when pinned** in catalog (`shasum -a 256`) |
| Persistence | `manifest.json` under `Application Support/UltramarAI/models/` |
| UI | Brain Model section in app shell (not onboarding gate) |

Apple Intelligence remains optional per ADR-004; edge Qwen download is independent.

---

## Consecuencias

1. `ModelStore` is a facade over `ModelDownloadService` + `ModelDownloadSession`
2. AppDelegate handles `handleEventsForBackgroundURLSession`
3. Gemma / multi-file HF tree deferred to Phase 2
4. Maintainers pin `ModelCatalog.qwenBrain.sha256` after verifying release GGUF

---

## Referencias

- Apple: [Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- LlamaBarn `ModelDownloader` (ggml-org) — progress aggregation, disk preflight
- [README](../README.md) — Brain model install + SHA pin steps
