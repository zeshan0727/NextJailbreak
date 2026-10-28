import MessageUI
import SwiftUI
import UIKit

enum JobListFilter: String, CaseIterable, Identifiable {
    case all
    case notStarted
    case inProgress
    case waiting
    case review
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .waiting: return "Waiting"
        case .review: return "Review"
        case .completed: return "Completed"
        }
    }

    var status: JobStatus? {
        switch self {
        case .all: return nil
        case .notStarted: return .notStarted
        case .inProgress: return .inProgress
        case .waiting: return .waitingForDocuments
        case .review: return .readyForReview
        case .completed: return .completed
        }
    }
}

struct JobsView: View {
    @EnvironmentObject private var store: JobStore
    @State private var searchText = ""
    @State private var filter: JobListFilter = .all

    private var filteredJobs: [AccountingJob] {
        store.sortedJobs.filter { job in
            let matchesStatus = filter.status == nil || job.status == filter.status
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || job.title.localizedCaseInsensitiveContains(query)
                || job.clientReference.localizedCaseInsensitiveContains(query)
                || store.typeName(for: job).localizedCaseInsensitiveContains(query)
            return matchesStatus && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    filterBar
                    if filteredJobs.isEmpty {
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: "No matching jobs",
                            message: "Change the search or status filter, or add a new job."
                        )
                        .padding(.top, 30)
                    } else {
                        ForEach(filteredJobs) { job in
                            NavigationLink {
                                JobDetailView(jobID: job.id)
                            } label: {
                                JobRow(job: job)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.delete(job)
                                } label: {
                                    Label("Delete Job", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Jobs")
            .searchable(text: $searchText, prompt: "Search title, client or type")
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(JobListFilter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(filter == item ? Color.white : Color.primary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(
                                filter == item ? AppPalette.accent : Color.primary.opacity(0.07),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct JobRow: View {
    @EnvironmentObject private var store: JobStore
    let job: AccountingJob

    private var isOverdue: Bool {
        job.status != .completed && job.dueDate < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(job.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(store.typeName(for: job))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !job.clientReference.isEmpty {
                        Text(job.clientReference)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                StatusBadge(status: job.status)
            }

            Divider().opacity(0.6)

            HStack {
                Label(DateFormatter.mediumDate.string(from: job.dueDate), systemImage: "calendar")
                    .foregroundStyle(isOverdue ? AppPalette.red : Color.secondary)
                Spacer()
                Text("\(store.settings.currency) \(job.price, specifier: "%.2f")")
                    .fontWeight(.semibold)
                Text("•")
                    .foregroundStyle(.secondary)
                Text("\(job.targetHours, specifier: "%.1f")h")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .glassCard()
    }
}
