import SwiftUI

/// Only the order changes; stable tab identifiers preserve controllers and data.
enum LedgerTabOrder {
    static let defaultValue = "home,budget,ledger,reports,settings"

    static func resolve(_ raw: String) -> [AppTab] {
        let preferred = raw.split(separator: ",").compactMap {
            AppTab(rawValue: String($0).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var seen = Set<AppTab>()
        var unique: [AppTab] = []
        for tab in preferred + AppTab.allCases where seen.insert(tab).inserted {
            unique.append(tab)
        }
        return unique
    }

    static func encode(_ tabs: [AppTab]) -> String {
        tabs.map(\.rawValue).joined(separator: ",")
    }
}

struct TabOrderSettingsView: View {
    @AppStorage("DailyLedgerTabOrder") private var tabOrder = LedgerTabOrder.defaultValue

    var body: some View {
        List {
            Section {
                ForEach(LedgerTabOrder.resolve(tabOrder), id: \.self) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .foregroundStyle(.primary)
                }
                .onMove { from, to in
                    var tabs = LedgerTabOrder.resolve(tabOrder)
                    tabs.move(fromOffsets: from, toOffset: to)
                    tabOrder = LedgerTabOrder.encode(tabs)
                }
            } header: {
                Text("Bottom Navigation")
            } footer: {
                Text("Drag the handles to arrange Home, Budget, Ledger, Reports and Settings. Your order is saved automatically and applied immediately.")
            }

            Section {
                Button("Restore Default Tab Order") {
                    tabOrder = LedgerTabOrder.defaultValue
                }
                .disabled(tabOrder == LedgerTabOrder.defaultValue)
            }
        }
        .navigationTitle("Rearrange Tabs")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
    }
}
