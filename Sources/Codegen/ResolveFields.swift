//
//  ResolveFields.swift
//  
//
//  Created by Luke Lau on 16/12/2021.
//

import Collections
import GraphQL

enum ResolvedField {
    case leaf(GraphQLOutputType)
    case nested(GraphQLOutputType, unconditional: ResolvedFieldMap, conditional: [String: ResolvedFieldMap], fragmentConformances: Set<String>)
    
//    typealias FragmentConformance = (String, [String])
}

/// This is essentially a map that will mirror the structs generated in codegen, computed from the AST.
/// Note that it's important it uses an ``OrderedDictionary``, otherwise the struct properties will get generated in an unstable order, and then initializer function signatures will upredictably change each time code generation is run.
typealias ResolvedFieldMap = OrderedDictionary<String, ResolvedField>


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
func resolveFields(selectionSet: SelectionSet, parentType: GraphQLNamedType, schema: GraphQLSchema, fragments: [FragmentDefinition]) -> (ResolvedFieldMap, [String: ResolvedFieldMap], Set<String>) {
    
    func makeResolvedField(field: Field) -> ResolvedField {
        let fieldDef = getFieldDef(schema: schema, parentType: parentType, fieldAST: field)!
        let type = fieldDef.type
        if let selectionSet = field.selectionSet {
            let (unconditional, conditional, fragmentConformances) = resolveFields(selectionSet: selectionSet, parentType: underlyingType(type), schema: schema, fragments: fragments)
            return .nested(
                type,
                unconditional: unconditional,
                conditional: conditional,
                fragmentConformances: fragmentConformances
            )
        } else {
            return .leaf(type)
        }
    }
    
    let fragmentMap = [Name: [FragmentDefinition]](grouping: fragments) { $0.name }.mapValues { $0.first! }
    return selectionSet.selections.reduce(([:], [:], Set())) { acc, selection in
        
        func handleFragment(selectionSet: SelectionSet, on fragmentType: GraphQLNamedType, named fragmentName: String? = nil) -> (ResolvedFieldMap, [String: ResolvedFieldMap], Set<String>) {
            var (unconditional, conditional, fragmentConformances) = resolveFields(selectionSet: selectionSet, parentType: fragmentType, schema: schema, fragments: fragments)
            var newFragmentConformances = acc.2.union(fragmentConformances)
            if let fragmentName = fragmentName {
                let baseProtocolName = fragmentName + "Fragment"
                unconditional = attachFragmentNestedConformances(unconditional, fragmentName: baseProtocolName)
                conditional = conditional.mapValues { attachFragmentNestedConformances($0, fragmentName: baseProtocolName) }
                newFragmentConformances.insert(baseProtocolName)
            }
            if try! isTypeSubTypeOf(schema, parentType, fragmentType) {
                // This fragment spread will always match, so count merge the unconditionals together
                return (
                    mergeResolvedFieldMaps(acc.0, unconditional),
                    acc.1.merging(conditional, uniquingKeysWith: mergeResolvedFieldMaps),
                    newFragmentConformances
                )
            } else {
                var oldConditionalMap = conditional[fragmentType.name] ?? [:]
                oldConditionalMap.merge(unconditional, uniquingKeysWith: mergeResolvedFields)
                conditional[fragmentType.name] = oldConditionalMap
                return (
                    acc.0,
                    acc.1.merging(conditional, uniquingKeysWith: mergeResolvedFieldMaps),
                    newFragmentConformances
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
                type = parentType
            }
            return handleFragment(selectionSet: inlineFragment.selectionSet, on: type)
        }
    }
}

func mergeResolvedFieldMaps(_ a: ResolvedFieldMap, _ b: ResolvedFieldMap) -> ResolvedFieldMap {
    a.merging(b, uniquingKeysWith: mergeResolvedFields)
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
    case let (.nested(atype, aunconditional, aconditional, aFragmentConfrmances), .nested(btype, bunconditional, bconditional, bFragmentConformances)):
        if !isEqualType(atype, btype) {
            fatalError("Merging two fields with the same key but different types")
        }
        return .nested(
            atype,
            unconditional: aunconditional.merging(bunconditional, uniquingKeysWith: mergeResolvedFields),
            conditional: aconditional.merging(bconditional, uniquingKeysWith: mergeResolvedFieldMaps),
            fragmentConformances: aFragmentConfrmances.union(bFragmentConformances)
        )
    }
}

private func attachFragmentNestedConformances(_ map: ResolvedFieldMap, fragmentName: String) -> ResolvedFieldMap {
    var res: ResolvedFieldMap = [:]
    for (name, field) in map {
        switch field {
        case let .leaf(x):
            res[name] = .leaf(x)
        case let .nested(type, unconditional, conditional, fragmentConformances):
            let conformance = fragmentName + name.firstUppercased
            res[name] = .nested(
                type,
                unconditional: attachFragmentNestedConformances(unconditional, fragmentName: conformance),
                conditional: conditional.reduce(into: [:]) { acc, x in
                    let (typeName, fieldMap) = x
                    acc[typeName] = attachFragmentNestedConformances(
                        fieldMap,
                        fragmentName: conformance + typeName
                    )
                },
                fragmentConformances: fragmentConformances.union([conformance])
            )
        }
    }
    return res
}

extension String {
    var firstUppercased: String { prefix(1).uppercased() + dropFirst() }
}
