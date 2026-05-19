//
//  AwaitingLinkView.swift
//  Tapp
//
//  Shown while we wait for the user to open the sign-in link from their email.
//  On a free Apple Personal Team, Universal Links aren't available — use the
//  paste field below instead (long-press the link in Mail → Copy Link).
//

import SwiftUI

struct AwaitingLinkView: View {
    @Environment(AuthStore.self) private var authStore

    let email: String
    let isSignup: Bool

    @State private var pastedLink: String = ""
    @State private var isSubmitting: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .padding(.top, 40)

                Text("Check your email")
                    .font(.title.bold())

                Text("We sent a \(isSignup ? "sign-up" : "sign-in") link to")
                    .foregroundStyle(.secondary)
                Text(email)
                    .font(.headline)

                Text("Open the email on this device, then paste the link below to finish \(isSignup ? "creating your account" : "signing in").")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign-in link")
                        .font(.headline)
                    TextField("Paste link from email", text: $pastedLink, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(3...6)
                    Text("In Mail: long-press the button or link → Copy Link, then paste here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Button(action: submitPastedLink) {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Continue")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(!pastedLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
                        ? Color.accentColor : Color.gray)
                    .cornerRadius(10)
                }
                .disabled(pastedLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                .padding(.horizontal, 24)

                if let err = authStore.lastLinkError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button("Cancel") {
                    authStore.cancelPendingLink()
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
    }

    private func submitPastedLink() {
        isSubmitting = true
        Task {
            await authStore.completeSignIn(withPastedLink: pastedLink)
            isSubmitting = false
        }
    }
}
