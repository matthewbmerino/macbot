import Foundation

/// Handles all slash commands, extracted from Orchestrator to reduce its size.
enum CommandHandler {

    static func handle(
        command: String,
        conv: Orchestrator.ConversationState,
        orchestrator: Orchestrator
    ) async throws -> String {
        let parts = command.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        let cmd = String(parts[0]).lowercased()
        let rest = parts.count > 1 ? String(parts[1]) : ""

        switch cmd {
        case "/upgrade", "/big":
            // Re-run the most recent user message through the reasoner (largest model)
            // for a more thorough answer.
            guard let reasoner = conv.agents[.reasoner] else {
                return "Reasoner agent unavailable."
            }
            // Find last user message in any agent's history
            var lastUser: String?
            for (_, agent) in conv.agents {
                for msg in agent.history.reversed() {
                    if let role = msg["role"] as? String, role == "user",
                       let content = msg["content"] as? String, !content.isEmpty {
                        lastUser = content
                        break
                    }
                }
                if lastUser != nil { break }
            }
            guard let prompt = lastUser else { return "No prior user message to upgrade." }
            conv.currentAgent = .reasoner
            return try await reasoner.run(prompt)

        case "/clear":
            // Auto-record episode from the most active agent before clearing
            await recordEpisodeFromConversation(conv: conv, orchestrator: orchestrator)
            for (_, agent) in conv.agents { agent.clearHistory() }
            conv.sessionStartedAt = Date()
            return "Conversation cleared."

        case "/status":
            return try await status(conv: conv, orchestrator: orchestrator)

        case "/code", "/coder":
            conv.currentAgent = .coder
            guard !rest.isEmpty, let agent = conv.agents[.coder] else { return "Switched to coder." }
            return try await agent.run(rest)

        case "/think", "/reason":
            conv.currentAgent = .reasoner
            guard !rest.isEmpty, let agent = conv.agents[.reasoner] else { return "Switched to reasoner." }
            return try await agent.run(rest)

        case "/see", "/vision":
            conv.currentAgent = .vision
            guard !rest.isEmpty, let agent = conv.agents[.vision] else { return "Switched to vision." }
            return try await agent.run(rest)

        case "/chat":
            conv.currentAgent = .general
            guard !rest.isEmpty, let agent = conv.agents[.general] else { return "Switched to general." }
            return try await agent.run(rest)

        case "/knowledge", "/rag":
            conv.currentAgent = .rag
            guard !rest.isEmpty, let agent = conv.agents[.rag] else { return "Switched to knowledge agent." }
            return try await agent.run(rest)

        case "/plan":
            guard !rest.isEmpty else { return "Usage: /plan <task description>" }
            let agent = conv.agents[conv.currentAgent] ?? conv.agents[.general]!
            return try await agent.run(rest, plan: true)

        case "/remember":
            guard !rest.isEmpty else { return "Usage: /remember <text>" }
            let id = orchestrator.memoryStore.save(category: "note", content: rest)
            return "Remembered (id=\(id)): \(rest)"

        case "/memories":
            let memories = orchestrator.memoryStore.recall(category: rest.isEmpty ? nil : rest)
            if memories.isEmpty { return "No memories found." }
            return memories.map { "[id=\($0.id ?? 0)] [\($0.category)] \($0.content)" }.joined(separator: "\n")

        case "/ingest":
            return try await ingest(path: rest, orchestrator: orchestrator)

        case "/backend":
            return "Backend: Ollama (llama.cpp Metal). All inference runs through Ollama for maximum performance."

        case "/parallel":
            orchestrator.parallelAgentsEnabled.toggle()
            return "Parallel agent execution: \(orchestrator.parallelAgentsEnabled ? "enabled" : "disabled")"

        case "/moa":
            orchestrator.mixtureOfAgentsEnabled.toggle()
            return "Mixture of Agents: \(orchestrator.mixtureOfAgentsEnabled ? "enabled" : "disabled")"

        case "/workflows":
            let tools = orchestrator.compositeToolStore.listAll()
            if tools.isEmpty { return "No learned workflows. Use /learn to create one." }
            return tools.map { "• \($0.name) — \($0.description) (\($0.decodedSteps.count) steps, used \($0.timesUsed)x)" }
                .joined(separator: "\n")

        case "/learn":
            return learn(rest: rest, orchestrator: orchestrator)

        case "/help":
            return helpText

        default:
            return "Unknown command: \(cmd). Type /help for commands."
        }
    }

