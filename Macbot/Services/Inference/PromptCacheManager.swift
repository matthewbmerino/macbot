import Foundation
import MLX

/// Manages pre-computed KV cache states for system prompts.
///
/// When an agent's system prompt hasn't changed, we can skip re-encoding it
/// by restoring the cached KV state. This saves re-processing 500+ tokens
/// on every turn for each agent.
actor PromptCacheManager {
    struct CacheEntry {
        let promptHash: Int
        let tokenCount: Int
        let kvStates: [(keys: MLXArray, values: MLXArray)]  // Per-layer KV cache
        let cachedAt: Date
        var hitCount: Int = 0
    }

    private var cache: [String: CacheEntry] = [:]  // key: agent name
    private let maxEntries = 6
    private let ttl: TimeInterval = 3600  // 1 hour

    /// Cache a KV state for an agent's system prompt.
    func store(
        agentName: String,
        prompt: String,
        tokenCount: Int,
        kvStates: [(keys: MLXArray, values: MLXArray)]
    ) {
        evictStale()

        cache[agentName] = CacheEntry(
            promptHash: prompt.hashValue,
            tokenCount: tokenCount,
            kvStates: kvStates,
            cachedAt: Date()
        )

        Log.inference.info("[prompt-cache] stored KV cache for '\(agentName)' (\(tokenCount) tokens, \(kvStates.count) layers)")
    }

    /// Retrieve cached KV states if the prompt hasn't changed.
    func retrieve(agentName: String, prompt: String) -> CacheEntry? {
        guard let entry = cache[agentName],
              entry.promptHash == prompt.hashValue,
              Date().timeIntervalSince(entry.cachedAt) < ttl
        else { return nil }

        cache[agentName]?.hitCount += 1
        Log.inference.info("[prompt-cache] hit for '\(agentName)' (hit #\(entry.hitCount + 1))")
        return entry
    }

    /// Check if a cached prompt is still valid.
    func isValid(agentName: String, prompt: String) -> Bool {
        guard let entry = cache[agentName] else { return false }
        return entry.promptHash == prompt.hashValue
            && Date().timeIntervalSince(entry.cachedAt) < ttl
    }

    /// Get cached token count for an agent's system prompt.
    func tokenCount(for agentName: String) -> Int? {
        cache[agentName]?.tokenCount
    }

    func invalidate(agentName: String) {
        cache.removeValue(forKey: agentName)
    }

    func invalidateAll() {
        cache.removeAll()
    }

    /// Get cache stats.
    func stats() -> [(agent: String, hits: Int, tokens: Int, age: TimeInterval)] {
        let now = Date()
        return cache.map {
            ($0.key, $0.value.hitCount, $0.value.tokenCount, now.timeIntervalSince($0.value.cachedAt))
        }
    }

    private func evictStale() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.cachedAt) < ttl }

        if cache.count >= maxEntries {
            let sorted = cache.sorted { $0.value.hitCount < $1.value.hitCount }
            for key in sorted.prefix(cache.count - maxEntries + 1).map(\.key) {
                cache.removeValue(forKey: key)
            }
        }
    }
}
