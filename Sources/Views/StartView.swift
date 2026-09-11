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
    @State private var overlapWarning: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                IconTile(systemName: "doc.on.doc", size: 64)
                    .accessibilityHidden(true)
                Text("MacTwin")
                    .appFont(.title2, weight: .bold)
                Text("Finds files with identical content, so you can trash the extra copies. Nothing is scanned outside the folders you pick.")
                    .appFont(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(commonFolders, id: \.url) { folder in
                    folderRow(name: folder.name, isOn: binding(for: folder.url))
                }
                ForEach(customFolders, id: \.self) { url in
                    folderRow(name: url.abbreviatedPath, isOn: binding(for: url))
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)

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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: allFileTypes)

            Button {
                model.startScan(roots: Array(checked), extensions: resolvedExtensions)
            } label: {
                Text("Scan for Duplicates")
                    .appFont(.body, weight: .semibold)
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(.appAccent)
            .controlSize(.large)
            .disabled(checked.isEmpty || (resolvedExtensions?.isEmpty ?? false))

            if checked.isEmpty {
                Text("Select at least one folder to scan.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            } else if resolvedExtensions?.isEmpty ?? false {
                Text("Select at least one file type, or turn on “All File Types.”")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .alert("Overlapping Folder", isPresented: Binding(get: { overlapWarning != nil }, set: { if !$0 { overlapWarning = nil } })) {
            Button("OK", role: .cancel) { overlapWarning = nil }
        } message: {
            Text(overlapWarning ?? "")
        }
    }

    @ViewBuilder
    private func folderRow(name: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(name).appFont(.body)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isOn.wrappedValue ? Color.appAccent.opacity(0.12) : Color.clear)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isOn.wrappedValue)
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

        // Early, UI-level warning for the common case (a user visibly picks
        // a folder that is a parent or child of one already checked). This
        // is a courtesy — not the safety guarantee — since it can be
        // bypassed by symlinks or by checking two folders independently
        // without ever triggering this picker path again; the real
        // guarantee is `DuplicateScanner.enumerate`'s canonical-path dedup,
        // which applies regardless of what happens here.
        if let overlap = firstOverlap(of: url, in: checked) {
            overlapWarning = overlap
        }

        if !customFolders.contains(url) { customFolders.append(url) }
        checked.insert(url)
    }

    /// Returns a human-readable warning if `url` is the same as, contains,
    /// or is contained by any folder already in `roots` — nil if there's no
    /// overlap.
    private func firstOverlap(of url: URL, in roots: Set<URL>) -> String? {
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL.path
        for root in roots {
            let existing = root.resolvingSymlinksInPath().standardizedFileURL.path
            guard existing != candidate else { continue } // re-checking the same folder isn't an overlap concern here
            if candidate == existing
                || candidate.hasPrefix(existing + "/")
                || existing.hasPrefix(candidate + "/") {
                return "“\(url.abbreviatedPath)” overlaps with the already-selected “\(root.abbreviatedPath)”. MacTwin automatically avoids counting the same file twice, but scanning both is redundant — consider selecting only the top-level folder."
            }
        }
        return nil
    }
}