    // MARK: - Subcommands

    private static func status(conv: Orchestrator.ConversationState, orchestrator: Orchestrator) async throws -> String {
        let models = try await orchestrator.client.listModels()
        let names = models.map(\.name).joined(separator: ", ")
        let memCount = orchestrator.memoryStore.recall(limit: 1000).count
        let chunkCount = orchestrator.chunkStore.totalChunkCount()
        let ingestedFiles = orchestrator.chunkStore.ingestedFiles()
        return """
        Models: \(names)
        Agent: \(conv.currentAgent.displayName)
        Backend: Ollama (llama.cpp Metal)
        Memories: \(memCount) (vector-indexed)
        Knowledge base: \(chunkCount) chunks from \(ingestedFiles.count) files
        Parallel agents: \(orchestrator.parallelAgentsEnabled ? "on" : "off")
        Mixture of Agents: \(orchestrator.mixtureOfAgentsEnabled ? "on" : "off")
        """
    }

    private static func ingest(path: String, orchestrator: Orchestrator) async throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Usage: /ingest <file or directory path>" }

        let ingester = DocumentIngester(
            client: orchestrator.activeClient,
            embeddingModel: orchestrator.modelConfig.embedding,
            chunkStore: orchestrator.chunkStore
        )

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir) else {
            return "Path not found: \(trimmed)"
        }

        if isDir.boolValue {
            let result = try await ingester.ingestDirectory(at: trimmed)
            return "Ingested \(result.files) files (\(result.chunks) chunks) into knowledge base."
        } else {
            let chunks = try await ingester.ingestFile(at: trimmed)
            return "Ingested \(URL(fileURLWithPath: trimmed).lastPathComponent): \(chunks) chunks."
        }
    }

    private static func learn(rest: String, orchestrator: Orchestrator) -> String {
        guard !rest.isEmpty else {
            return """
            Usage: /learn <name> | <description> | <trigger phrase>
            Example: /learn deploy_app | Deploy the app to production | deploy the app
            """
        }
        let parts = rest.components(separatedBy: " | ")
        guard parts.count >= 3 else {
            return "Format: /learn <name> | <description> | <trigger phrase>"
        }
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        let desc = parts[1].trimmingCharacters(in: .whitespaces)
        let trigger = parts[2].trimmingCharacters(in: .whitespaces)

        let id = orchestrator.compositeToolStore.save(name: name, description: desc, steps: [], triggerPhrase: trigger)
        return "Created workflow '\(name)' (id=\(id)). Trigger: \"\(trigger)\""
    }

    /// Pulls history from the most-active agent and asks the router model
    /// to summarize it into an Episode. Fire-and-forget — never blocks /clear.
    private static func recordEpisodeFromConversation(
        conv: Orchestrator.ConversationState,
        orchestrator: Orchestrator
    ) async {
        // Pick the agent with the longest history (most active)
        var bestAgent: BaseAgent?
        var bestCount = 0
        for (_, agent) in conv.agents where agent.history.count > bestCount {
            bestAgent = agent
            bestCount = agent.history.count
        }
        guard let agent = bestAgent, bestCount > 2 else { return }

        let messages = agent.history
        let started = conv.sessionStartedAt
        let ended = Date()
        let client = orchestrator.client
        let model = orchestrator.modelConfig.router  // tiny model for cheap summary

        Task.detached {
            await EpisodicMemory.shared.recordEpisode(
                messages: messages,
                startedAt: started,
                endedAt: ended,
                client: client,
                model: model
            )
        }
    }

    private static let helpText = """
    Commands:
      /code <msg> — force coding agent
      /think <msg> — force reasoning agent
      /see <msg> — force vision agent
      /chat <msg> — force general agent
      /knowledge <msg> — force knowledge/RAG agent
      /plan <task> — force planning mode
      /ingest <path> — ingest file/directory into knowledge base
      /remember <text> — save to memory
      /memories [category] — list memories
      /learn <name> | <desc> | <trigger> — create a reusable workflow
      /workflows — list learned workflows
      /backend — show inference backend info
      /parallel — toggle parallel agent execution
      /moa — toggle Mixture of Agents
      /clear — reset conversation
      /status — system info
    """
}
