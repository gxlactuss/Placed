import SwiftUI

struct CompanyListView: View {
    @StateObject private var viewModel = CompanyDSAViewModel()

    var body: some View {
        NavigationStack {
            List(viewModel.companies) { company in
                NavigationLink(company.name) {
                    CompanyQuestionsView(slug: company.slug, companyName: company.name)
                }
            }
            .navigationTitle("Companies")
            .task { await viewModel.loadCompanies() }
            .overlay {
                if viewModel.isLoading { ProgressView() }
            }
        }
    }
}

private struct CompanyQuestionsView: View {
    let slug: String
    let companyName: String
    @StateObject private var viewModel = CompanyDSAViewModel()

    var body: some View {
        List(viewModel.selectedCompanyQuestions?.questions ?? []) { question in
            VStack(alignment: .leading) {
                Text(question.title).font(.body)
                Text(question.difficulty).font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(companyName)
        .task { await viewModel.loadQuestions(for: slug) }
    }
}

#Preview {
    CompanyListView()
}
