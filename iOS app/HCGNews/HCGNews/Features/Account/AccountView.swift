import SwiftUI
import NewsAppModel
import HCGConnect

/// Compact account status for the top of Settings.
struct AccountSummaryRow: View {
    @Environment(NewsAppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.largeTitle)
                .foregroundStyle(Palette.silver)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.primaryText)
                Text(subtitle).font(.footnote).foregroundStyle(Palette.secondaryText)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch env.account.status?.authentication {
        case .signedIn(_, let name)?: env.account.decision?.displayName ?? name ?? "HCG account"
        default: "HCG Account"
        }
    }

    private var subtitle: String {
        switch env.account.status?.authentication {
        case .signedIn?: env.account.decision.map { "HCG News access: \(AccessText.label($0.status))" } ?? "Signed in"
        case .signedOut?: "Not signed in · public articles never need an account"
        case .expired?: "Session ended · sign in again"
        case .signingIn?: "Signing in…"
        case .unavailable?, nil: "Sign-in isn't set up for this app yet"
        }
    }
}

enum AccessText {
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

    static func event(_ event: ConnectEvent) -> String {
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

struct AccountView: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @State private var confirmSignOut = false

    var body: some View {
        let account = env.account
        Form {
            Section {
                switch account.status?.authentication {
                case .unavailable?, nil:
                    Text("HCG Connect sign-in isn't set up for HCG News yet. Public articles never require an account.")
                        .font(.footnote)
                    if !account.configurationProblems.isEmpty {
                        DisclosureGroup("Why") {
                            ForEach(account.configurationProblems, id: \.self) { Text($0).font(.caption).foregroundStyle(Palette.secondaryText) }
                        }
                        .font(.footnote)
                    }
                    Button("Open Advanced Settings") { router.showAdvancedSettings() }
                case .signedOut?, .expired?:
                    if case .expired? = account.status?.authentication {
                        Text("Your HCG session ended. Sign in again to continue.").font(.footnote)
                    }
                    Button { Task { await account.signIn() } } label: {
                        Label("Sign In with HCG Connect", systemImage: "person.badge.key")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(account.isWorking)
                    Text("Opens HCG's sign-in page in a secure system browser. HCG News never sees your password. Public articles never require an account.")
                        .font(.footnote).foregroundStyle(Palette.secondaryText)
                case .signingIn?:
                    HStack { ProgressView(); Text("Waiting for HCG Connect…") }
                case .signedIn(_, let tokenName)?:
                    identity(account: account, tokenName: tokenName)
                }
                if let event = account.status?.lastEvent {
                    Text(AccessText.event(event)).font(.footnote).foregroundStyle(Palette.secondaryText)
                }
            } header: {
                Text("HCG Connect")
            }

            if account.isSignedIn {
                accessSection(account)
                organisationSection(account)
                entitlementsSection(account)
                Section {
                    Button("Check Access Again") { Task { await account.checkAccess() } }.disabled(account.isWorking)
                    Button("Sign Out on This Device", role: .destructive) { confirmSignOut = true }.disabled(account.isWorking)
                }
            }

            Section("Not available yet") {
                Text("Subscriptions: HCG doesn't offer subscriptions in this app. Any entitlements HCG reports for your account appear above.")
                Text("Saved-article sync: saved articles and downloads stay on this device.")
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryText)

            Section { PublisherAttribution() }
        }
        .screenBackground()
        .navigationTitle("Account")
        .task { await account.refresh() }
        .confirmationDialog("Sign out of HCG Connect on this device?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await account.signOut() } }
        } message: {
            Text("This removes your HCG session from this device. Saved articles, downloads and local drafts stay on this device.")
        }
    }

    @ViewBuilder
    private func identity(account: AccountModel, tokenName: String?) -> some View {
        if let decision = account.decision {
            LabeledContent("Name", value: decision.displayName ?? tokenName ?? "Not provided by HCG")
            if let email = decision.email { LabeledContent("Email", value: email) }
            if let org = decision.currentOrganization { LabeledContent("Organisation", value: org.name) }
        } else {
            LabeledContent("Signed in", value: tokenName ?? "HCG account")
            Text("Identity details appear once HCG confirms your access.").font(.footnote).foregroundStyle(Palette.secondaryText)
        }
    }

    @ViewBuilder
    private func accessSection(_ account: AccountModel) -> some View {
        Section {
            switch account.status?.access {
            case .checking?:
                HStack { ProgressView(); Text("Checking access with HCG…") }
            case .decided(let decision)?:
                LabeledContent("HCG News access", value: AccessText.label(decision.status))
                if let reason = decision.reason, decision.status != .granted {
                    Text(reason).font(.footnote).foregroundStyle(Palette.secondaryText)
                }
                if let until = decision.validUntil {
                    LabeledContent("Valid until", value: NewsDate.full(until))
                }
                if decision.permissions.isEmpty {
                    Text("No capabilities issued.").font(.footnote).foregroundStyle(Palette.secondaryText)
                } else {
                    DisclosureGroup("Capabilities issued by HCG (\(decision.permissions.count))") {
                        ForEach(decision.permissions, id: \.self) { Text($0).font(.caption.monospaced()) }
                    }
                }
                if let newsroom = account.status?.newsroomURL {
                    Link(destination: newsroom) { Label("Open the HCG newsroom (web)", systemImage: "safari") }
                }
            case .refused(let reason)?:
                LabeledContent("HCG News access", value: "Not granted")
                if let reason { Text(reason).font(.footnote).foregroundStyle(Palette.secondaryText) }
            case .failed(let message)?:
                Text(message).font(.footnote).foregroundStyle(Palette.warning)
            case .notChecked?, nil:
                Text("Access not checked yet.").font(.footnote).foregroundStyle(Palette.secondaryText)
            }
        } header: {
            Text("Access")
        } footer: {
            Text("Access and capabilities come from HCG for this session. HCG News never derives privileges from your email address, name or job title.")
        }
    }

    @ViewBuilder
    private func organisationSection(_ account: AccountModel) -> some View {
        if let orgs = account.decision?.organizations, orgs.count > 1 {
            Section("Organisation") {
                Picker("Acting for", selection: Binding(
                    get: { account.decision?.organizationID ?? "" },
                    set: { id in Task { await account.selectOrganization(id.isEmpty ? nil : id) } })) {
                    ForEach(orgs) { Text($0.name).tag($0.id) }
                }
                Text("HCG decides what your account may do in each organisation.").font(.footnote).foregroundStyle(Palette.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func entitlementsSection(_ account: AccountModel) -> some View {
        if let entitlements = account.decision?.entitlements, !entitlements.isEmpty {
            Section("Licences and entitlements (from HCG)") {
                ForEach(entitlements) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                        Text(item.status + (item.validUntil.map { " · until \(NewsDate.short($0))" } ?? ""))
                            .font(.footnote).foregroundStyle(Palette.secondaryText)
                    }
                }
            }
        }
    }
}
