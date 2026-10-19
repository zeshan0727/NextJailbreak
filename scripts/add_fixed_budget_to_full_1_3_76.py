"""Patch FULL generated 1.3.76 sources only AFTER running apply_next_ledger_1_3_76.sh.
Fail on any missing or ambiguous expected anchor. Do not touch SMS daemon/source.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def get(p): return (ROOT/p).read_text(encoding="utf8")
def set_(p,v): (ROOT/p).write_text(v,encoding="utf8")
def patch(path,old,new):
    src=get(path)
    matches=src.count(old)
    if matches!=1:
        raise RuntimeError(f"Unexpected {path} anchor count {matches}: {old[:100]}")
    set_(path,src.replace(old,new,1))

for p in (
    "DailyLedger/Views/SMSImportConsoleView.swift",
    "DailyLedger/Views/SMSLatest15ReviewView.swift",
    "DailyLedger/Services/SMSImportConsoleService.swift",
    "DailyLedger/Views/FixedBudgetDashboardView.swift",
    "DailyLedger/Models/MonthlyFixedBudget.swift"
):
    if not (ROOT/p).exists(): raise RuntimeError("Missing full-source feature: "+p)
if "Fetch Latest 15 SMS" not in get("DailyLedger/Views/SMSImportConsoleView.swift"):
    raise RuntimeError("Wrong source: SMS Console is absent")

m="DailyLedger/Models/LedgerTransaction.swift"
patch(m,"    var settings: LedgerSettings\n\n    init(\n        version: Int = 5","    var settings: LedgerSettings\n    var fixedBudget: MonthlyFixedBudget\n\n    init(\n        version: Int = 5")
patch(m,"        settings: LedgerSettings = LedgerSettings()\n    ) {\n        self.version = version","        settings: LedgerSettings = LedgerSettings(),\n        fixedBudget: MonthlyFixedBudget = MonthlyFixedBudget()\n    ) {\n        self.version = version")
patch(m,"        self.settings = settings\n        normalize()\n    }\n\n    private enum CodingKeys: String, CodingKey {\n        case version","        self.settings = settings\n        self.fixedBudget = fixedBudget\n        normalize()\n    }\n\n    private enum CodingKeys: String, CodingKey {\n        case version")
patch(m,"        case version\n        case transactions\n        case accounts\n        case settings\n    }","        case version\n        case transactions\n        case accounts\n        case settings\n        case fixedBudget\n    }")
patch(m,"        settings = try values.decodeIfPresent(LedgerSettings.self, forKey: .settings) ?? LedgerSettings()\n        normalize()","        settings = try values.decodeIfPresent(LedgerSettings.self, forKey: .settings) ?? LedgerSettings()\n        fixedBudget = try values.decodeIfPresent(MonthlyFixedBudget.self, forKey: .fixedBudget) ?? MonthlyFixedBudget()\n        normalize()")

s="DailyLedger/Services/LedgerStore.swift"
patch(s,"    @Published private(set) var settings = LedgerSettings()","    @Published private(set) var settings = LedgerSettings()\n    @Published private(set) var fixedBudget = MonthlyFixedBudget()")
patch(s,"        settings = ledger.settings\n        runningBalances = running","        settings = ledger.settings\n        fixedBudget = ledger.fixedBudget\n        runningBalances = running")
patch(s,"    func syncBackupNow() {",'''    func saveFixedBudget(_ plan: MonthlyFixedBudget) {
        updateLedger(failureMessage: "Fixed budget could not be saved.") { ledger in
            ledger.fixedBudget = plan
        }
    }

    func syncBackupNow() {''')
patch(s,"            accounts: incoming.accounts,\n            restoring: incoming.settings\n        )","            accounts: incoming.accounts,\n            restoring: incoming.settings,\n            fixedBudget: incoming.fixedBudget\n        )")

d="DailyLedger/Services/LedgerDiskStore.swift"
patch(d,"        restoring settings: LedgerSettings? = nil\n    ) throws -> LedgerData","        restoring settings: LedgerSettings? = nil,\n        fixedBudget: MonthlyFixedBudget? = nil\n    ) throws -> LedgerData")
patch(d,"                if let settings {\n                    ledger.settings = settings\n                }\n                ledger.normalize()","                if let settings {\n                    ledger.settings = settings\n                }\n                if let fixedBudget { ledger.fixedBudget = fixedBudget }\n                ledger.normalize()")
ds=get(d)
if ds.count("var ledger = loadUnlocked()")!=3:
    raise RuntimeError("Storage write path mismatch")
ds=ds.replace("var ledger = loadUnlocked()","var ledger = try loadForMutationUnlocked()")
set_(d,ds)
patch(d,"    private func saveUnlocked(_ ledger: LedgerData) throws {",'''    // Never erase financial history merely because the ledger is unreadable.
    private func loadForMutationUnlocked() throws -> LedgerData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return LedgerData() }
        return try decoder.decode(LedgerData.self, from: Data(contentsOf: fileURL))
    }

    private func saveUnlocked(_ ledger: LedgerData) throws {''')

i="DailyLedger/Services/ImportExport.swift"
patch(i,"    let settings: LedgerSettings?\n}","    let settings: LedgerSettings?\n    let fixedBudget: MonthlyFixedBudget?\n}")
patch(i,"        settings: LedgerSettings\n    ) -> Data","        settings: LedgerSettings,\n        fixedBudget: MonthlyFixedBudget = MonthlyFixedBudget()\n    ) -> Data")
patch(i,"LedgerData(version: 5, transactions: transactions, accounts: accounts, settings: settings)","LedgerData(version: 5, transactions: transactions, accounts: accounts, settings: settings, fixedBudget: fixedBudget)")
patch(i,"                settings: ledger.settings\n            )",'''                settings: ledger.settings,
                fixedBudget: ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["fixedBudget"] != nil ? ledger.fixedBudget : nil
            )''')
isrc=get(i)
if isrc.count("settings: nil)")!=3:
    raise RuntimeError("Import payload shape mismatch")
set_(i,isrc.replace("settings: nil)","settings: nil, fixedBudget: nil)"))

v="DailyLedger/Views/SettingsView.swift"
patch(v,"            settings: store.settings\n        ))","            settings: store.settings,\n            fixedBudget: store.fixedBudget\n        ))")
patch(v,'''                        NavigationLink {
                            BudgetSettingsView()
                        } label: {''','''                        NavigationLink {
                            FixedBudgetDashboardView()
                        } label: {
                            SettingsRow(
                                title: "Fixed Monthly Budget",
                                subtitle: "Income, recurring expenses & 26th–25th cycle",
                                icon: "calendar.badge.clock",
                                color: AppTheme.purple
                            )
                        }
                        NavigationLink {
                            BudgetSettingsView()
                        } label: {''')
patch(v,'LabeledContent("Version", value: "1.3.76")','LabeledContent("Version", value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.79") + " (Build " + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "88") + ")")')

p="project.yml"
patch(p,'MARKETING_VERSION: "1.3.76"','MARKETING_VERSION: "1.3.79"')
patch(p,'CURRENT_PROJECT_VERSION: "84"','CURRENT_PROJECT_VERSION: "88"')
for feature in ("SMSImportConsoleView()","ModernAISettingsView()","FixedBudgetDashboardView()","BudgetSettingsView()"):
    if feature not in get(v): raise RuntimeError("Lost feature "+feature)
assert "1.3.79" in get(p)
print("PASS: Full generated Next Ledger 1.3.76 upgraded to 1.3.79, all core screens retained.")
