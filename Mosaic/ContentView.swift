//
//  ContentView.swift
//  Mosaic
//
//  Created by Jonathan Gaytan on 3/21/26.
//

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    private let gridCoordinateSpaceName = "collectionGrid"
    private let reorderAnimation = Animation.interpolatingSpring(stiffness: 240, damping: 24)
    private let dropCompletionAnimation = Animation.spring(response: 0.28, dampingFraction: 0.72)
    private let pickupAnimation = Animation.spring(response: 0.22, dampingFraction: 0.78)

    @Environment(\.modelContext) private var modelContext
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @Query(sort: [
        SortDescriptor(\MosaicCollection.order),
        SortDescriptor(\MosaicCollection.name)
    ]) private var collections: [MosaicCollection]
    @AppStorage("hasSeededDefaultCollections") private var hasSeededDefaultCollections = false
#if os(iOS)
    @State private var editMode: EditMode = .inactive
#else
    @State private var isEditingCollections = false
#endif
    @State private var isPresentingAddCollection = false
    @State private var pendingCollectionDeletion: PendingCollectionDeletion?
    @State private var draggedCollectionID: PersistentIdentifier?
    @State private var draggedCollectionLocation: CGPoint?
    @State private var draggedCollectionTouchOffset: CGSize = .zero
    @State private var collectionFrames: [PersistentIdentifier: CGRect] = [:]
    @State private var lastReorderTarget: ReorderTarget?
    @State private var currentGridColumnCount = 2
    @State private var isDragPreviewLifted = false
#if os(iOS)
    @State private var reorderFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
#endif

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ScrollView {
                        if collections.isEmpty {
                            EmptyMosaicView()
                                .padding(16)
                        } else {
                            LazyVGrid(columns: gridColumns(for: geometry.size.width), spacing: 16) {
                                ForEach(collections) { collection in
                                    collectionRow(for: collection)
                                }
                            }
                            .animation(reorderAnimation, value: collectionOrderSignature)
                            .padding(16)
                        }
                    }
                    .accessibilityIdentifier("collectionGrid")
                    .accessibilityValue(collections.map(\.name).joined(separator: "|"))
                    .coordinateSpace(name: gridCoordinateSpaceName)
                    .onPreferenceChange(CollectionFramePreferenceKey.self) { frames in
                        collectionFrames = frames
                    }
                    .onAppear {
                        currentGridColumnCount = columnCount(for: geometry.size.width)
                    }
                    .onChange(of: geometry.size.width) { _, width in
                        currentGridColumnCount = columnCount(for: width)
                    }

                    if let draggedCollection,
                       let draggedFrame = collectionFrames[draggedCollection.persistentModelID] {
                        CollectionCard(
                            collection: draggedCollection,
                            isDragged: false
                        )
                        .frame(width: draggedFrame.width, height: draggedFrame.height)
                        .scaleEffect(isDragPreviewLifted ? 1.05 : 1.01)
                        .shadow(
                            color: .black.opacity(isDragPreviewLifted ? 0.2 : 0.08),
                            radius: isDragPreviewLifted ? 16 : 8,
                            y: isDragPreviewLifted ? 10 : 4
                        )
                        .animation(pickupAnimation, value: isDragPreviewLifted)
                        .position(currentDraggedCenter())
                        .zIndex(10)
                        .allowsHitTesting(false)
                    }
                }
            }
#if os(iOS)
            .environment(\.editMode, $editMode)
