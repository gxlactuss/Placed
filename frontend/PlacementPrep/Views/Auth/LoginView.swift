import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                SecureField("Password", text: $password)

                Button("Log In") {
                    Task { await authViewModel.login(email: email, password: password) }
                }

                if let error = authViewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }

                // TODO: add a signup flow / NavigationLink to a SignupView using
                // authViewModel.signup(email:password:fullName:targetRole:)
            }
            .navigationTitle("Placement Prep")
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
