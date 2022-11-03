import GraphQL
import SwiftSyntax
import OrderedCollections

/// Ties together all the different passes from GraphQL AST to Swift syntax.
///
/// Here's an overview of the different passes involved:
///
/// ```
///            ┌─────────────┐
///            │             │  The AST from the graphql-swift library
///            │ GraphQL AST │  It will come in the form of an OperationDef or FragmentDef
///            │             │  from a Document, and we mostly use the SelectionSet
///            └──────┬──────┘
///                   │
///                   ▼
///         ┌───────────────────┐
///         │                   │  Like a SelectionSet but resolves named fragment references
///         │ UnmergedSelection │  from a list of all defined fragments in the document
///         │                   │
///         └─────────┬─────────┘
///                   │
///                   ▼
///          ┌─────────────────┐
///          │                 │           Where most of the magic happens:
///      ┌───┤   MergedObject  ├───┐       1) Merges overlapping nested objects
///      │   │                 │   │       2) Flattens unconditional fragments so they're just
///      │   └─────────────────┘   │          normal fields
///      │                         │       After this point the GraphQL library and types are
///      |                         ▼       no longer needed
///      |                  ┌───────────┐
///      |                  │           │  In each codegened query, there's two main parts:
///      |                  │ FragProto │  The object concrete type definitions, and the
///      |                  │           │  fragment protocol definitions. For the latter there's
///      |                  └──────┬────┘  the FragProto IR which helps reason about complex fragment
///      │                         │       heirarchies.
///      └────────────┬────────────┘
///                   │
///                   ▼
///              ┌─────────┐
///              │         │  SwiftSyntax is verbose and very much in the syntactical weeds
///              │ SwiftIR │  (need to worry about whitespace/keywords etc.)So SwiftIR is a
///              │         │  terser, higher level AST that makes it easier to work with.
///              └────┬────┘
///                   │
///                   ▼
///            ┌─────────────┐
///            │             │  SwiftIR then getse lowered into the SwiftSyntax AST, ready to
///            │ SwiftSyntax │  be written to a file or stdout
///            │             │
///            └─────────────┘
///
/// ```
public func generateDocument(_ rawDocument: Document, schema: GraphQLSchema, globalFragments: [FragmentDefinition]) -> SourceFileSyntax {
    let document = attachCacheableFields(schema: schema, document: rawDocument)
    var decls = [Decl]()
    
    let documentFragments = fragmentDefinitions(from: document)
    let fragmentInfo = FragmentInfo(fragmentDefinitions: globalFragments + documentFragments, schema: schema)
    
    for def in document.definitions {
        switch def {
        case let .executableDefinition(.operation(def)):
            let objectDecl = gen(operation: def, schema: schema, fragmentInfo: fragmentInfo)
            let operationDecl = attach(operation: def, to: objectDecl, schema: schema, fragmentInfo: fragmentInfo)
            decls.append(operationDecl)
        case let .executableDefinition(.fragment(def)):
            let fragmentName = def.name.value
            var object = fragmentInfo.objects[fragmentName]!
            decls += gen(fragment: object, named: fragmentName, fragmentInfo: fragmentInfo)
            
            // Generate a concrete object definition for the fragment, useful for constructing dummy values of the fragment for testing and design time
            object.fragmentConformances[fragmentName] = .unconditional
            decls.append(gen(
                object: object,
                named: "__\(def.name.value)Fragment",
                type: schema.getType(name: def.typeCondition.name.value)! as! (any GraphQLCompositeType),
                fragmentInfo: fragmentInfo,
                schema: schema
            ))
        default:
            break
        }
    }
    
    let swiftGen = SwiftGen()
    return genSourceFileWithImports(imports: ["Foundation", "SwiftUIGraphQL"], decls: decls.map(swiftGen.gen))
}

private func gen(operation def: OperationDefinition, schema: GraphQLSchema, fragmentInfo: FragmentInfo) -> Decl {
    let parentType = operationRootType(for: def.operation, schema: schema)
    let unmergedSelections = makeUnmergedSelections(selectionSet: def.selectionSet, parentType: parentType, schema: schema, fragments: fragmentInfo.definitions)
    let object = merge(unmergedSelections: unmergedSelections, type: parentType, schema: schema)
    
    let name = (def.name?.value.firstUppercased ?? "Anonymous") + operationSuffix(for: def.operation)
    
    return gen(object: object, named: name, type: parentType, fragmentInfo: fragmentInfo, schema: schema)
}

private func operationSuffix(for type: OperationType) -> String {
    switch type {
    case .query:
        return "Query"
    case .mutation:
        return "Mutation"
    case .subscription:
        return "Subscription"
    }
}

public func fragmentDefinitions(from document: Document) -> [FragmentDefinition] {
    document.definitions.compactMap {
        if case let .executableDefinition(.fragment(fragmentDef)) = $0 {
            return fragmentDef
        } else {
            return nil
        }
    }
}
