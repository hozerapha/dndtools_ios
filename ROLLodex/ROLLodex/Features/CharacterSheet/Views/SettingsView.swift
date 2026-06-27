import SwiftUI
import UniformTypeIdentifiers

/// Settings tab. Phase H home for homebrew content packs and character
/// import. (Character EXPORT lives on the sheet itself, next to the roll
/// actions — you share the character you're looking at.)
struct SettingsView: View {
    @Environment(ContentStore.self) private var content
    @Environment(CharacterStore.self) private var characterStore

    /// One `.fileImporter` serves both flows — stacking two on the same view
    /// is a SwiftUI footgun where only the last one fires. `importTarget`
    /// records which button opened it so the completion routes correctly.
    /// `Identifiable` so the dev paste sheet can present via `.sheet(item:)`.
    private enum ImportTarget: Identifiable {
        case pack, character
        var id: Int { self == .pack ? 0 : 1 }
    }
    @State private var importTarget: ImportTarget = .pack
    @State private var showImporter = false

    /// First general app-preference setting (persisted via @AppStorage, the
    /// same pattern as the dice tab's auto-roll toggle). The raw value is
    /// stored; `critStyle` wraps it as the enum.
    @AppStorage(CritStyle.storageKey) private var critStyleRaw = CritStyle.default.rawValue
    private var critStyle: CritStyle { CritStyle(rawValue: critStyleRaw) ?? .default }

    @State private var alert: SettingsAlert?
    /// Pack staged for deletion — removing a pack drops its content (and
    /// re-surfaces any bundled ids it shadowed), so it gets an explicit prompt.
    @State private var pendingPackDelete: ContentStore.ImportedPackInfo?

    #if DEBUG
    @State private var pasteTarget: ImportTarget?
    #endif

