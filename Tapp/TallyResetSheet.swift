//
//  TallyResetSheet.swift
//  Tapp
//
//  Owner-only sheet: off, reset now, or recurring daily / monthly / yearly resets.
//

import SwiftUI

struct TallyResetSheet: View {
    let tally: Tally
    let store: TallyStore

    @Environment(\.dismiss) private var dismiss

    @State private var selection: ResetOption
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(tally: Tally, store: TallyStore) {
        self.tally = tally
        self.store = store
        _selection = State(initialValue: ResetOption.from(tally: tally))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ResetOption.allCases) { option in
                        Button {
                            selection = option
                        } label: {
                            HStack {
                                Text(option.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selection == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Scheduled resets run the next time anyone updates this tally after the due time. Times use your device’s local timezone.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Resets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                switch selection {
                case .off:
                    try await store.clearResetSchedule(tally)
                case .resetNow:
                    try await store.resetCountNow(tally)
                case .daily:
                    try await store.setRecurringReset(tally, schedule: TallyResetSchedule.daily)
                case .monthly:
                    try await store.setRecurringReset(tally, schedule: TallyResetSchedule.monthly)
                case .yearly:
                    try await store.setRecurringReset(tally, schedule: TallyResetSchedule.yearly)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

private enum ResetOption: String, CaseIterable, Identifiable {
    case off
    case resetNow
    case daily
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .resetNow: return "Reset now"
        case .daily: return "Reset every day"
        case .monthly: return "Reset every month"
        case .yearly: return "Reset every year"
        }
    }

    static func from(tally: Tally) -> ResetOption {
        switch tally.effectiveResetSchedule {
        case TallyResetSchedule.daily: return .daily
        case TallyResetSchedule.monthly: return .monthly
        case TallyResetSchedule.yearly: return .yearly
        default: return .off
        }
    }
}
