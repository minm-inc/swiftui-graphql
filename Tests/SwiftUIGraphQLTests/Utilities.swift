@testable import SwiftUIGraphQL
@testable import Codegen
import GraphQL

func selectionFromQuery(schema: GraphQLSchema, _ queryString: String) -> ResolvedSelection<String> {
    let document = try! GraphQL.parse(source: Source(body: queryString))
    guard case .executableDefinition(.operation(let operation)) = document.definitions[0] else {
        fatalError()
    }
    let unmergedSelections = makeUnmergedSelections(selectionSet: operation.selectionSet,
                                                    parentType: schema.queryType,
                                                    schema: schema,
                                                    fragments: [])
    let mergedObject = merge(unmergedSelections: unmergedSelections, type: schema.queryType, schema: schema)
    return selectionFromMergedObject(mergedObject)
}

func selectionFromMergedObject(_ object: MergedObject) -> ResolvedSelection<String> {
    ResolvedSelection(
        fields: convertSelection(object.unconditional),
        conditional: object.conditional.reduce(into: [:]) { acc, x in
            let (typeCondition, selection) = x
            acc[typeCondition.type.name] = convertSelection(selection)
        }
    )
}

private func convertSelection(_ selection: MergedObject.Selection) -> [ObjectKey : ResolvedSelection<String>.Field] {
    selection.fields.reduce(into: [:]) { acc, x in
        let (key, field) = x
        let convertedField: ResolvedSelection<String>.Field = ResolvedSelection.Field(
            name: field.name,
            arguments: Dictionary(uniqueKeysWithValues: field.arguments.elements.map { ($0.key, $0.value) }),
            type: graphqlTypeToSwiftUIGraphQLType(field.type),
            nested: field.nested.map(selectionFromMergedObject(_:))
        )
        acc[ObjectKey(key)] = convertedField
    }
}
