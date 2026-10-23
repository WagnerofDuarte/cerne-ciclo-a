/// The four sub-states prototype-extract.md's "Tela 1 — Bookmark" names
/// verbatim. Per-message, per-viewer UI state (spec.md Key Entities) — never
/// persisted itself; the entry it may produce is the persisted side effect.
enum BookmarkStatus { idle, saving, saved, error }
