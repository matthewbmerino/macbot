import Foundation
import SwiftUI

@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var isStreaming = false
    var currentStatus: String?
    var activeAgent: AgentCategory = .general
    var inputText = ""
    var pendingImages: [Data] = []

    private let orchestrator: Orchestrator
    private let userId = "local"

    init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
    }

    @MainActor
    func send(images: [Data]? = nil) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingImages.isEmpty else { return }

        let attachedImages = images ?? (pendingImages.isEmpty ? nil : pendingImages)
        inputText = ""
        pendingImages = []

        var userMsg = ChatMessage(role: .user, content: text.isEmpty ? "What's in this image?" : text)
        userMsg.images = attachedImages
        messages.append(userMsg)
        isStreaming = true
        currentStatus = nil

        Task {
            var responseText = ""
            var agentCategory: AgentCategory?

            do {
                for try await event in orchestrator.handleMessageStream(
                    userId: userId, message: text.isEmpty ? "What's in this image?" : text, images: attachedImages
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
                let errorMsg = "Something went wrong: \(error.localizedDescription)"
                Log.agents.error("Chat error: \(error)")
                await MainActor.run {
                    updateLastAgentMessage(errorMsg, agent: agentCategory)
                }
            }

            await MainActor.run {
                if messages.last?.role != .assistant {
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: responseText.isEmpty ? "No response — Ollama may still be loading the model. Try again in a moment." : responseText,
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
