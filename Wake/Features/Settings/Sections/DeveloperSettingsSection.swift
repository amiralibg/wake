import SwiftUI

struct DeveloperSettingsSection: View {
    @Environment(DeveloperSettings.self) private var developer
    @State private var editing: DevProject?

    var body: some View {
        @Bindable var developer = developer
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Developer mode") {
                SettingsRow(label: "On automatically for localhost", detail: "Captures console, network and hot reload for local dev servers. Any thread can switch it on or off (⌥⌘D).") {
                    Toggle("", isOn: $developer.autoEnableForLocalhost).toggleStyle(.switch).labelsHidden()
                }
                SettingsDivider()
                SettingsRow(label: "Find local dev servers", detail: "Checks ports 3000–3010, 4200, 5173–5180, 6006, 8000 and 8080 and lists them in the app capsule.") {
                    Toggle("", isOn: $developer.scansPorts).toggleStyle(.switch).labelsHidden()
                }
                SettingsDivider()
                SettingsRow(label: "Open in editor", detail: "Where console errors and inspected components open.") {
                    Picker("", selection: $developer.editor) {
                        ForEach(CodeEditor.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(label: "Web Inspector", detail: "WebKit's full inspector (debugger, Timelines, Layers) from DevTools and ⌥⇧⌘I, and Inspect Element in page menus. Applies to pages opened afterwards.") {
                    Toggle("", isOn: $developer.webInspectorEnabled).toggleStyle(.switch).labelsHidden()
                }
            }
            ProjectsGroup(editing: $editing)
        }
        .sheet(item: $editing) { project in
            ProjectEditor(project: project)
        }
    }
}

private struct ProjectsGroup: View {
    @Binding var editing: DevProject?
    private var store: DevProjectStore { .shared }

    var body: some View {
        SettingsGroup(title: "Projects") {
            if store.projects.isEmpty {
                Text("Add a project to switch between local, staging and production with the same path, see its git branch, and open errors in your editor.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
            ForEach(Array(store.projects.enumerated()), id: \.element.id) { index, project in
                if index > 0 { SettingsDivider() }
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .foregroundStyle(project.folderPath == nil ? Color.secondary : Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name).font(.system(size: 13, weight: .medium))
                        Text(DevEnvironment.allCases.compactMap { env in project.origins[env].map { "\(env.label): \($0)" } }.joined(separator: "  ·  "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Edit…") { editing = project }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            SettingsDivider()
            Button {
                editing = DevProject(name: "New Project")
            } label: {
                Label("Add Project", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(14)
        }
    }
}

private struct ProjectEditor: View {
    @State var project: DevProject
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(DevProjectStore.shared.projects.contains { $0.id == project.id } ? "Edit Project" : "New Project")
                .font(.headline)
            Form {
                TextField("Name", text: $project.name)
                ForEach(DevEnvironment.allCases) { environment in
                    TextField(environment.label, text: origin(environment), prompt: Text(placeholder(environment)))
                }
                LabeledContent("Folder") {
                    HStack {
                        Text(project.folderPath ?? "Not linked")
                            .foregroundStyle(project.folderPath == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Button(project.folderPath == nil ? "Link…" : "Change…") {
                            if let folder = DevProjectStore.shared.pickFolder(for: project.name) {
                                project.folderBookmark = folder.bookmark
                                project.folderPath = folder.path
                            }
                        }
                    }
                }
            }
            .formStyle(.columns)
            HStack {
                if DevProjectStore.shared.projects.contains(where: { $0.id == project.id }) {
                    Button("Delete Project", role: .destructive) {
                        DevProjectStore.shared.delete(project)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    DevProjectStore.shared.save(project)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(project.name.trimmingCharacters(in: .whitespaces).isEmpty || project.origins.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func origin(_ environment: DevEnvironment) -> Binding<String> {
        Binding(
            get: { project.origins[environment] ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                project.origins[environment] = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private func placeholder(_ environment: DevEnvironment) -> String {
        switch environment {
        case .local: "http://localhost:5173"
        case .staging: "https://staging.example.com"
        case .production: "https://example.com"
        }
    }
}
