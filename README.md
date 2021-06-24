# swiftui-graphql

A description of this package.

# Code generation

Code generation generates structs that can be decoded directly from the resulting JSON output, as well as encoded back into GraphQL values for caching.

Here's the swift code a simple query might generate:

```graphql
{
    recentReleases {
        nodes {
            title
            artworkUrl
            artist {
                name
            }
        }
    }
}
```

```swift
struct ExploryQuerySpecimen2: Queryable, Codable {
    static let query: String = "..."
    
    let recentReleases: AlbumConnection
    struct AlbumConnection: Codable {
        let nodes: [Album?]?
        struct Album: Codable {
            let id: ID
            let __typename: String
            let title: String
            let artworkUrl: String
            let artist: Artist
            struct Artist: Codable {
                let id: ID
                let __typename: String
                let name: String
            }
        }
    }
}
```

## Caching
You might have noticed that the `id` and `__typename` fields were added to the structs.
This is because the actual query is modified a bit so that on any type which has an `id` field of type `ID`, the  `id` and `__typename` fields are added to the selection set.
So the actual query that will be sent to the server will look like this:

```graphql
{
    recentReleases {
        nodes {
            id
            __typename
            title
            artworkUrl
            artist {
                id
                __typename
                name
            }
        }
    }
}
```

Why are these fields added?
Well in order to be able to keep track of which object is which in the cache, swiftui-graphql creates a unique cache key based off of the `id` and `__typename`, magically adding it into your queries.

## Fragments

Say for example you have some reusable view and you define a fragment for it, so it can be included in other queries:

```graphql
fragment AlbumView on Album {
    title
    artworkUrl
}

query homeScreen {
    recentAlbums {
        ...AlbumView
    }
}
```

`swiftui-graphql` will generate a protocol that the underlying concrete types will conform to.

```swift
struct HomeScreenQuery: Codable {
    let recentAlbums: [Album]
    struct Album: Codable, AlbumView {
        let title: String
        let artworkUrl: String
    }
}

protocol AlbumView {
    var title: String { get }
    var artworkUrl: String { get }
}
```

You can then use it as a generic constraint in your view or function that requires it:

```swift
func foo<T: AlbumView>(_ fragment: T) { ... }
```

But what if there's a nested object inside the fragment?

```graphql
fragment AlbumView {
    title
    artworkUrl
    artist {
        name
    }
}
```

Then an `associatedtype` will then be added to the protocol:

```swift
protocol AlbumView {
    var title: String { get }
    var artworkUrl: String { get }
    associatedtype Artist: AlbumViewArtist
    var artist: Artist { get }
}
protocol AlbumViewArtist {
    var name: String { get }
}
```

## Conditional fragments
What about fragments that are only included on certain types?

```swift

struct AsdfQuery {
    let node: Node
    enum Node: Foo {
        
        var id: String {
            switch self {
            case .artist(let artist):
                return artist.id
            case .album(let album):
                return album.id
            }
        }
        
        case album(Album)
        case artist(Artist)
        struct Album: FooAlbum {
            let id: ID
            let color: String
        }
        struct Artist: FooArtist {
            let id: ID
            let name: String
        }
        
        var __type: FooType<Album, Artist> {
            switch self {
            case .artist(let artist):
                return .artist(artist)
            case .album(let album):
                return .album(album)
            }
        }
    }
}

protocol Foo {
    var id: String { get }
    associatedtype Album: FooAlbum
    associatedtype Artist: FooArtist
    var __type: FooType<Album, Artist> { get }
}

enum FooType<Album, Artist> {
    case album(Album), artist(Artist)
}

protocol FooAlbum {
    var color: String { get }
}

protocol FooArtist {
    var name: String { get }
}
```
