import SwiftUI

@MainActor
public class FragmentWatcher<Fragment: Cacheable>: ObservableObject {
    @Published public private(set) var fragment: Fragment
    private var watchTask: Task<Void, any Error>?
    public init(fragment: Fragment, graphqlClient: GraphQLClient? = nil) {
        self.fragment = fragment
        let selection = Fragment.selection.assumingNoVariables
        if let graphqlClient {
            watchTask = Task {
                for await change in await graphqlClient.cache.listenToChanges(selection: selection,
                                                                              on: CacheKey.object(typename: fragment.__typename, id: fragment.id)) {
                    if let change {
                        self.fragment = try! ValueDecoder(scalarDecoder: graphqlClient.scalarDecoder).decode(Fragment.self, from: .object(change))
                    }
                }
            }
        }
    }
    deinit {
        watchTask?.cancel()
    }
}
