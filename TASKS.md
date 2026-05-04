# AironBot — Tasks Tracking

This file tracks current and completed tasks for the project.

---

## Active Tasks

### High Priority
- [ ] Fix voice mode - microphone not activating (session 2026-05-04)

### Medium Priority
- [ ] Code cleanup and refactoring

### Low Priority
- [ ] Documentation updates

---

## Completed Tasks (Recent)

### Session 2026-05-04

#### Voice Mode Fixes
- [x] Fix voice mode immediate cutoff bug
- [x] Fix voice mode button only working once per conversation
- [x] Add microphone permission check before starting listening
- [x] Simplified state machine: listening → thinking → speaking → looping
- [x] Added `toggle()` method for reactivating voice mode

#### Features
- [x] Add aurora borealis splash screen for voice mode
- [x] Add floating camera button visible in voice mode
- [x] Increase TTS speed by 10% (0.55 → 0.65)
- [x] Increase test quota to 100 requests/day
- [x] Increase file quota to 10 uploads/day

#### Code Quality
- [x] Remove dead Ollama local client code
- [x] Fix microphone permission handling with caching
- [x] Optimize polling loops with conditional updates
- [x] Extract RegExp patterns to constants
- [x] Remove unused `_timeoutTimer` field

#### Files Modified
- `lib/features/chat/presentation/voice_conversation_service.dart`
- `lib/features/chat/presentation/voice_service.dart`
- `lib/features/chat/presentation/tts_natural_service.dart`
- `lib/features/chat/presentation/aurora_splash.dart`
- `lib/features/chat/presentation/chat_screen.dart`
- `lib/features/chat/data/quota_service.dart`
- `lib/features/chat/data/file_quota_service.dart`
- `lib/features/chat/data/image_upload_service.dart`
- `lib/features/chat/domain/message.dart`

---

## Task Legend

| Status | Description |
|--------|-------------|
| `[x]` | Completed |
| `[ ]` | Pending |
| `[?]` | In progress |
| `[!]` | Blocked |

---

*Last updated: 2026-05-04*
