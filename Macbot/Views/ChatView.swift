import SwiftUI
import MarkdownUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @FocusState private var inputFocused: Bool
    @State private var dragOver = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            chatContent
        }
        .frame(minWidth: 650, minHeight: 500)
        .onAppear { inputFocused = true }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header + New Chat
            HStack {
                Image(systemName: "brain")
                    .foregroundStyle(Color.accentColor)
                Text("Macbot")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.newChat() }) {
                    Image(systemName: "square.and.pencil")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("New Chat")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField("Search chats...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onChange(of: viewModel.searchQuery) { _, _ in
                        viewModel.search()
                    }
                if !viewModel.searchQuery.isEmpty {
                    Button(action: { viewModel.clearSearch() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider()

            // Search results or chat list
            if viewModel.isSearching {
                searchResultsList
            } else {
                chatList
            }

            Divider()

            // Status bar
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isStreaming ? Color.orange : Color.green)
                    .frame(width: 5, height: 5)
                Text(viewModel.isStreaming ? "Thinking..." : viewModel.activeAgent.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.chats.count) chats")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var chatList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(viewModel.chats) { chat in
                    chatRow(chat)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chatRow(_ chat: ChatRecord) -> some View {
        Button(action: { viewModel.selectChat(chat.id) }) {
            VStack(alignment: .leading, spacing: 3) {
                Text(chat.title)
                    .font(.caption)
                    .fontWeight(viewModel.currentChatId == chat.id ? .semibold : .regular)
                    .lineLimit(1)

                HStack {
                    Text(chat.lastMessage)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer()
                    Text(chat.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                viewModel.currentChatId == chat.id
                ? Color.accentColor.opacity(0.1)
                : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Delete", role: .destructive) {
                viewModel.deleteChat(chat.id)
            }
        }
    }

    private var searchResultsList: some View {
        ScrollView {
            if viewModel.searchResults.isEmpty {
                Text("No results for \"\(viewModel.searchQuery)\"")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding()
            } else {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(viewModel.searchResults.enumerated()), id: \.offset) { _, result in
                        Button(action: { viewModel.selectChat(result.message.chatId) }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.chatTitle)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(result.message.content)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    if viewModel.messages.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }

                            if let status = viewModel.currentStatus {
                                StatusIndicator(text: status)
                                    .padding(.horizontal, 20)
                                    .id("status")
                            }

                            if viewModel.isStreaming && viewModel.currentStatus == nil
                                && viewModel.messages.last?.role == .user {
                                typingIndicator
                                    .id("typing")
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .onChange(of: viewModel.messages.count) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if let lastId = viewModel.messages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Image preview
            if !viewModel.pendingImages.isEmpty {
                imagePreview
            }

            // Input bar
            inputBar
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $dragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
        .overlay {
            if dragOver {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .background(.ultraThinMaterial.opacity(0.3))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.largeTitle)
                            Text("Drop image to analyze")
                                .font(.caption)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .padding(4)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "brain")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("What can I help with?")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("All processing happens on this Mac.\nNothing leaves your network.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(0.4)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(i) * 0.2),
                        value: viewModel.isStreaming
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Image Preview

    private var imagePreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(viewModel.pendingImages.enumerated()), id: \.offset) { idx, data in
                    if let nsImage = NSImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button(action: { viewModel.pendingImages.remove(at: idx) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(.black.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 4, y: -4)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Attach button
            Button(action: { pickImage() }) {
                Image(systemName: "paperclip")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Attach image")

            TextField("Message macbot...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { sendMessage() }
                .disabled(viewModel.isStreaming)

            Button(action: { sendMessage() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
            }
            .disabled(!canSend)
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var canSend: Bool {
        (!viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || !viewModel.pendingImages.isEmpty)
        && !viewModel.isStreaming
    }

    // MARK: - Actions

    private func sendMessage() {
        viewModel.send()
        inputFocused = true
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let data = try? Data(contentsOf: url) {
                    viewModel.pendingImages.append(data)
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    if let image = image as? NSImage, let data = image.tiffRepresentation {
                        DispatchQueue.main.async {
                            viewModel.pendingImages.append(data)
                        }
                    }
                }
            }
        }
    }
}

struct AgentBadge: View {
    let category: AgentCategory

    var body: some View {
        Text(category.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary)
            .clipShape(Capsule())
    }
}
