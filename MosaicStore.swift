//
//  MosaicStore.swift
//  Mosaic
//
//  Created by Codex.
//

import Foundation
import SwiftData

struct FieldDraftTemplate: Equatable, Sendable {
    let name: String
    let type: FieldType
}

enum TileFieldInput: Equatable, Sendable {
    case text(String)
    case number(String)
    case date(Date)
    case rating(Int)
    case url(String)
    case tag(String)
}

enum MosaicCatalog {
    static let defaultCollectionKinds: [CollectionKind] = [.movies, .tvShows, .books, .albums]

    static func defaultFieldDrafts(for kind: CollectionKind) -> [FieldDraftTemplate] {
        switch kind {
        case .movies:
            return [
                FieldDraftTemplate(name: "Director", type: .text),
                FieldDraftTemplate(name: "Year", type: .number),
                FieldDraftTemplate(name: "Rating", type: .rating),
                FieldDraftTemplate(name: "Notes", type: .text)
            ]
        case .tvShows:
            return [
                FieldDraftTemplate(name: "Network", type: .text),
                FieldDraftTemplate(name: "Seasons", type: .number),
                FieldDraftTemplate(name: "Status", type: .text),
                FieldDraftTemplate(name: "Rating", type: .rating)
            ]
        case .books:
            return [
                FieldDraftTemplate(name: "Author", type: .text),
                FieldDraftTemplate(name: "Format", type: .text),
                FieldDraftTemplate(name: "Pages", type: .number),
                FieldDraftTemplate(name: "Rating", type: .rating)
            ]
        case .albums:
            return [
                FieldDraftTemplate(name: "Artist", type: .text),
                FieldDraftTemplate(name: "Year", type: .number),
                FieldDraftTemplate(name: "Genre", type: .text),
                FieldDraftTemplate(name: "Rating", type: .rating)
            ]
        case .custom:
            return []
        }
    }
}

enum MosaicStore {
    static func seedDefaultCollectionsIfNeeded(
        hasSeededDefaultCollections: inout Bool,
        existingCollectionsCount: Int,
        modelContext: ModelContext
    ) {
        guard !hasSeededDefaultCollections, existingCollectionsCount == 0 else { return }

        for (index, kind) in MosaicCatalog.defaultCollectionKinds.enumerated() {
            saveCollection(
                name: kind.displayName,
                kind: kind,
                customFields: [],
                collectionCount: index,
                modelContext: modelContext
            )
        }

        hasSeededDefaultCollections = true
    }

    static func saveCollection(
        name: String,
        kind: CollectionKind,
        customFields: [FieldDraftTemplate],
        collectionCount: Int,
        modelContext: ModelContext
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let collection = MosaicCollection(name: trimmedName, kind: kind, order: collectionCount)
        modelContext.insert(collection)

        let fields = kind == .custom ? customFields : MosaicCatalog.defaultFieldDrafts(for: kind)
        for (index, field) in fields.enumerated() {
            let trimmedFieldName = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedFieldName.isEmpty else { continue }

            let definition = FieldDefinition(
                name: trimmedFieldName,
                type: field.type,
                order: index,
                collection: collection
            )
            modelContext.insert(definition)
        }
    }

    static func saveTile(
        title: String,
        date: Date,
        collection: MosaicCollection,
        fieldInputs: [PersistentIdentifier: TileFieldInput],
        modelContext: ModelContext
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let tile = MosaicTile(title: trimmedTitle, date: date, collection: collection)
        modelContext.insert(tile)

        let sortedFields = collection.fieldDefinitions.sorted { $0.order < $1.order }
        for field in sortedFields {
            guard let input = fieldInputs[field.persistentModelID] else { continue }
            guard let value = makeFieldValue(for: field, input: input, tile: tile) else { continue }
            modelContext.insert(value)
        }
    }

    private static func makeFieldValue(
        for field: FieldDefinition,
        input: TileFieldInput,
        tile: MosaicTile
    ) -> FieldValue? {
        switch (field.type, input) {
        case let (.text, .text(text)):
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return nil }
            let value = FieldValue(fieldDefinition: field, tile: tile)
            value.textValue = trimmedText
            return value
        case let (.number, .number(numberText)):
            guard let number = Double(numberText) else { return nil }
            let value = FieldValue(fieldDefinition: field, tile: tile)
            value.numberValue = number
            return value
        case let (.date, .date(date)):
            let value = FieldValue(fieldDefinition: field, tile: tile)
            value.dateValue = date
            return value
        case let (.rating, .rating(rating)):
            guard rating > 0 else { return nil }
            let value = FieldValue(fieldDefinition: field, tile: tile)
            value.ratingValue = rating
            return value
        case let (.url, .url(urlText)):
            let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedURL.isEmpty else { return nil }
            let value = FieldValue(fieldDefinition: field, tile: tile)
            value.urlValue = trimmedURL
            return value
        case let (.tag, .tag(tagText)):
            let trimmedTag = tagText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTag.isEmpty else { return nil }
            let value = FieldValue(fieldDefinition: field, tile: tile)
            value.tagValue = trimmedTag
            return value
        default:
            return nil
        }
    }
}
