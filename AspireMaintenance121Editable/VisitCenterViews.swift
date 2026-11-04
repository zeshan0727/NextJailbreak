import SwiftUI

enum VisitCenterFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case pending = "Pending"
    case completed = "Completed"
    var id: String { rawValue }
}

struct VisitCenterView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var month = Date()
    @State private var filter: VisitCenterFilter = .all

    private var customerProgress: [VisitCustomerProgress] {
        store.monthlyMaintenanceCustomers.map { customer in
            let completed = store.completedVisitCount(for: customer.id, in: month)
            return VisitCustomerProgress(customer: customer, completed: completed, remaining: max(0, customer.plannedVisitsPerMonth - completed))
        }
        .sorted {
            if $0.remaining == 0 && $1.remaining != 0 { return false }
            if $0.remaining != 0 && $1.remaining == 0 { return true }
            if $0.remaining != $1.remaining { return $0.remaining > $1.remaining }
            return $0.customer.name.localizedCaseInsensitiveCompare($1.customer.name) == .orderedAscending
        }
    }

    private var filteredCustomers: [VisitCustomerProgress] {
        switch filter {
        case .all: return customerProgress
        case .pending: return customerProgress.filter { $0.remaining > 0 }
        case .completed: return customerProgress.filter { $0.remaining == 0 }
        }
    }

    private var monthVisits: [MaintenanceVisit] {
        store.visits(in: month).sorted { $0.date > $1.date }
    }

    private var totalPlanned: Int { customerProgress.reduce(0) { $0 + $1.customer.plannedVisitsPerMonth } }
    private var totalCompleted: Int { customerProgress.reduce(0) { $0 + min($1.completed, $1.customer.plannedVisitsPerMonth) } }
    private var totalPending: Int { max(0, totalPlanned - totalCompleted) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        MonthPicker(month: $month)

                        HStack(spacing: 10) {
                            VisitSummaryCard(title: "Done", value: "\(totalCompleted)", icon: "checkmark.circle.fill", good: true)
                            VisitSummaryCard(title: "Pending", value: "\(totalPending)", icon: "clock.fill", good: false)
                            VisitSummaryCard(title: "Planned", value: "\(totalPlanned)", icon: "calendar", good: nil)
                        }

                        Picker("Visit view", selection: $filter) {
                            ForEach(VisitCenterFilter.allCases) { item in Text(item.rawValue).tag(item) }
                        }
                        .pickerStyle(.segmented)

                        if filter == .completed {
                            CompletedVisitsList(monthVisits: monthVisits)
                        } else if filteredCustomers.isEmpty {
                            FullEmptyView(
                                title: filter == .pending ? "All Visits Completed" : "No Active Customers",
                                icon: filter == .pending ? "checkmark.seal.fill" : "person.2",
                                message: filter == .pending ? "There are no pending planned visits for this month." : "Add or activate customers to begin visit tracking."
                            )
                            .frame(minHeight: 280)
                        } else {
                            ForEach(filteredCustomers) { progress in
                                NavigationLink {
                                    VisitCustomerDetailView(customerID: progress.customer.id, month: month)
                                } label: {
                                    VisitCenterCustomerCard(progress: progress, month: month)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Visit Center")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink { CustomersView() } label: { Image(systemName: "person.2.fill") }
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape.fill") }
                }
            }
        }
    }
}

struct VisitCustomerProgress: Identifiable {
    let customer: Customer
    let completed: Int
    let remaining: Int
    var id: UUID { customer.id }
}

struct VisitSummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let good: Bool?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(good == true ? Color.aspireGreen : good == false ? Color.orange : Color.aspireGold)
            Text(value).font(.title3.bold())
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct VisitCenterCustomerCard: View {
    @EnvironmentObject private var store: AspireStore
    let progress: VisitCustomerProgress
    let month: Date

    private var isComplete: Bool { progress.remaining == 0 }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill((isComplete ? Color.aspireGreen : Color.orange).opacity(0.12))
                    Text(progress.customer.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased())
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(isComplete ? Color.aspireGreen : Color.orange)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.customer.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                    if !progress.customer.address.isEmpty {
                        Text(progress.customer.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(isComplete ? "COMPLETED" : "\(progress.remaining) LEFT")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(isComplete ? Color.aspireGreen : Color.orange)
                    Text("\(progress.completed)/\(progress.customer.plannedVisitsPerMonth)")
                        .font(.headline.weight(.bold))
                }
            }

            ProgressView(value: Double(min(progress.completed, progress.customer.plannedVisitsPerMonth)), total: Double(max(1, progress.customer.plannedVisitsPerMonth)))
                .tint(isComplete ? .aspireGreen : .orange)

            HStack(spacing: 6) {
                let assignments = store.visitAssignments(for: progress.customer.id, in: month)
                ForEach(1...max(1, progress.customer.plannedVisitsPerMonth), id: \.self) { slot in
                    let done = assignments[slot] != nil
                    HStack(spacing: 4) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        Text(VisitOrdinal.text(slot))
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(done ? Color.aspireGreen : Color.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background((done ? Color.aspireGreen : Color.orange).opacity(0.08), in: Capsule())
                }
            }
        }
        .aspirePanel()
    }
}

