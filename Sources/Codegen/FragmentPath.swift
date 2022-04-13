import OrderedCollections

/// An identifier for a protocol conformance to a fragment, or one of the nested objects within the fragment.
///
/// It doesn't actually contain any information about the fragment itself. Use ``FragmentInfo`` to extract it.
struct FragmentPath: Hashable {
    let fragmentName: String
    var nestedObjects: [String] = []
    
    var fullyQualifiedName: String {
        fragmentName + "Fragment" + nestedObjects.map(\.firstUppercased).joined()
    }
    
    func appending(nestedObject name: String) -> FragmentPath {
        var res = self
        res.nestedObjects.append(name)
        return res
    }
}
