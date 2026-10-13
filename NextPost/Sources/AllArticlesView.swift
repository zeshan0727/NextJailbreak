import SwiftUI
import UIKit

/// Full catalogue of published site articles. Numbers always follow the
/// global newest-first sequence, even when the list is filtered by search.
struct AllArticlesView: View {
    @ObservedObject var store: NextPostStore
    let onUseArticle: () -> Void

    @State private var searchText = ""

    private struct NumberedArticle: Identifiable {
        let position: Int
        let article: PublishedArticle
        var id: String { article.id }
    }

    private var visibleArticles: [NumberedArticle] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.allArticles.enumerated().compactMap { index, article in
            if !query.isEmpty &&
                !article.title.localizedCaseInsensitiveContains(query) &&
                !article.name.localizedCaseInsensitiveContains(query) &&
                !(article.version?.localizedCaseInsensitiveContains(query) ?? false) &&
                !(article.category?.label?.localizedCaseInsensitiveContains(query) ?? false) {
                return nil
            }
            return NumberedArticle(position: index + 1, article: article)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.04, blue: 0.08),
                        Color(red: 0.03, green: 0.07, blue: 0.13),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Label("\(store.allArticles.count) published articles", systemImage: "newspaper")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("Newest first")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    if store.allArticles.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "text.book.closed")
                                .font(.system(size: 38))
                                .foregroundStyle(.blue)
                            Text("No articles loaded")
                                .font(.headline)
                            Text("Pull to refresh or tap the refresh icon to load published articles.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Refresh Articles") {
                                Task { await store.refreshStats(manual: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isRefreshing)
                        }
                        .padding(25)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if visibleArticles.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        List(visibleArticles) { row in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(row.position)")
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.blue)
                                    .frame(width: 32, alignment: .leading)
                                    .padding(.top, 3)

                                VStack(alignment: .leading, spacing: 7) {
                                    Button {
                                        UIApplication.shared.open(row.article.publishedURL)
                                    } label: {
                                        Text(row.article.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)

                                    HStack(spacing: 8) {
                                        if let category = row.article.category?.label, !category.isEmpty {
                                            Text(category)
                                                .lineLimit(1)
                                        }
                                        if let date = row.article.publishedAt, date.count >= 10 {
                                            Text(String(date.prefix(10)))
                                                .monospacedDigit()
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                    HStack(spacing: 8) {
                                        if store.isGenerated(row.article) {
                                            Label("Generated", systemImage: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        } else {
                                            Label("Available", systemImage: "circle.dotted")
                                                .foregroundStyle(.secondary)

                                            Button {
                                                store.selectRemainingArticle(row.article)
                                                onUseArticle()
                                            } label: {
                                                Label("Use for Post", systemImage: "plus.circle")
                                                    .fontWeight(.semibold)
                                            }
                                            .buttonStyle(.borderless)
                                            .foregroundStyle(.blue)
                                        }
                                    }
                                    .font(.caption)
                                }
                            }
                            .padding(.vertical, 7)
                            .listRowBackground(Color.white.opacity(0.055))
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .refreshable { await store.refreshStats(manual: true) }
                    }
                }
            }
            .navigationTitle("All Articles")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refreshStats(manual: true) }
                    } label: {
                        if store.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(store.isRefreshing || store.isLoading)
                    .accessibilityLabel("Refresh all articles")
                }
            }
            .searchable(text: $searchText, prompt: "Search all published articles")
        }
    }
}