struct CompletedVisitsList: View {
    @EnvironmentObject private var store: AspireStore
    let monthVisits: [MaintenanceVisit]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Completed Visits", subtitle: "All recorded maintenance visits for the selected month")
            if monthVisits.isEmpty {
                EmptyInlineView(icon: "leaf", text: "No completed visits recorded")
            } else {
                ForEach(monthVisits) { visit in
                    NavigationLink {
                        if let customer = store.customer(id: visit.customerID) {
                            VisitCustomerDetailView(customerID: customer.id, month: visit.date)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.aspireGreen)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.customer(id: visit.customerID)?.name ?? "Unknown Customer")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                HStack(spacing: 5) {
                                    Text(visit.visitNumber.map { VisitOrdinal.text($0) + " visit" } ?? "Maintenance visit")
                                    Text("•")
                                    Text(DateFormatter.shortDate.string(from: visit.date))
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let employee = store.employee(id: visit.employeeID) {
                                Text(employee.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    if visit.id != monthVisits.last?.id { Divider() }
                }
            }
        }
        .aspirePanel()
    }
}

struct VisitCustomerDetailView: View {
    @EnvironmentObject private var store: AspireStore
    let customerID: UUID
    let month: Date
    @State private var visitDate = Date()
    @State private var employeeID: UUID?
    @State private var notes = ""
    @State private var scheduleSlot = 1
    @State private var scheduleDate = Date()
    @State private var message: String?

    private var customer: Customer? { store.customer(id: customerID) }
    private var assignments: [Int: MaintenanceVisit] { store.visitAssignments(for: customerID, in: month) }
    private var pendingSlots: [Int] {
        guard let customer else { return [] }
        return Array(1...max(1, customer.plannedVisitsPerMonth)).filter { assignments[$0] == nil }
    }

    var body: some View {
        Group {
            if let customer {
                ScrollView {
                    LazyVStack(spacing: 15) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(customer.name).font(.title3.bold())
                                    Text(DateFormatter.monthAndYear.string(from: month)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                let done = assignments.count
                                Text("\(done)/\(customer.plannedVisitsPerMonth)")
                                    .font(.title2.bold())
                                    .foregroundStyle(done >= customer.plannedVisitsPerMonth ? Color.aspireGreen : Color.orange)
                            }
                            ProgressView(value: Double(min(assignments.count, customer.plannedVisitsPerMonth)), total: Double(max(1, customer.plannedVisitsPerMonth)))
                                .tint(assignments.count >= customer.plannedVisitsPerMonth ? .aspireGreen : .orange)
                        }
                        .aspirePanel()

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Record Completed Visit", subtitle: "Choose the actual visit date, time and employee, then tap a pending visit below")
                            DatePicker("Visit date", selection: $visitDate, displayedComponents: .date)
                            DatePicker("Visit time", selection: $visitDate, displayedComponents: .hourAndMinute)
                            Picker("Job done by", selection: $employeeID) {
                                Text("Not selected").tag(UUID?.none)
                                ForEach(store.activeEmployees) { employee in Text(employee.name).tag(Optional(employee.id)) }
                            }
                            TextField("Visit notes (optional)", text: $notes, axis: .vertical).lineLimit(2...4)
                        }
                        .aspirePanel()

                        if !pendingSlots.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Schedule Next Visit", subtitle: "Set the planned date and time shown on Dashboard and Today's Visits")
                                Picker("Planned visit", selection: $scheduleSlot) {
                                    ForEach(pendingSlots, id: \.self) { slot in
                                        Text("\(VisitOrdinal.text(slot)) Visit").tag(slot)
                                    }
                                }
                                DatePicker("Schedule date", selection: $scheduleDate, displayedComponents: .date)
                                DatePicker("Schedule time", selection: $scheduleDate, displayedComponents: .hourAndMinute)
                                Button {
                                    saveSchedule()
                                } label: {
                                    Label("Save Visit Schedule", systemImage: "calendar.badge.checkmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.aspireGreen)
                            }
                            .aspirePanel()
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Planned Visits", subtitle: "Orange = pending • Green = completed • Scheduled time appears under pending visits")
                            let columns = [GridItem(.adaptive(minimum: 135), spacing: 10)]
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(1...max(1, customer.plannedVisitsPerMonth), id: \.self) { slot in
                                    VisitSlotButton(
                                        slot: slot,
                                        visit: assignments[slot],
                                        scheduledAt: store.scheduledVisit(for: customerID, slot: slot, in: month)?.scheduledAt,
                                        action: { complete(slot: slot) }
                                    )
                                }
                            }
                        }
                        .aspirePanel()

                        if !assignments.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Completed This Month", subtitle: "Recorded date, time and employee")
                                ForEach(assignments.keys.sorted(), id: \.self) { slot in
                                    if let visit = assignments[slot] {
                                        HStack(spacing: 10) {
                                            Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.aspireGreen)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(VisitOrdinal.text(slot)) Visit").font(.subheadline.weight(.semibold))
                                                Text(DateFormatter.shortDateTime.string(from: visit.date)).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(store.employee(id: visit.employeeID)?.name ?? visit.staffName)
                                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                            }
                            .aspirePanel()
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Monthly Visit Schedule")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                FullEmptyView(title: "Customer Not Found", icon: "person.crop.circle.badge.exclamationmark", message: "This customer is no longer available.")
            }
        }
        .onAppear {
            visitDate = VisitDateDefaults.date(in: month)
            scheduleDate = defaultScheduleDate(in: month)
            if let first = pendingSlots.first { scheduleSlot = first }
            syncScheduleDate()
        }
        .onChange(of: scheduleSlot) { _ in syncScheduleDate() }
        .alert("Visit Center", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func complete(slot: Int) {
        guard assignments[slot] == nil else { return }
        if store.recordVisitSlot(customerID: customerID, slot: slot, date: visitDate, employeeID: employeeID, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)) {
            notes = ""
            if let next = pendingSlots.first { scheduleSlot = next }
        } else {
            message = store.lastErrorMessage ?? "Unable to record visit."
        }
    }

