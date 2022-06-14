import GraphQL
/// A container that holds useful information about the fragments in a ``GraphQL/Document``
class FragmentInfo {
    let objects: [String: MergedObject]
    let conformanceGraph: [FragmentProtocolPath: ProtocolConformance]
    let definitions: [FragmentDefinition]
    
    init(fragmentDefinitions: [FragmentDefinition], schema: GraphQLSchema) {
        self.definitions = fragmentDefinitions
        self.objects = fragmentDefinitions.reduce(into: [:]) { (acc, def) in
            let type = schema.typeMap[def.typeCondition.name.value]! as! (any GraphQLCompositeType)
            let unmergedSelections = makeUnmergedSelections(
                selectionSet: def.selectionSet,
                parentType: type,
                schema: schema,
                fragments: fragmentDefinitions
            )
            acc[def.name.value] = merge(unmergedSelections: unmergedSelections, type: type, schema: schema)
        }
        self.conformanceGraph = ProtocolConformance.buildConformanceGraph(fragmentObjects: self.objects, schema: schema)
    }
    
    /// Returns the underlying ``MergedObject.Selection`` for the ``FragmentPath``
    func selection(for path: FragmentProtocolPath) -> MergedObject.Selection {
        var obj: MergedObject? = objects[path.fragmentName]!
        var selection: MergedObject.Selection = obj!.unconditional
        for component in path.components {
            switch component {
            case .nested(let key):
                obj = selection.fields[key]!.nested!
                selection = obj!.unconditional
            case .type(let type):
                selection = obj!.conditional[AnyGraphQLCompositeType(type)]!
                obj = nil
            }
        }
        return selection
    }
    
    /// Returns the ``MergedObject`` for the ``FragmentPath``.
    ///
    /// Note this will trap if the path doesn't lead to an object, i.e. ``FragmentPath``s that lead to a conditional selection
    func object(for path: FragmentProtocolPath) -> MergedObject {
        var obj = objects[path.fragmentName]!
        var iterator = path.components.makeIterator()
        while let component = iterator.next() {
            switch component {
            case .nested(let key):
                obj = obj.unconditional.fields[key]!.nested!
            case .type(let type):
                guard case .nested(let key) = iterator.next() else { fatalError("FragmentPath \(path) doesn't lead to an object") }
                obj = obj.conditional[AnyGraphQLCompositeType(type)]!.fields[key]!.nested!
            }
        }
        return obj
    }
    
    
    /// Given a ``FragmentPath``, returns the type that would correspond to it e.g. `FooFragment<A, B>`
    func makeUnderlyingFragmentEnumType(path: FragmentProtocolPath) -> DeclType {
        assert(path.isContainer)
        return .named(
            path.containerEnumName,
            genericArguments: object(for: path).conditional.keys.map { .named($0.type.name) }
        )
    }

}
