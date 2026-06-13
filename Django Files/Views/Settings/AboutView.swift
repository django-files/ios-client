import SwiftUI
import UIKit

struct AboutView: View {
    var serverVersion: String?

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        if version == "0.0" { return "dev (source)" }
        return "\(version) (\(build))"
    }

    private var deviceInfo: String {
        let device = UIDevice.current
        return "\(device.model), iOS \(device.systemVersion)"
    }

    private var appIssueURL: URL {
        let body = """
        **What went wrong?**


        **What was expected?**


        **Steps to reproduce**
        1.
        2.
        3.

        **Environment**
        - Device: \(deviceInfo)
        - App Version: \(appVersion)
        """
        var components = URLComponents(string: "https://github.com/django-files/ios-client/issues/new")!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url!
    }

    private var serverIssueURL: URL {
        let serverLine = serverVersion.map { "- Server Version: \($0)\n" } ?? ""
        let body = """
        **What went wrong?**


        **What was expected?**


        **Steps to reproduce**
        1.
        2.
        3.

        **Environment**
        - Device: \(deviceInfo)
        - App Version: \(appVersion)
        \(serverLine)
        """
        var components = URLComponents(string: "https://github.com/django-files/django-files/issues/new")!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url!
    }

    var body: some View {
        List {
            Section(header: Text("Version")) {
                HStack {
                    Text("Django Files iOS")
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Report an Issue")) {
                Link(destination: appIssueURL) {
                    Label("iOS App Issue", systemImage: "exclamationmark.bubble")
                }
                Link(destination: serverIssueURL) {
                    Label("Server Issue", systemImage: "exclamationmark.triangle")
                }
            }

            Section {
                NavigationLink {
                    OpenSourceView()
                } label: {
                    Label("Open Source Software", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("About")
    }
}

#Preview {
    NavigationStack {
        AboutView(serverVersion: "2025.1.0")
    }
}
