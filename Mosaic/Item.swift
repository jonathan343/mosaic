//
//  Item.swift
//  Mosaic
//
//  Created by Jonathan Gaytan on 3/21/26.
//

import Foundation
import SwiftData

enum CollectionKind: String, CaseIterable, Identifiable {
    case movies
    case tvShows
    case books
    case albums
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .movies:
            return "Movies"
        case .tvShows:
            return "TV Shows"
        case .books:
            return "Books"
        case .albums:
            return "Albums"
        case .custom:
            return "Custom"
        }
    }
}

enum FieldType: String, CaseIterable, Identifiable {
    case text
    case number
    case date
    case rating
    case url
    case tag

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .number:
            return "Number"
        case .date:
            return "Date"
        case .rating:
            return "Rating"
        case .url:
            return "URL"
        case .tag:
            return "Tag"
        }
    }
}

@Model
final class MosaicCollection {
    var name: String
    var kindRaw: String
    var createdAt: Date
    var order: Int

    @Relationship(deleteRule: .cascade, inverse: \MosaicTile.collection)
    var tiles: [MosaicTile]

    @Relationship(deleteRule: .cascade, inverse: \FieldDefinition.collection)
    var fieldDefinitions: [FieldDefinition]

    init(name: String, kind: CollectionKind, order: Int) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.createdAt = Date()
        self.order = order
        self.tiles = []
        self.fieldDefinitions = []
    }

    var kind: CollectionKind {
        get {
            CollectionKind(rawValue: kindRaw) ?? .custom
        }
        set {
            kindRaw = newValue.rawValue
        }
    }
}

@Model
final class MosaicTile {
    var title: String
    var date: Date
    var createdAt: Date

    var collection: MosaicCollection?

    @Relationship(deleteRule: .cascade, inverse: \FieldValue.tile)
    var fieldValues: [FieldValue]

    init(title: String, date: Date, collection: MosaicCollection?) {
        self.title = title
        self.date = date
        self.createdAt = Date()
        self.collection = collection
        self.fieldValues = []
    }
}

@Model
final class FieldDefinition {
    var name: String
    var typeRaw: String
    var order: Int

    var collection: MosaicCollection?

    init(name: String, type: FieldType, order: Int, collection: MosaicCollection?) {
        self.name = name
        self.typeRaw = type.rawValue
        self.order = order
        self.collection = collection
    }

    var type: FieldType {
        get {
            FieldType(rawValue: typeRaw) ?? .text
        }
        set {
            typeRaw = newValue.rawValue
        }
    }
}

@Model
final class FieldValue {
    var textValue: String?
    var numberValue: Double?
    var dateValue: Date?
    var ratingValue: Int?
    var urlValue: String?
    var tagValue: String?

    var fieldDefinition: FieldDefinition?
    var tile: MosaicTile?

    init(fieldDefinition: FieldDefinition?, tile: MosaicTile?) {
        self.fieldDefinition = fieldDefinition
        self.tile = tile
    }
}
