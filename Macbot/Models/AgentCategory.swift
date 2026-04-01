import Foundation

enum AgentCategory: String, Codable, CaseIterable, Identifiable {
    case general
    case coder
    case vision
    case reasoner
    case rag

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: "General"
        case .coder: "Coder"
        case .vision: "Vision"
        case .reasoner: "Reasoner"
        case .rag: "Knowledge"
        }
    }
}
