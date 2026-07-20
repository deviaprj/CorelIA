# CorelIA — Project Memory Index

Structured memory files are stored in `~/.claude/projects/-home-geekai-workspace-CorelIA/memory/`.

- [Project Overview](project-overview.md) — Platforms, tech stack, golden rule
- [Architecture Decisions](architecture-decisions.md) — ADRs: Flutter, Firebase, DeepSeek, dual backend
- [AI Models & Routing](ai-models-and-routing.md) — Model registry, routing table, TTS chain
- [Critical Files Map](critical-files.md) — What lives where, god class locations
- [God Class Split Plan](god-class-split-plan.md) — Phase 1-3 plan for splitting chat_notifier.dart

## Quick Reference

- **State**: Riverpod, go_router, MVVM pattern
- **Firebase Project**: `corelia-1773058753`
- **Collections**: `users`, `conversations`, `messages`, `projects`, `referrals`
- **AI Free**: `deepseek-v4-flash` (DeepSeek direct API)
- **AI Pro**: OpenRouter (Mistral Large, GPT-4o-mini)
- **TTS Chain**: gpt-4o-mini-tts → kokoro-82m → flutter_tts
- **Context Limit**: 20 messages
- **Stream Throttle**: 8 tokens / 150ms
- **Demo Mode**: `--dart-define=DEMO_MODE=true` or Chrome extension
