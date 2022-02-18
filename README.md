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

For your query type, swiftui-graphql will always generate a **concrete type** composed of structs and enums.

For fragments, because they can be inhabited by various different query types, swiftui-graphql will always generate **protocols** for them.

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

## Conditional fields inside fragments

Conditional fields *inside* fragments are a bit trickier.
Consider this example, where foo returns a union inhabited by either type A, B or C.

```graphql
fragment Foo {
    ... on A {
        a1
    }
    ... on B {
        b1
    }
}

query {
    foo {
        ...Foo
        ... on A {
            a2
        }
        ... on C {
            c1
        }
    }
}
```

What should the protocol generated for `Foo` look like? Well because Swift doesn't have type classes over sum types, we need to do some wrapping.
The code generator will first generate a enum type, made generic over the actual enum contents:

```swift
enum FooFragment<A: FooFragmentA, B: FooFragmentB> {
    case a(A), b(B), __other
}
protocol FooFragmentA { var a1: String { get } }
protocol FooFragmentB { var b1: String { get } }
```

And then it generates a protocol that the actual **concrete** enum on the query type conforms to

```swift
protocol ContainsFooFragment {
    associatedtype A: FooFragmentA
    associatedtype B: FooFragmentB
    var __fooFragment: FooFragment<A, B> { get } 
}

struct Query {
    let foo: Foo
    enum Foo: ContainsFooFragment {
        case a(A)
        case b(B)
        case c(C)
        case __other
        struct A { let a1, a2: String }
        struct B { let b1: String }
        struct C { let c1: String }
        var __fooFragment: FooFragment<A, B> {
            switch self {
                case .a(let a): return .a(a)
                case .b(let b): return .b(b)
                default: return .__other
            }
        }
    }
}

```

You can then access the union on the fragment with the `__fooFragment` method.


## Conditionally nested conditionally nested fragments 
```graphql
fragment Foo on SomeUnion {
    ... on A {
        a {
            c
            ...Bar
        }
    }
}

fragment Bar on SomeInterface {
    ... on B {
        b
    }
}
```

```swift
enum FooFragment<A: FooFragmentA> {
    case a(A), __other
}

```

```
fragment Baz on SomeInterface {
    ... on X { x }
    ... on Y { y }
    z
}

query {
    foo {
        ...Foo
    }
}
```

```
protocol ContainsFooFragment {
    associatedtype A: FooFragmentA
    var __fooFragment: FooFragment<A> { get }
}

protocol FooFragmentA {
    associatedtype A: ContainsBarFragment
    var 1: Bar
}

protocol ContainsBazFragment {
    var z: Int { get }
    associatedtype X: BazFragmentX
    associatedtype Y: BazFragmentY
    var __bazFragment: BazFragment<X, Y> { get }
}

protocol BazFragmentX {
    var x: Int { get }
    var y: Int { get }
}
``` 

# Tests

To run the tests from Xcode, you need to create a link to the SwiftSyntax lib:

```bash
ln -s \
 /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain//usr/lib/swift/macosx/lib_InternalSwiftSyntaxParser.dylib \
 /Users/luke/Library/Developer/Xcode/DerivedData/Minm-*/Build/Products/Debug
```
