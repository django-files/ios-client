//
//  AppSettings.swift
//  Django Files
//

import SwiftUI
import FirebaseCrashlytics

struct PrivacySettingsView: View {
    @AppStorage("firebaseAnalyticsEnabled") private var firebaseAnalyticsEnabled = true
    @AppStorage("crashlyticsEnabled") private var crashlyticsEnabled = true
    @State private var showAnalyticsAlert = false
    @State private var showCrashlyticsAlert = false
    @State private var pendingAnalyticsValue = true
    @State private var pendingCrashlyticsValue = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { firebaseAnalyticsEnabled },
                    set: { newValue in
                        if !newValue {
                            pendingAnalyticsValue = newValue
                            showAnalyticsAlert = true
                        } else {
                            firebaseAnalyticsEnabled = newValue
                            DFAnalytics.setCollectionEnabled(newValue)
                        }
                    }
                )) {
                    VStack(alignment: .leading) {
                        Text("Analytics")
                        Text("Help improve the app by sending anonymous usage data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .alert("Disable Analytics?", isPresented: $showAnalyticsAlert) {
                    Button("Keep Enabled", role: .cancel) { firebaseAnalyticsEnabled = true }
                    Button("Disable", role: .destructive) {
                        firebaseAnalyticsEnabled = pendingAnalyticsValue
                        DFAnalytics.setCollectionEnabled(pendingAnalyticsValue)
                    }
                } message: {
                    Text("Please consider leaving analytics enabled to help improve Django Files. We do not collect ANY personal information with analytics.")
                }

                Toggle(isOn: Binding(
                    get: { crashlyticsEnabled },
                    set: { newValue in
                        if !newValue {
                            pendingCrashlyticsValue = newValue
                            showCrashlyticsAlert = true
                        } else {
                            crashlyticsEnabled = newValue
                            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(newValue)
                        }
                    }
                )) {
                    VStack(alignment: .leading) {
                        Text("Crash Reporting")
                        Text("Send crash reports to help identify and fix issues")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .alert("Disable Crash Reporting?", isPresented: $showCrashlyticsAlert) {
                    Button("Keep Enabled", role: .cancel) { crashlyticsEnabled = true }
                    Button("Disable", role: .destructive) {
                        crashlyticsEnabled = pendingCrashlyticsValue
                        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(pendingCrashlyticsValue)
                    }
                } message: {
                    Text("Please consider leaving crash reporting enabled. We collect no personal information, only information pertaining to application errors.")
                }
            } footer: {
                Text("These settings help us improve Django Files. No personal information is ever collected.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PrivacySettingsView()
    }
}
