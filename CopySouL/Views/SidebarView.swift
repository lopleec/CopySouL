import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var showingImporter = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    soulSection
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.visible)

            footer
        }
        .background(sidebarBackground)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.importSoulPack(from: url)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 82)

            Button {
                viewModel.isSidebarVisible.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.48))
            }
            .buttonStyle(.plain)
            .help("Collapse sidebar")

            Spacer()
        }
        .frame(height: 52)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField("搜索", text: $viewModel.soulSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 31)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var soulSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showingImporter = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .medium))
                    Text("导入 SOUL Pack")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.primary)
                .frame(height: 34)
                .padding(.horizontal, 10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("SOUL")
                .sidebarSectionLabel()
                .padding(.top, 24)

            if viewModel.filteredSouls.isEmpty {
                Text("没有匹配的 SOUL")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 34)
                    .padding(.horizontal, 10)
            } else {
                ForEach(viewModel.filteredSouls) { soul in
                    SoulRow(
                        soul: soul,
                        isSelected: soul.id == viewModel.selectedSoulID
                    ) {
                        viewModel.selectedSoulID = soul.id
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.55))
                .frame(height: 1)

            HStack(spacing: 7) {
                Text("CopySouL")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Button(action: openSettingsWindow) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")

                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(height: 50)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.28))
        }
    }

    private func openSettingsWindow() {
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private var sidebarBackground: some View {
        SidebarMaterial()
            .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.10))
    }

}

private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .sidebar
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

private struct SoulRow: View {
    let soul: SoulPack
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.70))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Text(String(soul.name.prefix(1)).uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.primary)
                    )

                Text(soul.name)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if soul.settings.enableMemeReplies {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 34)
            .padding(.horizontal, 10)
            .background(isSelected ? Color(nsColor: .controlBackgroundColor).opacity(0.70) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func sidebarSectionLabel() -> some View {
        self
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 30)
            .padding(.horizontal, 10)
    }
}
