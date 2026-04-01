import os

enum Log {
    static let inference = Logger(subsystem: "com.macbot", category: "inference")
    static let agents = Logger(subsystem: "com.macbot", category: "agents")
    static let tools = Logger(subsystem: "com.macbot", category: "tools")
    static let memory = Logger(subsystem: "com.macbot", category: "memory")
    static let app = Logger(subsystem: "com.macbot", category: "app")
}
