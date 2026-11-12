import SwiftUI
import UniformTypeIdentifiers
import NewsCore
import NewsAppModel
import HCGConnect

struct SettingsView: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @AppStorage(AppearanceChoice.storageKey) private var appearanceRaw = AppearanceChoice.system.rawValue

    var body: some View {
        Form {
            Section {
                NavigationLink(value: SettingsRoute.account) {
                    if let platformAccount = env.platformAccount {
                        HCGAccountSummaryRow(account: platformAccount)
                    } else {
                        AccountSummaryRow()
                    }
                }
            }
            Section("Reading") {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
                NavigationLink("Text and layout", value: SettingsRoute.reading)
                NavigationLink("Notifications", value: SettingsRoute.notifications)
            }
            if env.showsNewsroomEntry {
                Section("Newsroom") {
                    Button {
                        router.openNewsroomFromSettings()
                    } label: {
                        Label("Open Newsroom", systemImage: "square.and.pencil")
                    }
                    Text(env.newsroomDesk != nil
                         ? "Write, edit and publish HCG News articles, as your HCG News role allows."
                         : "Write and keep drafts on this device. Sending to the newsroom needs a newsroom service and HCG access.")
                        .font(.footnote).foregroundStyle(Palette.secondaryText)
                }
            }
            Section {
                NavigationLink(value: SettingsRoute.advanced) {
                    HStack {
                        Text("Advanced")
                        Spacer()
                        ConnectionBadge(status: env.connection.publication)
                    }
                }
                NavigationLink("About HCG News", value: SettingsRoute.about)
            }
        }
        .screenBackground()
        .navigationTitle("Settings")
        .task { if env.platformAccount == nil { await env.account.refresh() } }
    }
}

struct SettingsDestinationView: View {
    let route: SettingsRoute

    var body: some View {
        switch route {
        case .account:
            if let platformAccount = env.platformAccount { HCGAccountView(account: platformAccount) } else { AccountView() }
        case .reading: ReadingSettingsView()
        case .notifications: NotificationSettingsView()
        case .storage: SavedView()
        case .advanced: AdvancedSettingsView()
        case .importConfiguration: ConfigurationImportView()
        case .diagnostics: DiagnosticsView()
        case .about: AboutView()
        }
    }
}

struct ConnectionBadge: View {
    let status: ConnectionModel.PublicationStatus

    var body: some View {
        switch status {
        case .notConfigured: StatusBadge(text: "Not connected")
        case .invalid: StatusBadge(text: "Needs attention", tone: .attention)
        case .configured: StatusBadge(text: "Configured")
        case .checking: ProgressView().controlSize(.small)
        case .verified: StatusBadge(text: "Connected", tone: .good, systemImage: "checkmark")
        case .failed: StatusBadge(text: "Check failed", tone: .problem)
        }
    }
}

struct ReadingSettingsView: View {
    @AppStorage(ReadingSize.storageKey) private var readingStep = 0
    @AppStorage(LineSpacingChoice.storageKey) private var spacingRaw = LineSpacingChoice.comfortable.rawValue
    @AppStorage(ReadingWidthChoice.storageKey) private var widthRaw = ReadingWidthChoice.standard.rawValue
    @AppStorage(ArticleTypeface.storageKey) private var typefaceRaw = ArticleTypeface.serif.rawValue

    var body: some View {
        Form {
            Section {
                Stepper(value: $readingStep, in: ReadingSize.range) { Text("Text size: \(ReadingSize.label(for: readingStep))") }
                Picker("Line spacing", selection: $spacingRaw) { ForEach(LineSpacingChoice.allCases) { Text($0.title).tag($0.rawValue) } }
                Picker("Reading width", selection: $widthRaw) { ForEach(ReadingWidthChoice.allCases) { Text($0.title).tag($0.rawValue) } }
                Picker("Typeface", selection: $typefaceRaw) { ForEach(ArticleTypeface.allCases) { Text($0.title).tag($0.rawValue) } }
            } footer: {
                Text("Text size starts from your device's text size, including accessibility sizes.")
            }
            Section("Preview") {
                Text("Readers who follow the publication closely will notice the difference a comfortable line length makes.")
                    .font(Typography.body(ArticleTypeface(rawValue: typefaceRaw) ?? .serif))
                    .lineSpacing((LineSpacingChoice(rawValue: spacingRaw) ?? .comfortable).points)
            }
        }
        .screenBackground()
        .navigationTitle("Text and layout")
    }
}

