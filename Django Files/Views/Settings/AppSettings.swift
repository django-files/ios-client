//
//  AppSettings.swift
//  Django Files
//
//  Created by Ralph Luaces on 5/31/25.
//

import SwiftUI
import FirebaseAnalytics
import FirebaseCrashlytics

struct AppSettings: View {
    @AppStorage("firebaseAnalyticsEnabled") private var firebaseAnalyticsEnabled = true
    @AppStorage("crashlyticsEnabled") private var crashlyticsEnabled = true
    @State private var showAnalyticsAlert = false
    @State private var showCrashlyticsAlert = false
    @State private var pendingAnalyticsValue = true
    @State private var pendingCrashlyticsValue = true
    
    private var versionInfo: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        if version == "0.0" {
            return "dev (source)"
        }
        return "\(version) (\(build))"
    }
    
    var body: some View {
        Form {
            Section(header: Text("Privacy")) {
                Toggle(isOn: Binding(
                    get: { firebaseAnalyticsEnabled },
                    set: { newValue in
                        if !newValue {
                            pendingAnalyticsValue = newValue
                            showAnalyticsAlert = true
                        } else {
                            firebaseAnalyticsEnabled = newValue
                            Analytics.setAnalyticsCollectionEnabled(newValue)
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
                    Button("Keep Enabled", role: .cancel) {
                        firebaseAnalyticsEnabled = true
                    }
                    Button("Disable", role: .destructive) {
                        firebaseAnalyticsEnabled = pendingAnalyticsValue
                        Analytics.setAnalyticsCollectionEnabled(pendingAnalyticsValue)
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
                    Button("Keep Enabled", role: .cancel) {
                        crashlyticsEnabled = true
                    }
                    Button("Disable", role: .destructive) {
                        crashlyticsEnabled = pendingCrashlyticsValue
                        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(pendingCrashlyticsValue)
                    }
                } message: {
                    Text("Please consider leaving crash analytics enabled. We collect no personal information, only information portaining to application errors.")
                }
            }
            
            Section(header: Text("About")) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(versionInfo)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationView {
        AppSettings()
    }
}

