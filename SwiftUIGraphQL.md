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