/// Local preferences with an honest status: notifications are not active.
struct NotificationSettingsView: View {
    @Environment(NewsAppEnvironment.self) private var env
    @State private var prefs = NotificationPreferences.load(from: .standard)

    var body: some View {
        Form {
            Section {
                if case .unavailable(let reason) = SecondaryFeatures.pushNotifications {
                    Label { Text(reason).font(.footnote) } icon: { Image(systemName: "bell.slash").foregroundStyle(Palette.silver) }
                }
            }
            Section("Breaking news") {
                Toggle("Breaking news", isOn: $prefs.breakingNews)
                if prefs.breakingNews {
                    ForEach(["Breaking", "Developing"], id: \.self) { category in
                        Toggle(category, isOn: Binding(
                            get: { prefs.breakingCategories.contains(category) },
                            set: { if $0 { prefs.breakingCategories.insert(category) } else { prefs.breakingCategories.remove(category) } }))
                    }
                }
            }
            Section("Topics") {
                Toggle("HCG Announcements", isOn: $prefs.hcgAnnouncements)
                ForEach(env.sections.allSections) { section in
                    Toggle(section.name, isOn: Binding(
                        get: { prefs.sections.contains(section.slug) },
                        set: { if $0 { prefs.sections.insert(section.slug) } else { prefs.sections.remove(section.slug) } }))
                }
                if env.sections.allSections.isEmpty {
                    Text("Section topics appear once the publication is connected.").font(.footnote).foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .screenBackground()
        .navigationTitle("Notifications")
        .onChange(of: prefs) { _, value in value.save(to: .standard) }
        .task { await env.sections.loadIfNeeded() }
    }
}

// MARK: - Advanced

struct AdvancedSettingsView: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(AppContainer.self) private var container
    @State private var confirmRemove: ConfigurationKind?
    @State private var exportDocument: DataDocument?
    @State private var exportName = "configuration.json"
    @State private var showingExporter = false
    @State private var events: [LocalEvent] = []

    var body: some View {
        let connection = env.connection
        Form {
            if let message = container.lastChangeMessage {
                Section {
                    Text(message).font(.footnote)
                    Button("Dismiss") { container.clearChangeMessage() }
                }
            }
            configurationSection(.publication, title: "Publication", state: describe(env.publicationConfiguration),
                                 source: env.publicationSource) {
                PublicationCheckRow(status: connection.publication)
            }
            configurationSection(.connect, title: "HCG Connect", state: describe(env.connectConfiguration),
                                 source: env.connectSource) {
                ConnectCheckRow(status: connection.connect)
            }
            Section {
                Button {
                    Task { await connection.checkAll() }
                } label: {
                    Label("Check Connection", systemImage: "arrow.triangle.2.circlepath")
                }
                NavigationLink("Import Configuration…", value: SettingsRoute.importConfiguration)
                NavigationLink("Diagnostics", value: SettingsRoute.diagnostics)
            } footer: {
                Text("“Configured” means settings are installed. “Connected” means the publication answered with a supported contract in this session. For HCG Connect, only a successful sign-in and access check verify the connection.")
            }
            Section {
                ForEach(events.prefix(20)) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.message).font(.footnote)
                        Text("\(NewsDate.full(event.at)) · \(event.category.rawValue)").font(.caption2).foregroundStyle(Palette.secondaryText)
                    }
                }
                if events.isEmpty { Text("No events yet.").font(.footnote).foregroundStyle(Palette.secondaryText) }
            } header: {
                Text("On this device")
            } footer: {
                Text("This is a troubleshooting history kept only on this device. It is not the newsroom's audit history and never contains passwords, tokens or article text.")
            }
        }
        .screenBackground()
        .navigationTitle("Advanced")
        .task { events = await container.stores.log.all() }
        .confirmationDialog("Remove the imported configuration?", isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
                            titleVisibility: .visible, presenting: confirmRemove) { kind in
            Button("Remove \(kind.title) Configuration", role: .destructive) { Task { await container.remove(kind) } }
        } message: { kind in
            Text(kind == .connect
                 ? "The built-in configuration (if any) will apply. If the sign-in setup changes, you'll be signed out on this device and newsroom links on local drafts are removed. Drafts, saved articles and downloads are kept."
                 : "The built-in configuration (if any) will apply. Saved articles and downloads are kept.")
        }
        .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .json, defaultFilename: exportName) { _ in }
    }

    @ViewBuilder
    private func configurationSection<Check: View>(_ kind: ConfigurationKind, title: String, state: (String, [String]),
                                                   source: ConfigurationSource, @ViewBuilder check: () -> Check) -> some View {
        Section(title) {
            LabeledContent("Status", value: state.0)
            LabeledContent("Source", value: sourceLabel(source))
            ForEach(state.1, id: \.self) { problem in
                Text(problem).font(.footnote).foregroundStyle(Palette.warning)
            }
            check()
            if case .imported = source {
                Button("Export Imported \(title) Configuration") {
                    Task {
                        if let data = await container.stores.configuration.importedData(kind) {
                            exportDocument = DataDocument(data: data)
                            exportName = "hcg-news-\(kind.rawValue)-configuration.json"
                            showingExporter = true
                        }
                    }
                }
                Button("Remove Imported \(title) Configuration", role: .destructive) { confirmRemove = kind }
            }
        }
    }

    private func describe(_ state: NewsConfigurationState) -> (String, [String]) {
        switch state {
        case .awaitingSetup: ("Not configured", [])
        case .invalid(let p): ("Invalid", p)
        case .ready(let c):
            if let p = c.platform { ("Connected to the HCG platform · \(c.environment) · \(p.publicationURL.host ?? "")", []) }
            else { ("Configured · \(c.environment) · \(c.apiBaseURL.host ?? "")", []) }
        }
    }

    private func describe(_ state: ConnectConfigurationState) -> (String, [String]) {
        switch state {
        case .awaitingSetup: ("Not configured", [])
        case .invalid(let p): ("Invalid", p)
        case .ready(let c): ("Configured · \(c.environment) · \(c.issuer.host ?? "")", [])
        }
    }

    private func sourceLabel(_ source: ConfigurationSource) -> String {
        switch source {
        case .imported(let date): "Imported \(NewsDate.short(date))"
        case .bundled: "Built into the app"
        case .none: "None"
        }
    }
}

