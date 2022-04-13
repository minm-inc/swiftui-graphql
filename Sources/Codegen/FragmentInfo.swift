import GraphQL
/// A container that holds useful information about the fragments in a ``GraphQL/Document``
class FragmentInfo {
    let selections: [String: MergedSelection]
    let conformanceGraph: [FragmentPath: ProtocolConformance]
    
    init(fragmentDefinitions: [FragmentDefinition], schema: GraphQLSchema) {
        self.selections = fragmentDefinitions.reduce(into: [:]) { (acc, def) in
            let type = schema.typeMap[def.typeCondition.name.value]!
            let unmergedSelections = makeUnmergedSelections(
                selectionSet: def.selectionSet,
                parentType: type,
                schema: schema,
                fragments: fragmentDefinitions
            )
            acc[def.name.value] = merge(unmergedSelections: unmergedSelections, type: type, schema: schema)
        }
        self.conformanceGraph = ProtocolConformance.buildConformanceGraph(fragmentSelections: self.selections)
    }
    
    /// Returns the underlying ``MergedSelection`` for the path
    func selection(for path: FragmentPath) -> MergedSelection {
        var nestedObj = selections[path.fragmentName]!
        for nestedKey in path.nestedObjects {
            if let field = nestedObj.fields[nestedKey.firstLowercased] {
                nestedObj = field.nested!
            } else if let conditional = nestedObj.conditionals[nestedKey] {
                nestedObj = conditional
            } else {
                fatalError()
            }
        }
        return nestedObj
    }
    
    /// Given a ``FragmentPath``, returns the type that would correspond to it e.g. `FooFragment<A, B>`
    func makeUnderlyingFragmentEnumType(path: FragmentPath) -> DeclType {
        .named(
            path.fullyQualifiedName,
            genericArguments: selection(for: path).conditionals.keys.map { .named($0) }
        )
    }

}
