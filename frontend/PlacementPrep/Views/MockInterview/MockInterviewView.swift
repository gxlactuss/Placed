import SwiftUI

struct MockInterviewView: View {
    @StateObject private var viewModel = MockInterviewViewModel()
    @State private var targetRole: String = "Software Engineer Intern"

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ScrollView {
                    ForEach(viewModel.transcript) { turn in
                        HStack {
                            if turn.speaker == "user" { Spacer() }
                            Text(turn.text)
                                .padding(10)
                                .background(turn.speaker == "user" ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            if turn.speaker == "ai" { Spacer() }
                        }
                        .padding(.horizontal)
                    }
                }

                if viewModel.uiState == .listeningForAnswer {
                    Text(viewModel.liveTranscription)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                controlButton
                    .padding(.bottom)
            }
            .navigationTitle("Mock Interview")
            .task {
                if viewModel.transcript.isEmpty {
                    await viewModel.startInterview(targetRole: targetRole)
                }
            }
        }
    }

    @ViewBuilder
    private var controlButton: some View {
        switch viewModel.uiState {
        case .idle:
            Button("Speak Your Answer") { viewModel.beginListening() }
                .buttonStyle(.borderedProminent)
        case .listeningForAnswer:
            Button("Done Speaking") { Task { await viewModel.finishAnsweringAndSubmit() } }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        case .aiSpeaking, .submittingAnswer:
            ProgressView()
        case .finished:
            Text("Interview complete. Great job!")
                .font(.headline)
        case .error(let message):
            Text(message)
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    MockInterviewView()
}
