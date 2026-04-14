import SwiftUI

struct RootView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 0) {
            if viewModel.isSidebarVisible {
                SidebarView()
                    .frame(width: 252)
            }

            ChatView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.clear)
        .background(WindowConfigurator())
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $viewModel.showingOnboarding) {
            OnboardingView()
                .environmentObject(viewModel)
                .frame(width: 620)
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
