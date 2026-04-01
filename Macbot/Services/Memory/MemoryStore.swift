import Foundation
import GRDB

struct Memory: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var category: String
    var content: String
    var metadata: String
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "memories"
}

struct ConversationSummary: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var userId: String
    var summary: String
    var messageCount: Int
    var createdAt: Date

    static let databaseTableName = "conversations"
}

final class MemoryStore {
    private let db: DatabasePool

    init(db: DatabasePool = DatabaseManager.shared.dbPool) {
        self.db = db
    }

    @discardableResult
    func save(category: String, content: String, metadata: String = "{}") -> Int64 {
        let now = Date()
        var memory = Memory(
            category: category, content: content, metadata: metadata,
            createdAt: now, updatedAt: now
        )
        try! db.write { db in
            try memory.insert(db)
        }
        return memory.id!
    }

    func recall(category: String? = nil, limit: Int = 20) -> [Memory] {
        try! db.read { db in
            var query = Memory.order(Column("updatedAt").desc).limit(limit)
            if let category {
                query = query.filter(Column("category") == category)
            }
            return try query.fetchAll(db)
        }
    }

    func search(query: String, limit: Int = 10) -> [Memory] {
        try! db.read { db in
            try Memory
                .filter(Column("content").like("%\(query)%"))
                .order(Column("updatedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func forget(memoryId: Int64) -> Bool {
        try! db.write { db in
            try Memory.deleteOne(db, id: memoryId)
        }
    }

    func saveConversationSummary(userId: String, summary: String, messageCount: Int) {
        var record = ConversationSummary(
            userId: userId, summary: summary,
            messageCount: messageCount, createdAt: Date()
        )
        try! db.write { db in
            try record.insert(db)
        }
    }

    func getRecentConversations(userId: String, limit: Int = 3) -> [ConversationSummary] {
        try! db.read { db in
            try ConversationSummary
                .filter(Column("userId") == userId)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func formatForPrompt(limit: Int = 15) -> String {
        let memories = recall(limit: limit)
        guard !memories.isEmpty else { return "" }

        var lines = ["[Persistent Memory]"]
        for m in memories {
            lines.append("- [\(m.category)] \(m.content)")
        }
        return lines.joined(separator: "\n")
    }
}
