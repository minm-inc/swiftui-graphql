# Objects

Codegeneration generates concrete types for each operation.
The concrete types are made up of nested levels of objects.
An object maps one to one with an object in the transport, i.e. a JSON object.

Each operation generates one type with lots of nested types within it for each object.

Objects can be one of either two flavours:

## Monomorphic
If an object **will always** have the same fields no matter what the underlying type is, then from SwiftUIGraphQL's perspective it is monomorphic:
We can use one concrete type to decode all possible responses.
swiftui-graphql will then generate a struct for it like so:

```swift
struct Album: Cacheable {
    let id: ID
    let __typename: String
    let title: String
    let artist: Artist
    struct Artist: Cacheable {
        let id: ID
        let __typename: String
        let name: String
    }
}
```

Note that a monomorphic object might be polymorphic in it's GraphQL type.
Consider a selection on an interface:

```graphql
{
    node {
        id
    }
}
```

```swift
struct Node {
    let id: ID
    let __typename: String // This can vary!
}
```

## Polymorphic
Monomorphic types are simple and easy to work with, but often times the fields included in an object returned by GraphQL might vary.
If an object **might not** have the same fields, then swiftui-graphql generates a polymorphic object.

Polymorphic objects are defined by the **discriminated types** that any fragments are conditional on.
They can be any GraphQL compound type, so a concrete object, interface or union.

There are then two kinds of polymorphic objects that can be generated.

### Disjoint polymorphic

If discriminated types are considered **disjoint**, then swiftui-graphql generates an enum.
Since none of the types are subtypes of the others, the result can only ever conform to one of the disjointed types at a time.


```graphql
{
    node {
        ... on Album { ... }
        ... on Artist { ... }
        ... on Track { ... }
    }
}
```

```swift
enum Node {
    case album(Album)
    struct Album { ... }
    case artist(Artist)
    struct Artist { ... }
    case track(Track)
    struct Track { ... }
    case __other(__Other)
    struct __Other { ... }
}
```

Note that an `__other` case gets generated with an `__Other` type which contains all the unconditionally included fields.
It's always possible that the server will return a type not specified in the interface.

### Intersecting polymorphic

However, if the types are not disjoint, then the underlying object could conform to multiple to types simulatneously, so we can't generate an enum.
Instead swiftui-graphql will generate a struct with optional fields for each discriminated type.
```swift

struct Node {
    let __c: C?
    struct C { }
    let __b: B?
    struct B { }
    let __a: A?
    struct A { }
    init(from decoder: Decoder) {
        switch typename {
        case "c":
            self.c = C(from: decoder)
            self.a = A(from: decoder)
            self.b = B(from: decoder)
        case "???":
            self.a = A(from: decoder)
            self.b = nil
            self.c = nil
        case "???":
            self.a = nil
            self.b = B(from: decodeR)
            self.c = nil
        }
    }
}
```

You might be wondering why we don't just generate a protocol and make a field of type `let node: any NodeProtocol`.
It's because if the protocol conforms to a fragment protocol, it might then have an associated type (see below).
But because the field is an existential type, existential types + associated types severely restricts their use and prevents you from doing things like pattern matching on them etc.

# Fragments
For fragments, `swiftui-graphql` will generate a protocol that the underlying concrete types will conform to.

Again like objects, there are two flavours, monomorphic and polymorphic.

## Monomorphic

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

Then a second protocol will be generated and an `associatedtype` will be added to the fragment protocol:

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

## Polymorphic

For polymorphic fragments, each underlying concrete

```graphql
interface A implements Node {}
interface B implements Node {}
object C implements A, B {}

fragment F on Node {
    ... on A {}
    ... on B {}
    ... on C {}
}
```

```swift
protocol ContainsFFragment {
    associatedtype A: FFragmentA
    associatedtype B: FFragmentB
    var __fFragment: FFragment<A, B, C> { get }
}
enum FFragment<A: FFragmentA, B: FFragmentB, C: FFragmentC> {
    case a(A)
    case b(B)
    enum A {
        case c(C)
        case __other(A)
    }
    enum B {
        case c(C)
        case __other(B)
    }
}

protocol FFragmentB

```
