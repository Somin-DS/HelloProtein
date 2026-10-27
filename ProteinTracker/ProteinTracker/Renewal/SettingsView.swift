import SwiftUI
import MessageUI

/// Information-only screen: opening settings never loads or writes the user's store.
@available(iOS 15.0, *)
struct SettingsView: View {
    static let supportAddress = "ramgoods2@gmail.com"
    @Environment(\.dismiss) private var dismiss
    @State private var showingMail = false
    @State private var mailUnavailable = false
    @State private var mailFailed = false
    @State private var copied = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("renewal_settings_preferences")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("renewal_settings_goal", systemImage: "target").font(.headline)
                        Text("renewal_settings_goal_hint").font(.subheadline).foregroundColor(.secondary)
                    }.padding(.vertical, 8)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("renewal_settings_language", systemImage: "globe").font(.headline)
                        Text("renewal_settings_language_hint").font(.subheadline).foregroundColor(.secondary)
                    }.padding(.vertical, 8)
                }
                Section(header: Text("renewal_settings_support")) {
                    Text(Self.supportAddress).textSelection(.enabled)
                    Button {
                        if MFMailComposeViewController.canSendMail() { showingMail = true }
                        else { mailUnavailable = true }
                    } label: {
                        Label("renewal_settings_email", systemImage: "envelope").frame(minHeight: 44)
                    }.accessibilityIdentifier("renewal.settings.email")
                    Button {
                        UIPasteboard.general.string = Self.supportAddress
                        copied = true
                    } label: {
                        Label(copied ? "renewal_settings_copied" : "renewal_settings_copy", systemImage: "doc.on.doc")
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("renewal.settings.copy")
                    Text("renewal_settings_email_note").font(.footnote).foregroundColor(.secondary)
                }
                Section(header: Text("renewal_settings_about")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hello Protein").font(.headline)
                        Text(version).font(.subheadline).foregroundColor(.secondary)
                    }.accessibilityIdentifier("renewal.settings.version")
                    NavigationLink(destination: CreditsView()) {
                        Label("renewal_settings_credits", systemImage: "doc.text").frame(minHeight: 44)
                    }.accessibilityIdentifier("renewal.settings.credits")
                }
            }
            .navigationTitle(Text("renewal_settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("renewal_settings_done") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("renewal.settings.done")
                }
            }
            .sheet(isPresented: $showingMail) {
                SupportMailComposer { failed in
                    showingMail = false
                    // Present after the composer has finished dismissing.
                    if failed { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { mailFailed = true } }
                }
            }
            .alert("renewal_settings_mail_unavailable", isPresented: $mailUnavailable) {
                Button("renewal_settings_copy") { UIPasteboard.general.string = Self.supportAddress; copied = true }
                Button("renewal_cancel", role: .cancel) {}
            } message: { Text("renewal_settings_mail_unavailable_message") }
            .alert("renewal_settings_mail_failed", isPresented: $mailFailed) {
                Button("renewal_settings_done", role: .cancel) {}
            } message: { Text("renewal_settings_mail_unavailable_message") }
        }
        .navigationViewStyle(.stack)
        .tint(RenewalTheme.action)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return RenewalStrings.format("renewal_settings_version", info["CFBundleShortVersionString"] as? String ?? "—",
                                     info["CFBundleVersion"] as? String ?? "—")
    }
}

@available(iOS 15.0, *)
private struct CreditsView: View {
    var body: some View {
        List {
            Section(header: Text("renewal_settings_food_sources")) {
                Text("renewal_settings_english_source")
                Text("renewal_settings_korean_source")
            }
            Section(header: Text("renewal_settings_libraries")) {
                NavigationLink(destination: licenseText) {
                    Text("renewal_settings_licenses").frame(minHeight: 44)
                }.accessibilityIdentifier("renewal.settings.licenses")
                Text("renewal_settings_licenses_note").font(.footnote).foregroundColor(.secondary)
            }
        }
        .navigationTitle(Text("renewal_settings_credits"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var licenseText: some View {
        ScrollView {
            Text(notices).font(.body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .accessibilityIdentifier("renewal.settings.licenseText")
        }
        .navigationTitle(Text("renewal_settings_licenses"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var notices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return RenewalStrings.text("renewal_settings_licenses_unavailable")
        }
        return text
    }
}

@available(iOS 15.0, *)
private struct SupportMailComposer: UIViewControllerRepresentable {
    let onFinish: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([SettingsView.supportAddress])
        controller.setSubject("[Hello Protein] Support")
        // No records, diagnostics or identifiers are attached automatically.
        return controller
    }
    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(error != nil || result == .failed)
        }
    }
}
