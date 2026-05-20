//
//  ColorPickerSheet.swift
//  Tapp
//
//  Modal sheet with the 12-swatch palette + Default. Tapping a swatch writes to
//  UserDefaults via LocalTallyColors and notifies the parent so it can re-tint.
//

import SwiftUI

struct ColorPickerSheet: View {
    let tallyId: String
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selection: Int? // nil == Default

    init(tallyId: String, onChange: @escaping () -> Void) {
        self.tallyId = tallyId
        self.onChange = onChange
        _selection = State(initialValue: LocalTallyColors.storedSwatchIndex(for: tallyId))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick a color")
                    .font(.title2.bold())
                    .padding(.top, 8)

                Text("Only you see this color, only on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)
                LazyVGrid(columns: columns, spacing: 14) {
                    swatch(index: nil, label: "Default")
                    ForEach(Array(TallyColorPalette.swatches.enumerated()), id: \.offset) { idx, _ in
                        swatch(index: idx, label: nil)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func swatch(index: Int?, label: String?) -> some View {
        let isSelected = selection == index
        Button {
            selection = index
            LocalTallyColors.setSwatchIndex(index, for: tallyId)
            onChange()
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(LocalTallyColors.previewSwatchColor(for: index))
                    .frame(width: 48, height: 48)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.primary, lineWidth: isSelected ? 3 : 0)
                    )
                if let label {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
