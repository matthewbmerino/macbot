import Foundation

struct ModelConfig: Codable {
    var general: String = "qwen3.5:9b"
    var coder: String = "devstral-small-2"
    var vision: String = "qwen3-vl:8b"
    var reasoner: String = "deepseek-r1:14b"
    var router: String = "qwen3.5:0.8b"
    var embedding: String = "qwen3-embedding:0.6b"

    func model(for category: AgentCategory) -> String {
        switch category {
        case .general: general
        case .coder: coder
        case .vision: vision
        case .reasoner: reasoner
        case .rag: general
        }
    }

    var numCtx: [AgentCategory: Int] {
        [.general: 32768, .coder: 65536, .vision: 16384, .reasoner: 32768]
    }
}
