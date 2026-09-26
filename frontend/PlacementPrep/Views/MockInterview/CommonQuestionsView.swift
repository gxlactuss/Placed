import SwiftUI

struct CommonQuestion: Decodable, Identifiable, Hashable {
    let id: String
    let question: String
    let why: String
    let tips: [String]
    let sample: String
}

struct CommonQuestionSection: Decodable, Identifiable {
    let id: String
    let title: String
    let questions: [CommonQuestion]

    /// The bundled HR questions, loaded once.
    static let all: [CommonQuestionSection] = {
        struct File: Decodable { let sections: [CommonQuestionSection] }
        guard
            let url = Bundle.main.url(forResource: "CommonQuestions", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [] }
        return file.sections
    }()
}

/// Questions nearly every HR round asks, with why they're asked and a sample fresher's answer.
struct CommonQuestionsView: View {

    var onPractise: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<CommonQuestion.ID> = []

    private let sections = CommonQuestionSection.all

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PPSpacing.md) {
                    Text("Nearly every HR round asks some of these. Read why each is asked, then make the sample answer your own.")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(sections) { section in
                        PPSectionHeader(section.title)
                            .padding(.top, PPSpacing.md)
                        ForEach(section.questions) { question in
                            card(question)
                        }
                    }

                    if let onPractise {
                        Button {
                            dismiss()
                            onPractise()
                        } label: {
                            Label("Practise in an HR round", systemImage: "mic")
                        }
                        .buttonStyle(.ppPrimary)
                        .padding(.top, PPSpacing.lg)
                    }
                }
                .padding(PPSpacing.xl)
                .ppContentColumn()
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Common HR questions").font(.ppTitle)
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

    private func card(_ question: CommonQuestion) -> some View {
        let isOpen = expanded.contains(question.id)
        return PPCard {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                Button {
                    withAnimation(PPMotion.settle) {
                        if isOpen { expanded.remove(question.id) } else { expanded.insert(question.id) }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: PPSpacing.sm) {
                        Text(question.question)
                            .font(.ppBodyMedium)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down")
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(isOpen ? "Hides the answer" : "Shows how to answer")

                if isOpen {
                    detail(question)
                        .transition(.opacity)
                }
            }
        }
    }

    private func detail(_ question: CommonQuestion) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            block("Why they ask") {
                Text(question.why)
            }
            block("How to answer") {
                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    ForEach(question.tips, id: \.self) { tip in
                        HStack(alignment: .firstTextBaseline, spacing: PPSpacing.sm) {
                            Text("•").foregroundStyle(Color.ppAccent400)
                            Text(tip)
                        }
                    }
                }
            }
            block("Sample answer") {
                Text(question.sample)
                    .padding(PPSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.ppGround, in: .rect(cornerRadius: PPRadius.md))
                    .textSelection(.enabled)
            }
        }
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.xs) {
            Text(title).ppSectionLabelStyle()
            content()
                .font(.ppCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    CommonQuestionsView(onPractise: {})
}