struct PublicationCheckRow: View {
    let status: ConnectionModel.PublicationStatus

    var body: some View {
        switch status {
        case .notConfigured, .invalid, .configured:
            LabeledContent("Connection", value: "Not checked")
        case .checking:
            HStack { Text("Connection"); Spacer(); ProgressView() }
        case .verified(_, let at, let caps):
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent("Connection") { StatusBadge(text: "Connected", tone: .good, systemImage: "checkmark") }
                Text("Verified \(NewsDate.short(at)) · search: \(caps.serverSearch ? "publication" : "not offered") · full text: \(caps.fullContent ? "yes" : "summaries only")")
                    .font(.caption).foregroundStyle(Palette.secondaryText)
            }
        case .failed(let error, let at):
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent("Connection") { StatusBadge(text: "Failed", tone: .problem) }
                Text("\(error.title) · \(NewsDate.short(at))").font(.caption).foregroundStyle(Palette.secondaryText)
            }
        }
    }
}

struct ConnectCheckRow: View {
    let status: ConnectionModel.ConnectStatus

    var body: some View {
        switch status {
        case .notConfigured, .invalid, .configured:
            LabeledContent("Connection", value: "Not checked")
        case .checking:
            HStack { Text("Connection"); Spacer(); ProgressView() }
        case .reachable(_, let at):
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent("Connection") { StatusBadge(text: "Reachable") }
                Text("The sign-in service answered \(NewsDate.short(at)). Sign in to verify the connection.")
                    .font(.caption).foregroundStyle(Palette.secondaryText)
            }
        case .unreachable(let message, _):
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent("Connection") { StatusBadge(text: "Unreachable", tone: .problem) }
                Text(message).font(.caption).foregroundStyle(Palette.secondaryText)
            }
        case .verified(_, let at):
            LabeledContent("Connection") { StatusBadge(text: "Verified \(NewsDate.short(at))", tone: .good, systemImage: "checkmark") }
        }
    }
}

// MARK: - Import

