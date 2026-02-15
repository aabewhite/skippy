import SwiftUI

struct NewEmulatorView: View {
    @Environment(EmulatorManager.self) private var manager
    @State private var selectedProfile: DeviceProfile?
    @State private var selectedAPILevel: APILevel?
    @State private var name: String = ""
    @State private var isAutoUpdatingName: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Device Profile", selection: $selectedProfile) {
                    Text("Select...").tag(nil as DeviceProfile?)
                    ForEach(manager.deviceProfiles) { profile in
                        Text(profile.name).tag(profile as DeviceProfile?)
                    }
                }
                .disabled(manager.isLoadingProfiles)

                Picker("API Level", selection: $selectedAPILevel) {
                    Text("Select...").tag(nil as APILevel?)
                    ForEach(manager.apiLevels) { level in
                        Text("\(level.name) (API \(level.level))").tag(level as APILevel?)
                    }
                }
                .disabled(manager.isLoadingLevels)

                TextField("Name", text: $name)
                    .onChange(of: name) {
                        // If the user manually edits the name, stop auto-updating
                        let autoName = generateAutoName()
                        if name != autoName {
                            isAutoUpdatingName = false
                        }
                    }
            }
            .formStyle(.grouped)

            if !manager.createOutput.isEmpty {
                Divider()
                ScrollView {
                    Text(manager.createOutput)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(WindowFrameSaver(name: "newEmulatorWindow"))
        .navigationTitle("New Emulator")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    guard let profile = selectedProfile, let apiLevel = selectedAPILevel else { return }
                    manager.createEmulator(name: name, deviceProfile: profile, apiLevel: apiLevel)
                }
                .disabled(selectedProfile == nil || selectedAPILevel == nil || name.isEmpty || manager.isCreating)
            }
        }
        .onChange(of: selectedProfile) {
            if isAutoUpdatingName || name.isEmpty {
                isAutoUpdatingName = true
                name = generateAutoName()
            }
        }
        .onChange(of: selectedAPILevel) {
            if isAutoUpdatingName || name.isEmpty {
                isAutoUpdatingName = true
                name = generateAutoName()
            }
        }
        .onAppear {
            if manager.deviceProfiles.isEmpty { manager.loadDeviceProfiles() }
            if manager.apiLevels.isEmpty { manager.loadAPILevels() }
        }
        .onChange(of: manager.deviceProfiles) {
            if selectedProfile == nil {
                selectedProfile = manager.deviceProfiles.first(where: { $0.id == "pixel_7" })
            }
        }
        .onChange(of: manager.apiLevels) {
            if selectedAPILevel == nil {
                selectedAPILevel = manager.apiLevels.first(where: { $0.level == 34 })
            }
        }
    }

    private func generateAutoName() -> String {
        guard let profile = selectedProfile, let level = selectedAPILevel else { return "" }
        let baseName = "\(profile.id)_\(level.level)"
        if !manager.emulators.contains(baseName) {
            return baseName
        }
        var counter = 2
        while manager.emulators.contains("\(baseName)_\(counter)") {
            counter += 1
        }
        return "\(baseName)_\(counter)"
    }
}
