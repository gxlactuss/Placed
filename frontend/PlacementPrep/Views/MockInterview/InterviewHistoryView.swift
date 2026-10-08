import SwiftUI

struct InterviewHistoryView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var interviews: [InterviewSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selected: InterviewSummary?

    // Pagination. `nextOffset` counts raw rows the server has handed us (before
    // de-duplication), so a new interview landing at the top mid-scroll only
    // causes an overlap — which `append` drops — never a gap.
    private static let pageSize = 30
    @State private var nextOffset = 0
    @State private var hasMore = true
    @State private var isLoadingMore = false
    @State private var loadMoreFailed = false
    /// Bumped on every reset so a page request still in flight from before the
    /// reset can't append stale rows to the fresh list.
    @State private var generation = 0

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loading
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if interviews.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color.ppText)
            .ppScreenBackground()
            .navigationTitle("Saved interviews")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.font(.ppBodyMedium)
                }
            }
            .navigationDestination(item: $selected) { summary in
                InterviewTranscriptView(summaryID: summary.id)
            }
        }
        .task { await load() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: PPSpacing.md) {
                ForEach(interviews) { interview in
                    Button { selected = interview } label: { row(interview) }
                        .buttonStyle(.ppPressable)
                        .onAppear {
                            if interview.id == interviews.last?.id {
                                Task { await loadMore() }
                            }
                        }
                }

                if isLoadingMore {
                    loadingMoreRow
                } else if loadMoreFailed {
                    loadMoreFailedRow
                }
            }
            .padding(PPSpacing.xl)
            .ppContentColumn()
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ interview: InterviewSummary) -> some View {
        PPCard {
            HStack(alignment: .top, spacing: PPSpacing.lg) {
                PPIconTile(
                    systemName: interview.round?.icon ?? "text.bubble",
                    tint: .ppAccent400
                )

                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    Text(interview.round?.title ?? "Mock interview")
                        .font(.ppHeadline)
                    Text(interview.roleLine)
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                    HStack(spacing: PPSpacing.sm) {
                        Text(interview.startedAt.formatted(date: .abbreviated, time: .shortened))
                        Text("·").accessibilityHidden(true)
                        Text("^[\(interview.answerCount) answer](inflect: true)")
                    }
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
                }

                Spacer(minLength: PPSpacing.sm)

                VStack(alignment: .trailing, spacing: PPSpacing.xs) {
                    if let rating = interview.rating {
                        Text("\(rating)/10")
                            .font(.ppBodyMedium)
                            .foregroundStyle(tint(for: rating))
                            .accessibilityLabel("Rated \(rating) out of 10")
                    }
                    if interview.status == .abandoned {
                        PPBadge("Ended early", tone: .neutral)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var loadingMoreRow: some View {
        HStack(spacing: PPSpacing.sm) {
            ProgressView().tint(Color.ppAccent400)
            Text("Loading more…")
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PPSpacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading more interviews")
    }

    private var loadMoreFailedRow: some View {
        Button {
            Task { await loadMore() }
        } label: {
            HStack(spacing: PPSpacing.sm) {
                Image(systemName: "arrow.clockwise")
                Text("Couldn't load more. Tap to retry")
            }
            .font(.ppCaption)
            .foregroundStyle(Color.ppMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, PPSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Couldn't load more interviews")
        .accessibilityHint("Double-tap to try again")
        .accessibilityAddTraits(.isButton)
    }

    private func tint(for rating: Int) -> Color {
        switch rating {
        case 8...: .ppEasy
        case 5..<8: .ppAccent400
        default: .ppHard
        }
    }

    private var loading: some View {
        VStack(spacing: PPSpacing.md) {
            ProgressView().tint(Color.ppAccent400)
            Text("Loading your interviews…")
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
        }
    }

    private var emptyState: some View {
        VStack(spacing: PPSpacing.md) {
            PPIconTile(systemName: "text.bubble", tint: .ppMuted)
            Text("No interviews yet").font(.ppHeadline)
            Text("Finish a round and it'll be saved here, with its transcript and mark.")
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PPSpacing.xxl)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: PPSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.ppAccent400)
                .accessibilityHidden(true)
            Text(message)
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { Task { await load() } }
                .buttonStyle(PPButtonStyle(variant: .secondary, expands: false))
        }
        .padding(PPSpacing.xxl)
    }

    /// Resets to page one. Drives the full-screen loading / error / empty states.
    private func load() async {
        generation += 1
        let token = generation
        isLoading = true
        errorMessage = nil
        isLoadingMore = false
        loadMoreFailed = false
        do {
            let page = try await fetchPage(offset: 0)
            guard token == generation else { return }
            interviews = []
            append(page)
            nextOffset = page.count
            hasMore = page.count >= Self.pageSize
        } catch {
            guard token == generation else { return }
            interviews = []
            errorMessage = "Couldn't load your saved interviews. Check your connection and try again."
        }
        isLoading = false
    }

    /// Fetches the next page. On failure the loaded rows stay and an inline
    /// retry row is shown instead of the full-screen error.
    private func loadMore() async {
        // Runs on the main actor, so this check-then-set can't interleave.
        guard hasMore, !isLoading, !isLoadingMore else { return }
        let token = generation
        isLoadingMore = true
        loadMoreFailed = false
        do {
            let page = try await fetchPage(offset: nextOffset)
            guard token == generation else { return }
            let added = append(page)
            nextOffset += page.count
            hasMore = page.count >= Self.pageSize
            isLoadingMore = false
            // A page made entirely of rows we already have leaves the last row
            // unchanged, so its onAppear won't fire again; keep going ourselves.
            if added == 0 && hasMore {
                await loadMore()
            }
        } catch {
            guard token == generation else { return }
            loadMoreFailed = true
            isLoadingMore = false
        }
    }

    private func fetchPage(offset: Int) async throws -> [InterviewSummary] {
        try await NetworkManager.shared.request(
            path: "/api/interview?limit=\(Self.pageSize)&offset=\(offset)"
        )
    }

    /// Appends rows not already present (by id); returns how many were added.
    @discardableResult
    private func append(_ page: [InterviewSummary]) -> Int {
        var seen = Set(interviews.map(\.id))
        let fresh = page.filter { seen.insert($0.id).inserted }
        interviews.append(contentsOf: fresh)
        return fresh.count
    }
}
