import OrderedCollections
import GraphQL
import SwiftUIGraphQL

/// Represents an object at the transport level, and the fields it may contain.
///
/// A ``MergedObject`` is created from resolving any fragments that are included in a selection with ``merge(unmergedSelections:type:schema)``
/// It is a one to one mapping with an object at the transport level.
///
/// The fields it contains and the fragments it conforms to are split into two types: ``unconditional`` and ``conditional``.
///
/// Unconditional fields will always be present on the object no matter the underlying GraphQL type of the object that is returned, and likewise so will the fragment conformances.
/// 
/// Conditional fields on the other hand will only be present whenever the object is a certain type.
/// This happens whenever we are selecting a `GraphQLAbstractType` and include a fragment, inline or otherwise, that has a type condition.
///
/// If a ``MergedObject`` contains conditional fields/fragment conformances, then it is considered **polymorphic**. See ``MergedObject.isMonomorphic``
struct MergedObject: CustomDebugStringConvertible {
    var unconditional: Selection
    var conditional: OrderedDictionary<AnyGraphQLCompositeType, Selection>
    let type: any GraphQLCompositeType
    // Map from framgment name to conformance
    var fragmentConformances: OrderedDictionary<String, FragmentConformance>
    
    enum FragmentConformance: Equatable {
        static func == (lhs: MergedObject.FragmentConformance, rhs: MergedObject.FragmentConformance) -> Bool {
            switch (lhs, rhs) {
            case (.unconditional, .unconditional): return true
            case (.conditional(let x), .conditional(let y)): return x === y
            default: return false
            }
        }
        
        case unconditional, conditional(any GraphQLCompositeType)
    }
    
    var debugDescription: String {
        [
            "\(type.name)@ {",
            unconditional.debugDescription.indented(),
            conditional.map { type, selection in
                "... on \(type.type.name) {\n" + selection.debugDescription.indented() + "\n}"
            }.joined(separator: "\n").indented(),
            "\n} conforms to \(fragmentConformances.keys.joined(separator: ", "))"
        ].joined(separator: "\n")
    }
    
    struct Selection: CustomDebugStringConvertible {
        typealias Arguments = OrderedDictionary<String, NonConstValue>
        typealias Field = SelectionField<Arguments, MergedObject, any GraphQLOutputType>
        var fields: OrderedDictionary<String, Field>
//        var fragmentConformances: OrderedSet<String>
        
        mutating func merge(_ incoming: Selection, ignoringFragments: Bool = false) {
            merge(incoming.fields, into: &fields)
//            if !ignoringFragments {
//                fragmentConformances.formUnion(incoming.fragmentConformances)
//            }
        }
        
        var debugDescription: String {
            fields.map { key, field in
                var s = field.type.debugDescription
                if let nested = field.nested {
                    s += " -> " + nested.debugDescription
                }
                return "\(key): \(s)"
            }.joined(separator: "\n")
        }
        
        private func merge(_ incoming: OrderedDictionary<String, Field>, into existing: inout OrderedDictionary<String, Field>) {
            for (k, v) in incoming {
                if existing.keys.contains(k) {
                    merge(v, into: &existing[k]!)
                } else {
                    existing[k] = v
                }
            }
        }
        
        private func merge(_ incoming: Field, into existing: inout Field) {
            assert(incoming.name == existing.name)
            assert(incoming.arguments == existing.arguments)
            assert((incoming.nested != nil) == (existing.nested != nil))
            existing.nested?.merge(incoming.nested!)
        }
        
        static var empty = Selection(fields: [:])
    }
    
    static func empty(type: any GraphQLCompositeType) -> MergedObject {
        MergedObject(
            unconditional: Selection(
                fields: [:]
            ),
            conditional: [:],
            type: type,
            fragmentConformances: [:]
        )
    }
    
    /// Whether or not any of the possible conditional types that this object may be overlap with each other.
    ///
    /// Basically, if this returns false then the object will only ever be of one of the possible conditional types at a time
    func arePossibleTypesDisjoint(schema: GraphQLSchema) -> Bool {
        for type in conditional.keys {
            let otherTypes = conditional.keys.filter { $0 != type }
            let anySubTypes = otherTypes.contains { schema.isSubType(abstractType: type.type, maybeSubType: $0.type) }
            if anySubTypes {
                return false
            }
        }
        return true
    }
    
    /// Merge in a field which you know is always going to be present, no matter the type of the object.
    mutating func merge(unconditionalField field: MergedObject.Selection.Field, key: String) {
        let selection = Selection(fields: [key: field])
        unconditional.merge(selection)
        for typename in conditional.keys {
            conditional[typename]!.merge(selection)
        }
    }
    