    var body: some View {
        NavigationStack {
            Form {
                if !content.loadErrors.isEmpty { contentErrorSection }
                contentPacksSection
                charactersSection
                combatSection
                #if DEBUG
                devSection
                #endif
                aboutSection
                legalSection
            }
            .navigationTitle("Settings")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch importTarget {
                case .pack:      handlePackImport(result)
                case .character: handleCharacterImport(result)
                }
            }
            .alert(
                alert?.title ?? "",
                isPresented: Binding(
                    get: { alert != nil },
                    set: { if !$0 { alert = nil } }
                ),
                presenting: alert
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { alert in
                Text(alert.message)
            }
            .confirmationDialog(
                "Delete Content Pack",
                isPresented: Binding(
                    get: { pendingPackDelete != nil },
                    set: { if !$0 { pendingPackDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingPackDelete
            ) { pack in
                Button("Delete \(pack.name)", role: .destructive) {
                    content.removeImportedPack(fileName: pack.fileName)
                }
                Button("Cancel", role: .cancel) {}
            } message: { pack in
                Text("Removes \(pack.summary) from this pack. Any bundled content it overrode will return. This can't be undone, but you can re-import the pack.")
            }
            #if DEBUG
            .sheet(item: $pasteTarget) { target in
                PasteImportSheet(
                    title: target == .pack ? "Paste Pack JSON" : "Paste Character JSON",
                    perform: { text in performPaste(target, text: text) },
                    onSuccess: { alert = $0 }
                )
            }
            #endif
        }
    }

    // MARK: - Sections

    private var contentPacksSection: some View {
        Section {
            Button {
                importTarget = .pack
                showImporter = true
            } label: {
                Label("Import Content Pack", systemImage: "square.and.arrow.down")
            }

            let packs = content.importedPacks
            if packs.isEmpty {
                Text("No homebrew packs imported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(packs) { pack in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pack.name).font(.body)
                        Text(pack.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // Explicit per-row action in addition to swipe, so the
                    // delete affordance is discoverable. Both stage the
                    // confirmation rather than removing outright.
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingPackDelete = pack
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingPackDelete = pack
                        } label: {
                            Label("Delete Pack", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("Content Packs")
        } footer: {
            Text("Import a homebrew `.json` pack — classes, species, spells, items, and more. Imported entries override bundled content sharing the same id; deleting a pack restores the originals.")
        }
    }

    private var charactersSection: some View {
        Section {
            Button {
                importTarget = .character
                showImporter = true
            } label: {
                Label("Import Character", systemImage: "person.crop.circle.badge.plus")
            }
        } header: {
            Text("Characters")
        } footer: {
            Text("Import a character `.json` exported from ROLLodex. It's added as a new copy. Export any character from its sheet's ⋯ menu.")
        }
    }

    #if DEBUG
    private var devSection: some View {
        Section {
            Button {
                pasteTarget = .pack
            } label: {
                Label("Paste Pack JSON", systemImage: "doc.on.clipboard")
            }
            Button {
                pasteTarget = .character
            } label: {
                Label("Paste Character JSON", systemImage: "doc.on.clipboard")
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Paste JSON directly instead of copying a file onto the simulator. Debug builds only.")
        }
    }
    #endif

    private var contentErrorSection: some View {
        Section {
            ForEach(content.loadErrors, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Content Problems")
        } footer: {
            Text("Some bundled game data couldn't be loaded, so parts of the app may be missing. Reinstalling the app usually fixes this.")
        }
    }

    private var combatSection: some View {
        Section {
            Picker("Natural 20 style", selection: $critStyleRaw) {
                ForEach(CritStyle.allCases) { style in
                    Text(style.label).tag(style.rawValue)
                }
            }
        } header: {
            Text("Combat")
        } footer: {
            // Show the chosen style's explanation so the effect is clear.
            Text(critStyle.detail)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Bundled classes", value: "\(content.classes.count)")
            LabeledContent("Bundled spells", value: "\(content.spells.count)")
        }
    }

    /// CC-BY-4.0 requires this attribution statement to appear in-app — it's
    /// the license condition for using the bundled SRD content, not optional.
    /// The statement text is shown verbatim; the two source links are also
    /// surfaced as tappable rows. Per the license: no other WotC attribution,
    /// no implied endorsement.
    private var legalSection: some View {
        Section {
            Text(Self.srdAttribution)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Link("System Reference Document 5.2.1",
                 destination: URL(string: "https://www.dndbeyond.com/srd")!)
            Link("Creative Commons Attribution 4.0 (CC BY 4.0)",
                 destination: URL(string: "https://creativecommons.org/licenses/by/4.0/legalcode")!)
        } header: {
            Text("Legal & Attribution")
        } footer: {
            Text("ROLLodex is compatible with fifth edition. Not affiliated with or endorsed by Wizards of the Coast.")
        }
    }

    /// Verbatim CC-BY attribution statement from SRD 5.2.1's Legal Information.
    private static let srdAttribution = """
    This work includes material from the System Reference Document 5.2.1 \
    (“SRD 5.2.1”) by Wizards of the Coast LLC, available at \
    https://www.dndbeyond.com/srd. The SRD 5.2.1 is licensed under the \
    Creative Commons Attribution 4.0 International License, available at \
    https://creativecommons.org/licenses/by/4.0/legalcode.
    """

    // MARK: - Import handling

    private func handlePackImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            alert = SettingsAlert(title: "Import Failed", message: error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let pack = try content.importPack(from: url)
                alert = SettingsAlert(title: "Pack Imported", message: "Added \(pack.summary).")
            } catch {
                alert = SettingsAlert(title: "Import Failed", message: error.localizedDescription)
            }
        }
    }

    private func handleCharacterImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            alert = SettingsAlert(title: "Import Failed", message: error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let character = try characterStore.importCharacter(from: url)
                alert = SettingsAlert(title: "Character Imported", message: "Added “\(character.name)”.")
            } catch {
                alert = SettingsAlert(title: "Import Failed", message: error.localizedDescription)
            }
        }
    }

    #if DEBUG
    /// Returns success message or a failure message for the paste sheet to
    /// show inline (so the user can fix the JSON without losing their paste).
    private func performPaste(_ target: ImportTarget, text: String) -> PasteOutcome {
        guard let data = text.data(using: .utf8) else {
            return .failure("Couldn't read the pasted text.")
        }
        do {
            switch target {
            case .pack:
                let pack = try content.importPack(data: data, suggestedName: "Pasted Pack")
                return .success("Added \(pack.summary).")
            case .character:
                let character = try characterStore.importCharacter(data: data)
                return .success("Added “\(character.name)”.")
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }
    #endif
}

private struct SettingsAlert: Identifiable {
    let title: String
    let message: String
    var id: String { title + message }
}

#if DEBUG
/// Success or failure message from a paste import. (Not `Result` — that
/// requires the failure type to be an `Error`, and these are plain strings.)
private enum PasteOutcome {
    case success(String)
    case failure(String)
}

/// Dev-only: paste JSON instead of dropping a file onto the simulator.
/// Routes through the same validator/import path as the file picker. On
/// failure it shows the error inline and keeps the text so you can fix it.
private struct PasteImportSheet: View {
    let title: String
    let perform: (String) -> PasteOutcome
    let onSuccess: (SettingsAlert) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.3))
                    )
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") {
                        switch perform(text) {
                        case .success(let alert):
                            onSuccess(SettingsAlert(title: "Imported", message: alert))
                            dismiss()
                        case .failure(let message):
                            error = message
                        }
                    }
                    .bold()
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
#endif
