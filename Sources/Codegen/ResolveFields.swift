//
//  ResolveFields.swift
//  
//
//  Created by Luke Lau on 16/12/2021.
//

import GraphQL
import SwiftUIGraphQL
import OrderedCollections

// TODO: Replace this pass with another pass that feeds in from resolveselections
enum ResolvedField {
    case leaf(GraphQLOutputType)
    case nested(Object)
    
    struct Object {
        let type: GraphQLOutputType
        let unconditional: ResolvedFieldMap
        let conditional: OrderedDictionary<GraphQLTypeName, Object>
        let fragProtos: OrderedDictionary<FragmentQualifier, ProtocolInfo>
        typealias GraphQLTypeName = String
        
        func conformsTo(fragmentName: FragmentQualifier) -> Bool {
            func go(fragProtos: OrderedDictionary<FragmentQualifier, ProtocolInfo>) -> Bool {
                fragProtos.contains { qualifier, info in
                    if qualifier == fragmentName {
                        return true
                    } else {
                        return go(fragProtos: info.alsoConformsTo)
                    }
                }
            }
            return go(fragProtos: fragProtos)
        }
        
        func anyFragmentsInHierarchyDeclareField(fieldName: String) -> FragmentQualifier? {
            declaresField(fieldName: fieldName, in: fragProtos)
        }
        
        private func declaresField(fieldName: String, in fragmentInfos: OrderedDictionary<FragmentQualifier, ProtocolInfo>) -> FragmentQualifier? {
            for (qualifier, info) in fragmentInfos {
                if info.declaredFields.contains(fieldName) {
                    return qualifier
                } else if let qualifier = declaresField(fieldName: fieldName, in: info.alsoConformsTo) {
                    return qualifier
                }
            }
            return nil
        }
    }
}

typealias ResolvedFieldMap = OrderedDictionary<String, ResolvedField>

indirect enum FragmentQualifier: Hashable {
    case base(String)
    case nested(FragmentQualifier, String)
    
    var protocolName: String {
        switch self {
        case let .base(s):
            return s.firstUppercased + "Fragment"
        case let .nested(parent, s):
            return parent.protocolName + s.firstUppercased
        }
    }
}
struct ProtocolInfo: Hashable {
    let possibleTypes: OrderedSet<String>
    let declaredFields: OrderedSet<String>
    let alsoConformsTo: OrderedDictionary<FragmentQualifier, ProtocolInfo>
    let isConditional: Bool
}

/// This is essentially a map that will mirror the concrete structs and enums generated in codegen, computed from the AST.
/// Note that it's important it uses an ``OrderedDictionary``, otherwise the struct properties will get generated in an unstable order, and then initializer function signatures will upredictably change each time code generation is run.
//struct ResolvedFieldMap {
//    let fields: OrderedDictionary<String, ResolvedField>
//    let fragmentConformances: Set<String>
//
//    func merging(_ other: ResolvedFieldMap) -> ResolvedFieldMap {
//        ResolvedFieldMap(
//            fields: fields.merging(other.fields, uniquingKeysWith: mergeResolvedFields),
//            fragmentConformances: fragmentConformances.union(other.fragmentConformances)
//        )
//    }
//
//    static let empty = ResolvedFieldMap(fields: [:], fragmentConformances: [])
//}


/** Given a query with a ``SelectionSet`` like this
 
 ```
 { # on Node
    foo
    ...bar
    ... on Baz {
        qux
    }
 }
 fragment bar on Bar {
    x
    ...bar2
 }
 fragment bar2 on Bar {
    y
 }
 ```
 
 We need to be able to work out what the resulting data structure returned from the server will look like – i.e. what fields will it include whenever you include all fragments.
 ``resolveFields``s does this, by reaching in and resolving every fragment.
 
 It returns two maps of fields, one where the fields are always guaranteed to be included *unconditionally*, and another where the fields are *conditionally* included on specific underlying types.
 */
