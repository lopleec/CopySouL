import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var showingImageImporter = false
    @State private var addingModelSlot: LLMModelSlot?

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.70))
                .frame(height: 1)

            messageList
            InputBar(showingImageImporter: $showingImageImporter)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $showingImageImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                viewModel.attachImages(from: urls)
            }
        }
        .sheet(item: $addingModelSlot) { slot in
            AddModelSheet(slot: slot)
                .environmentObject(viewModel)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if !viewModel.isSidebarVisible {
                Button {
                    viewModel.isSidebarVisible = true
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show sidebar")
            }

            HStack(spacing: 6) {
                Text(viewModel.selectedSoul?.name ?? "CopySouL")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                HeaderModelMenu(addingModelSlot: $addingModelSlot)
            }

            Spacer()
        }
        .padding(.leading, 22)
        .padding(.trailing, 24)
        .frame(height: 52)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 1)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 26)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: viewModel.messages.count) {
                if let id = viewModel.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct HeaderModelMenu: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Binding var addingModelSlot: LLMModelSlot?

    var body: some View {
        Menu {
            ForEach(LLMModelSlot.allCases) { slot in
                Menu(slot.title) {
                    ForEach(viewModel.configuration.models(for: slot), id: \.self) { model in
                        Button {
                            viewModel.selectModel(model, for: slot)
                        } label: {
                            if model == viewModel.configuration.selectedModel(for: slot) {
                                Label(model, systemImage: "checkmark")
                            } else {
                                Text(model)
                            }
                        }
                    }

                    Divider()

                    Button("Add \(slot.title) Model...") {
                        addingModelSlot = slot
                    }

                    Button("Delete Current \(slot.title) Model") {
                        viewModel.removeSelectedModel(for: slot)
                    }
                    .disabled(viewModel.configuration.models(for: slot).count <= 1)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(viewModel.configuration.chatModel.shortModelName)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: 180, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("Select models")
    }
}

private struct AddModelSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    let slot: LLMModelSlot
    @State private var modelName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add \(slot.title) Model")
                .font(.title3.weight(.semibold))

            TextField("Model name", text: $modelName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addModel)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Add") {
                    addModel()
                }
                .buttonStyle(.borderedProminent)
                .disabled(modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    private func addModel() {
        viewModel.addModel(modelName, for: slot)
        dismiss()
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 80) }

            VStack(alignment: .leading, spacing: 8) {
                if !message.content.isEmpty {
                    Text(message.content)
                        .textSelection(.enabled)
                        .font(.body)
                        .foregroundStyle(message.role == .user ? .white : .primary)
                }

                ForEach(message.attachments) { attachment in
                    AttachmentPreview(attachment: attachment)
                }

                if let meme = message.selectedMeme {
                    MemePreview(asset: meme)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(message.role == .user ? Color.accentColor.opacity(0.90) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: 620, alignment: message.role == .user ? .trailing : .leading)

            if message.role != .user { Spacer(minLength: 80) }
        }
    }
}

private struct InputBar: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Binding var showingImageImporter: Bool

    var body: some View {
        VStack(spacing: 10) {
            if !viewModel.pendingAttachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.pendingAttachments) { attachment in
                            AttachmentChip(attachment: attachment) {
                                viewModel.removeAttachment(attachment)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 74)
                .frame(maxWidth: 960)
            }

            VStack(spacing: 0) {
                TextField("有问题，尽管问", text: $viewModel.draftText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.top, 13)
                    .padding(.bottom, 8)
                    .onSubmit {
                        viewModel.sendMessage()
                    }

                HStack(spacing: 18) {
                    inputIcon("plus") {
                        showingImageImporter = true
                    }
                    inputIcon(viewModel.allowsScreenAccess ? "eye.fill" : "eye", isActive: viewModel.allowsScreenAccess) {
                        viewModel.toggleScreenAccess()
                    }

                    Spacer()

                    Button {
                        viewModel.sendMessage()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(viewModel.selectedSoul == nil ? Color.secondary : Color(nsColor: .windowBackgroundColor))
                            .frame(width: 34, height: 34)
                            .background(viewModel.selectedSoul == nil ? Color.secondary.opacity(0.20) : Color.primary.opacity(0.62))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.selectedSoul == nil)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: 960)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)
            )
            .shadow(color: Color.primary.opacity(0.08), radius: 8, y: 2)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .padding(.top, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func inputIcon(_ name: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 17))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 18, height: 26)
        }
        .buttonStyle(.plain)
    }
}

private extension String {
    var shortModelName: String {
        guard count > 22 else { return self }
        return "\(prefix(10))...\(suffix(8))"
    }
}

private struct AttachmentChip: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AttachmentPreview(attachment: attachment)
                .frame(width: 72, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .padding(4)
        }
    }
}

private struct AttachmentPreview: View {
    let attachment: ChatAttachment

    var body: some View {
        if let image = NSImage(contentsOf: attachment.url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: 260, maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Label(attachment.url.lastPathComponent, systemImage: "photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MemePreview: View {
    let asset: SoulAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AttachmentPreview(attachment: ChatAttachment(url: asset.fileURL, mimeType: asset.fileURL.pathExtension))
            Text(asset.relativePath)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
