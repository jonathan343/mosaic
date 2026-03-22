//
//  MosaicTests.swift
//  MosaicTests
//
//  Created by Jonathan Gaytan on 3/21/26.
//

import Foundation
import SwiftData
import Testing
@testable import Mosaic

@MainActor
struct MosaicTests {
    @Test
    func seedDefaultCollectionsCreatesExpectedCollectionsAndFields() throws {
        let container = try makeModelContainer()
        let context = container.mainContext
        var hasSeededDefaultCollections = false

        MosaicStore.seedDefaultCollectionsIfNeeded(
            hasSeededDefaultCollections: &hasSeededDefaultCollections,
            existingCollectionsCount: 0,
            modelContext: context
        )

        let collections = try fetchCollections(in: context)
        #expect(hasSeededDefaultCollections)
        #expect(collections.map(\.name) == ["Movies", "TV Shows", "Books", "Albums"])
        #expect(collections.map(\.order) == [0, 1, 2, 3])

        let movieFields = try #require(collections.first?.fieldDefinitions.sorted { $0.order < $1.order })
        #expect(movieFields.map(\.name) == ["Director", "Year", "Rating", "Notes"])
        #expect(movieFields.map(\.type) == [.text, .number, .rating, .text])

        MosaicStore.seedDefaultCollectionsIfNeeded(
            hasSeededDefaultCollections: &hasSeededDefaultCollections,
            existingCollectionsCount: collections.count,
            modelContext: context
        )

        #expect(try fetchCollections(in: context).count == 4)
    }

    @Test
    func saveCustomCollectionTrimsNameAndSkipsBlankFields() throws {
        let container = try makeModelContainer()
        let context = container.mainContext

        MosaicStore.saveCollection(
            name: "  Games  ",
            kind: .custom,
            customFields: [
                FieldDraftTemplate(name: " Platform ", type: .text),
                FieldDraftTemplate(name: "   ", type: .number)
            ],
            collectionCount: 0,
            modelContext: context
        )

        let collection = try #require(fetchCollections(in: context).first)
        #expect(collection.name == "Games")
        #expect(collection.kind == .custom)
        #expect(collection.order == 0)

        let fields = collection.fieldDefinitions.sorted { $0.order < $1.order }
        #expect(fields.count == 1)
        #expect(fields.first?.name == "Platform")
        #expect(fields.first?.type == .text)
    }

    @Test
    func saveTilePersistsOnlyMeaningfulFieldValues() throws {
        let container = try makeModelContainer()
        let context = container.mainContext
        let releaseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let watchedDate = Date(timeIntervalSince1970: 1_701_000_000)

        let collection = MosaicCollection(name: "Movies", kind: .movies, order: 0)
        context.insert(collection)

        let directorField = FieldDefinition(name: "Director", type: .text, order: 0, collection: collection)
        let yearField = FieldDefinition(name: "Year", type: .number, order: 1, collection: collection)
        let releaseField = FieldDefinition(name: "Release", type: .date, order: 2, collection: collection)
        let ratingField = FieldDefinition(name: "Rating", type: .rating, order: 3, collection: collection)
        let linkField = FieldDefinition(name: "Link", type: .url, order: 4, collection: collection)
        let genreField = FieldDefinition(name: "Genre", type: .tag, order: 5, collection: collection)

        context.insert(directorField)
        context.insert(yearField)
        context.insert(releaseField)
        context.insert(ratingField)
        context.insert(linkField)
        context.insert(genreField)

        MosaicStore.saveTile(
            title: "  Dune  ",
            date: watchedDate,
            collection: collection,
            fieldInputs: [
                directorField.persistentModelID: .text(" Denis Villeneuve "),
                yearField.persistentModelID: .number("not a number"),
                releaseField.persistentModelID: .date(releaseDate),
                ratingField.persistentModelID: .rating(0),
                linkField.persistentModelID: .url(" https://example.com/dune "),
                genreField.persistentModelID: .tag(" sci-fi ")
            ],
            modelContext: context
        )

        let tile = try #require(fetchTiles(in: context).first)
        #expect(tile.title == "Dune")
        #expect(tile.date == watchedDate)

        let values = try fetchFieldValues(in: context)
        #expect(values.count == 4)
        #expect(values.contains { $0.textValue == "Denis Villeneuve" })
        #expect(values.contains { $0.dateValue == releaseDate })
        #expect(values.contains { $0.urlValue == "https://example.com/dune" })
        #expect(values.contains { $0.tagValue == "sci-fi" })
        #expect(values.allSatisfy { $0.numberValue == nil })
        #expect(values.allSatisfy { $0.ratingValue == nil })
    }

    @Test
    func unknownRawValuesFallBackSafely() {
        let collection = MosaicCollection(name: "Test", kind: .movies, order: 0)
        collection.kindRaw = "unexpected"

        let field = FieldDefinition(name: "Field", type: .rating, order: 0, collection: collection)
        field.typeRaw = "unexpected"

        #expect(collection.kind == .custom)
        #expect(field.type == .text)
    }

    private func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([
            MosaicCollection.self,
            MosaicTile.self,
            FieldDefinition.self,
            FieldValue.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func fetchCollections(in context: ModelContext) throws -> [MosaicCollection] {
        let descriptor = FetchDescriptor<MosaicCollection>(
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchTiles(in context: ModelContext) throws -> [MosaicTile] {
        let descriptor = FetchDescriptor<MosaicTile>(sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(descriptor)
    }

    private func fetchFieldValues(in context: ModelContext) throws -> [FieldValue] {
        let descriptor = FetchDescriptor<FieldValue>()
        return try context.fetch(descriptor)
    }
}
