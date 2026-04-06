# TODO

Items flagged during the quality elevation pass. These are not silently
rewritten because they touch behavior; they live here so a human can
prioritize them.

## Bugs

_(All previously listed bugs in this section have been fixed. See git
log for `MutablePersistableRecord` and `OllamaClient.embed` decoding
fixes — both were silently disabling semantic memory and RAG.)_

## Refactor candidates

These files exceed 200 lines and are flagged here per the elevation plan.
Splitting any of them is a behavior-preserving change that should land in
a focused PR, not a quality pass.

| File | Lines | Suggested split |
|---|---|---|
| `Services/Inference/MLX/MLXClient.swift` | 1162 | Extract model loader, KV cache wiring, and quantization paths into separate files |
| `Services/Orchestrator.swift` | 898 | Extract trace builder, learned-routing merge, and skill injection into helpers |
| `Services/Tools/ChartTools.swift` | 652 | Group by chart type (stock, comparison, generic) into peer files |
| `Services/Tools/MacOSTools.swift` | 626 | Group by capability (apps, processes, screen, system) |
| `Services/Agents/BaseAgent.swift` | 582 | Extract ReAct reflection loop and history compaction |
| `Services/Tools/SkillTools.swift` | 577 | Each tool (`weather_lookup`, `calculator`, etc.) is independent — peer files |

## Concurrency

- `MemoryStore.search()` uses a `DispatchSemaphore` to bridge async semantic
  search into a synchronous call site. Tracked here so the call sites can
  be migrated to `async` and the semaphore removed.
- `TraceStore` has Swift 6 `Sendable` warnings around `var trace = ...`
  captured by a detached task. Pre-existing.
- `SkillStore` has the same captured-var warning at line 163.

## Testing gaps

Phase 1 covers core non-UI logic. Areas still without tests, in priority
order:

- `EpisodicMemory` summarization trigger and retrieval
- `LearnedRouter` k-NN tool prediction from traces
- `TraceStore` write/read round trip
- `OllamaClient` request body shape (could be tested with a stub URL
  protocol that records bytes — would catch keep_alive regressions)
- `CommandHandler` parser (`/code`, `/think`, `/see`, etc.)
