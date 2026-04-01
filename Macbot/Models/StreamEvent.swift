import Foundation

enum StreamEvent {
    case text(String)
    case status(String)
    case image(Data, String)  // image data, filename
    case agentSelected(AgentCategory)
}
