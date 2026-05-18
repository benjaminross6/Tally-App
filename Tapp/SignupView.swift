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
    @State private var email: String = ""
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isSubmitting: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // App branding
                VStack(spacing: 8) {
                    Text("Tapp")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text("Join the Tapp Party Today!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 60)
                .padding(.bottom, 40)
                
                // Signup form
                VStack(spacing: 20) {
                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        TextField("Enter your name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                    
                    // Email field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    
                    // Error message
                    if showingError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Submit button
                    Button(action: handleSignup) {
                        Group {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Text("Sign Up")
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
                }
                .padding(.horizontal, 32)
                
                Spacer()
            }
            .navigationBarHidden(true)
        }
    }
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidEmail(email)
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func handleSignup() {
        showingError = false
        errorMessage = ""

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        if trimmedName.isEmpty {
            errorMessage = "Please enter your name"
            showingError = true
            return
        }

        if trimmedEmail.isEmpty {
            errorMessage = "Please enter your email"
            showingError = true
            return
        }

        if !isValidEmail(trimmedEmail) {
            errorMessage = "Please enter a valid email address"
            showingError = true
            return
        }

        isSubmitting = true
        Task {
            do {
                try await authStore.signUp(name: trimmedName, email: trimmedEmail)
                // RootView observes AuthStore.state and will navigate automatically.
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            isSubmitting = false
        }
    }
}

#Preview {
    SignupView()
        .environment(AuthStore())
}

