import OrderedCollections
import GraphQL
import SwiftUIGraphQL

/// A selection constructed by merging all nested objects together, and flattening unconditional fragments
/// This is a one to one mapping with an object at the transport level.
///
/// It has an invariant that conditional selections cannot contain any further conditional selections, i.e. it
/// must be flat
struct MergedSelection {
    typealias Arguments = OrderedDictionary<String, NonConstValue>
    typealias Field = SelectionField<Arguments, MergedSelection>
    var fields: OrderedDictionary<String, Field>
    struct Conditional {
        var fields: OrderedDictionary<String, Field>
        var fragmentConformances: OrderedSet<String>
    }
    var conditionals: OrderedDictionary<String, MergedSelection>
    var fragmentConformances: OrderedSet<String>
    
    /// Returns all the possible keys that can be returned for this object (*not* the nested keys)
    func selectedKeys() -> OrderedSet<String> {
        var selectedKeys = fields.keys
        for (_, conditional) in conditionals {
            selectedKeys.formUnion(conditional.fields.keys)
        }
        return selectedKeys
    }
    
    /// Returns the field that would be returned on `typename` for the key  `key`, if it exists on this selection.
    subscript(key: String, forTypename typename: String) -> Field? {
        if let conditional = conditionals[typename] {
            return conditional.fields[key]
        }
        return fields[key]
    }
}

func merge(unmergedSelections: [UnmergedSelection], type: GraphQLNamedType, schema: GraphQLSchema) -> MergedSelection {
    SelectionMerger(schema: schema).go(selections: unmergedSelections, type: type)
}

private struct SelectionMerger {
    let schema: GraphQLSchema
    
    func go(selections: [UnmergedSelection], type: GraphQLNamedType) -> MergedSelection {
        var fragmentConformances: OrderedSet<String> = []
        
        let emptySelection = MergedSelection(fields: [:], conditionals: [:], fragmentConformances: [])
        return selections.reduce(into: emptySelection) { acc, selection in
            switch selection {
            case let .field(field):
                let key = field.alias ?? field.name
                let field = MergedSelection.Field(
                    name: FieldName(field.name),
                    arguments: field.arguments,
                    type: graphqlTypeToSwiftUIGraphQLType(field.type),
                    nested: field.selections.isEmpty ? nil : go(
                        selections: field.selections,
                        type: underlyingType(field.type)
                    )
                )
                merge(field: field, key: key, into: &acc)
            case let .fragment(fragment):
                var nested = go(selections: fragment.selections, type: fragment.type)
                if try! isTypeSubTypeOf(schema, type, underlyingType(fragment.type)) {
                    // The fragment will always match because the object type is a subtype of the fragment type
                    // so flatten these selections since they'll always be included unconditionally
                    
                    merge(nested, into: &acc)
                    
                    fragmentConformances.formUnion(nested.fragmentConformances)
                    if let fragmentName = fragment.name {
                        // The flattened object conforms to the fragment
                        acc.fragmentConformances.append(fragmentName)
                    }
                } else {
                    // Otherwise it is conditional and may or may not be included in the result
                    if let fragmentName = fragment.name {
                        // The nested object conforms to the fragment
                        nested.fragmentConformances.append(fragmentName)
                    }
                    let typename = fragment.type.name
                    
                    // Move the nested's unconditional into conditionals
                    let unconditional = MergedSelection(
                        fields: nested.fields,
                        conditionals: [:],
                        fragmentConformances: nested.fragmentConformances
                    )
                    nested.conditionals[typename] = unconditional
                    
                    // Merge the conditionals as normal
                    acc.conditionals.merge(nested.conditionals) { existing, incoming in
                        var existing = existing
                        merge(incoming, into: &existing)
                        return existing
                    }
                }
            }
        }
    }
    
    private func merge(field incoming: MergedSelection.Field, key: String, into selection: inout MergedSelection) {
        merge(field: incoming, key: key, into: &selection.fields)
        for typename in selection.conditionals.keys {
            merge(field: incoming, key: key, into: &(selection.conditionals[typename])!.fields)
        }
    }
    
    private func merge(field incoming: MergedSelection.Field, key: String, into fields: inout OrderedDictionary<String, MergedSelection.Field>) {
        if let existing = fields[key] {
            fields[key] = merge(incoming, into: existing)
        } else {
            fields[key] = incoming
        }
    }

    private func merge(_ incoming: MergedSelection.Field, into existing: MergedSelection.Field) -> MergedSelection.Field {
        var result = existing
        if var existingNested = existing.nested, let incomingNested = incoming.nested {
            merge(incomingNested, into: &existingNested)
            result.nested = existingNested
        } else if existing.nested == nil && incoming.nested == nil {
            result.nested = nil
        } else {
            fatalError("Merging a leaf and an object")
        }
        return result
    }
    
    private func merge(_ incoming: MergedSelection, into existing: inout MergedSelection) {
        existing.fields.merge(incoming.fields, uniquingKeysWith: merge(_:into:))
        existing.conditionals.merge(incoming.conditionals) { existingSelection, incomingSelection in
            var existingSelection = existingSelection
            merge(incomingSelection, into: &existingSelection)
            return existingSelection
        }
        // Conditionals should contain all the unconditional fields,
        // i.e. be a superset of fields
        existing.conditionals = existing.conditionals.mapValues { selection in
            var selection = selection
            selection.fields = merge(incoming.fields, into: selection.fields)
            return selection
        }
        existing.fragmentConformances.formUnion(incoming.fragmentConformances)
    }
    
    private func merge(_ incoming: OrderedDictionary<String, MergedSelection.Field>, into existing: OrderedDictionary<String, MergedSelection.Field>) -> OrderedDictionary<String, MergedSelection.Field> {
        existing.merging(incoming, uniquingKeysWith: merge(_:into:))
    }
    
}
