import SwiftUI

/// Every interview the student has recorded, newest first.
///
/// Nothing here is "saved" by an explicit action — every round has always been
/// written to the server as it happened. What was missing was any way back to
/// them, so this is the door rather than a new store. Rounds where nothing was
/// answered are filtered out server-side; opening a round writes a session
/// immediately, so without that the list would fill with interviews that never
/// took place.
struct InterviewHistoryView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var interviews: [InterviewSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selected: InterviewSummary?

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
                }
            }
            .padding(PPSpacing.xl)
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
                    Text(interview.targetRole)
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                    HStack(spacing: PPSpacing.sm) {
                        Text(interview.startedAt.formatted(date: .abbreviated, time: .shortened))
                        Text("·")
                        Text("^[\(interview.answerCount) answer](inflect: true)")
                    }
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
                }

                Spacer(minLength: PPSpacing.sm)

                VStack(alignment: .trailing, spacing: PPSpacing.xs) {
                    // A mark only exists if the debrief was generated, which a
                    // student can skip by leaving before the results screen.
                    if let rating = interview.rating {
                        Text("\(rating)/10")
                            .font(.ppBodyMedium)
                            .foregroundStyle(tint(for: rating))
                    }
                    if interview.status == .abandoned {
                        PPBadge("Ended early", tone: .neutral)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Same thresholds as the results ring, so a colour means one thing app-wide.
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

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            interviews = try await NetworkManager.shared.request(path: "/api/interview")
        } catch {
            errorMessage = "Couldn't load your saved interviews. Check your connection and try again."
        }
    }
}
