import Foundation
import SwiftUI

@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var isStreaming = false
    var currentStatus: String?
    var activeAgent: AgentCategory = .general
    var inputText = ""

    private let orchestrator: Orchestrator
    private let userId = "local"

    init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
    }

    @MainActor
    func send(images: [Data]? = nil) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        messages.append(ChatMessage(role: .user, content: text))
        isStreaming = true
        currentStatus = nil

        Task {
            var responseText = ""
            var agentCategory: AgentCategory?

            do {
                for try await event in orchestrator.handleMessageStream(
                    userId: userId, message: text, images: images
                ) {
                    await MainActor.run {
                        switch event {
                        case .text(let chunk):
                            responseText += chunk
                            currentStatus = nil
                            updateLastAgentMessage(responseText, agent: agentCategory)

                        case .status(let status):
                            currentStatus = status

                        case .agentSelected(let category):
                            agentCategory = category
                            activeAgent = category

                        case .image(let data, _):
                            // Store image data for display
                            if var last = messages.last, last.role == .assistant {
                                messages.removeLast()
                                var images = last.images ?? []
                                images.append(data)
                                last.images = images
                                messages.append(last)
                            }
                        }
                    }
                }
            } catch {
                responseText = "Error: \(error.localizedDescription)"
            }

            await MainActor.run {
                if responseText.isEmpty && messages.last?.role != .assistant {
                    messages.append(ChatMessage(
                        role: .assistant, content: "No response generated.",
                        agentCategory: agentCategory
                    ))
                }
                isStreaming = false
                currentStatus = nil
            }
        }
    }

    @MainActor
    private func updateLastAgentMessage(_ text: String, agent: AgentCategory?) {
        if let last = messages.last, last.role == .assistant {
            messages[messages.count - 1] = ChatMessage(
                role: .assistant, content: text, agentCategory: agent
            )
        } else {
            messages.append(ChatMessage(
                role: .assistant, content: text, agentCategory: agent
            ))
        }
    }

    func clearConversation() {
        messages.removeAll()
        Task {
            _ = try? await orchestrator.handleMessage(userId: userId, message: "/clear")
        }
    }
}
