//
//  File.swift
//  
//
//  Created by Luke Lau on 07/01/2022.
//

import Foundation

struct TestQuery: FooFragment, BarFragment {
    let library: Library
    struct Library: FooFragmentLibrary, BarFragmentLibrary {
//        typealias Node = TestQueryLibraryNode
        let nodes: [Node]
        enum Node: FooFragmentLibraryNode, BarFragmentLibraryNode {
            var id: ID {
                switch self {
                case let .album(album):
                    return album.id
                case let .__other(other):
                    return other.id
                }
            }
            var addedToLibrary: Bool {
                switch self {
                case let .album(album):
                    return album.addedToLibrary
                case let .__other(other):
                    return other.addedToLibrary
                }
            }
            case album(Album)
            case __other(__Other)
            
            struct Album: FooFragmentLibraryNodeAlbum, BarFragmentLibraryNodeAlbum {
                let id: ID
                let title: String
                let addedToLibrary: Bool
                let artist: Artist
                let releasedOn: Date
                struct Artist: FooFragmentLibraryNodeAlbumArtist {
                    let name: String
                }
            }
            
            struct __Other {
                let id: ID
                let addedToLibrary: Bool
            }
            
            func __underlying() -> FooFragmentLibraryNodeUnderlying<Album> {
                switch self {
                case let .album(album):
                    return .album(album)
                case .__other(_):
                    return .__other
                }
            }
            
            func __underlying() -> BarFragmentLibraryNodeUnderlying<Album> {
                switch self {
                case let .album(album):
                    return .album(album)
                case .__other(_):
                    return .__other
                }
            }
        }
    }
}

protocol FooFragment {
    var library: Library { get }
    associatedtype Library: FooFragmentLibrary
}

protocol FooFragmentLibrary {
    var nodes: [Node] { get }
    associatedtype Node: FooFragmentLibraryNode
}

protocol FooFragmentLibraryNode {
    func __underlying() -> FooFragmentLibraryNodeUnderlying<Album>
//    typealias Underlying = FooFragmentLibraryNodeUnderlying<Album>
    var id: String { get }
    associatedtype Album: FooFragmentLibraryNodeAlbum
}
    
enum FooFragmentLibraryNodeUnderlying<Album: FooFragmentLibraryNodeAlbum> {
    case album(Album)
    case __other
}

protocol FooFragmentLibraryNodeAlbum {
    var title: String { get }
    var artist: Artist { get }
    associatedtype Artist: FooFragmentLibraryNodeAlbumArtist
}

protocol FooFragmentLibraryNodeAlbumArtist {
    var name: String { get }
}

func foo<T: FooFragment>(_ x: T) {
    for node in x.library.nodes {
        switch node.__underlying() {
        case .album(let album):
            print(album.title)
        case .__other:
            print("other")
        }
    }
}

func bar<T: BarFragment>(_ x: T) {
    for node in x.library.nodes {
        print(node.addedToLibrary)
        switch node.__underlying() {
        case .album(let album):
            print(album.releasedOn)
        case .__other:
            print("other")
        }
    }
}

func test(_ x: TestQuery) {
    foo(x)
    bar(x)
}

protocol BarFragment {
    var library: Library { get }
    associatedtype Library: BarFragmentLibrary
}

protocol BarFragmentLibrary {
    var nodes: [Node] { get }
    associatedtype Node: BarFragmentLibraryNode
}

protocol BarFragmentLibraryNode {
    var addedToLibrary: Bool { get }
    
    func __underlying() -> BarFragmentLibraryNodeUnderlying<Album>
//    typealias Underlying = FooFragmentLibraryNodeUnderlying<Album>
    var id: String { get }
    associatedtype Album: BarFragmentLibraryNodeAlbum
}

enum BarFragmentLibraryNodeUnderlying<Album> {
    case album(BarFragmentLibraryNodeAlbum)
    case __other
}

protocol BarFragmentLibraryNodeAlbum {
    var releasedOn: Date { get }
}


struct LibraryQuery: Queryable, Codable {
    let viewer: User?
    struct User: Codable, Identifiable {
        let library: LibraryItemConnection
        struct LibraryItemConnection: Codable, LibraryViewFragment {
            let edges: [LibraryItemEdge]
            struct LibraryItemEdge: Codable, LibraryViewFragmentEdges {
                let cursor: String
                let dateAdded: Date
                let node: LibraryItem
                enum LibraryItem: Codable, LibraryViewFragmentEdgesNode {
                    case track(Track)
                    case album(Album)
                    case other(Other)
                    struct Track: Codable, Identifiable, LibraryViewFragmentEdgesNodeTrack {
                        let title: String
                        let album: Album
                        struct Album: Codable, Identifiable, LibraryViewFragmentEdgesNodeTrackAlbum {
                            let artworkUrl: String
                            let id: ID
                            var __typename: String = "Album"
                        }
                        let id: ID
                        var __typename: String = "Track"
                    }
                    struct Album: Codable, Identifiable, LibraryViewFragmentEdgesNodeAlbum {
                        let title: String
                        let artworkUrl: String
                        let id: ID
                        var __typename: String = "Album"
                    }
                    struct Other: Codable {
                    }
                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: TypenameCodingKeys.self)
                        let typename = try container.decode(String.self, forKey: .__typename)
                        switch typename {
                        case "Track":
                            self = .track(try Track(from: decoder))
                        case "Album":
                            self = .album(try Album(from: decoder))
                        default:
                            self = .other(try Other(from: decoder))
                        }
                    }
                    func encode(to encoder: Encoder) throws {
                        switch self {
                        case .track(let track):
                            try track.encode(to: encoder)
                        case .album(let album):
                            try album.encode(to: encoder)
                        case .other(let other):
                            try other.encode(to: encoder)
                        }
                    }
                }
            }
        }
        let id: ID
        var __typename: String = "User"
    }
    static let query = """
 {
viewer {
library {
...LibraryView
}
id
__typename
}
}
fragment LibraryView on LibraryItemConnection {
edges {
cursor
dateAdded
node {
... on Album {
title
artworkUrl
id
__typename
}
... on Track {
title
album {
artworkUrl
id
__typename
}
id
__typename
}
}
}
}
"""
}