    /// Merge in another object.
    mutating func merge(_ incoming: MergedObject) {
        unconditional.merge(incoming.unconditional)
        
        for (type, condSelection) in incoming.conditional {
            var condSelection = condSelection
            condSelection.merge(unconditional)
            if conditional.keys.contains(type) {
                conditional[type]!.merge(condSelection)
            } else {
                conditional[type] = condSelection
            }
        }
        
        // Conditionals should contain all the unconditional fields,
        // i.e. be a superset of fields
        // So merge the incoming unconditional selection into the conditional selections
        // Don't merge the fragments though!
        // TODO: Set this up so that eventually we generate discriminated types that do conform to all the fragments that their container type conforms to
        for k in conditional.keys {
            conditional[k]!.merge(incoming.unconditional, ignoringFragments: true)
        }
    }
    
    /// Mark this obejct as **unconditionally** conforming to this fragment
//    mutating func conform(toFragment fragmentName: String) {
//        unconditional.fragmentConformances.append(fragmentName)
//        for typename in conditional.keys {
//            conditional[typename]!.fragmentConformances.append(fragmentName)
//        }
//    }
    
    /// Whether or not this object is monomorphic, i.e. are all the fields unconditional
    var isMonomorphic: Bool {
        conditional.isEmpty
    }
    
    /// Returns the field that would be returned on `typename` for the key  `key`, if it exists on this selection.
    subscript(key: String, onType type: any GraphQLCompositeType) -> Selection.Field? {
        if let conditional = conditional[AnyGraphQLCompositeType(type)] {
            return conditional.fields[key]
        }
        return unconditional.fields[key]
    }
    
    /// Returns all the possible keys that can be returned for this object (*not* the nested keys)
    func selectedKeys() -> OrderedSet<String> {
        var selectedKeys = unconditional.fields.keys
        for (_, conditional) in conditional {
            selectedKeys.formUnion(conditional.fields.keys)
        }
        return selectedKeys
    }
}


func merge(unmergedSelections: [UnmergedSelection], type: any GraphQLCompositeType, schema: GraphQLSchema) -> MergedObject {
    let object = SelectionMerger(schema: schema).go(selections: unmergedSelections, type: type)
    if !object.arePossibleTypesDisjoint(schema: schema) {
        fatalError("""
        Possible object types are not disjoint: \(object.conditional.keys)
        swiftui-graphql doesn't know how to generate types for these selections yet
        """)
    }
    // If this is a concrete object type we are merging then there should be no conditional types
    if type is GraphQLObjectType {
        assert(object.conditional.isEmpty)
    }
    return object
}

private struct SelectionMerger {
    let schema: GraphQLSchema
    
    func go(selections: [UnmergedSelection], type: any GraphQLCompositeType) -> MergedObject {
        
        return selections.reduce(into: .empty(type: type)) { acc, selection in
            switch selection {
            case let .field(field):
                let key = field.alias ?? field.name
                let field = MergedObject.Selection.Field(
                    name: FieldName(field.name),
                    arguments: field.arguments,
                    type: field.type,
                    nested: field.selections.isEmpty ? nil : go(
                        selections: field.selections,
                        type: underlyingType(field.type) as! any GraphQLCompositeType
                    )
                )
                acc.merge(unconditionalField: field, key: key)
            case let .fragment(fragment):
                var nested = go(selections: fragment.selections, type: fragment.type)
                
                if try! isTypeSubTypeOf(schema, type, underlyingType(fragment.type)) {
                    // The fragment will always match because the object type is a subtype of the fragment type
                    // so flatten these selections since they'll always be included unconditionally
                    
                    // Remove unnecessary conditionals that will never match
                    let irrelevantTypes = nested.conditional.keys.filter {
                        try! !isTypeSubTypeOf(schema, $0.type, type)
                    }
                    for irrelevantType in irrelevantTypes {
                        nested.conditional.removeValue(forKey: irrelevantType)
                    }
                    
                    if type is GraphQLObjectType {
                        // If this type is a concrete type then we can directly merge in the conditional/unconditional fields
                        let concreteSelection = nested.conditional[AnyGraphQLCompositeType(type)] ?? nested.unconditional
                        acc.unconditional.merge(concreteSelection)
                    } else {
                        // Otherwise we also need to merge in the fragment's conditionals
                        acc.merge(nested)
                    }
                    
                    if let fragmentName = fragment.name {
                        acc.fragmentConformances[fragmentName] = .unconditional
                    }
                } else {
                    // Otherwise it is conditional and may or may not be included in the result

                    // If the fragment is on a concrete object then we can copy over the unconditionals to a conditional on said fragment type
                    if fragment.type is GraphQLObjectType {
                        nested.conditional[AnyGraphQLCompositeType(fragment.type)] = nested.unconditional
                    }
                    // The unconditional selections don't apply here
                    nested.unconditional = MergedObject.Selection(fields: [:])
                    
                    if let fragmentName = fragment.name {
                        acc.fragmentConformances[fragmentName] = .conditional(fragment.type)
                    }
                    
                    acc.merge(nested)
                }
            }
        }
    }

}

extension String {
    func indented(by spaces: Int = 2) -> String {
        split(separator: "\n")
            .map { Array(repeating: " ", count: spaces) + $0}
            .joined(separator: "\n")
    }
}
