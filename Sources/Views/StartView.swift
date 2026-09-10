import SwiftUI
import AppKit

struct StartView: View {
    @EnvironmentObject var model: DupeModel
    @Environment(\.isProLicensed) private var isProLicensed

    private let commonFolders: [(name: String, url: URL)] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ("Downloads", home.appendingPathComponent("Downloads")),
            ("Pictures", home.appendingPathComponent("Pictures")),
            ("Desktop", home.appendingPathComponent("Desktop")),
            ("Documents", home.appendingPathComponent("Documents")),
            ("Movies", home.appendingPathComponent("Movies")),
        ]
    }()

    @State private var checked: Set<URL> = []
    @State private var customFolders: [URL] = []
    @State private var allFileTypes = true
    @State private var selectedCategories: Set<FileCategory> = []
    @State private var customExtensions = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("DupeFinder")
                    .appFont(.title2, weight: .bold)
                Text("Finds files with identical content, so you can trash the extra copies. Nothing is scanned outside the folders you pick.")
                    .appFont(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(commonFolders, id: \.url) { folder in
                    Toggle(folder.name, isOn: binding(for: folder.url))
                        .appFont(.body)
                }
                ForEach(customFolders, id: \.self) { url in
                    Toggle(url.abbreviatedPath, isOn: binding(for: url))
                        .appFont(.body)
                }

                if isProLicensed {
                    Button("Choose Folder…") { chooseFolder() }
                        .appFont(.body)
                        .padding(.top, 4)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            UnlockProButton(label: "Unlock Pro to Add Any Folder")
                        }
                        Text("Free version scans the 5 folders above only.")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(width: 320, alignment: .leading)
            .padding(20)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 10) {
                Toggle("All File Types", isOn: $allFileTypes)
                    .appFont(.body)
                if !allFileTypes {
                    ForEach(FileCategory.allCases) { category in
                        Toggle(category.rawValue, isOn: binding(for: category))
                            .appFont(.body)
                    }
                    TextField("Custom extensions, comma-separated (e.g. psd, sketch)", text: $customExtensions)
                        .textFieldStyle(.roundedBorder)
                        .appFont(.body)
                }
            }
            .frame(width: 320, alignment: .leading)
            .padding(20)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            Button {
                model.startScan(roots: Array(checked), extensions: resolvedExtensions)
            } label: {
                Text("Scan for Duplicates")
                    .appFont(.body)
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(checked.isEmpty || (resolvedExtensions?.isEmpty ?? false))

            Spacer()
        }
        .padding()
    }

    private func binding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { checked.contains(url) },
            set: { isOn in
                if isOn { checked.insert(url) } else { checked.remove(url) }
            })
    }

    private func binding(for category: FileCategory) -> Binding<Bool> {
        Binding(
            get: { selectedCategories.contains(category) },
            set: { isOn in
                if isOn { selectedCategories.insert(category) } else { selectedCategories.remove(category) }
            })
    }

    /// `nil` means "no filter" (scan every file). Non-nil is always the
    /// resolved union of checked categories + parsed custom extensions, even
    /// if that union is empty — the Scan button disables on empty rather
    /// than silently falling back to "everything."
    private var resolvedExtensions: Set<String>? {
        guard !allFileTypes else { return nil }
        var extensions = selectedCategories.reduce(into: Set<String>()) { $0.formUnion($1.extensions) }
        let custom = customExtensions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
        extensions.formUnion(custom)
        return extensions
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !customFolders.contains(url) { customFolders.append(url) }
        checked.insert(url)
    }
}
