//
//  ContentView.swift
//  Mosaic
//
//  Created by Jonathan Gaytan on 3/21/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
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

    var body: some View {
        NavigationStack {
            List {
                if collections.isEmpty {
                    EmptyMosaicView()
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(collections) { collection in
                        collectionRow(for: collection)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                    .onDelete(perform: deleteCollections)
                    .onMove(perform: moveCollections)
                }
            }
            .listStyle(.plain)
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
            }
        }
    }

    private func seedCollectionsIfNeeded() {
        MosaicStore.seedDefaultCollectionsIfNeeded(
            hasSeededDefaultCollections: &hasSeededDefaultCollections,
            existingCollectionsCount: collections.count,
            modelContext: modelContext
        )
    }

    private func deleteCollections(offsets: IndexSet) {
        let collectionsToDelete = offsets.map { collections[$0] }
        guard !collectionsToDelete.isEmpty else { return }

        pendingCollectionDeletion = PendingCollectionDeletion(collections: collectionsToDelete)
    }

    private func confirmCollectionDeletion(_ deletion: PendingCollectionDeletion) {
        let collectionIDs = deletion.collectionIDs
        let survivingCollections = collections.filter { collection in
            !collectionIDs.contains(collection.persistentModelID)
        }

        withAnimation {
            for collection in collections where collectionIDs.contains(collection.persistentModelID) {
                modelContext.delete(collection)
            }
            normalizeCollectionOrder(for: survivingCollections)
        }
    }

    private func moveCollections(from source: IndexSet, to destination: Int) {
        var reorderedCollections = collections
        reorderedCollections.move(fromOffsets: source, toOffset: destination)

        withAnimation {
            for (index, collection) in reorderedCollections.enumerated() {
                collection.order = index
            }
        }
    }

    private func normalizeCollectionOrder(for collections: [MosaicCollection]? = nil) {
        let collectionsToNormalize = collections ?? self.collections
        for (index, collection) in collectionsToNormalize.enumerated() {
            collection.order = index
        }
    }

    @ViewBuilder
    private func collectionRow(for collection: MosaicCollection) -> some View {
#if os(iOS)
        NavigationLink {
            CollectionDetailView(collection: collection)
        } label: {
            CollectionCard(collection: collection)
        }
        .buttonStyle(.plain)
#else
        HStack(spacing: 12) {
            NavigationLink {
                CollectionDetailView(collection: collection)
            } label: {
                CollectionCard(collection: collection)
            }
            .buttonStyle(.plain)

            if isEditingCollections {
                VStack(spacing: 8) {
                    Button {
                        moveCollection(collection, by: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .accessibilityLabel("Move collection up")
                    .disabled(index(of: collection) == 0)

                    Button {
                        moveCollection(collection, by: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .accessibilityLabel("Move collection down")
                    .disabled(index(of: collection) == collections.count - 1)

                    Button(role: .destructive) {
                        deleteCollection(collection)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete collection")
                }
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
            }
        }
#endif
    }

#if os(macOS)
    private func index(of collection: MosaicCollection) -> Int {
        collections.firstIndex { $0.persistentModelID == collection.persistentModelID } ?? 0
    }

    private func moveCollection(_ collection: MosaicCollection, by delta: Int) {
        let currentIndex = index(of: collection)
        let targetIndex = currentIndex + delta
        guard collections.indices.contains(targetIndex) else { return }

        var reorderedCollections = collections
        reorderedCollections.swapAt(currentIndex, targetIndex)

        withAnimation {
            for (index, collection) in reorderedCollections.enumerated() {
                collection.order = index
            }
        }
    }

    private func deleteCollection(_ collection: MosaicCollection) {
        pendingCollectionDeletion = PendingCollectionDeletion(collections: [collection])
    }
#endif

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
