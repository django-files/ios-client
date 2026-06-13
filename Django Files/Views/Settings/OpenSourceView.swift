import SwiftUI

private struct OSSPackage: Identifiable {
    let id = UUID()
    let name: String
    let author: String
    let license: String
    let url: String
}

private let packages: [OSSPackage] = [
    OSSPackage(
        name: "Firebase iOS SDK",
        author: "Google",
        license: "Apache 2.0",
        url: "https://github.com/firebase/firebase-ios-sdk"
    ),
    OSSPackage(
        name: "GoogleAppMeasurement",
        author: "Google",
        license: "Apache 2.0",
        url: "https://github.com/google/GoogleAppMeasurement"
    ),
    OSSPackage(
        name: "GoogleDataTransport",
        author: "Google",
        license: "Apache 2.0",
        url: "https://github.com/google/GoogleDataTransport"
    ),
    OSSPackage(
        name: "GoogleUtilities",
        author: "Google",
        license: "Apache 2.0",
        url: "https://github.com/google/GoogleUtilities"
    ),
    OSSPackage(
        name: "GTM Session Fetcher",
        author: "Google",
        license: "Apache 2.0",
        url: "https://github.com/google/gtm-session-fetcher"
    ),
    OSSPackage(
        name: "Interop iOS for Google SDKs",
        author: "Google",
        license: "Apache 2.0",
        url: "https://github.com/google/interop-ios-for-google-sdks"
    ),
    OSSPackage(
        name: "Abseil C++ (binary)",
        author: "Google",
        license: "Apache 2.0",
        url: "https://github.com/google/abseil-cpp-binary"
    ),
    OSSPackage(
        name: "gRPC (binary)",
        author: "gRPC Authors",
        license: "Apache 2.0",
        url: "https://github.com/google/grpc-binary"
    ),
    OSSPackage(
        name: "Promises",
        author: "Google",
        license: "Apache 2.0",
        url: "https://github.com/google/promises"
    ),
    OSSPackage(
        name: "FLAnimatedImage",
        author: "Flipboard",
        license: "MIT",
        url: "https://github.com/Flipboard/FLAnimatedImage"
    ),
    OSSPackage(
        name: "HighlightSwift",
        author: "Stefan Britton",
        license: "MIT",
        url: "https://github.com/appstefan/highlightswift"
    ),
    OSSPackage(
        name: "HaishinKit",
        author: "shogo4405",
        license: "BSD 3-Clause",
        url: "https://github.com/shogo4405/HaishinKit.swift"
    ),
    OSSPackage(
        name: "Logboard",
        author: "shogo4405",
        license: "BSD 3-Clause",
        url: "https://github.com/shogo4405/Logboard"
    ),
    OSSPackage(
        name: "swift-http-types",
        author: "Apple",
        license: "Apache 2.0",
        url: "https://github.com/apple/swift-http-types"
    ),
    OSSPackage(
        name: "swift-protobuf",
        author: "Apple",
        license: "Apache 2.0",
        url: "https://github.com/apple/swift-protobuf"
    ),
    OSSPackage(
        name: "LevelDB",
        author: "Google / Firebase",
        license: "BSD 3-Clause",
        url: "https://github.com/firebase/leveldb"
    ),
    OSSPackage(
        name: "nanopb",
        author: "Firebase",
        license: "zlib",
        url: "https://github.com/firebase/nanopb"
    ),
]

struct OpenSourceView: View {
    var body: some View {
        List(packages) { pkg in
            Link(destination: URL(string: pkg.url)!) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pkg.name)
                        .foregroundColor(.primary)
                    HStack {
                        Text(pkg.author)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(pkg.license)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Open Source Software")
    }
}

#Preview {
    NavigationStack {
        OpenSourceView()
    }
}