#endif
            .navigationTitle("Mosaic")
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    if !collections.isEmpty {
                        Button(editMode.isEditing ? "Done" : "Edit") {
                            withAnimation {
                                editMode = editMode.isEditing ? .inactive : .active
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresentingAddCollection = true
                    } label: {
                        Label("Add Collection", systemImage: "plus")
                    }
                }
#else
                ToolbarItem {
                    if !collections.isEmpty {
                        Button(isEditingCollections ? "Done" : "Edit") {
                            withAnimation {
                                isEditingCollections.toggle()
                            }
                        }
                    }
                }
                ToolbarItem {
                    Button {
                        isPresentingAddCollection = true
                    } label: {
                        Label("Add Collection", systemImage: "plus")
                    }
                }
#endif
            }
            .sheet(isPresented: $isPresentingAddCollection) {
                AddCollectionSheet(collectionCount: collections.count)
            }
            .alert(item: $pendingCollectionDeletion) { deletion in
                Alert(
                    title: Text(deletion.title),
                    message: Text(deletion.message),
                    primaryButton: .destructive(Text("Delete")) {
                        confirmCollectionDeletion(deletion)
                    },
                    secondaryButton: .cancel()
                )
            }
            .task {
                seedCollectionsIfNeeded()
#if os(iOS)
                reorderFeedbackGenerator.prepare()
#endif
            }
            .onChange(of: isCollectionEditing) { _, isEditing in
                if !isEditing {
                    resetDragState()
                }
            }
        }
    }

    private var isCollectionEditing: Bool {
#if os(iOS)
        editMode.isEditing
#else
        isEditingCollections
#endif
    }

    private var collectionOrderSignature: [PersistentIdentifier] {
        collections.map(\.persistentModelID)
    }

    private var draggedCollection: MosaicCollection? {
        guard let draggedCollectionID else { return nil }
        return collections.first { $0.persistentModelID == draggedCollectionID }
    }

    private func seedCollectionsIfNeeded() {
        MosaicStore.seedDefaultCollectionsIfNeeded(
            hasSeededDefaultCollections: &hasSeededDefaultCollections,
            existingCollectionsCount: collections.count,
            modelContext: modelContext
        )
    }

    private func confirmCollectionDeletion(_ deletion: PendingCollectionDeletion) {
        let collectionIDs = deletion.collectionIDs
        let survivingCollections = collections.filter { collection in
            !collectionIDs.contains(collection.persistentModelID)
        }

        withAnimation(reorderAnimation) {
            for collection in collections where collectionIDs.contains(collection.persistentModelID) {
                modelContext.delete(collection)
            }
            normalizeCollectionOrder(for: survivingCollections)
        }
    }

    private func normalizeCollectionOrder(for collections: [MosaicCollection]? = nil) {
        let collectionsToNormalize = collections ?? self.collections
        for (index, collection) in collectionsToNormalize.enumerated() {
            collection.order = index
        }
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let count = columnCount(for: width)
        let spacing: CGFloat = 16

        return Array(
            repeating: GridItem(.flexible(), spacing: spacing, alignment: .top),
            count: count
        )
    }

    private func columnCount(for width: CGFloat) -> Int {
        let spacing: CGFloat = 16
        let horizontalPadding: CGFloat = 32
        let availableWidth = max(width - horizontalPadding, 0)
        let targetCardWidth: CGFloat = 180
#if os(iOS)
        let minimumColumnCount = horizontalSizeClass == .compact ? 2 : 2
#else
        let minimumColumnCount = 1
#endif
        let fittedColumnCount = Int((availableWidth + spacing) / (targetCardWidth + spacing))
        return max(minimumColumnCount, fittedColumnCount)
    }

    @ViewBuilder
    private func collectionRow(for collection: MosaicCollection) -> some View {
        let card = CollectionCard(
            collection: collection,
            isDragged: draggedCollectionID == collection.persistentModelID
        )
        .accessibilityIdentifier("collectionCard.\(collection.name)")
        .background {
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: CollectionFramePreferenceKey.self,
                        value: [collection.persistentModelID: geometry.frame(in: .named(gridCoordinateSpaceName))]
                    )
            }
        }
        .overlay(alignment: .topTrailing) {
            if isCollectionEditing && draggedCollectionID != collection.persistentModelID {
                Button(role: .destructive) {
                    deleteCollection(collection)
                } label: {
                    Image(systemName: "trash")
                        .font(.headline)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Delete \(collection.name)")
                .accessibilityIdentifier("deleteCollection.\(collection.name)")
                .padding(10)
            }
        }
        .zIndex(draggedCollectionID == collection.persistentModelID ? 1 : 0)

        if isCollectionEditing {
            card
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .gesture(dragGesture(for: collection))
        } else {
            NavigationLink {
                CollectionDetailView(collection: collection)
            } label: {
                card
            }
            .buttonStyle(.plain)
        }
    }

    private func dragGesture(for collection: MosaicCollection) -> some Gesture {
        DragGesture(coordinateSpace: .named(gridCoordinateSpaceName))
            .onChanged { value in
                updateDrag(for: collection, value: value)
            }
            .onEnded { _ in
                endDrag()
            }
    }

    private func index(of collection: MosaicCollection) -> Int {
        collections.firstIndex { $0.persistentModelID == collection.persistentModelID } ?? 0
    }

    @discardableResult
    private func moveCollection(
        _ collection: MosaicCollection,
        relativeTo targetCollection: MosaicCollection,
        insertingAfter: Bool
    ) -> Bool {
        let currentIndex = index(of: collection)
        let targetIndex = index(of: targetCollection)
        guard currentIndex != targetIndex else { return false }

        var reorderedCollections = collections
        let movingCollection = reorderedCollections.remove(at: currentIndex)
        guard let adjustedTargetIndex = reorderedCollections.firstIndex(where: {
            $0.persistentModelID == targetCollection.persistentModelID
        }) else {
            return false
        }

        let destinationIndex = insertingAfter ? adjustedTargetIndex + 1 : adjustedTargetIndex
        reorderedCollections.insert(movingCollection, at: destinationIndex)

        guard reorderedCollections.map(\.persistentModelID) != collections.map(\.persistentModelID) else {
            return false
        }

        withAnimation(reorderAnimation) {
            for (index, collection) in reorderedCollections.enumerated() {
                collection.order = index
            }
        }

#if os(iOS)
        reorderFeedbackGenerator.impactOccurred(intensity: 0.8)
        reorderFeedbackGenerator.prepare()
#endif
        return true
    }

    private func deleteCollection(_ collection: MosaicCollection) {
        pendingCollectionDeletion = PendingCollectionDeletion(collections: [collection])
    }

    private func updateDrag(for collection: MosaicCollection, value: DragGesture.Value) {
        if draggedCollectionID == nil {
            beginDrag(for: collection, value: value)
        }

        guard draggedCollectionID == collection.persistentModelID else { return }

        draggedCollectionLocation = value.location
        guard let reorderTarget = reorderTarget(for: currentDraggedCenter(), dragging: collection) else {
            lastReorderTarget = nil
            return
        }
        guard reorderTarget != lastReorderTarget else { return }
        guard let targetCollection = collectionForID(reorderTarget.collectionID) else { return }

        lastReorderTarget = reorderTarget
        let didMove = moveCollection(
            collection,
            relativeTo: targetCollection,
            insertingAfter: reorderTarget.insertingAfter
        )

        if !didMove {
            lastReorderTarget = nil
        }
    }

    private func beginDrag(for collection: MosaicCollection, value: DragGesture.Value) {
        draggedCollectionID = collection.persistentModelID
        lastReorderTarget = nil
        isDragPreviewLifted = false

        guard let frame = collectionFrames[collection.persistentModelID] else {
            draggedCollectionLocation = value.location
            draggedCollectionTouchOffset = .zero
            withAnimation(pickupAnimation) {
                isDragPreviewLifted = true
            }
            return
        }

        draggedCollectionLocation = value.location
        draggedCollectionTouchOffset = CGSize(
            width: value.startLocation.x - frame.midX,
            height: value.startLocation.y - frame.midY
        )

        withAnimation(pickupAnimation) {
            isDragPreviewLifted = true
        }
    }

    private func endDrag() {
        guard let draggedCollectionID,
              let frame = collectionFrames[draggedCollectionID] else {
            resetDragState()
            return
        }

        let settledLocation = CGPoint(
            x: frame.midX + draggedCollectionTouchOffset.width,
            y: frame.midY + draggedCollectionTouchOffset.height
        )

        withAnimation(dropCompletionAnimation) {
            isDragPreviewLifted = false
            draggedCollectionLocation = settledLocation
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            resetDragState()
        }
    }

    private func resetDragState() {
        draggedCollectionID = nil
        draggedCollectionLocation = nil
        draggedCollectionTouchOffset = .zero
        lastReorderTarget = nil
        isDragPreviewLifted = false
    }

    private func currentDraggedCenter() -> CGPoint {
        CGPoint(
            x: (draggedCollectionLocation?.x ?? 0) - draggedCollectionTouchOffset.width,
            y: (draggedCollectionLocation?.y ?? 0) - draggedCollectionTouchOffset.height
        )
    }

    private func reorderTarget(for draggedCenter: CGPoint, dragging collection: MosaicCollection) -> ReorderTarget? {
        let otherCollections = collections.filter { $0.persistentModelID != draggedCollectionID }
        let draggingIndex = index(of: collection)
        let draggingRow = draggingIndex / max(currentGridColumnCount, 1)
        let draggingColumn = draggingIndex % max(currentGridColumnCount, 1)

        for targetCollection in otherCollections {
            guard let frame = collectionFrames[targetCollection.persistentModelID] else { continue }
            let activeFrame = frame.insetBy(dx: frame.width * 0.04, dy: frame.height * 0.04)
            guard activeFrame.contains(draggedCenter) else { continue }

            let targetIndex = index(of: targetCollection)
            let targetRow = targetIndex / max(currentGridColumnCount, 1)
            let targetColumn = targetIndex % max(currentGridColumnCount, 1)

            let insertsAfter: Bool
            if currentGridColumnCount == 1 || targetRow != draggingRow {
                let verticalThreshold = frame.height * 0.12
                insertsAfter = draggedCenter.y > frame.midY - verticalThreshold
            } else if targetColumn != draggingColumn {
                let horizontalThreshold = frame.width * 0.12
                insertsAfter = draggedCenter.x > frame.midX - horizontalThreshold
            } else {
                let dx = draggedCenter.x - frame.midX
                let dy = draggedCenter.y - frame.midY
                insertsAfter = abs(dx) > abs(dy) ? dx > 0 : dy > 0
            }

            return ReorderTarget(
                collectionID: targetCollection.persistentModelID,
                insertingAfter: insertsAfter
            )
        }

        return nil
    }

    private func collectionForID(_ id: PersistentIdentifier) -> MosaicCollection? {
        collections.first { $0.persistentModelID == id }
    }

}

