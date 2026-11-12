import SwiftUI
import NewsAppModel
import HCGPlatform

/// HCG-branded sign-in with the person's existing HCG account (the same account as the
/// HCG website and HCG ONE). The password goes only to HCG's sign-in service over HTTPS
/// and is never stored; the field is cleared after every attempt.
struct HCGSignInView: View {
    let account: PlatformAccountModel
    var onSignedIn: (() -> Void)?
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    @Environment(NewsAppEnvironment.self) private var env

    enum Field { case email, password }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                HCGMark(height: 44)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("Sign in with your HCG account")
                    .font(Typography.headline(.title3))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Use the same email and password as on the Hakmi Capital Group website and in HCG ONE. Reading public articles never needs an account.")
                    .font(.footnote).foregroundStyle(Palette.secondaryText).multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    .padding(12)
                    .background(Palette.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("hcg-signin-email")
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .padding(12)
                    .background(Palette.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("hcg-signin-password")
            }
            if let error = account.signInError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Palette.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let reason = account.expiredReason {
                Label(reason, systemImage: "clock.badge.exclamationmark")
                    .font(.footnote).foregroundStyle(Palette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: submit) {
                HStack {
                    if account.isWorking { ProgressView().tint(Palette.onAccent) }
                    Text(account.isWorking ? "Signing in…" : "Sign In")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(account.isWorking || email.isEmpty || password.isEmpty)
            .accessibilityIdentifier("hcg-signin-submit")
            if let website = env.platformWebsiteURL {
                Link("Forgot your password? Reset it on the HCG website", destination: website.appendingPathComponent("auth"))
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
            Text("HCG decides what your account can do. Signing in never grants newsroom access by itself.")
                .font(.caption).foregroundStyle(Palette.secondaryText).multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: 460)
    }

    private func submit() {
        guard !account.isWorking, !email.isEmpty, !password.isEmpty else { return }
        let secret = password
        password = ""
        Task {
            await account.signIn(email: email, password: secret)
            if account.isSignedIn { onSignedIn?() }
        }
    }
}

/// The signed-in HCG account: identity, HCG News roles and HCG workspaces, exactly as
/// HCG reported them.
struct HCGAccountView: View {
    let account: PlatformAccountModel
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var confirmSignOut = false

    var body: some View {
        Group {
            if account.user == nil {
                ScrollView {
                    VStack(spacing: 16) {
                        HCGSignInView(account: account)
                        if let message = account.lastMessage {
                            Text(message).font(.footnote).foregroundStyle(Palette.secondaryText)
                                .multilineTextAlignment(.center).padding(.horizontal, 20)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                signedInForm
            }
        }
        .screenBackground()
        .navigationTitle("HCG Account")
        .confirmationDialog("Sign out of your HCG account on this device?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await account.signOut() } }
        } message: {
            Text("Newsroom lists and access information are removed from this device. Unsaved newsroom edits stay on this device for your account. Saved articles and downloads are kept.")
        }
        .alert("Workspace", isPresented: Binding(get: { account.workspaceError != nil }, set: { if !$0 { account.clearMessages() } })) {
            Button("OK") { account.clearMessages() }
        } message: { Text(account.workspaceError ?? "") }
    }

    private var signedInForm: some View {
        Form {
            if let user = account.user {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName ?? user.email ?? "HCG account").font(.headline)
                        if let email = user.email, user.displayName != nil {
                            Text(email).font(.footnote).foregroundStyle(Palette.secondaryText)
                        }
                        Text("Signed in with your HCG account").font(.caption).foregroundStyle(Palette.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
                newsroomSection
                workspacesSection
                Section {
                    Button {
                        Task { await account.refreshAccess() }
                    } label: { Label("Refresh Access", systemImage: "arrow.clockwise") }
                    .disabled(account.isWorking)
                    Button("Sign Out", role: .destructive) { confirmSignOut = true }
                } footer: {
                    Text("Roles and workspace access are managed centrally in the HCG ERP. Changes apply here the next time access is checked, including when you return to the app.")
                }
            }
        }
    }

    @ViewBuilder
    private var newsroomSection: some View {
        Section("HCG News access") {
            switch account.permissions {
            case .notChecked, .checking:
                HStack { ProgressView(); Text("Checking with HCG…").foregroundStyle(Palette.secondaryText) }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").font(.footnote)
            case .ready(let permissions):
                if permissions.isStaff {
                    ForEach(permissions.orderedRoles, id: \.self) { role in
                        Label(role.title, systemImage: "checkmark.seal").foregroundStyle(Palette.primaryText)
                    }
                    Button {
                        router.openNewsroomFromSettings()
                    } label: { Label("Open Newsroom", systemImage: "square.and.pencil") }
                } else {
                    Text("No newsroom role. You can read and save articles as usual.")
                        .font(.footnote).foregroundStyle(Palette.secondaryText)
                }
                Text("Checked \(NewsDate.short(permissions.checkedAt))")
                    .font(.caption).foregroundStyle(Palette.secondaryText)
                if let problem = account.accessCheckProblem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.footnote)
                }
            }
        }
    }

    @ViewBuilder
    private var workspacesSection: some View {
        Section {
            switch account.workspaces {
            case .notChecked, .checking:
                HStack { ProgressView(); Text("Checking HCG workspaces…").foregroundStyle(Palette.secondaryText) }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").font(.footnote)
            case .ready(let directory):
                let shown = directory.workspaces.filter { ["erp", "ceo_suite"].contains($0.id) || $0.permitted }
                if shown.isEmpty {
                    Text("HCG listed no workspaces for this account.").font(.footnote).foregroundStyle(Palette.secondaryText)
                }
                ForEach(shown) { workspace in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workspace.displayTitle)
                            Text(status(workspace)).font(.caption).foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        if workspace.permitted && workspace.available {
                            Button {
                                Task { if let url = await account.workspaceLink(workspace.handoffTarget) { openURL(url) } }
                            } label: {
                                if account.openingWorkspace == workspace.handoffTarget { ProgressView() } else { Text("Open") }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(account.openingWorkspace != nil)
                            .accessibilityLabel("Open \(workspace.displayTitle)")
                        }
                    }
                }
            }
        } header: {
            Text("HCG workspaces")
        } footer: {
            Text("Opens on the HCG website in Safari with a one-time sign-in link (valid for about a minute). HCG checks your access again there; the app holds no ERP permissions.")
        }
    }

    private func status(_ w: HCGWorkspaceDirectory.Workspace) -> String {
        if !w.permitted { return "Not available to your account" }
        return w.available ? "Available" : "Temporarily unavailable"
    }
}

/// Compact account row for the top of Settings (HCG platform).
struct HCGAccountSummaryRow: View {
    let account: PlatformAccountModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.largeTitle).foregroundStyle(Palette.silver).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.user.map { $0.displayName ?? $0.email ?? "HCG account" } ?? "HCG Account")
                    .font(.headline).foregroundStyle(Palette.primaryText)
                Text(subtitle).font(.footnote).foregroundStyle(Palette.secondaryText)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if account.expiredReason != nil { return "Session ended · sign in again" }
        guard account.isSignedIn else { return "Not signed in · public articles never need an account" }
        switch account.permissions {
        case .ready(let p): return p.isStaff ? "HCG News: " + p.orderedRoles.map(\.title).joined(separator: ", ") : "Signed in"
        case .failed: return "Signed in · access not checked"
        default: return "Signed in · checking access…"
        }
    }
}
