//
//  PermissionsSheet.swift
//  Tapp
//
//  3-column table (Username / View / Edit) over the current user's friends.
//  Used both by the Add Tally sheet and by the per-tally "Friends and Permissions"
//  sheet on Full Screen Tally.
//

import SwiftUI

/// Value-typed state for the table. `permissions[uid] == "edit" | "view"`.
struct PermissionsTable: Equatable {
    /// Ordered list of friend uids, sorted by displayed name. Drives row order.
    var friendUids: [String]
    var permissions: [String: String]

    func role(for uid: String) -> TallyRole {
        switch permissions[uid] {
        case "edit": return .edit
        case "view": return .view
        default: return .none
        }
    }

    mutating func setRole(_ role: TallyRole, for uid: String) {
        switch role {
        case .edit: permissions[uid] = "edit"
        case .view: permissions[uid] = "view"
        case .none, .owner: permissions.removeValue(forKey: uid)
        }
    }
}

struct PermissionsTableEditor: View {
    @Binding var table: PermissionsTable
    let directory: UserDirectory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Username")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("View")
                    .frame(width: 56)
                Text("Edit")
                    .frame(width: 56)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if table.friendUids.isEmpty {
                Text("Add friends in Settings to share tallies with them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(table.friendUids, id: \.self) { uid in
                            row(for: uid)
                            Divider()
                        }
                    }
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await directory.prefetchUids(table.friendUids)
        }
    }

    private func row(for uid: String) -> some View {
        let summary = directory.cached(uid: uid)
        return HStack {
            HStack(spacing: 8) {
                AvatarBadge(summary: summary, size: 24)
                Text(summary?.displayUsername ?? "@…")
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: viewBinding(for: uid))
                .labelsHidden()
                .frame(width: 56)

            Toggle("", isOn: editBinding(for: uid))
                .labelsHidden()
                .frame(width: 56)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task {
            await directory.fetch(uid: uid)
        }
    }

    private func viewBinding(for uid: String) -> Binding<Bool> {
        Binding(
            get: { table.role(for: uid) != .none },
            set: { isOn in
                if isOn {
                    if table.role(for: uid) == .none {
                        table.setRole(.view, for: uid)
                    }
                } else {
                    table.setRole(.none, for: uid)
                }
            }
        )
    }

    private func editBinding(for uid: String) -> Binding<Bool> {
        Binding(
            get: { table.role(for: uid) == .edit },
            set: { isOn in
                if isOn {
                    table.setRole(.edit, for: uid)
                } else {
                    if table.role(for: uid) == .edit {
                        table.setRole(.view, for: uid)
                    }
                }
            }
        )
    }
}

/// Round monogram avatar used by the permissions table, owner badge on rows, and
/// the friends list in Settings.
struct AvatarBadge: View {
    let summary: UserSummary?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            Text(summary?.avatarInitial ?? "?")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var backgroundColor: Color {
        if let uid = summary?.uid, let hex = summary?.avatarColorHex, !hex.isEmpty {
            return AvatarColorAssignment.color(for: uid, hex: hex)
        }
        guard let uid = summary?.uid else { return Color.gray }
        return AvatarColorAssignment.color(for: uid)
    }
}

