# Contributing to macbot

Thanks for taking the time to contribute. macbot is a native macOS AI assistant
that runs models locally — contributions that protect that privacy posture and
keep the project approachable are most welcome.

## Prerequisites

- macOS 15 (Sequoia) or newer — macOS 26 (Tahoe) supported, on Apple Silicon (M-series)
- Xcode 16+ or the matching Swift toolchain (Swift 6.0+)
- [Ollama](https://ollama.com) for the inference backend
- ~20 GB free disk for the default model set

Pull the default models once Ollama is running:

```bash
ollama pull qwen3.5:9b
ollama pull qwen3-embedding:0.6b
ollama pull gemma4:e4b   # vision; optional
```

macbot auto-detects hardware and picks a model tier (e.g. `qwen3.5:4b` on 8 GB
Macs, `gemma4:26b` on 64 GB+). See `model-tiers.json`.

## Build

```bash
git clone https://github.com/matthewbmerino/macbot
cd macbot
swift build
```

To run the app from the command line:

```bash
swift run Macbot
```

For a release `.app` bundle (required for persistent permissions like Screen
Recording, Accessibility):

```bash
./bundle.sh
open macbot.app
```

## Run the tests

```bash
swift test
```

The test target uses `@testable import Macbot` and a `MockInferenceProvider` so
the suite runs fully offline — Ollama does not need to be running. Tests that
touch persistence use `DatabaseManager.makeTestPool()`, which creates a fresh
temp-file-backed `DatabasePool` and applies migrations. Cleanup happens in each
test's `tearDown`.

## Project layout

```
Macbot/
├── Views/           # SwiftUI views — ChatView, CanvasView, etc.
│   └── Canvas/      # Canvas-specific subviews (nodes, minimap, scroll)
├── ViewModels/      # @Observable state containers
├── Services/        # Orchestrator, agents, inference, RAG
│   └── Agents/      # BaseAgent and specialised agents
├── Database/        # GRDB schema and migrations
├── Models/          # Value types (ChatMessage, CanvasNode, StreamEvent)
└── Utilities/       # Hardware scanning, system monitoring, logging
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the deeper technical breakdown.

## Areas to contribute

- **Canvas interactions** — node interactions, layout, AI orchestration
  modes (Execute / Widget / Expand)
- **Agents** — new tools in `Services/Tools/` or specialised agents
- **RAG / memory** — improving semantic recall, context retrieval
- **Performance** — profiling and fixing bottlenecks (canvas rendering, AI
  streaming, database I/O)
- **Privacy & security** — hardening, permission flows, audit

See `TODO.md` for the current backlog.

## Pull request expectations

- `swift build` and `swift test` must pass on the CI target. Both run
  automatically against your PR.
- Keep changes focused. If you find unrelated issues, open them separately or
  add an entry to `TODO.md`.
- Don't force-push to `main`. Force-pushing your own PR branch is fine.
- New behavior should have a test. Bug fixes should have a regression test
  that fails without the fix.
- Match the existing code style. SwiftLint runs via CI (`.swiftlint.yml`) as a
  non-blocking advisory until the project's baseline is clean.
- Don't introduce hardcoded paths, API keys, or anything that requires a
  specific machine. Secrets belong in the user's Keychain via
  `KeychainManager`.
- Don't add dependencies lightly — the privacy posture depends on keeping the
  attack surface small. Prefer vendoring or rolling your own for small utils.

## Reporting issues

Please include:

1. macOS version and chip (e.g. macOS 26.4, M3 Pro 18 GB)
2. Output of `ollama list`
3. Steps to reproduce
4. Relevant log output:
   ```bash
   log show --predicate 'subsystem == "com.macbot"' --last 5m
   ```

For UI / visual bugs, a screenshot or screen recording is extremely helpful.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
