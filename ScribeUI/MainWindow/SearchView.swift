import SwiftUI
import ScribeCore

/// Full-text search across meetings via FTS5
public struct SearchView: View {
    @Binding var selectedMeetingId: UUID?
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false

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
            if isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if results.isEmpty {
                ContentUnavailableView(
                    "Search Meetings",
                    systemImage: "magnifyingglass",
                    description: Text("Search across transcripts, notes, and summaries.")
                )
            } else {
                List {
                    ForEach(results) { result in
                        SearchResultRow(result: result)
                            .onTapGesture {
                                selectedMeetingId = result.meetingId
                            }
                    }
                }
            }
        }
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }

        isSearching = true
        Task {
            let searchResults = (try? await SearchIndex.shared.search(query: q)) ?? []
            await MainActor.run {
                results = searchResults
                isSearching = false
            }
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
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
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
        }
    }
}
