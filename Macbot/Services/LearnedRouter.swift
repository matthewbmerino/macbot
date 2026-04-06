import Foundation

/// Learned tool/agent prediction via k-NN over the trace store.
/// When a new query arrives, embed it, retrieve the K nearest past
/// interactions, and vote on agent + tool selection. Cheap, no training,
/// improves continuously as the trace store grows.
///
/// This is the first concrete application of the bitter lesson in macbot:
/// hand-coded keyword routing eventually loses to a tiny learned model
/// trained on the user's actual interaction history.
struct LearnedPrediction {
    let agent: String?           // most-voted agent, nil if no consensus
    let agentConfidence: Float   // top vote / total votes
    let tools: [String]          // tools to bias toward
    let neighborCount: Int       // how many similar past turns voted
    let topSimilarity: Float     // how similar the closest neighbor was
}

enum LearnedRouter {

    /// Embed the query, k-NN over traces, vote on agent + tools.
    /// Returns nil if there are no useful neighbors above the similarity floor.
    static func predict(
        query: String,
        client: any InferenceProvider,
        embeddingModel: String,
        topK: Int = 8,
        minSimilarity: Float = 0.55
    ) async -> LearnedPrediction? {
        // Embed the query
        let queryVec: [Float]
        do {
            let vecs = try await client.embed(model: embeddingModel, text: [query])
            guard let v = vecs.first, !v.isEmpty else { return nil }
            queryVec = v
        } catch {
            return nil
        }

        let neighbors = TraceStore.shared.searchSimilar(embedding: queryVec, topK: topK)
        let filtered = neighbors.filter { $0.1 >= minSimilarity }
        guard !filtered.isEmpty else { return nil }

        // Vote on agent — weighted by similarity
        var agentScores: [String: Float] = [:]
        var toolScores: [String: Float] = [:]
        var totalWeight: Float = 0
        for (trace, sim) in filtered {
            agentScores[trace.routedAgent, default: 0] += sim
            totalWeight += sim
            for call in trace.toolCallList {
                if let name = call["name"] as? String {
                    toolScores[name, default: 0] += sim
                }
            }
        }

        let topAgent = agentScores.max { $0.value < $1.value }
        let agentConfidence: Float
        if let top = topAgent, totalWeight > 0 {
            agentConfidence = top.value / totalWeight
        } else {
            agentConfidence = 0
        }

        // Tool list: any tool that appeared in at least 25% of weighted neighbors
        let toolThreshold = totalWeight * 0.25
        let predictedTools = toolScores
            .filter { $0.value >= toolThreshold }
            .sorted { $0.value > $1.value }
            .map(\.key)

        return LearnedPrediction(
            agent: topAgent?.key,
            agentConfidence: agentConfidence,
            tools: predictedTools,
            neighborCount: filtered.count,
            topSimilarity: filtered.first?.1 ?? 0
        )
    }
}