func resolveFields(selectionSet: SelectionSet, parentType: GraphQLOutputType, schema: GraphQLSchema, fragments: [FragmentDefinition], expandFragments: Bool = true) -> ResolvedField.Object {
    
    func makeResolvedField(field: Field) -> ResolvedField {
        let fieldDef = getFieldDef(schema: schema, parentType: underlyingType(parentType), fieldAST: field)!
        let type = fieldDef.type
        if let selectionSet = field.selectionSet {
            let object = resolveFields(selectionSet: selectionSet, parentType: type, schema: schema, fragments: fragments)
            return .nested(object)
        } else {
            return .leaf(type)
        }
    }
    
    let fragmentMap = [Name: [FragmentDefinition]](grouping: fragments) { $0.name }.mapValues { $0.first! }
    typealias Accumulator = (ResolvedFieldMap, OrderedDictionary<String, ResolvedField.Object>, OrderedDictionary<FragmentQualifier, ProtocolInfo>)
    let (unconditional, conditional, fragProtos) = selectionSet.selections.reduce(([:], [:], [:])) { (acc: Accumulator, selection) in
        
        func handleFragment(selectionSet: SelectionSet, on fragmentType: GraphQLNamedType, named fragmentName: String? = nil) -> Accumulator {
            // All these fields that we're going to include: we need to now attach the corresponding nested-object-protocols to them
            let object = resolveFields(selectionSet: selectionSet, parentType: fragmentType as! GraphQLOutputType, schema: schema, fragments: fragments, expandFragments: expandFragments)

            if try! isTypeSubTypeOf(schema, underlyingType(parentType), fragmentType) {
                // This fragment spread will always match, so merge the unconditionals together
                
                // If it has a name, then this object will always conform to said fragment (and anything that fragment conforms to)

                var newFragProtos = acc.2
                if let fragmentName = fragmentName {
                    let qualifier = FragmentQualifier.base(fragmentName)
                    let fragmentInfo = ProtocolInfo(
                        possibleTypes: object.conditional.keys,
                        declaredFields: object.unconditional.keys,
                        alsoConformsTo: object.fragProtos,
                        isConditional: !object.conditional.isEmpty
                    )
                    newFragProtos[qualifier] = fragmentInfo
                }
                
                if expandFragments {
                    return (
                        mergeResolvedFieldMaps(acc.0, object.unconditional),
                        acc.1.merging(object.conditional, uniquingKeysWith: mergeObjects),
                        newFragProtos
                    )
                } else {
                    return (acc.0, acc.1, newFragProtos)
                }
            } else {
                // This fragment is conditional: it will only include the fields if the type matches
                // So merge in a conditional match for the fragments object, on the fragments type constraint
                
                var newObjectFragProtos = object.fragProtos
                if let fragmentName = fragmentName {
                    let qualifier = FragmentQualifier.base(fragmentName)
                    let fragmentInfo = ProtocolInfo(
                        possibleTypes: object.conditional.keys,
                        declaredFields: object.unconditional.keys,
                        alsoConformsTo: object.fragProtos,
                        isConditional: !object.conditional.isEmpty
                    )
                    newObjectFragProtos[qualifier] = fragmentInfo
                }
                let newObject = ResolvedField.Object(
                    type: object.type,
                    unconditional: object.unconditional,
                    conditional: object.conditional,
                    fragProtos: newObjectFragProtos
                )
                
                return (
                    acc.0,
                    acc.1.merging([fragmentType.name: newObject], uniquingKeysWith: mergeObjects),
                    acc.2
                )
            }
        }
        
        switch selection {
        case let .field(field):
            let name = (field.alias ?? field.name).value
            let toMerge: ResolvedFieldMap = [name: makeResolvedField(field: field)]
            return (mergeResolvedFieldMaps(acc.0, toMerge), acc.1, acc.2)
            
        case let .fragmentSpread(fragmentSpread):
            let fragment = fragmentMap[fragmentSpread.name]!
            let type = schema.getType(name: fragment.typeCondition.name.value)!
            return handleFragment(selectionSet: fragment.selectionSet, on: type, named: fragment.name.value)
        case let .inlineFragment(inlineFragment):
            let type: GraphQLNamedType
            if let typeCondition = inlineFragment.typeCondition {
                type = schema.getType(name: typeCondition.name.value)!
            } else {
                type = underlyingType(parentType)
            }
            return handleFragment(selectionSet: inlineFragment.selectionSet, on: type)
        }
    }
    
    return ResolvedField.Object(
        type: parentType,
        unconditional: unconditional,
        conditional: conditional.mapValues(mergeObjectConditional(withUnconditional: unconditional)),
        fragProtos: fragProtos
    )
}

