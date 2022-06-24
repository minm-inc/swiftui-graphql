# ``SwiftUIGraphQL``

A type-safe GraphQL client for SwiftUI with a normalized cache.

```swift
struct MyView: View {
    @Query var query: GraphQLResult<AlbumQuery>
    var body: some View {
        if let user = query.data {
            Text("Hello \(user.name)")
        }
    }
}
```

SwiftUIGraphQL is a GraphQL client designed for declarative data fetching, and works alongside declarative UIs written with SwiftUI.

It features two main components:

**Code generation** that produces Swift type for your queries, mutations and fragments, so that you get compile-time type-safety whilst using your schema.
It generates *fragments as protocols*, which means that you can write generic views based off of fragments without the need for any existential types:

```swift
struct UserBadge<Fragment: UserBadgeFragment>: View {
    let user: Fragment
    var body: some View {
        VStack {
            AsyncImage(url: user.avatar)
            Text(user.name)
        }
    }
}
```

**A client library**, SwiftUIGraphQL, that lets you easily build views in SwiftUI that are automatically kept up to date with your queries.

## Installation
TODO
