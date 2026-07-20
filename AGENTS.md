# SchoNavi Agent Guide

This file gives coding agents project-specific instructions for working in this repository. It is tool-neutral; follow the same project rules even if your agent runtime uses different commands or workflows.

## Project Overview

SchoNavi is a Flutter application for AI-assisted academic and competition navigation. It uses an HTTP backend for all recommendations, chat, history, favorites, and profile data, persists only client-owned data (preparation plans, assistant history, level diagnosis, reminder preferences) locally, and relies on LLM-backed reasoning served by the backend to recommend professors, competitions, and preparation plans.

Primary app entry points:

- `lib/main.dart` starts the Flutter app.
- `lib/app.dart` hosts the app shell.
- `lib/core/router/app_router.dart` defines GoRouter routes.
- `lib/core/di/providers.dart` wires repositories, stores, services, and LLM clients.

## Repository Layout

- `lib/core` — app config, dependency injection, routing, AI clients, storage, theme, and platform services.
- `lib/domain` — business entities, repository interfaces, and domain services.
- `lib/data` — DTOs, HTTP implementations, local persistence for client-owned data, and data-source adapters.
- `lib/features` — user-facing feature modules and pages.
- `lib/shared` — reusable UI components.
- `assets` — fonts, icons, and preparation-template JSON assets.
- `test` — Flutter unit/widget tests mirroring `lib` structure.
- `docs/superpowers` — existing design specs and implementation plans.

Backend lives in a separate repository (deployed at `8.156.88.100`, FastAPI). It is **not** under this Flutter repo — the former `web/backend` / `web/backend_agent` layout is an abandoned plan; do not reintroduce a `web/` backend here. The authoritative API contract is `docs/api-contract.md` + `docs/openapi.yaml`; deployment details are in `DEPLOYMENT.md`.

Ignore `.claude/worktrees/**` unless explicitly instructed to work in one of those worktrees; they are generated working copies.

## Architecture Rules

- Keep the layer boundary clear: UI/features depend on domain abstractions; data implementations live under `lib/data`; wiring belongs in `lib/core/di/providers.dart`.
- Prefer existing repository interfaces over direct data access from widgets.
- Keep Riverpod providers manual and explicit unless the surrounding code already uses generated code.
- Use dependency overrides in tests instead of global mutable state.
- Use `Result`-style implementations consistently with nearby code when adding domain/data behavior.
- Backend-owned data (professors, competitions, recommendations, chat, history, favorites, profile, feedback) is only accessed over HTTP; do not add mock or local fallbacks for it. Only client-owned data (preparation plans, assistant history, level diagnosis, reminder preferences) is persisted locally.
- In tests, override repositories/stores with fakes or stubs via provider overrides; do not reach into `LocalStore` keys directly from feature code.
- Keep LLMs grounded in candidate/source facts; do not let generated text invent professor, competition, or evidence data.
- Do not introduce new state-management, routing, persistence, or HTTP libraries without explicit approval.

## Flutter Conventions

- Current app stack: Flutter/Dart, `flutter_riverpod`, `go_router`, `dio`, `shared_preferences`, `flutter_secure_storage`, `gpt_markdown`, and `flutter_svg`.
- Prefer small, feature-local widgets and providers that follow existing feature directory patterns.
- Preserve Chinese product copy style unless the touched screen already uses English.
- For UI changes, run the app and manually verify the changed screen when feasible; tests alone are not enough for visual behavior.
- Do not add broad compatibility shims or feature flags for one-off changes.
- Default to no comments. Add a short comment only when the reason is not obvious from names and structure.

## LLM and Secrets

- Runtime LLM config is supplied through Dart defines or environment variables, not committed files.
- Common Flutter Dart defines: `LLM_API_KEY`, `LLM_BASE_URL`, and `LLM_MODEL`.
- The current LLM path is provider-neutral and DeepSeek/OpenAI-compatible. Do not switch providers or add Anthropic/Claude SDK code unless the user explicitly asks.
- Never commit API keys, tokens, credentials, raw private data, local databases, or real `.env` files.
- Project deployment docs explicitly say: do not create real `.env` files. Use `.env.example` for new key names and keep real values in Doppler or the caller's runtime environment.

## Common Commands

From the repository root:

```bash
flutter pub get
flutter analyze
flutter test
```

Useful targeted checks:

```bash
flutter test test/path/to_test.dart
flutter test test/path/to_test.dart --plain-name "test name"
dart format --set-exit-if-changed lib test
```

For release-tag Android artifact parity with CI:

```bash
flutter build apk --release
```

For backend-agent tests, work in the separate backend repo (not in this Flutter repo) and prefer isolated tests by default:

```bash
uv run python -m pytest -m "not realdata" -q
```

Only run real-data backend tests after the user confirms local data/indexes are prepared.

## Verification Expectations

- Before reporting a code change complete, run the smallest relevant test first, then broader checks when practical.
- For Flutter code, at minimum consider `flutter analyze` plus targeted `flutter test` files for touched behavior.
- For UI changes, start the app or preview target and exercise the golden path and likely edge cases. If local device/emulator/browser verification is not possible, say so explicitly.
- For backend-agent changes (in the separate backend repo), avoid tests marked `realdata` unless explicitly requested or required data is confirmed available.
- Do not bypass failing hooks, analyzers, or tests with `--no-verify` or equivalent flags.

## Git and Working Tree Safety

- The working tree may contain user changes. Do not overwrite, delete, reset, clean, or discard files unless the user explicitly authorizes it.
- Do not commit, amend, push, open PRs, or trigger deployments unless explicitly requested.
- Stage specific files only when committing is requested.
- Treat generated worktrees under `.claude/worktrees` as disposable copies; do not edit them from the main workspace unless explicitly asked.

## Agent Workflow

- Inspect the relevant files before editing. Do not infer project conventions from memory alone.
- Make focused changes that directly serve the requested task.
- Prefer editing existing files over creating new abstractions.
- Keep changes testable and run relevant checks before claiming completion.
- If requirements are ambiguous or multiple approaches have different trade-offs, ask before implementing.
- If you discover unrelated issues, report them separately instead of expanding scope.

## Documentation Updates

- Keep `README.md` focused on project overview and launch basics.
- Use `CLAUDE.md` for Claude Code behavior and project guardrails.
- Use `AGENTS.md` for tool-neutral instructions for other coding agents.
- Do not create extra planning, status, or summary documents unless the user asks for them.