/// If we have some fields that are truly unconditional, this will merge them throughout all the object's conditional fields as well
private func mergeObjectConditional(withUnconditional unconditional: ResolvedFieldMap) -> (ResolvedField.Object) -> ResolvedField.Object {
    return { object in
        var x = object.unconditional
        for (fieldName, field) in unconditional {
            if let existingField = x[fieldName] {
                switch existingField {
                case .nested(let nestedObj):
                    guard case let .nested(foo) = field else { fatalError() }
                    x[fieldName] = .nested(mergeObjectConditional(withUnconditional: foo.unconditional)(nestedObj))
                case .leaf:
                    break
                }
            } else {
                x[fieldName] = field
            }
        }
        return ResolvedField.Object(
            type: object.type,
            unconditional: x,
            conditional: object.conditional.mapValues(mergeObjectConditional(withUnconditional: unconditional)),
            fragProtos: object.fragProtos
        )
    }
}

private func mergeResolvedFieldMaps(_ a: ResolvedFieldMap, _ b: ResolvedFieldMap) -> ResolvedFieldMap {
    a.merging(b, uniquingKeysWith: mergeResolvedFields)
}

private func mergeObjects(_ a: ResolvedField.Object, _ b: ResolvedField.Object) -> ResolvedField.Object {
    if !isEqualType(a.type, b.type) {
        fatalError("Merging two objects with different types")
    }
    let unconditional = mergeResolvedFieldMaps(a.unconditional, b.unconditional)
    let conditional = a.conditional.merging(b.conditional, uniquingKeysWith: mergeObjects).mapValues(mergeObjectConditional(withUnconditional: unconditional))
    let res = ResolvedField.Object(
        type: a.type,
        unconditional: unconditional,
        conditional: conditional,
        fragProtos: a.fragProtos.merging(b.fragProtos, uniquingKeysWith: mergeFragmentInfos)
    )
    assert(unconditionalsCoverConditionalUnconditionals(resolvedField: .nested(res)))
    return res
}

private func mergeResolvedFields(_ a: ResolvedField, _ b: ResolvedField) -> ResolvedField {
    switch (a, b) {
    case let (.leaf(typeA), .leaf(typeB)):
        guard isEqualType(typeA, typeB) else {
            fatalError("Can't merge two leaves with different types")
        }
        return .leaf(typeA)
    case (.leaf, .nested), (.nested, .leaf):
        fatalError("Mismatching leaf and nested types")
    case let (.nested(objectA), .nested(objectB)):
        return .nested(mergeObjects(objectA, objectB))
    }
}


private func mergeFragmentInfos(_ a: ProtocolInfo, _ b: ProtocolInfo) -> ProtocolInfo {
    ProtocolInfo(
        possibleTypes: a.possibleTypes.union(b.possibleTypes),
        declaredFields: a.declaredFields.union(b.declaredFields),
        alsoConformsTo: a.alsoConformsTo.merging(b.alsoConformsTo, uniquingKeysWith: mergeFragmentInfos),
        isConditional: a.isConditional || b.isConditional
    )
}

/**
 Annotates a `ResolveField.Object` with the
 */
