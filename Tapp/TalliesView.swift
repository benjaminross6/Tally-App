//
//  TalliesView.swift
//  Tapp
//
//  Home page. Scrollable list of tallies under a gear + add + sort button
//  triplet. Long-press a row to open the Full Screen Tally. Tap a row to
//  increment (or shake, when view-only).
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct TalliesView: View {
    @Environment(AuthStore.self) private var authStore
    let profile: UserProfile

    @State private var store: TallyStore
    @State private var friendsStore: FriendsStore
    @State private var directory: UserDirectory

    @State private var showingAddTally: Bool = false
    @State private var openTally: Tally?
    @State private var openSettings: Bool = false
    @State private var errorMessage: String?

    @State private var rowFrames: [String: CGRect] = [:]
    @State private var draggingTallyId: String?
    @State private var dragDropIndex: Int?
    @State private var dragGrabOffsetY: CGFloat = 0
    @State private var dragRowFrame: CGRect = .zero
    @State private var dragFingerY: CGFloat = 0
    /// Row frames captured when a drag begins, used for pinned-zone clamping.
    @State private var dragZoneFrames: [String: CGRect] = [:]
    /// Set after a short hold on the handle; drag mode starts only once the finger moves.
    @State private var dragArmedTallyId: String?
    /// Finger Y when drag was armed; movement is measured from here (not touch-down).
    @State private var dragArmBaselineY: CGFloat?
    @State private var didLogWaitingForMove = false
    @State private var dragHandleTouchStart: Date?
    @State private var dragHandleActiveId: String?
    @State private var didLogHoldWaiting = false
    @State private var dragStartIndex: Int?
    @State private var showDragOverlay = false

    private let dragLog = DragDebugLog.shared
    private let dragHoldDuration: TimeInterval = 0.15

    private var dragDropAnimation: Animation {
        .spring(response: 0.32, dampingFraction: 0.82)
    }

    /// List stays in place while dragging; only the floating copy moves until drop.
    private var listTallies: [Tally] {
        store.tallies
    }

    init(profile: UserProfile) {
        self.profile = profile
        let uid = profile.id ?? Auth.auth().currentUser?.uid ?? ""
        _store = State(initialValue: TallyStore(userId: uid))
        _friendsStore = State(initialValue: FriendsStore(userId: uid))
        _directory = State(initialValue: UserDirectory())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 16) {
                    headerButtons
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    if store.isLoading {
                        Spacer()
                        ProgressView()
                        Spacer()
                    } else if store.tallies.isEmpty {
                        Spacer()
                        Text("No tallies yet. Tap + to make one.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    } else {
                        tallyList
                    }
                }

            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $openSettings) {
                SettingsView(
                    profile: profile,
                    friendsStore: friendsStore,
                    directory: directory
                )
            }
        }
        .fullScreenCover(item: $openTally) { tally in
            FullScreenTallyView(
                initialTally: tally,
                store: store,
                friendsStore: friendsStore,
                directory: directory,
                onDismiss: { openTally = nil }
            )
        }
        .sheet(isPresented: $showingAddTally) {
            AddTallySheet(store: store, friendsStore: friendsStore, directory: directory)
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await prewarmDirectory()
        }
        .onDisappear {
            if TappFeatures.manualReorderEnabled {
                endDrag()
            }
        }
    }

    // MARK: - Header

    private var headerButtons: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Button {
                    openSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Settings")
            }

            HStack(spacing: 12) {
                Button {
                    store.toggleSort()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(store.sortEnabled ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundStyle(store.sortEnabled ? Color.white : Color.primary)
                        .clipShape(Circle())
                }
                .accessibilityLabel(store.sortEnabled ? "Sort on" : "Sort off")

                Button {
                    showingAddTally = true
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .frame(height: 44)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel("Add tally")
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Tally list

    private var tallyList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(listTallies) { tally in
                    tallyListRow(tally: tally)
                        .id(tally.id)
                }
            }
            .coordinateSpace(name: "tallyListContent")
            .overlay(alignment: .topLeading) {
                if TappFeatures.manualReorderEnabled {
                    dragDropIndicator
                    dragFloatingOverlay
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollDisabled(
            TappFeatures.manualReorderEnabled
                && (dragHandleActiveId != nil || draggingTallyId != nil)
        )
        .onPreferenceChange(TallyRowFramePreferenceKey.self) { rowFrames = $0 }
        .overlay {
            if TappFeatures.manualReorderEnabled, draggingTallyId != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { endDrag() }
            }
        }
    }

    @ViewBuilder
    private var dragDropIndicator: some View {
        if showDragOverlay,
           draggingTallyId != nil,
           let dropIndex = dragDropIndex,
           let lineY = insertionLineY(for: dropIndex),
           dragRowFrame.width > 0 {
            Capsule()
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: dragRowFrame.width, height: 3)
                .position(x: dragRowFrame.midX, y: lineY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var dragFloatingOverlay: some View {
        if showDragOverlay,
           let draggingTallyId,
           let tally = store.tallies.first(where: { $0.id == draggingTallyId }),
           dragRowFrame.width > 0 {
            HStack(spacing: 8) {
                TallyDragHandleView(isPinned: store.isPinned(draggingTallyId))
                TallyBarView(
                    tally: tally,
                    currentUid: store.currentUid,
                    directory: directory
                )
            }
            .frame(width: dragRowFrame.width, height: dragRowFrame.height, alignment: .leading)
            .scaleEffect(1.04, anchor: .topLeading)
            .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
            .position(x: dragRowFrame.midX, y: clampedOverlayTopY + dragRowFrame.height / 2)
            .transaction { transaction in
                transaction.animation = nil
            }
            .allowsHitTesting(false)
            .zIndex(100)
        }
    }

    @ViewBuilder
    private func tallyListRow(tally: Tally) -> some View {
        let tallyId = tally.id ?? ""
        let isGhostRow = draggingTallyId == tallyId

        HStack(spacing: 8) {
            if !store.sortEnabled,
               TappFeatures.manualReorderEnabled || store.isPinned(tallyId) {
                let handle = TallyDragHandleView(
                    isPinned: store.isPinned(tallyId),
                    showsDragGrip: TappFeatures.manualReorderEnabled
                )
                .contentShape(Rectangle())
                .frame(minWidth: 36, minHeight: 44)

                if TappFeatures.manualReorderEnabled {
                    handle.highPriorityGesture(dragHandleGesture(for: tallyId))
                } else {
                    handle
                }
            }
            TallyRow(
                tally: tally,
                currentUid: store.currentUid,
                directory: directory,
                onTap: { handleRowTap(tally) },
                onLongPress: { handleRowLongPress(tally) }
            )
        }
        .opacity(isGhostRow ? 0 : 1)
        .allowsHitTesting(!isGhostRow)
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: TallyRowFramePreferenceKey.self,
                    value: [tallyId: geo.frame(in: .named("tallyListContent"))]
                )
            }
        }
    }

    private var clampedOverlayTopY: CGFloat {
        dragFingerY - dragGrabOffsetY
    }

    private func dragHandleGesture(for tallyId: String) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("tallyListContent"))
            .onChanged { drag in
                guard TappFeatures.manualReorderEnabled else { return }
                if dragHandleActiveId == nil {
                    dragHandleActiveId = tallyId
                    dragHandleTouchStart = Date()
                    didLogHoldWaiting = false
                    dragLog.pausesLivePanelUpdates = true
                    dragLog.log("touch began tally=\(tallyId)")
                }
                guard dragHandleActiveId == tallyId else { return }

                guard let touchStart = dragHandleTouchStart else { return }
                let held = Date().timeIntervalSince(touchStart) >= dragHoldDuration
                if !held {
                    if !didLogHoldWaiting {
                        didLogHoldWaiting = true
                        dragLog.log("holding… \(String(format: "%.2f", dragHoldDuration))s tally=\(tallyId)")
                    }
                    return
                }

                if dragArmedTallyId != tallyId && draggingTallyId != tallyId {
                    armDrag(tallyId: tallyId)
                }

                if draggingTallyId == nil {
                    if dragArmBaselineY == nil {
                        dragArmBaselineY = drag.location.y
                        dragLog.log("arm baseline Y=\(String(format: "%.1f", drag.location.y)) tally=\(tallyId)")
                        return
                    }
                    let deltaY = abs(drag.location.y - dragArmBaselineY!)
                    guard deltaY >= 8 else {
                        if !didLogWaitingForMove {
                            didLogWaitingForMove = true
                            dragLog.log("waiting for 8pt move Δy=\(String(format: "%.1f", deltaY)) tally=\(tallyId)")
                        }
                        return
                    }
                    didLogWaitingForMove = false
                    beginDrag(tallyId: tallyId, drag: drag)
                }

                guard draggingTallyId == tallyId else { return }
                dragFingerY = clampedFingerY(drag.location.y, draggedId: tallyId)
                let newIndex = clampedDropIndex(
                    dropIndex(forY: dragFingerY),
                    draggedId: tallyId
                )
                if newIndex != dragDropIndex {
                    dragLog.log("dropIndex \(dragDropIndex.map(String.init) ?? "nil") → \(newIndex) fingerY=\(String(format: "%.1f", dragFingerY)) (static list)")
                    dragDropIndex = newIndex
                }
            }
            .onEnded { drag in
                guard TappFeatures.manualReorderEnabled else { return }
                dragLog.log("touch ended tally=\(tallyId) armed=\(dragArmedTallyId ?? "nil") dragging=\(draggingTallyId ?? "nil")")
                dragHandleActiveId = nil
                dragHandleTouchStart = nil
                didLogHoldWaiting = false
                finishDrag(tallyId: tallyId, drag: drag)
            }
    }

    private func armDrag(tallyId: String) {
        guard dragArmedTallyId != tallyId else { return }
        dragArmedTallyId = tallyId
        dragArmBaselineY = nil
        didLogWaitingForMove = false
        dragZoneFrames = rowFrames
        let frame = rowFrames[tallyId] ?? .zero
        dragLog.log("ARMED tally=\(tallyId) frame=\(frame) framesCount=\(rowFrames.count)")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Always clears drag UI state. Commits reorder only when a drag actually started.
    private func finishDrag(tallyId: String, drag: DragGesture.Value) {
        let wasDragging = draggingTallyId == tallyId
        var destination: Int?

        if wasDragging {
            dragFingerY = clampedFingerY(drag.location.y, draggedId: tallyId)
            let filteredDest = clampedDropIndex(
                dropIndex(forY: dragFingerY),
                draggedId: tallyId
            )
            destination = store.fullListInsertionIndex(
                draggedId: tallyId,
                insertionWithoutDragged: filteredDest
            )
            dragLog.log("FINISH commit filtered=\(filteredDest) full=\(destination!) tally=\(tallyId)")
        } else {
            dragLog.log("FINISH cancel (never began drag) tally=\(tallyId)")
        }

        endDrag()

        guard wasDragging, let destination else { return }
        let currentIds = store.tallies.compactMap(\.id)
        guard store.reorderedIds(draggedId: tallyId, toIndex: destination) != currentIds else {
            dragLog.log("FINISH no-op (order unchanged) tally=\(tallyId)")
            return
        }
        withAnimation(dragDropAnimation) {
            store.moveTally(draggedId: tallyId, toIndex: destination)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dragLog.log("moveTally committed")
    }

    private func beginDrag(tallyId: String, drag: DragGesture.Value) {
        let frame = dragZoneFrames[tallyId] ?? rowFrames[tallyId] ?? .zero
        guard frame.width > 0, frame.height > 0 else {
            dragLog.log("BEGIN blocked — zero frame tally=\(tallyId)")
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        let startIndex = store.tallies.firstIndex(where: { $0.id == tallyId }) ?? 0
        withTransaction(transaction) {
            draggingTallyId = tallyId
            dragArmedTallyId = nil
            dragStartIndex = startIndex
            dragRowFrame = frame
            dragGrabOffsetY = drag.startLocation.y - frame.minY
            dragFingerY = clampedFingerY(drag.location.y, draggedId: tallyId)
            dragDropIndex = clampedDropIndex(
                dropIndex(forY: dragFingerY),
                draggedId: tallyId
            )
        }
        dragLog.log("BEGIN drag tally=\(tallyId) startIdx=\(startIndex) overlayY=\(String(format: "%.1f", clampedOverlayTopY)) (static list)")
        DispatchQueue.main.async {
            showDragOverlay = true
            dragLog.log("BEGIN overlay shown")
        }
    }

    private func endDrag() {
        if draggingTallyId != nil || dragArmedTallyId != nil {
            dragLog.log("END drag state cleared wasDragging=\(draggingTallyId ?? "nil") wasArmed=\(dragArmedTallyId ?? "nil")")
        }
        dragLog.pausesLivePanelUpdates = false
        dragLog.flushPendingToPanel()
        showDragOverlay = false
        draggingTallyId = nil
        dragArmedTallyId = nil
        dragArmBaselineY = nil
        dragDropIndex = nil
        dragStartIndex = nil
        dragGrabOffsetY = 0
        dragRowFrame = .zero
        dragFingerY = 0
        dragZoneFrames = [:]
        didLogWaitingForMove = false
        dragHandleActiveId = nil
        dragHandleTouchStart = nil
        didLogHoldWaiting = false
    }

    private func layoutFrames(for id: String) -> CGRect? {
        if draggingTallyId != nil, let frame = dragZoneFrames[id] {
            return frame
        }
        return rowFrames[id] ?? dragZoneFrames[id]
    }

    private func dropIndex(forY y: CGFloat) -> Int {
        var insertionIndex = 0
        for tally in store.tallies {
            guard let id = tally.id, let frame = layoutFrames(for: id) else { continue }
            if id == draggingTallyId {
                if y < frame.midY { return insertionIndex }
                continue
            }
            if y < frame.midY { return insertionIndex }
            insertionIndex += 1
        }
        return insertionIndex
    }

    private var insertionSlotCount: Int {
        guard draggingTallyId != nil else { return store.tallies.count }
        return max(0, store.tallies.count - 1)
    }

    /// Frame of the list row immediately above `tallyId` (may be the drag ghost placeholder).
    private func frameImmediatelyAbove(tallyId: String) -> CGRect? {
        var previous: CGRect?
        for tally in store.tallies {
            guard let id = tally.id, let frame = layoutFrames(for: id) else { continue }
            if id == tallyId { return previous }
            previous = frame
        }
        return previous
    }

    /// Vertical center of the gap before the filtered insertion index (list-content coordinates).
    private func insertionLineY(for filteredIndex: Int) -> CGFloat? {
        let spacing: CGFloat = 10
        let targetIds = store.tallies.compactMap(\.id).filter { $0 != draggingTallyId }
        guard !targetIds.isEmpty else { return nil }

        if filteredIndex >= targetIds.count {
            guard let lastId = targetIds.last, let frame = layoutFrames(for: lastId) else { return nil }
            return frame.maxY + spacing / 2
        }

        let targetId = targetIds[filteredIndex]
        guard let targetFrame = layoutFrames(for: targetId) else { return nil }

        if let above = frameImmediatelyAbove(tallyId: targetId) {
            return above.maxY + (targetFrame.minY - above.maxY) / 2
        }
        return targetFrame.minY - spacing / 2
    }

    private func clampedDropIndex(_ raw: Int, draggedId: String) -> Int {
        let pinnedCount = store.tallies.filter { store.isPinned($0.id ?? "") }.count
        if store.isPinned(draggedId) {
            let otherPinned = max(0, pinnedCount - 1)
            return min(max(0, raw), otherPinned)
        }
        return min(max(raw, pinnedCount), insertionSlotCount)
    }

    private func clampedFingerY(_ y: CGFloat, draggedId: String) -> CGFloat {
        guard let range = allowedFingerYRange(draggedId: draggedId) else { return y }
        let top = y - dragGrabOffsetY
        let clampedTop = min(max(top, range.minY), range.maxY - dragRowFrame.height)
        return clampedTop + dragGrabOffsetY
    }

    /// Vertical band the floating row may occupy (tallyListContent coordinates).
    private func allowedFingerYRange(draggedId: String) -> (minY: CGFloat, maxY: CGFloat)? {
        guard dragRowFrame.height > 0 else { return nil }

        var unpinnedFrames: [CGRect] = []
        var pinnedFrames: [CGRect] = []

        for tally in store.tallies {
            guard let id = tally.id, let frame = dragZoneFrames[id] else { continue }
            if store.isPinned(id) {
                pinnedFrames.append(frame)
            } else {
                unpinnedFrames.append(frame)
            }
        }

        if store.isPinned(draggedId) {
            guard let minY = pinnedFrames.map(\.minY).min(),
                  let maxY = pinnedFrames.map(\.maxY).max() else { return nil }
            return (minY, maxY)
        }

        guard let bandMin = unpinnedFrames.map(\.minY).min(),
              let bandMax = unpinnedFrames.map(\.maxY).max() else { return nil }

        // Unpinned tallies cannot land above the pinned section, but the finger must
        // be able to reach the gap before the first unpinned row (midY is ~½ row down).
        let reachAboveFirstUnpinned = bandMin - dragRowFrame.height
        let zoneTop = pinnedFrames.map(\.minY).min() ?? reachAboveFirstUnpinned
        return (min(zoneTop, reachAboveFirstUnpinned), bandMax)
    }

    // MARK: - Actions

    private func handleRowTap(_ tally: Tally) {
        guard tally.role(for: store.currentUid).canIncrement else { return }
        Task {
            do {
                try await store.increment(tally)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleRowLongPress(_ tally: Tally) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        openTally = tally
    }

    private func prewarmDirectory() async {
        let ownerRefs = store.tallies.map(\.owner)
        await directory.prefetch(ownerRefs)
        await directory.prefetch(friendsStore.friendRefs)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

// MARK: - Row layout

private struct TallyRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct TallyDragHandleView: View {
    let isPinned: Bool
    var showsDragGrip: Bool = true

    var body: some View {
        VStack(spacing: 6) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if showsDragGrip {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 28)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if showsDragGrip {
            return isPinned ? "Drag pinned tally" : "Drag tally"
        }
        return "Pinned tally"
    }
}

private struct TallyBarView: View {
    let tally: Tally
    let currentUid: String
    let directory: UserDirectory

    private var role: TallyRole { tally.role(for: currentUid) }
    private let colorObserver = LocalTallyColorsObserver.shared

    var body: some View {
        let ownerUid = tally.owner.documentID
        let ownerSummary = directory.cached(uid: ownerUid)
        let _ = colorObserver.version

        ZStack(alignment: .topLeading) {
            LocalTallyColors.backgroundTint(for: tally.id ?? "")
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tally.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text("\(tally.count)")
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 6) {
                    AvatarBadge(summary: ownerSummary, size: 20)
                    Text(ownerSummary?.displayUsername ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if role.hasLock {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("View only")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 80)
        .task {
            await directory.fetch(uid: ownerUid)
        }
    }
}

// MARK: - Row

private struct TallyRow: View {
    let tally: Tally
    let currentUid: String
    let directory: UserDirectory
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var nudge: Int = 0
    @State private var pressed: Bool = false

    private var role: TallyRole { tally.role(for: currentUid) }

    var body: some View {
        TallyBarView(tally: tally, currentUid: currentUid, directory: directory)
            .scaleEffect(pressed ? 0.98 : 1.0)
            .shake(times: nudge)
            .contentShape(Rectangle())
            .onTapGesture {
                if role.canIncrement {
                    onTap()
                } else {
                    withAnimation(.linear(duration: 0.3)) { nudge &+= 1 }
                }
            }
            .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 30, pressing: { isPressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    pressed = isPressing
                }
            }, perform: {
                onLongPress()
            })
    }
}

// MARK: - Add Tally sheet

private struct AddTallySheet: View {
    let store: TallyStore
    let friendsStore: FriendsStore
    let directory: UserDirectory

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var table: PermissionsTable = .init(friendUids: [], permissions: [:])
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        TextField("e.g. Push-ups", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Share with")
                            .font(.headline)
                        PermissionsTableEditor(table: $table, directory: directory)
                            .frame(minHeight: 220)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .navigationTitle("New Tally")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { submit() }
                        .bold()
                        .disabled(!isValid || isSubmitting)
                }
            }
        }
        .task {
            table = PermissionsTable(friendUids: friendsStore.friendUids, permissions: [:])
            await directory.prefetch(friendsStore.friendRefs)
        }
    }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 40
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        Task {
            do {
                _ = try await store.addTally(
                    name: String(trimmed.prefix(40)),
                    initialPermissions: table.permissions
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

#Preview {
    TalliesView(profile: UserProfile(
        id: "preview",
        name: "Ben",
        username: "ben",
        email: "ben@example.com",
        joined: .now,
        tallies: [],
        friends: []
    ))
    .environment(AuthStore())
}
