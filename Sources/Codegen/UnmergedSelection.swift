import OrderedCollections
import GraphQL
import SwiftUIGraphQL

/// A relatively simple compilation that just looks up fragments from a list of them.
enum UnmergedSelection {
    case field(Field)
    struct Field {
        let name: String
        let alias: String?
        let arguments: OrderedDictionary<String, NonConstValue>
        let type: any GraphQLOutputType
        let selections: [UnmergedSelection]
    }
    case fragment(Fragment)
    struct Fragment {
        let name: String?
        let type: any GraphQLCompositeType
        let selections: [UnmergedSelection]
    }
}

func makeUnmergedSelections(selectionSet: SelectionSet, parentType: any GraphQLNamedType, schema: GraphQLSchema, fragments: [FragmentDefinition]) -> [UnmergedSelection] {
    let fragmentMap = [Name: [FragmentDefinition]](grouping: fragments) { $0.name }.mapValues { $0.first! }
    return makeUnmergedSelections(selectionSet: selectionSet, parentType: parentType, schema: schema, fragmentMap: fragmentMap)
}

private func makeUnmergedSelections(selectionSet: SelectionSet, parentType: any GraphQLNamedType, schema: GraphQLSchema, fragmentMap: [Name: FragmentDefinition]) -> [UnmergedSelection] {
    selectionSet.selections.map { selection in
        switch selection {
        case let .field(field):
            let fieldDef = getFieldDef(schema: schema, parentType: underlyingType(parentType), fieldAST: field)!
            let selections: [UnmergedSelection]
            if let selectionSet = field.selectionSet {
                selections = makeUnmergedSelections(
                    selectionSet: selectionSet,
                    parentType: underlyingType(fieldDef.type),
                    schema: schema,
                    fragmentMap: fragmentMap
                )
            } else {
                selections = []
            }
            return .field(.init(
                name: field.name.value,
                alias: field.alias?.value,
                arguments: field.arguments.reduce(into: [:], {
                    $0[$1.name.value] = graphqlValueToSwiftUIGraphQLValue($1.value)
                }),
                type: fieldDef.type,
                selections: selections
            ))
        case let .fragmentSpread(fragmentSpread):
            let fragment = fragmentMap[fragmentSpread.name]!
            let type = schema.getType(name: fragment.typeCondition.name.value)! as! (any GraphQLCompositeType)
            return .fragment(.init(
                name: fragment.name.value,
                type: type,
                selections: makeUnmergedSelections(
                    selectionSet: fragment.selectionSet,
                    parentType: type,
                    schema: schema,
                    fragmentMap: fragmentMap
                )
            ))
        case let .inlineFragment(inlineFragment):
            let type: any GraphQLCompositeType
            if let typeCondition = inlineFragment.typeCondition {
                type = schema.getType(name: typeCondition.name.value)! as! any GraphQLCompositeType
            } else {
                type = underlyingType(parentType) as! any GraphQLCompositeType
            }
            return .fragment(.init(
                name: nil,
                type: type,
                selections: makeUnmergedSelections(
                    selectionSet: inlineFragment.selectionSet,
                    parentType: type,
                    schema: schema,
                    fragmentMap: fragmentMap
                ))
            )
        }
    }
}

private func graphqlValueToSwiftUIGraphQLValue(_ x: GraphQL.Value) -> NonConstValue {
    switch x {
    case .booleanValue(let x):
        return .boolean(x.value)
    case .enumValue(let x):
        return .enum(x.value)
    case .intValue(let x):
        return .int(Int(x.value)!)
    case .stringValue(let x):
        return .string(x.value)
    case .floatValue(let x):
        return .float(Double(x.value)!)
    case .objectValue(let x):
        return .object(x.fields.reduce(into: [:]) {
            $0[ObjectKey($1.name.value)] = graphqlValueToSwiftUIGraphQLValue($1.value)
        })
    case .listValue(let x):
        return .list(x.values.map(graphqlValueToSwiftUIGraphQLValue))
    case .nullValue:
        return .null
    case .variable(let x):
        return .variable(x.name.value)
    }
}