protocol LibraryViewFragment: Codable {
    associatedtype Edges: LibraryViewFragmentEdges
    var edges: [Edges] { get }
}

protocol LibraryViewFragmentEdges: Codable {
    var cursor: String { get }
    var dateAdded: Date { get }
    associatedtype Node: LibraryViewFragmentEdgesNode
    var node: Node { get }
}

protocol LibraryViewFragmentEdgesNode: Codable {
    func __underlying() -> LibraryViewFragmentEdgesNodeUnderlying<Track, Album>
    associatedtype Track: LibraryViewFragmentEdgesNodeTrack
    associatedtype Album: LibraryViewFragmentEdgesNodeAlbum
}

enum LibraryViewFragmentEdgesNodeUnderlying<Track: LibraryViewFragmentEdgesNodeTrack, Album: LibraryViewFragmentEdgesNodeAlbum> : Codable {
    case track(Track)
    case album(Album)
    case __other
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypenameCodingKeys.self)
        let typename = try container.decode(String.self, forKey: .__typename)
        switch typename {
        case "Track":
            self = .track(try Track(from: decoder))
        case "Album":
            self = .album(try Album(from: decoder))
        default:
            self = .__other
        }
    }
    func encode(to encoder: Encoder) throws {
        switch self {
        case .track(let track):
            try track.encode(to: encoder)
        case .album(let album):
            try album.encode(to: encoder)
        case .__other(let __other):
            try __other.encode(to: encoder)
        }
    }
}

protocol LibraryViewFragmentEdgesNodeTrack: Codable {
    var title: String { get }
    associatedtype Album: LibraryViewFragmentEdgesNodeTrackAlbum
    var album: Album { get }
    var id: ID { get }
    var __typename: String { get }
}

protocol LibraryViewFragmentEdgesNodeTrackAlbum: Codable {
    var artworkUrl: String { get }
    var id: ID { get }
    var __typename: String { get }
}

protocol LibraryViewFragmentEdgesNodeAlbum: Codable {
    var title: String { get }
    var artworkUrl: String { get }
    var id: ID { get }
    var __typename: String { get }
}

struct RemoveFromLibraryMutation: Queryable, Codable {
    let removeFromLibrary: AddToLibraryPayload?
    struct AddToLibraryPayload: Codable {
        let library: LibraryItemConnection
        struct LibraryItemConnection: Codable, LibraryViewFragment {
            let edges: [LibraryItemEdge]
            struct LibraryItemEdge: Codable, LibraryViewFragmentEdges {
                let cursor: String
                let dateAdded: Date
                let node: LibraryItem
                enum LibraryItem: Codable, LibraryViewFragmentEdgesNode {
                    case track(Track)
                    case album(Album)
                    case other(Other)
                    struct Track: Codable, Identifiable, LibraryViewFragmentEdgesNodeTrack {
                        let title: String
                        let album: Album
                        struct Album: Codable, Identifiable, LibraryViewFragmentEdgesNodeTrackAlbum {
                            let artworkUrl: String
                            let id: ID
                            var __typename: String = "Album"
                        }
                        let id: ID
                        var __typename: String = "Track"
                    }
                    struct Album: Codable, Identifiable, LibraryViewFragmentEdgesNodeAlbum {
                        let title: String
                        let artworkUrl: String
                        let id: ID
                        var __typename: String = "Album"
                    }
                    struct Other: Codable {
                    }
                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: TypenameCodingKeys.self)
                        let typename = try container.decode(String.self, forKey: .__typename)
                        switch typename {
                        case "Track":
                            self = .track(try Track(from: decoder))
                        case "Album":
                            self = .album(try Album(from: decoder))
                        default:
                            self = .other(try Other(from: decoder))
                        }
                    }
                    func encode(to encoder: Encoder) throws {
                        switch self {
                        case .track(let track):
                            try track.encode(to: encoder)
                        case .album(let album):
                            try album.encode(to: encoder)
                        case .other(let other):
                            try other.encode(to: encoder)
                        }
                    }
                }
            }
        }
    }
    static let query = """
mutation removeFromLibrary ($itemId: ID!) {
removeFromLibrary(itemId: $itemId) {
library {
...LibraryView
}
}
}
fragment LibraryView on LibraryItemConnection {
edges {
cursor
dateAdded
node {
... on Album {
title
artworkUrl
id
__typename
}
... on Track {
title
album {
artworkUrl
id
__typename
}
id
__typename
}
}
}
}
"""
    struct Variables: Encodable, Equatable {
        let itemId: ID
    }
}
