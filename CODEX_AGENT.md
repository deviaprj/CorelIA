# CODEX_AGENT.md — Codex Agent Strategy

## Meta

- **Project**: Corely (ex-CorelIA) — Flutter/Dart AI Chat + Chrome Extension
- **Branch**: `br-CorelIA-V2` (target: beta-ready)
- **Agent**: Codex (OpenAI) autonome, strict, zero-regression
- **Rule**: Always read CLAUDE.md, MEMORY.md, TASKS.md, DECISIONS.md before any action

---

## Codex-Specific Instructions

Codex uses different tool names and context handling than Claude Code. Adapt as follows:

### Tool Mapping (Claude Code → Codex)

| Claude Code | Codex Equivalent |
|-------------|------------------|
| `Read` | `read_file` or inline context |
| `Edit` | `apply_diff` / `replace_string` |
| `Write` | `write_file` |
| `Bash` | `bash` |
| `TaskCreate` | Not available — track manually in TASKS.md |
| `Agent` | Not available — work sequentially |

### Context Handling

- Codex has a smaller context window than Claude. **Always summarize** file contents before asking Codex to edit.
- Use `///` doc comments in Dart to help Codex understand function contracts.
- When fixing a bug, provide: (1) the error message, (2) the relevant file snippet, (3) the expected behavior.

---

## Project Rules (same as AGENTS.md)

1. **Zero Regression**: Every fix must include a test or verification step.
2. **Root Cause Only**: Fix the source, never the symptom.
3. **Systematic Updates**: After every change, update:
   - `CLAUDE.md` — technical context
   - `TASKS.md` — task status
   - `DECISIONS.md` — architectural decisions
   - `MEMORY.md` — reasoning and links
4. **No Local Backend**: APK and Chrome Extension must be 100% autonomous.
5. **Flutter Unavailable**: If Flutter is not installed, rely on static analysis and write tests.

---

## Critical Architecture

### State Management (Riverpod)

```dart
// WRONG — causes re-initialization cascade
class MyNotifier extends Notifier<State> {
  @override
  State build() {
    state = state.copyWith(...); // NEVER do this
    return State();
  }
}

// CORRECT
class MyNotifier extends Notifier<State> {
  @override
  State build() {
    return State(...);
  }
}
```

### Conditional Imports

Mobile (`dart:io`) and Web (`dart:html`) must have paired implementations:
- `lib/core/api/dio_client.dart` → exports `_io` / `_web`
- `lib/features/chat/data/image_upload_service.dart` → exports `_io` / `_web`
- `lib/features/monetization/ads/ad_service.dart` → exports `_mobile` / `_web`

### Extension Chrome — Manifest V3 Constraints

- No inline `<script>` tags → all JS in external files
- No CDN scripts → CanvasKit must be local (`useLocalCanvasKit: true`)
- No Flutter Service Worker → neutralized in build script
- CSP: `script-src 'self' 'wasm-unsafe-eval'`

---

## Known Critical Bugs (Session V12+)

| Bug | Status | Key Files |
|-----|--------|-----------|
| Advanced search (flights/hotels/products) | In progress | `enhanced_search_service.dart`, `chat_notifier.dart` |
| DOCX/XLSX/PPTX extraction | In progress | `file_upload_service.dart` |
| DuckDuckGo HTML scraping fragile | In progress | `search_service.dart` |
| Slash commands extension | Fixed V12 | `extension_bridge.js`, `chat_notifier.dart` |
| Images base64 Firestore | Fixed V12 | `message.dart` |
| PDF extraction FlateDecode | Fixed V12 | `file_upload_service.dart` |

---

## Decision Log

When making architectural decisions, append to `DECISIONS.md` using this format:

```markdown
## ADR-NNN : Title

**Date**: YYYY-MM-DD
**Status**: Accepted / Deprecated

### Context
Why this decision was needed.

### Decision
What was decided.

### Alternatives Considered
- Option A (rejected because...)
- Option B (rejected because...)

### Consequences
- ✅ Positive outcome
- ⚠️ Risk or trade-off
```

---

## Testing Strategy

1. Unit tests for pure logic (parsers, formatters, routers)
2. Widget tests for critical UI flows (chat screen, input bar)
3. Integration tests for end-to-end flows (extension bridge, voice)
4. Mock external APIs (Dio, Firebase, SpeechToText)

### Test Commands

```bash
# Run all tests
bash scripts/run_tests.sh all

# Run specific test
flutter test test/features/chat/data/search_service_test.dart

# Run with coverage
flutter test --coverage
```

---

## Communication Style

- Be concise and technical
- Reference file paths and line numbers
- Explain WHY, not WHAT (the code shows what)
- Never ask open-ended questions — deduce from TASKS.md
- When uncertain, propose a decision with pros/cons rather than asking

---

## Restart Protocol

When resuming work:

1. Read `TASKS.md` top section (latest session)
2. Read `DECISIONS.md` last 3 entries
3. Read `MEMORY.md` index
4. Check `git status` and `git log --oneline -5`
5. Identify the next highest-priority unfixed bug
6. Execute fix + verification + documentation update

---

*Last updated: 2026-05-21 — Session V12*