private struct PendingCollectionDeletion: Identifiable {
    let id = UUID()
    let collectionIDs: [PersistentIdentifier]
    let collectionNames: [String]

    init(collections: [MosaicCollection]) {
        self.collectionIDs = collections.map(\.persistentModelID)
        self.collectionNames = collections.map(\.name)
    }

    var title: String {
        collectionNames.count == 1 ? "Delete Collection?" : "Delete Collections?"
    }

    var message: String {
        if collectionNames.count == 1, let name = collectionNames.first {
            return "\"\(name)\" and all of its tiles will be permanently deleted."
        }

        return "\(collectionNames.count) collections and all of their tiles will be permanently deleted."
    }
}

private struct EmptyMosaicView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start Your Mosaic")
                .font(.title2.weight(.semibold))
            Text("Create collections for movies, TV shows, books, albums, or anything you want to track.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.gray.opacity(0.12))
        )
    }
}

private struct CollectionCard: View {
    let collection: MosaicCollection
    let isDragged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(collection.name)
                .font(.headline)
                .foregroundStyle(.white)
            Text("\(collection.tiles.count) tiles")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(gradient(for: collection.kind))
        )
        .opacity(isDragged ? 0.001 : 1)
        .scaleEffect(isDragged ? 0.98 : 1)
        .shadow(color: .black.opacity(isDragged ? 0.18 : 0), radius: isDragged ? 14 : 0, y: isDragged ? 8 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(collection.name)
    }

    private func gradient(for kind: CollectionKind) -> LinearGradient {
        let colors: [Color]
        switch kind {
        case .movies:
            colors = [Color(red: 0.18, green: 0.27, blue: 0.38), Color(red: 0.39, green: 0.19, blue: 0.52)]
        case .tvShows:
            colors = [Color(red: 0.15, green: 0.32, blue: 0.31), Color(red: 0.18, green: 0.49, blue: 0.58)]
        case .books:
            colors = [Color(red: 0.22, green: 0.36, blue: 0.25), Color(red: 0.46, green: 0.31, blue: 0.16)]
        case .albums:
            colors = [Color(red: 0.33, green: 0.16, blue: 0.13), Color(red: 0.52, green: 0.34, blue: 0.22)]
        case .custom:
            colors = [Color(red: 0.20, green: 0.20, blue: 0.28), Color(red: 0.38, green: 0.28, blue: 0.36)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct ReorderTarget: Equatable {
    let collectionID: PersistentIdentifier
    let insertingAfter: Bool
}

private struct CollectionFramePreferenceKey: PreferenceKey {
    static var defaultValue: [PersistentIdentifier: CGRect] = [:]

    static func reduce(value: inout [PersistentIdentifier: CGRect], nextValue: () -> [PersistentIdentifier: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct CollectionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isPresentingAddTile = false
    @Bindable var collection: MosaicCollection

    private var sortedTiles: [MosaicTile] {
        collection.tiles.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            if sortedTiles.isEmpty {
                Text("No tiles yet. Add one to start tracking.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedTiles) { tile in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tile.title)
                            .font(.headline)
                        Text(tile.date, format: Date.FormatStyle(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteTiles)
            }
        }
        .navigationTitle(collection.name)
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isPresentingAddTile = true
                } label: {
                    Label("Add Tile", systemImage: "plus")
                }
            }
#else
            ToolbarItem {
                Button {
                    isPresentingAddTile = true
                } label: {
                    Label("Add Tile", systemImage: "plus")
                }
            }
#endif
        }
        .sheet(isPresented: $isPresentingAddTile) {
            AddTileSheet(collection: collection)
        }
    }

    private func deleteTiles(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(sortedTiles[index])
            }
        }
    }
}

private struct AddCollectionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let collectionCount: Int

    @State private var name = ""
    @State private var kind: CollectionKind = .movies
    @State private var customFields: [FieldDraft] = [FieldDraft(name: "Notes", type: .text)]

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Collection Type", selection: $kind) {
                        ForEach(CollectionKind.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }

                Section("Name") {
                    TextField("Collection name", text: $name)
                }

                if kind == .custom {
                    Section("Custom Fields") {
                        ForEach($customFields) { $field in
                            HStack(spacing: 12) {
                                TextField("Field name", text: $field.name)
                                Picker("Type", selection: $field.type) {
                                    ForEach(FieldType.allCases) { fieldType in
                                        Text(fieldType.displayName).tag(fieldType)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                        .onDelete(perform: deleteCustomFields)

                        Button {
                            addCustomField()
                        } label: {
                            Label("Add Field", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle("New Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCollection()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: kind) { _, newKind in
                if newKind != .custom {
                    if name.isEmpty || CollectionKind.allCases.contains(where: { $0.displayName == name }) {
                        name = newKind.displayName
                    }
                }
            }
            .onAppear {
                if name.isEmpty {
                    name = kind.displayName
                }
            }
        }
    }

    private func addCustomField() {
        customFields.append(FieldDraft(name: "", type: .text))
    }

    private func deleteCustomFields(offsets: IndexSet) {
        customFields.remove(atOffsets: offsets)
    }

    private func saveCollection() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let customFieldTemplates = customFields.map { FieldDraftTemplate(name: $0.name, type: $0.type) }
        MosaicStore.saveCollection(
            name: trimmedName,
            kind: kind,
            customFields: customFieldTemplates,
            collectionCount: collectionCount,
            modelContext: modelContext
        )
        dismiss()
    }
}

private struct AddTileSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var collection: MosaicCollection

    @State private var title = ""
    @State private var date = Date()

    @State private var textValues: [PersistentIdentifier: String] = [:]
    @State private var numberValues: [PersistentIdentifier: String] = [:]
    @State private var dateValues: [PersistentIdentifier: Date] = [:]
    @State private var ratingValues: [PersistentIdentifier: Int] = [:]
    @State private var urlValues: [PersistentIdentifier: String] = [:]
    @State private var tagValues: [PersistentIdentifier: String] = [:]

    private var sortedFields: [FieldDefinition] {
        collection.fieldDefinitions.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tile") {
                    TextField("Title", text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                if !sortedFields.isEmpty {
                    Section("Fields") {
                        ForEach(sortedFields) { field in
                            fieldInputRow(for: field)
                        }
                    }
                }
            }
            .navigationTitle("New Tile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTile()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func fieldInputRow(for field: FieldDefinition) -> some View {
        switch field.type {
        case .text:
            TextField(field.name, text: textBinding(for: field))
        case .number:
            TextField(field.name, text: numberBinding(for: field))
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
        case .date:
            DatePicker(field.name, selection: dateBinding(for: field), displayedComponents: .date)
        case .rating:
            Stepper {
                HStack {
                    Text(field.name)
                    Spacer()
                    Text("\(ratingBinding(for: field).wrappedValue)")
                        .foregroundStyle(.secondary)
                }
            } onIncrement: {
                let current = ratingBinding(for: field).wrappedValue
                ratingBinding(for: field).wrappedValue = min(current + 1, 5)
            } onDecrement: {
                let current = ratingBinding(for: field).wrappedValue
                ratingBinding(for: field).wrappedValue = max(current - 1, 0)
            }
        case .url:
            TextField(field.name, text: urlBinding(for: field))
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
#endif
        case .tag:
            TextField(field.name, text: tagBinding(for: field))
        }
    }

    private func textBinding(for field: FieldDefinition) -> Binding<String> {
        Binding(
            get: { textValues[field.persistentModelID] ?? "" },
            set: { textValues[field.persistentModelID] = $0 }
        )
    }

    private func numberBinding(for field: FieldDefinition) -> Binding<String> {
        Binding(
            get: { numberValues[field.persistentModelID] ?? "" },
            set: { numberValues[field.persistentModelID] = $0 }
        )
    }

    private func dateBinding(for field: FieldDefinition) -> Binding<Date> {
        Binding(
            get: { dateValues[field.persistentModelID] ?? Date() },
            set: { dateValues[field.persistentModelID] = $0 }
        )
    }

    private func ratingBinding(for field: FieldDefinition) -> Binding<Int> {
        Binding(
            get: { ratingValues[field.persistentModelID] ?? 0 },
            set: { ratingValues[field.persistentModelID] = $0 }
        )
    }

    private func urlBinding(for field: FieldDefinition) -> Binding<String> {
        Binding(
            get: { urlValues[field.persistentModelID] ?? "" },
            set: { urlValues[field.persistentModelID] = $0 }
        )
    }

    private func tagBinding(for field: FieldDefinition) -> Binding<String> {
        Binding(
            get: { tagValues[field.persistentModelID] ?? "" },
            set: { tagValues[field.persistentModelID] = $0 }
        )
    }

    private func saveTile() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        var fieldInputs: [PersistentIdentifier: TileFieldInput] = [:]
        for (identifier, value) in textValues {
            fieldInputs[identifier] = .text(value)
        }
        for (identifier, value) in numberValues {
            fieldInputs[identifier] = .number(value)
        }
        for (identifier, value) in dateValues {
            fieldInputs[identifier] = .date(value)
        }
        for (identifier, value) in ratingValues {
            fieldInputs[identifier] = .rating(value)
        }
        for (identifier, value) in urlValues {
            fieldInputs[identifier] = .url(value)
        }
        for (identifier, value) in tagValues {
            fieldInputs[identifier] = .tag(value)
        }

        MosaicStore.saveTile(
            title: trimmedTitle,
            date: date,
            collection: collection,
            fieldInputs: fieldInputs,
            modelContext: modelContext
        )

        dismiss()
    }
}

private struct FieldDraft: Identifiable {
    let id = UUID()
    var name: String
    var type: FieldType
}

#Preview {
    ContentView()
        .modelContainer(for: [MosaicCollection.self, MosaicTile.self, FieldDefinition.self, FieldValue.self], inMemory: true)
}
