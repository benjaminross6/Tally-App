//
//  SignupView.swift
//  Tapp
//
//  Created by Ben Ross on 11/17/25.
//

import SwiftUI

struct SignupView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var name: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var errorMessage: String?
    @State private var isSubmitting: Bool = false
    @State private var showingLogin: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Tapp")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Join the Tapp Party Today!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 60)
                .padding(.bottom, 24)

                VStack(spacing: 16) {
                    LabeledField(label: "Name") {
                        TextField("Your name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }

                    LabeledField(label: "Username") {
                        TextField("3-20 chars, a-z, 0-9, _", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: username) { _, newValue in
                                username = UsernameClaim.sanitize(newValue)
                            }
                    }

                    LabeledField(label: "Password") {
                        SecureField("At least 6 characters", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    LabeledField(label: "Confirm password") {
                        SecureField("Repeat password", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: handleSignup) {
                        Group {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Text("Create Account")
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
                    .padding(.top, 8)

                    Button("Already have an account? Log in") {
                        showingLogin = true
                    }
                    .font(.footnote)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingLogin) {
                LoginView()
                    .environment(authStore)
            }
        }
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && UsernameClaim.isWellFormed(username)
            && password.count >= 6
            && password == confirmPassword
    }

    private func handleSignup() {
        errorMessage = nil
        isSubmitting = true
        Task {
            do {
                try await authStore.signUp(name: name, username: username, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

private struct LabeledField<Field: View>: View {
    let label: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.headline)
                .foregroundStyle(.primary)
            field
        }
    }
}

#Preview {
    SignupView()
        .environment(AuthStore())
}