func attachFragProtos(to object: ResolvedField.Object, fragment: FragmentDefinition, schema: GraphQLSchema, fragments: [FragmentDefinition]) -> ResolvedField.Object {
    let rootFragmentObject = resolveFields(
        selectionSet: fragment.selectionSet,
        parentType: schema.getType(name: fragment.typeCondition.name.value)! as! GraphQLOutputType,
        schema: schema,
        fragments: fragments,
        expandFragments: false
    )
    let fragmentBaseQualifier = FragmentQualifier.base(fragment.name.value)
    func attachFragProtos(to map: ResolvedFieldMap, qualifier: FragmentQualifier, fragmentObject: ResolvedField.Object) -> ResolvedFieldMap {
        var newMap: ResolvedFieldMap = [:]
        for (fieldName, field) in map {
            if case .nested(let fragmentObject) = fragmentObject.unconditional[fieldName],
               case .nested(let object) = field {
                
                var newFragProtos = object.fragProtos
                let newQualifier = FragmentQualifier.nested(qualifier, fieldName)
                newFragProtos[newQualifier] = ProtocolInfo(
                    possibleTypes: fragmentObject.conditional.keys,
                    declaredFields: fragmentObject.unconditional.keys,
                    alsoConformsTo: [:],
                    isConditional: !fragmentObject.conditional.isEmpty
                )
                newMap[fieldName] = .nested(ResolvedField.Object(
                    type: object.type,
                    unconditional: attachFragProtos(to: object.unconditional, qualifier: newQualifier, fragmentObject: fragmentObject),
                    conditional: attachFragProtos(to: object.conditional, qualifier: newQualifier, fragmentObject: fragmentObject),
                    fragProtos: newFragProtos
                ))
                
            } else {
                newMap[fieldName] = field
            }
        }
        return newMap
    }
    
    func attachFragProtos(to conditionalMap: OrderedDictionary<String, ResolvedField.Object>, qualifier: FragmentQualifier, fragmentObject: ResolvedField.Object) -> OrderedDictionary<String, ResolvedField.Object> {
        conditionalMap.reduce(into: [:]) { acc, x in
            if let condFragObj = fragmentObject.conditional[x.key] {
                let newQuali = FragmentQualifier.nested(qualifier, x.key)
                let object = attachFragProtos(to: x.value, qualifier: newQuali, fragmentObject: condFragObj)
                var newFragProtos = object.fragProtos
                newFragProtos[newQuali] = ProtocolInfo(
                    possibleTypes: object.conditional.keys,
                    declaredFields: object.unconditional.keys,
                    alsoConformsTo: object.fragProtos,
                    isConditional: false
                )
                acc[x.key] = ResolvedField.Object(
                    type: object.type,
                    unconditional: object.unconditional,
                    conditional: object.conditional,
                    fragProtos: newFragProtos
                )
            } else {
                acc[x.key] = x.value
            }
        }
    }
    
    func attachFragProtos(to object: ResolvedField.Object, qualifier: FragmentQualifier, fragmentObject: ResolvedField.Object) -> ResolvedField.Object {
        ResolvedField.Object(
            type: object.type,
            unconditional: attachFragProtos(to: object.unconditional, qualifier: qualifier, fragmentObject: fragmentObject),
            conditional: attachFragProtos(to: object.conditional, qualifier: qualifier, fragmentObject: fragmentObject),
            fragProtos: object.fragProtos
        )
    }
    
    func go(_ object: ResolvedField.Object) -> ResolvedField.Object {
        var res = object
        if res.conformsTo(fragmentName: fragmentBaseQualifier) {
            res = attachFragProtos(to: res, qualifier: fragmentBaseQualifier, fragmentObject: rootFragmentObject)
        }
        return ResolvedField.Object(
            type: res.type,
            unconditional: res.unconditional.mapValues { field in
                switch field {
                case .leaf:
                    return field
                case .nested(let object):
                    return .nested(go(object))
                }
            },
            conditional: res.conditional.mapValues(go),
            fragProtos: res.fragProtos
        )
    }
    
    return go(object)
}

extension String {
    var firstUppercased: String { prefix(1).uppercased() + dropFirst() }
    var firstLowercased: String { prefix(1).lowercased() + dropFirst() }
}

/// Useful for sanity checking that every object.conditional.unconditional is also included in the object.unconditional
func unconditionalsCoverConditionalUnconditionals(resolvedField: ResolvedField) -> Bool {
    switch resolvedField {
    case .leaf:
        return true
    case .nested(let object):
        let unconditionalKeys = Set(object.unconditional.keys)
        for conditional in object.conditional.values {
            if !unconditionalKeys.isSubset(of: conditional.unconditional.keys) {
                return false
            }
        }
        if !object.unconditional.values.allSatisfy(unconditionalsCoverConditionalUnconditionals) {
            return false
        }
        if !object.conditional.values.map({ .nested($0) }).allSatisfy(unconditionalsCoverConditionalUnconditionals) {
            return false
        }
        return true
    }
}
