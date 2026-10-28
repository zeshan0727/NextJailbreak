import MessageUI
import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var store: JobStore

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Summary", systemImage: "square.grid.2x2.fill") }

            JobsView()
                .tabItem { Label("Jobs", systemImage: "briefcase.fill") }

            AddJobScreen()
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }

            JobTypesView()
                .tabItem { Label("Types", systemImage: "tag.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(AppPalette.accent)
        .preferredColorScheme(store.settings.theme.colorScheme)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: JobStore

    private var dueSoon: [AccountingJob] {
        let limit = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return store.sortedJobs.filter {
            $0.status != .completed && $0.dueDate <= limit
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    statusGrid
                    valueGrid
                    dueSoonSection
                    recentSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(background)
            .navigationTitle("Next Job")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppPalette.accent, AppPalette.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text(store.settings.companyName)
                    .font(.headline)
                Text("Part-time accounting job tracker")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(store.jobs.count) jobs recorded")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.accent)
            }
            Spacer()
        }
        .glassCard()
    }

    private var statusGrid: some View {
        VStack(spacing: 12) {
            SectionHeader("Work Summary", subtitle: "Live status of all recorded jobs")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCard(
                    title: "Not Started",
                    value: "\(store.count(for: .notStarted))",
                    subtitle: "Waiting to begin",
                    icon: JobStatus.notStarted.icon,
                    tint: AppPalette.status(.notStarted)
                )
                MetricCard(
                    title: "In Progress",
                    value: "\(store.count(for: .inProgress))",
                    subtitle: "Currently being worked",
                    icon: JobStatus.inProgress.icon,
                    tint: AppPalette.status(.inProgress)
                )
                MetricCard(
                    title: "Waiting",
                    value: "\(store.count(for: .waitingForDocuments))",
                    subtitle: "Documents requested",
                    icon: JobStatus.waitingForDocuments.icon,
                    tint: AppPalette.status(.waitingForDocuments)
                )
                MetricCard(
                    title: "Completed",
                    value: "\(store.count(for: .completed))",
                    subtitle: "Ready or already emailed",
                    icon: JobStatus.completed.icon,
                    tint: AppPalette.status(.completed)
                )
            }
        }
    }

    private var valueGrid: some View {
        VStack(spacing: 12) {
            SectionHeader("Price & Time", subtitle: "Completed work and remaining workload")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCard(
                    title: "Completed Value",
                    value: money(store.completedValue),
                    subtitle: "Price of completed jobs",
                    icon: "checkmark.circle.fill",
                    tint: AppPalette.green
                )
                MetricCard(
                    title: "Outstanding Value",
                    value: money(store.outstandingValue),
                    subtitle: "Price still in progress",
                    icon: "hourglass",
                    tint: AppPalette.orange
                )
                MetricCard(
                    title: "Target Time",
                    value: hours(store.totalTargetHours),
                    subtitle: "Planned across all jobs",
                    icon: "target",
                    tint: AppPalette.purple
                )
                MetricCard(
                    title: "Time Recorded",
                    value: hours(store.totalActualHours),
                    subtitle: "Actual work entered",
                    icon: "timer",
                    tint: AppPalette.cyan
                )
            }
        }
    }

    @ViewBuilder
    private var dueSoonSection: some View {
        VStack(spacing: 12) {
            SectionHeader("Due Soon", subtitle: "Open jobs due within seven days")
            if dueSoon.isEmpty {
                EmptyStateView(
                    icon: "calendar.badge.checkmark",
                    title: "Nothing urgent",
                    message: "Open jobs due within seven days will appear here."
                )
            } else {
                ForEach(dueSoon.prefix(4)) { job in
                    NavigationLink {
                        JobDetailView(jobID: job.id)
                    } label: {
                        JobRow(job: job)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(spacing: 12) {
            SectionHeader("Recent Jobs")
            if store.sortedJobs.isEmpty {
                EmptyStateView(
                    icon: "briefcase",
                    title: "No jobs yet",
                    message: "Use the Add tab to record your first KB Accountants job."
                )
            } else {
                ForEach(store.sortedJobs.prefix(5)) { job in
                    NavigationLink {
                        JobDetailView(jobID: job.id)
                    } label: {
                        JobRow(job: job)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [AppPalette.accent.opacity(0.09), Color.clear, AppPalette.purple.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func money(_ amount: Double) -> String {
        "\(store.settings.currency) " + String(format: "%.0f", amount)
    }

    private func hours(_ amount: Double) -> String {
        String(format: "%.1fh", amount)
    }
}
