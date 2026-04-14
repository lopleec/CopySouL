import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var screenRecordingGranted = ScreenRecordingPermission.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Model Settings")
                .font(.title2.weight(.semibold))

            ProviderSettingsForm()
            PermissionGrantPanel(screenRecordingGranted: $screenRecordingGranted)

            HStack {
                Spacer()
                Button("Save") {
                    viewModel.saveConfiguration()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .background(.thinMaterial)
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var screenRecordingGranted = ScreenRecordingPermission.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set up CopySouL")
                    .font(.largeTitle.weight(.semibold))
                Text("Choose the model provider for chat, image understanding, and the smaller memory summarizer.")
                    .foregroundStyle(.secondary)
            }

            ProviderSettingsForm()
            PermissionGrantPanel(screenRecordingGranted: $screenRecordingGranted)

            HStack {
                Spacer()
                Button("Start") {
                    viewModel.saveConfiguration()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .background(.thinMaterial)
    }
}

private struct PermissionGrantPanel: View {
    @Binding var screenRecordingGranted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: screenRecordingGranted ? "checkmark.circle.fill" : "record.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(screenRecordingGranted ? Color.green : Color.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Screen Recording")
                        .font(.system(size: 14, weight: .semibold))
                    Text(screenRecordingGranted ? "take_screenshot is ready." : "Grant permission for take_screenshot.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(screenRecordingGranted ? "Open Settings" : "Grant Permission") {
                    if ScreenRecordingPermission.request() == false {
                        ScreenRecordingPermission.openSystemSettings()
                    }
                    screenRecordingGranted = ScreenRecordingPermission.isGranted
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
        .onAppear {
            screenRecordingGranted = ScreenRecordingPermission.isGranted
        }
    }
}

private struct ProviderSettingsForm: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                Text("Provider")
                    .foregroundStyle(.secondary)
                Picker("", selection: $viewModel.configuration.provider) {
                    ForEach(ProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
            }

            GridRow {
                Text("Base URL")
                    .foregroundStyle(.secondary)
                TextField("https://api.openai.com", text: baseURLBinding)
                    .textFieldStyle(.roundedBorder)
            }

            GridRow {
                Text("API key")
                    .foregroundStyle(.secondary)
                SecureField("Stored in Keychain", text: $viewModel.apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
            }

            GridRow {
                Text("Chat models")
                    .foregroundStyle(.secondary)
                ModelListEditor(slot: .chat)
            }

            GridRow {
                Text("Vision models")
                    .foregroundStyle(.secondary)
                ModelListEditor(slot: .vision)
            }

            GridRow {
                Text("Memory models")
                    .foregroundStyle(.secondary)
                ModelListEditor(slot: .memory)
            }
        }
        .onChange(of: viewModel.configuration.provider) {
            applyProviderDefaults()
        }
    }

    private var baseURLBinding: Binding<String> {
        Binding {
            viewModel.configuration.baseURL.absoluteString
        } set: { value in
            if let url = URL(string: value) {
                viewModel.configuration.baseURL = url
            }
        }
    }

    private func applyProviderDefaults() {
        switch viewModel.configuration.provider {
        case .openAICompatible:
            viewModel.configuration.baseURL = URL(string: "https://api.openai.com")!
        case .claude:
            viewModel.configuration.baseURL = URL(string: "https://api.anthropic.com")!
        case .gemini:
            viewModel.configuration.baseURL = URL(string: "https://generativelanguage.googleapis.com")!
        case .ollamaCompatible:
            viewModel.configuration.baseURL = URL(string: "http://localhost:11434")!
        }
        viewModel.applyProviderDefaults()
    }
}

private struct ModelListEditor: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let slot: LLMModelSlot
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: selection) {
                ForEach(viewModel.configuration.models(for: slot), id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .labelsHidden()

            HStack(spacing: 8) {
                TextField("Add \(slot.title.lowercased()) model", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addModel)

                Button {
                    addModel()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    viewModel.removeSelectedModel(for: slot)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.configuration.models(for: slot).count <= 1)
            }
        }
    }

    private var selection: Binding<String> {
        Binding {
            viewModel.configuration.selectedModel(for: slot)
        } set: { model in
            viewModel.selectModel(model, for: slot)
        }
    }

    private func addModel() {
        viewModel.addModel(draft, for: slot)
        draft = ""
    }
}
