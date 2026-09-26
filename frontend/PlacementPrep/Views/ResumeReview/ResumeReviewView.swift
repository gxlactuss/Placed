import SwiftUI

@MainActor
@Observable
final class ResumeReviewer {

    enum Phase: Equatable {
        case idle
        case reading
        case reviewing
        case done(SavedResumeReview)
        case failed(String)

        var isBusy: Bool { self == .reading || self == .reviewing }
    }

    private(set) var phase: Phase = .idle
    private(set) var resumeText: String?

    func restore(_ saved: SavedResumeReview?) {
        guard phase == .idle, let saved else { return }
        phase = .done(saved)
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }

    func reset() {
        phase = .idle
        resumeText = nil
    }

    func review(_ url: URL, targetRole: String, store: ResumeReviewStore) async {
        phase = .reading
        resumeText = nil
        do {
            let document = try await ResumeTextExtractor.extract(from: url)
            await review(document: document, fileName: url.lastPathComponent, targetRole: targetRole, store: store)
        } catch let error as ResumeTextExtractor.ExtractionError {
            phase = .failed(error.localizedDescription)
        } catch {
            phase = .failed(NetworkError.userMessage(for: error))
        }
    }

    func review(
        document: ResumeTextExtractor.Document,
        fileName: String,
        targetRole: String,
        store: ResumeReviewStore
    ) async {
        do {
            let redacted = ResumeParser.redactForReview(document.text)
            guard redacted.count >= 50 else { throw ResumeTextExtractor.ExtractionError.noTextFound }
            resumeText = document.text

            let hash = ResumeReviewStore.hash(text: redacted, role: targetRole)
            if let cached = store.cached(hash: hash) {
                store.record(cached)
                phase = .done(cached)
                return
            }

            phase = .reviewing
            let review: ResumeReview = try await NetworkManager.shared.request(
                path: "/api/resume/review",
                method: .post,
                body: ResumeReviewRequest(
                    targetRole: targetRole,
                    resumeText: redacted,
                    device: ResumeParser.deviceSignals(for: document)
                )
            )
            let saved = SavedResumeReview(
                id: UUID(),
                textHash: hash,
                fileName: fileName,
                targetRole: targetRole,
                reviewedAt: .now,
                review: review
            )
            store.record(saved)
            phase = .done(saved)
        } catch let error as ResumeTextExtractor.ExtractionError {
            phase = .failed(error.localizedDescription)
        } catch {
            phase = .failed(NetworkError.userMessage(for: error))
        }
    }
}

struct ResumeReviewView: View {

    @Environment(ResumeReviewStore.self) private var store
    @Environment(InterviewSetupStore.self) private var setupStore
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var reviewer = ResumeReviewer()
    @State private var interviewImport: ResumeImporter?
    @State private var showFileImporter = false

    private var targetRole: String {
        let role = auth.currentUser?.targetRole?.trimmingCharacters(in: .whitespaces) ?? ""
        return role.isEmpty ? SampleData.targetRole : role
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                content
                    .padding(PPSpacing.xl)
                    .ppContentColumn()
            }
            .scrollIndicators(.hidden)

            if case .done = reviewer.phase {
                footer
            }
        }
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .onAppear { reviewer.restore(store.latest) }
        .animation(PPMotion.snappy, value: reviewer.phase)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .png, .jpeg, .heic],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                interviewImport = nil
                Task { await reviewer.review(url, targetRole: targetRole, store: store) }
            case .failure(let error):
                reviewer.fail(error.localizedDescription)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Resume review").font(.ppTitle)
            Spacer()
            Button("Done") { dismiss() }
                .font(.ppBodyMedium)
                .foregroundStyle(Color.ppAccent400)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.top, PPSpacing.xl)
        .padding(.bottom, PPSpacing.md)
        .ppContentColumn()
    }

    @ViewBuilder
    private var content: some View {
        switch reviewer.phase {
        case .idle:
            uploadCard
        case .reading:
            busyCard("Reading your resume on this device…")
        case .reviewing:
            busyCard("Reviewing it for \(targetRole)…")
        case .done(let saved):
            ResumeReviewResultView(saved: saved, previousScore: store.previousScore(before: saved))
        case .failed(let message):
            failureCard(message)
        }
    }

    private var uploadCard: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPCard {
                VStack(alignment: .leading, spacing: PPSpacing.lg) {
                    HStack(alignment: .top, spacing: PPSpacing.lg) {
                        PPIconTile(systemName: "doc.text.magnifyingglass", tint: .ppAccent400)
                        VStack(alignment: .leading, spacing: PPSpacing.xs) {
                            Text("Get your resume scored").font(.ppHeadline)
                            Text("A score out of 100 for \(targetRole), the checks screening software runs, and exactly what to fix first.")
                                .font(.ppCaption)
                                .foregroundStyle(Color.ppMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    Button("Choose PDF or image") { showFileImporter = true }
                        .buttonStyle(.ppPrimary)
                }
            }
            privacyNote
        }
    }

    private var privacyNote: some View {
        Text("Read on your phone. Your email, phone number and links are removed before anything is sent, and we try to remove your name too. Nothing is stored on our servers.")
            .font(.ppMicro)
            .foregroundStyle(Color.ppMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func busyCard(_ label: String) -> some View {
        PPCard {
            HStack(spacing: PPSpacing.lg) {
                ProgressView().tint(Color.ppAccent400)
                Text(label)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                Spacer(minLength: 0)
            }
        }
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPCard {
                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    HStack(alignment: .top, spacing: PPSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.ppAccent400)
                        Text(message)
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    Button("Try another file") { showFileImporter = true }
                        .buttonStyle(.ppInlineLink)
                }
            }
            privacyNote
        }
    }

    private var footer: some View {
        HStack(spacing: PPSpacing.md) {
            Button("Review another version") { showFileImporter = true }
                .buttonStyle(.ppSecondary)

            if let text = reviewer.resumeText {
                Button {
                    useForInterviews(text)
                } label: {
                    Text(interviewButtonTitle)
                }
                .buttonStyle(.ppPrimary)
                .disabled(interviewButtonDisabled)
            }
        }
        .padding(PPSpacing.xl)
        .ppContentColumn()
        .background(.ultraThinMaterial)
        .background(Color.ppGround.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ppBorder).frame(height: 1)
        }
    }

    private var interviewButtonTitle: String {
        guard let importer = interviewImport else { return "Use for mock interviews" }
        switch importer.phase {
        case .idle, .reading, .summarising: return "Saving…"
        case .failed: return "Try again"
        case .done, .noProjects: return importer.hasResume ? "Saved for interviews" : "Nothing to use"
        }
    }

    private var interviewButtonDisabled: Bool {
        guard let importer = interviewImport else { return false }
        if case .failed = importer.phase { return false }
        return true
    }

    private func useForInterviews(_ text: String) {
        let importer = ResumeImporter()
        interviewImport = importer
        Task {
            await importer.process(text: text, targetRole: targetRole)
            if let setup = importer.setup {
                setupStore.save(setup)
                PPHaptics.success()
            }
        }
    }
}

#Preview {
    ResumeReviewView()
        .environment(ResumeReviewStore.preview())
        .environment(InterviewSetupStore.preview())
        .environmentObject(AuthViewModel())
}
