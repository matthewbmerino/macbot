import SwiftUI
import MarkdownUI

/// Three-pane notebook UI: notebooks sidebar | pages list | editor.
///
/// Pattern-matched from Apple Notes / Evernote. Left pane holds notebooks
/// (folders). Middle pane lists pages in the selected notebook. Right pane
/// is the Markdown editor with live preview toggle.
struct NotebookView: View {
    @Bindable var viewModel: NotebookViewModel

    @State private var renamingNotebookId: String?
    @State private var notebookRenameField: String = ""
    @State private var isPreviewing: Bool = false
    @FocusState private var titleFocused: Bool
    @FocusState private var contentFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            notebooksPane
                .frame(width: 200)
                .background(MacbotDS.Mat.chrome)

            Divider()

            pagesPane
                .frame(width: 260)

            Divider()

            editorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacbotDS.Colors.bg)
        }
        .onAppear {
            if viewModel.currentNotebookId == nil {
                viewModel.bootstrap()
            }
        }
    }

    // MARK: - Notebooks pane (left)

    private var notebooksPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader(title: "Notebooks", trailingIcon: "plus") {
                viewModel.createNotebook()
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.notebooks) { notebook in
                        notebookRow(notebook)
                    }
                }
                .padding(.vertical, MacbotDS.Space.xs)
            }
        }
    }

    private func notebookRow(_ notebook: NotebookRecord) -> some View {
        let isSelected = viewModel.currentNotebookId == notebook.id
        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isSelected ? MacbotDS.Colors.accent : .clear)
                .frame(width: 3)
                .padding(.vertical, 4)

            if renamingNotebookId == notebook.id {
                TextField("Notebook name", text: $notebookRenameField)
                    .textFieldStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MacbotDS.Colors.textPri)
                    .padding(.horizontal, MacbotDS.Space.sm)
                    .padding(.vertical, MacbotDS.Space.sm)
                    .onSubmit {
                        let trimmed = notebookRenameField.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            viewModel.renameNotebook(id: notebook.id, to: trimmed)
                        }
                        renamingNotebookId = nil
                    }
                    .onKeyPress(.escape) {
                        renamingNotebookId = nil
                        return .handled
                    }
            } else {
                HStack(spacing: MacbotDS.Space.sm) {
                    Image(systemName: "book.closed")
                        .font(.caption)
                        .foregroundStyle(isSelected ? MacbotDS.Colors.accent : MacbotDS.Colors.textTer)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(notebook.title)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? MacbotDS.Colors.textPri : MacbotDS.Colors.textSec)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, MacbotDS.Space.sm)
                .padding(.vertical, MacbotDS.Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, MacbotDS.Space.xs)
        .background(isSelected ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear))
        .clipShape(RoundedRectangle(cornerRadius: MacbotDS.Radius.sm, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { viewModel.selectNotebook(notebook.id) }
        .contextMenu {
            Button("Rename") {
                notebookRenameField = notebook.title
                renamingNotebookId = notebook.id
            }
            Button("New page in this notebook") {
                viewModel.createPage(inNotebook: notebook.id, openIt: true)
            }
            if viewModel.notebooks.count > 1 {
                Button("Delete", role: .destructive) {
                    viewModel.deleteNotebook(id: notebook.id)
                }
            }
        }
    }

    // MARK: - Pages pane (middle)

    private var pagesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader(title: "Pages", trailingIcon: "square.and.pencil") {
                viewModel.createPageInCurrentNotebook()
            }

            Divider()

            if viewModel.pages.isEmpty {
                emptyPagesState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.pages) { page in
                            pageRow(page)
                            Divider().padding(.horizontal, MacbotDS.Space.md)
                        }
                    }
                }
            }
        }
    }

    private func pageRow(_ page: PageSummary) -> some View {
        let isSelected = viewModel.currentPageId == page.id
        return VStack(alignment: .leading, spacing: 4) {
            Text(page.title.isEmpty ? "Untitled" : page.title)
                .font(.callout.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? MacbotDS.Colors.textPri : MacbotDS.Colors.textPri)
                .lineLimit(1)

            Text(page.preview.isEmpty ? " " : page.preview)
                .font(.caption)
                .foregroundStyle(MacbotDS.Colors.textTer)
                .lineLimit(2)

            Text(page.updatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(MacbotDS.Colors.textTer)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MacbotDS.Space.md)
        .padding(.vertical, MacbotDS.Space.sm)
        .background(isSelected ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear))
        .contentShape(Rectangle())
        .onTapGesture { viewModel.loadPage(page.id) }
        .contextMenu {
            Button("Delete", role: .destructive) { viewModel.deletePage(page.id) }
        }
    }

    private var emptyPagesState: some View {
        VStack(alignment: .leading, spacing: MacbotDS.Space.sm) {
            Image(systemName: "doc.text")
                .font(.title3)
                .foregroundStyle(MacbotDS.Colors.textTer)
            Text("No pages yet. Press ⌘J or tap the pencil icon to create one.")
                .font(.caption)
                .foregroundStyle(MacbotDS.Colors.textTer)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(MacbotDS.Space.md)
    }

    // MARK: - Editor pane (right)

    @ViewBuilder
    private var editorPane: some View {
        if viewModel.currentPageId == nil {
            noPageState
        } else {
            VStack(spacing: 0) {
                editorHeader
                Divider()
                if isPreviewing {
                    ScrollView {
                        Markdown(viewModel.currentContent.isEmpty ? "_Nothing yet._" : viewModel.currentContent)
                            .markdownTheme(.basic)
                            .padding(.horizontal, MacbotDS.Space.xl * 2)
                            .padding(.vertical, MacbotDS.Space.xl)
                            .frame(maxWidth: 760, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    editorBody
                }
            }
        }
    }

    private var editorHeader: some View {
        HStack(spacing: MacbotDS.Space.md) {
            TextField("Untitled", text: $viewModel.currentTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(MacbotDS.Colors.textPri)
                .focused($titleFocused)
                .onChange(of: viewModel.currentTitle) { _, _ in
                    viewModel.scheduleTitleSave()
                }
                .onSubmit {
                    contentFocused = true
                }

            Spacer()

            Button(action: {
                withAnimation(Motion.snappy) { isPreviewing.toggle() }
            }) {
                HStack(spacing: MacbotDS.Space.xs) {
                    Image(systemName: isPreviewing ? "pencil" : "doc.richtext")
                        .font(.system(size: 10))
                    Text(isPreviewing ? "Edit" : "Preview")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(MacbotDS.Colors.textSec)
                .padding(.horizontal, MacbotDS.Space.sm)
                .padding(.vertical, MacbotDS.Space.xs)
                .background(.fill.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Toggle Markdown preview")
        }
        .padding(.horizontal, MacbotDS.Space.xl)
        .padding(.vertical, MacbotDS.Space.md)
    }

    private var editorBody: some View {
        TextEditor(text: $viewModel.currentContent)
            .font(.system(.body, design: .default))
            .foregroundStyle(MacbotDS.Colors.textPri)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, MacbotDS.Space.xl)
            .padding(.vertical, MacbotDS.Space.md)
            .focused($contentFocused)
            .onChange(of: viewModel.currentContent) { _, _ in
                viewModel.scheduleContentSave()
            }
    }

    private var noPageState: some View {
        VStack(spacing: MacbotDS.Space.md) {
            Image(systemName: "book.pages")
                .font(.largeTitle)
                .foregroundStyle(MacbotDS.Colors.textTer)
            Text("Select a notebook and create a page to start writing.")
                .font(.callout)
                .foregroundStyle(MacbotDS.Colors.textTer)
            Button("New Page (⌘J)") {
                viewModel.createPageInCurrentNotebook()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared chrome

    private func paneHeader(title: String, trailingIcon: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(MacbotDS.Colors.textTer)
                .kerning(0.5)
            Spacer()
            Button(action: action) {
                Image(systemName: trailingIcon)
                    .font(.caption)
                    .foregroundStyle(MacbotDS.Colors.textSec)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MacbotDS.Space.md)
        .padding(.vertical, MacbotDS.Space.sm)
    }
}