/// Manual JSON configuration import through Files: choose, validate and preview,
/// then apply. Nothing changes until "Apply"; a failed import keeps the previous configuration.
struct ConfigurationImportView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ConfigurationKind = .publication
    @State private var showingPicker = false
    @State private var preview: ConfigurationImportPreview?
    @State private var fileName: String?
    @State private var readError: String?
    @State private var applyError: String?
    @State private var confirmIdentityChange = false
    @State private var isApplying = false

    var body: some View {
        Form {
            Section {
                Picker("Configuration", selection: $kind) {
                    ForEach(ConfigurationKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _, _ in preview = nil; fileName = nil }
                Button { showingPicker = true } label: { Label("Choose File…", systemImage: "folder") }
            } footer: {
                Text("Choose a JSON file provided by HCG. Files containing client secrets, passwords or privileged keys are rejected. See the configuration example in the project documentation.")
            }
            if let readError {
                Section { Text(readError).foregroundStyle(Palette.warning) }
            }
            if let preview {
                Section("Preview — \(fileName ?? "file")") {
                    if preview.isValid {
                        LabeledContent("Environment", value: preview.environment ?? "—")
                        ForEach(preview.destinations, id: \.self) { Text($0).font(.footnote) }
                        ForEach(preview.notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(Palette.secondaryText) }
                        if preview.changesIdentity {
                            Label("Applying this changes the sign-in setup. You'll be signed out on this device, and newsroom links on local drafts are removed. Drafts, saved articles and downloads are kept.",
                                  systemImage: "person.badge.key")
                                .font(.footnote).foregroundStyle(Palette.warning)
                        }
                    } else {
                        Label("This file can't be used. Nothing was changed.", systemImage: "xmark.octagon")
                            .foregroundStyle(Palette.destructive)
                        ForEach(preview.problems, id: \.self) { Text("• " + $0).font(.footnote) }
                    }
                }
                if preview.isValid {
                    Section {
                        Button {
                            if preview.changesIdentity { confirmIdentityChange = true } else { Task { await apply(preview) } }
                        } label: {
                            if isApplying { ProgressView() } else { Text("Apply \(preview.kind.title) Configuration") }
                        }
                        .disabled(isApplying)
                        if let applyError { Text(applyError).font(.footnote).foregroundStyle(Palette.destructive) }
                    }
                }
            }
        }
        .screenBackground()
        .navigationTitle("Import Configuration")
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.json]) { result in
            Task { await read(result) }
        }
        .confirmationDialog("Change the sign-in setup?", isPresented: $confirmIdentityChange, titleVisibility: .visible) {
            Button("Apply and Sign Out", role: .destructive) { if let preview { Task { await apply(preview) } } }
        }
    }

    private func read(_ result: Result<URL, Error>) async {
        readError = nil
        applyError = nil
        preview = nil
        switch result {
        case .failure:
            readError = "The file couldn't be opened."
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                readError = "The file couldn't be read."
                return
            }
            fileName = url.lastPathComponent
            preview = await container.preview(data, as: kind)
        }
    }

    private func apply(_ preview: ConfigurationImportPreview) async {
        isApplying = true
        defer { isApplying = false }
        do {
            try await container.apply(preview)
            dismiss()
        } catch {
            applyError = "The configuration couldn't be saved. The previous configuration is still active."
        }
    }
}

struct DiagnosticsView: View {
    @Environment(AppContainer.self) private var container
    @State private var text = ""
    @State private var showingExporter = false

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "Preparing…" : text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .screenBackground()
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingExporter = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .disabled(text.isEmpty)
            }
        }
        .fileExporter(isPresented: $showingExporter, document: DataDocument(data: Data(text.utf8), type: .plainText),
                      contentType: .plainText, defaultFilename: "hcg-news-diagnostics.txt") { _ in }
        .task { text = await container.diagnostics() }
    }
}

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    HCGMark(height: 64)
                        .padding(12)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("HCG News").font(Typography.headline(.title2))
                    Text("Version \(AppBootstrap.appVersion) · development build, not released")
                        .font(.footnote).foregroundStyle(Palette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("The publication") {
                Link("Editorial policy", destination: URL(string: "https://news.hakmicapitalgroup.com/editorial-policy")!)
                Link("Corrections", destination: URL(string: "https://news.hakmicapitalgroup.com/corrections")!)
                Link("Advertising disclosure", destination: URL(string: "https://news.hakmicapitalgroup.com/advertising-disclosure")!)
                Link("Privacy", destination: URL(string: "https://news.hakmicapitalgroup.com/privacy")!)
                Link("Contact", destination: URL(string: "https://news.hakmicapitalgroup.com/contact")!)
            }
            Section("Not available in this version") {
                Text("Push notifications (no notification service yet)")
                Text("Saved-article sync between devices (no sync service yet)")
                Text("Subscriptions and payments (none offered in the app)")
            }
            .font(.footnote)
            Section { PublisherAttribution(large: true).padding(.vertical, 8) }
        }
        .screenBackground()
        .navigationTitle("About")
    }
}

/// A generic file document for exports.
struct DataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var data: Data
    var type: UTType = .json

    init(data: Data, type: UTType = .json) {
        self.data = data
        self.type = type
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
