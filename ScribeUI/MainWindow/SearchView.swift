import SwiftUI
import ScribeCore

/// Full-text search across meetings — titles, transcripts, notes, and summaries
public struct SearchView: View {
    @Binding var selectedMeetingId: UUID?
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    public init(selectedMeetingId: Binding<UUID?>) {
        self._selectedMeetingId = selectedMeetingId
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search across all meetings...", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { performSearch() }

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }

                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding()

            Divider()

            // Results
            if results.isEmpty && !query.isEmpty && !isSearching {
                ContentUnavailableView.search(text: query)
            } else if results.isEmpty && query.isEmpty {
                ContentUnavailableView(
                    "Search Meetings",
                    systemImage: "magnifyingglass",
                    description: Text("Search across titles, transcripts, notes, and summaries.")
                )
            } else {
                List {
                    ForEach(results) { result in
                        SearchResultRow(result: result)
                            .transition(.opacity)
                            .onTapGesture {
                                selectedMeetingId = result.meetingId
                            }
                    }
                }
                .animation(Anim.standard, value: results.count)
            }
        }
        .onChange(of: query) { _ in
            debouncedSearch()
        }
    }

    private func debouncedSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearchAsync(q)
        }
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        Task { await performSearchAsync(q) }
    }

    private func performSearchAsync(_ q: String) async {
        // Search FTS index (transcripts, notes, summaries)
        let ftsResults = (try? await SearchIndex.shared.search(query: q)) ?? []

        // Also search meeting titles directly
        let titleResults = (try? await SearchIndex.shared.searchTitles(query: q)) ?? []

        // Merge, deduplicate by meetingId for title results
        var seen = Set<UUID>()
        var merged: [SearchResult] = []

        // Title matches first
        for r in titleResults {
            if seen.insert(r.meetingId).inserted {
                merged.append(r)
            }
        }

        // Then FTS results
        for r in ftsResults {
            merged.append(r)
        }

        await MainActor.run {
            results = merged
            isSearching = false
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.meetingTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                SourceBadge(source: result.source)
            }

            Text(cleanSnippet(result.snippet))
                .font(.body)
                .lineLimit(3)
                .foregroundStyle(.secondary)

            Text(formatDate(result.timestamp))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func cleanSnippet(_ html: String) -> String {
        html.replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: "")
    }

    private func formatDate(_ date: Date) -> String {
        ScribeDateFormatting.fullDate(date)
    }
}

struct SourceBadge: View {
    let source: SearchResult.SearchSource

    var body: some View {
        Text(source.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch source {
        case .transcript: return .blue
        case .note: return .green
        case .summary: return .purple
        case .title: return .orange
        }
    }
}
