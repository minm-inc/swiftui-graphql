import GraphQL
import SwiftUIGraphQL
func resolve(selectionSet: SelectionSet, parentType: GraphQLOutputType, schema: GraphQLSchema, fragments: [FragmentDefinition]) -> [ResolvedSelection<String>] {
    let fragmentMap = [Name: [FragmentDefinition]](grouping: fragments) { $0.name }.mapValues { $0.first! }
    
    func handleFragment(selectionSet: SelectionSet, on fragmentType: GraphQLNamedType, named fragmentName: String? = nil) -> [ResolvedSelection<String>] {
        if try! isTypeSubTypeOf(schema, underlyingType(parentType), fragmentType) {
            // This fragment spread will always match, so just return the unconditional fields
            return resolve(
                selectionSet: selectionSet,
                parentType: parentType,
                schema: schema,
                fragments: fragments
            )
        } else {
            // This fragment spread might not match, so use a fragment with a type condition
            return [.fragment(
                typeCondition: fragmentType.name,
                selections: resolve(
                    selectionSet: selectionSet,
                    parentType: fragmentType as! GraphQLOutputType,
                    schema: schema,
                    fragments: fragments
                )
            )]
        }
    }
    
    return selectionSet.selections.reduce(into: []) { acc, selection in
        switch selection {
        case let .field(field):
            let fieldDef = getFieldDef(schema: schema, parentType: underlyingType(parentType), fieldAST: field)!
            let selections: [ResolvedSelection<String>]
            if let selectionSet = field.selectionSet {
                selections = resolve(
                    selectionSet: selectionSet,
                    parentType: fieldDef.type,
                    schema: schema,
                    fragments: fragments
                )
            } else {
                selections = []
            }
            let selection = ResolvedSelection.field(.init(
                name: (field.alias ?? field.name).value,
                arguments: field.arguments.reduce(into: [:]) {
                    $0[$1.name.value] = graphqlValueToSwiftUIGraphQLValue($1.value)
                },
                type: graphqlTypeToSwiftUIGraphQLType(fieldDef.type),
                selections: selections
            ))
            merge(selection: selection, into: &acc)
        case let .fragmentSpread(spread):
            let fragment = fragmentMap[spread.name]!
            let type = schema.getType(name: fragment.typeCondition.name.value)!
            handleFragment(selectionSet: fragment.selectionSet, on: type, named: spread.name.value).forEach {
                merge(selection: $0, into: &acc)
            }
        case let .inlineFragment(fragment):
            let type: GraphQLNamedType
            if let typeCondition = fragment.typeCondition {
                type = schema.getType(name: typeCondition.name.value)!
            } else {
                type = underlyingType(parentType)
            }
            handleFragment(selectionSet: fragment.selectionSet, on: type).forEach {
                merge(selection: $0, into: &acc)
            }
        }
    }
}
    
private func merge(selection: ResolvedSelection<String>, into selections: inout [ResolvedSelection<String>]) {
    switch selection {
    case .field(let incoming):
        let possibleExisting: (Int, ResolvedSelection<String>.Field)? = selections.enumerated().compactMap({ (offset, element) in
            guard case .field(let existingField) = element, existingField.name == incoming.name else {
                return nil
            }
            return (offset, existingField)
        }).first
        if let (existingIndex, existing) = possibleExisting {
            let new = ResolvedSelection.Field(
                name: existing.name,
                arguments: existing.arguments,
                type: existing.type,
                selections: incoming.selections.reduce(into: existing.selections) { merge(selection: $1, into: &$0) }
            )
            selections[existingIndex] = .field(new)
        } else {
            selections.append(selection)
        }
    case let .fragment(incomingTypeCondition, incomingSelections):
        let possibleExisting: (Int, String, [ResolvedSelection<String>])? = selections.enumerated().compactMap({ (offset, element) in
            guard case let .fragment(typeCondition, selections) = element, typeCondition == incomingTypeCondition else {
                return nil
            }
            return (offset, typeCondition, selections)
        }).first
        if let (existingIndex, typeCondition, existingSelections) = possibleExisting {
            selections[existingIndex] = ResolvedSelection.fragment(
                typeCondition: typeCondition,
                selections: incomingSelections.reduce(into: existingSelections) { merge(selection: $1, into: &$0) }
            )
        } else {
            selections.append(selection)
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
            $0[$1.name.value] = graphqlValueToSwiftUIGraphQLValue($1.value)
        })
    case .listValue(let x):
        return .list(x.values.map(graphqlValueToSwiftUIGraphQLValue))
    case .nullValue:
        return .null
    case .variable(let x):
        return .variable(x.name.value)
    }
}

private func graphqlTypeToSwiftUIGraphQLType(_ x: GraphQLType) -> SwiftUIGraphQL.`Type` {
    switch x {
    case let x as GraphQLNamedType:
        return .named(x.name)
    case let x as GraphQLList:
        return .list(graphqlTypeToSwiftUIGraphQLType(x.ofType))
    case let x as GraphQLNonNull:
        return .nonNull(graphqlTypeToSwiftUIGraphQLNonNullType(x.ofType))
    default:
        fatalError("Can't convert this type")
    }
}

private func graphqlTypeToSwiftUIGraphQLNonNullType(_ x: GraphQLNullableType) -> SwiftUIGraphQL.NonNullType {
    switch x {
    case let x as GraphQLNamedType:
        return .named(x.name)
    default:
        return .nonNull(graphqlTypeToSwiftUIGraphQLType(x))
    }
}
