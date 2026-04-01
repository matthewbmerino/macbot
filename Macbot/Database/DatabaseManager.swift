import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()

    let dbPool: DatabasePool

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Macbot", isDirectory: true)

        try! FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let dbPath = appSupport.appendingPathComponent("macbot.db").path
        dbPool = try! DatabasePool(path: dbPath)

        try! migrator.migrate(dbPool)
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

        return migrator
    }
}
