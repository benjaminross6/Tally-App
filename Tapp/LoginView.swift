//
//  LoginView.swift
//  Tapp
//
//  Returning-user screen: username and password.
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isSubmitting: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Welcome back")
                        .font(.system(size: 32, weight: .bold))
                    Text("Sign in with your username and password.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                .padding(.horizontal, 32)

                VStack(spacing: 16) {
                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: username) { _, newValue in
                            username = UsernameClaim.sanitize(newValue)
                        }

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: handleSignIn) {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Log In")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isFormValid && !isSubmitting ? Color.accentColor : Color.gray)
                        .cornerRadius(10)
                    }
                    .disabled(!isFormValid || isSubmitting)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var isFormValid: Bool {
        UsernameClaim.isWellFormed(username) && password.count >= 6
    }

    private func handleSignIn() {
        errorMessage = nil
        isSubmitting = true
        Task {
            do {
                try await authStore.signIn(username: username, password: password)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthStore())
}
