import Foundation

@MainActor
final class CompanyDSAViewModel: ObservableObject {
    @Published var companies: [CompanySummary] = []
    @Published var selectedCompanyQuestions: CompanyQuestionList?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let network = NetworkManager.shared

    func loadCompanies() async {
        isLoading = true
        defer { isLoading = false }
        do {
            companies = try await network.request(path: "/api/companies")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadQuestions(for slug: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            selectedCompanyQuestions = try await network.request(path: "/api/companies/\(slug)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
