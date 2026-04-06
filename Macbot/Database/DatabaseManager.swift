import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()

    let dbPool: DatabasePool

    private init() {
        guard let appSupportBase = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            fatalError("[database] could not locate Application Support directory")
        }
        let appSupport = appSupportBase.appendingPathComponent("Macbot", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        } catch {
            Log.app.error("[database] failed to create app support directory: \(error)")
            fatalError("[database] failed to create app support directory: \(error)")
        }

        let dbPath = appSupport.appendingPathComponent("macbot.db").path
        do {
            dbPool = try DatabasePool(path: dbPath)
        } catch {
            Log.app.error("[database] failed to open database at \(dbPath): \(error)")
            fatalError("[database] failed to open database: \(error)")
        }

        do {
            try migrator.migrate(dbPool)
        } catch {
            Log.app.error("[database] migration failed: \(error)")
            fatalError("[database] migration failed: \(error)")
        }
        Log.app.info("Database ready at \(dbPath)")
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "memories") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("category", .text).notNull()
                t.column("content", .text).notNull()
                t.column("metadata", .text).defaults(to: "{}")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_memories_category", on: "memories", columns: ["category"])

            try db.create(table: "conversations") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("userId", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("messageCount", .integer).defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_conversations_user", on: "conversations", columns: ["userId"])
        }

        migrator.registerMigration("v2_chat_history") { db in
            try db.create(table: "chats") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("lastMessage", .text).notNull().defaults(to: "")
                t.column("agentCategory", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "chat_messages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("chatId", .text).notNull().references("chats", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("agentCategory", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_chat_messages_chatId", on: "chat_messages", columns: ["chatId"])
        }

        // RAG document chunks and ingestion tracking
        migrator.registerMigration("v3_rag") { db in
            try db.create(table: "document_chunks") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sourceFile", .text).notNull()
                t.column("chunkIndex", .integer).notNull()
                t.column("content", .text).notNull()
                t.column("embedding", .blob).notNull()
                t.column("tokenCount", .integer).defaults(to: 0)
                t.column("metadata", .text).defaults(to: "{}")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_chunks_source", on: "document_chunks", columns: ["sourceFile"])

            try db.create(table: "ingested_files") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("filePath", .text).notNull().unique()
                t.column("fileHash", .text).notNull()
                t.column("chunkCount", .integer).defaults(to: 0)
                t.column("totalTokens", .integer).defaults(to: 0)
                t.column("ingestedAt", .datetime).notNull()
                t.column("modifiedAt", .datetime).notNull()
            }
        }

        // Vector embeddings for semantic memory search
        migrator.registerMigration("v4_memory_embeddings") { db in
            try db.alter(table: "memories") { t in
                t.add(column: "embedding", .blob)
            }
        }

        // Composite tools (learned workflows)
        migrator.registerMigration("v5_composite_tools") { db in
            try db.create(table: "composite_tools") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("description", .text).notNull()
                t.column("steps", .text).notNull()
                t.column("triggerPhrase", .text).notNull()
                t.column("timesUsed", .integer).defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        // Episodic memory — auto-summarized conversation episodes
        migrator.registerMigration("v6_episodes") { db in
            try db.create(table: "episodes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("topics", .text).defaults(to: "[]")  // JSON array of strings
                t.column("messageCount", .integer).defaults(to: 0)
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime).notNull()
                t.column("embedding", .blob)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_episodes_startedAt", on: "episodes", columns: ["startedAt"])
        }

        return migrator
    }
}
