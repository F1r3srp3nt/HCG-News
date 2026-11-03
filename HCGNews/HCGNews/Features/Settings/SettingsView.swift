import SwiftUI
import NewsCore
import NewsAppModel
import HCGConnect

struct SettingsView: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(\.palette) private var palette
    @AppStorage("readerStyle") private var styleRaw = ReaderStyle.future.rawValue
    @AppStorage(ReadingSize.storageKey) private var readingStep = 0

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $styleRaw) {
                    ForEach(ReaderStyle.allCases) { style in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.title)
                            Text(style.summary).font(.footnote).foregroundStyle(palette.secondaryText)
                        }
                        .tag(style.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Picker("Article text size", selection: $readingStep) {
                    ForEach(Array(ReadingSize.range), id: \.self) { step in
                        Text(ReadingSize.label(for: step)).tag(step)
                    }
                }
            } header: {
                Text("Reading")
            } footer: {
                Text("Article text starts from your device's text size, including accessibility sizes, and this setting adjusts it further.")
            }
            .listRowBackground(palette.surface)

            AccountSection()
                .listRowBackground(palette.surface)

            Section {
                switch env.contentConfiguration {
                case .ready(let configuration):
                    LabeledContent("Status", value: env.isUsingTestFixtures ? "Test fixtures" : "Connected")
                    LabeledContent("Environment", value: configuration.environment)
                    LabeledContent("Contract", value: "v\(configuration.contractVersion)")
                case .awaitingSetup, .invalid:
                    LabeledContent("Status", value: "Not connected")
                    ForEach(env.contentConfigurationProblems, id: \.self) { problem in
                        Text(problem).font(.footnote).foregroundStyle(palette.secondaryText)
                    }
                }
                Link(destination: URL(string: "https://news.hakmicapitalgroup.com")!) {
                    Label("news.hakmicapitalgroup.com", systemImage: "safari")
                }
            } header: {
                Text("Publication")
            }
            .listRowBackground(palette.surface)

            Section {
                LabeledContent("Version", value: Self.versionString)
                Text("Development build. Not released.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Not in this version").font(.subheadline.weight(.semibold))
                    ForEach(Self.limitations, id: \.self) { item in
                        Text("• \(item)").font(.footnote).foregroundStyle(palette.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text("About")
            } footer: {
                HStack {
                    Spacer()
                    Image("HCGLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("Hakmi Capital Group")
                    Spacer()
                }
                .padding(.top, 16)
            }
            .listRowBackground(palette.surface)
        }
        .screenBackground()
        .navigationTitle("Settings")
        .task { await env.account.refresh() }
    }

    static let limitations = [
        "Offline reading: saved articles keep the headline and link only.",
        "Notifications.",
        "Saved-article sync between devices.",
        "Newsroom editing and publishing.",
    ]

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// HCG Connect status. Public reporting never requires sign-in.
struct AccountSection: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(\.palette) private var palette
    @State private var confirmSignOut = false

    var body: some View {
        let account = env.account
        Section {
            switch account.status?.authentication {
            case .unavailable?, nil:
                Text("Signing in with HCG Connect isn't set up for HCG News yet. Public articles never require an account.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                if !account.configurationProblems.isEmpty {
                    DisclosureGroup("Missing HCG configuration") {
                        ForEach(account.configurationProblems, id: \.self) { problem in
                            Text(problem).font(.caption.monospaced()).foregroundStyle(palette.secondaryText)
                        }
                    }
                    .font(.footnote)
                }
            case .signedOut?, .expired?:
                if case .expired? = account.status?.authentication {
                    Text("Your HCG session ended. Sign in again to continue.")
                        .font(.footnote)
                }
                Button {
                    Task { await account.signIn() }
                } label: {
                    Label("Sign In with HCG Connect", systemImage: "person.badge.key")
                }
                .disabled(account.isWorking)
                Text("Opens HCG's sign-in page in a secure system browser. Public articles never require an account.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            case .signingIn?:
                HStack { ProgressView(); Text("Waiting for HCG Connect…") }
            case .signedIn(_, let displayName)?:
                LabeledContent("Signed in", value: displayName ?? "HCG account")
                accessRows(account.status?.access)
                if let newsroom = account.status?.newsroomURL {
                    Link(destination: newsroom) {
                        Label("Open the newsroom", systemImage: "square.and.pencil")
                    }
                    Text("HCG's newsroom checks your permissions again when it opens.")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
                Button("Check Access Again") { Task { await account.checkAccess() } }
                    .disabled(account.isWorking)
                Button("Sign Out", role: .destructive) { confirmSignOut = true }
                    .disabled(account.isWorking)
            }
            if let event = account.status?.lastEvent {
                Text(Self.message(for: event))
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        } header: {
            Text("HCG Account")
        }
        .confirmationDialog("Sign out of HCG Connect on this device?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await account.signOut() } }
        } message: {
            Text("This removes your HCG session from this device. Saved articles stay on this device.")
        }
    }

    @ViewBuilder
    private func accessRows(_ access: AccessStatus?) -> some View {
        switch access {
        case .checking?:
            HStack { ProgressView(); Text("Checking access with HCG…") }
        case .decided(let decision)?:
            LabeledContent("HCG News access", value: Self.label(decision.status))
            if let reason = decision.reason, decision.status != .granted {
                Text(reason).font(.footnote).foregroundStyle(palette.secondaryText)
            }
        case .refused(let reason)?:
            LabeledContent("HCG News access", value: "Not granted")
            if let reason { Text(reason).font(.footnote).foregroundStyle(palette.secondaryText) }
        case .failed(let message)?:
            Text(message).font(.footnote).foregroundStyle(palette.secondaryText)
        case .notChecked?, nil:
            EmptyView()
        }
    }

    static func label(_ status: AppAccessDecision.Status) -> String {
        switch status {
        case .granted: "Granted"
        case .denied: "Not granted"
        case .revoked: "Revoked"
        case .unlicensed: "Not licensed"
        case .suspended: "Suspended"
        case .unknown(let raw): raw
        }
    }

    static func message(for event: ConnectEvent) -> String {
        switch event {
        case .cancelled: "Sign-in was cancelled."
        case .denied: "Sign-in was declined."
        case .failed(let message): message
        case .expired: "Your HCG session expired. Sign in again to continue."
        case .revoked: "HCG revoked this app's access for your account. You've been signed out on this device."
        case .signedOut(let report):
            switch report.central {
            case .acknowledged: "Signed out on this device. HCG Connect confirmed the sign-out request."
            case .notConfigured: "Signed out on this device. Other devices and the HCG website are not affected."
            case .failed: "Signed out on this device. HCG Connect couldn't be reached to confirm, so the session may stay valid elsewhere until it expires."
            }
        }
    }
}