    private func saveSchedule() {
        guard pendingSlots.contains(scheduleSlot) else {
            message = "Choose a pending monthly visit to schedule."
            return
        }
        if store.setVisitSchedule(customerID: customerID, slot: scheduleSlot, scheduledAt: scheduleDate) {
            message = "\(VisitOrdinal.text(scheduleSlot)) visit scheduled for \(DateFormatter.shortDateTime.string(from: scheduleDate))."
        } else {
            message = store.lastErrorMessage ?? "Unable to save visit schedule."
        }
    }

    private func syncScheduleDate() {
        if let existing = store.scheduledVisit(for: customerID, slot: scheduleSlot, in: month) {
            scheduleDate = existing.scheduledAt
        } else {
            scheduleDate = defaultScheduleDate(in: month)
        }
    }

    private func defaultScheduleDate(in month: Date) -> Date {
        let calendar = Calendar.current
        if calendar.isDate(month, equalTo: Date(), toGranularity: .month) {
            return calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        }
        let components = calendar.dateComponents([.year, .month], from: month)
        let start = calendar.date(from: components) ?? month
        return calendar.date(byAdding: .hour, value: 9, to: start) ?? start
    }
}

struct VisitSlotButton: View {
    let slot: Int
    let visit: MaintenanceVisit?
    let scheduledAt: Date?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: visit == nil ? (scheduledAt == nil ? "clock.badge.checkmark" : "calendar.badge.clock") : "checkmark.circle.fill")
                    .font(.title2)
                Text("\(VisitOrdinal.text(slot)) Visit").font(.subheadline.weight(.bold))
                Text(statusText)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .opacity(0.85)
            }
            .foregroundStyle(visit == nil ? Color.orange : Color.aspireGreen)
            .frame(maxWidth: .infinity, minHeight: 102)
            .background((visit == nil ? Color.orange : Color.aspireGreen).opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke((visit == nil ? Color.orange : Color.aspireGreen).opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(visit != nil)
    }

    private var statusText: String {
        if let visit { return DateFormatter.shortDateTime.string(from: visit.date) }
        if let scheduledAt { return "Scheduled \(DateFormatter.shortDateTime.string(from: scheduledAt))" }
        return "Tap to mark done"
    }
}

enum VisitOrdinal {
    static func text(_ value: Int) -> String {
        let mod100 = value % 100
        if 11...13 ~= mod100 { return "\(value)th" }
        switch value % 10 {
        case 1: return "\(value)st"
        case 2: return "\(value)nd"
        case 3: return "\(value)rd"
        default: return "\(value)th"
        }
    }
}

enum VisitDateDefaults {
    static func date(in month: Date) -> Date {
        let calendar = Calendar.current
        if calendar.isDate(month, equalTo: Date(), toGranularity: .month) { return Date() }
        let comps = calendar.dateComponents([.year, .month], from: month)
        return calendar.date(from: comps) ?? month
    }
}

extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
