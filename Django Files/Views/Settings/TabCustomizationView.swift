import SwiftUI

private struct AppTabInfo: Identifiable {
    let id: String
    let label: String
    let icon: String
}

private let allConfigurableTabs: [AppTabInfo] = [
    AppTabInfo(id: "files",   label: "Files",   icon: "document.fill"),
    AppTabInfo(id: "albums",  label: "Albums",  icon: "square.stack"),
    AppTabInfo(id: "shorts",  label: "Shorts",  icon: "link"),
    AppTabInfo(id: "streams", label: "Streams", icon: "video.fill"),
]

struct TabCustomizationView: View {
    @AppStorage("tabOrder")  private var tabOrderString  = "files,albums,shorts,streams"
    @AppStorage("hiddenTabs") private var hiddenTabsString = ""

    @State private var orderedTabs: [AppTabInfo] = []
    @State private var hiddenTabIds: Set<String> = []

    var body: some View {
        List {
            Section {
                ForEach(orderedTabs) { tab in
                    HStack {
                        Image(systemName: tab.icon)
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                        Text(tab.label)
                        Spacer()
                        Toggle("", isOn: visibilityBinding(for: tab))
                            .labelsHidden()
                    }
                }
                .onMove { from, to in
                    orderedTabs.move(fromOffsets: from, toOffset: to)
                    saveOrder()
                }
            } footer: {
                Text("Settings is always visible. Drag to reorder. At least one tab must remain visible.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Customize Tabs")
        .onAppear(perform: loadState)
    }

    private func visibilityBinding(for tab: AppTabInfo) -> Binding<Bool> {
        Binding(
            get: { !hiddenTabIds.contains(tab.id) },
            set: { visible in
                if visible {
                    hiddenTabIds.remove(tab.id)
                } else {
                    let visibleCount = orderedTabs.filter { !hiddenTabIds.contains($0.id) }.count
                    guard visibleCount > 1 else { return }
                    hiddenTabIds.insert(tab.id)
                }
                saveHidden()
            }
        )
    }

    private func loadState() {
        let order  = tabOrderString.split(separator: ",").map(String.init)
        let hidden = Set(hiddenTabsString.split(separator: ",").map(String.init).filter { !$0.isEmpty })

        var result: [AppTabInfo] = order.compactMap { id in
            allConfigurableTabs.first { $0.id == id }
        }
        for tab in allConfigurableTabs where !result.contains(where: { $0.id == tab.id }) {
            result.append(tab)
        }
        orderedTabs = result
        hiddenTabIds = hidden
    }

    private func saveOrder() {
        tabOrderString = orderedTabs.map { $0.id }.joined(separator: ",")
    }

    private func saveHidden() {
        hiddenTabsString = hiddenTabIds.joined(separator: ",")
    }
}

#Preview {
    NavigationStack {
        TabCustomizationView()
    }
}
