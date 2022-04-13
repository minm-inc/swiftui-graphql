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
///      ┌───┤ MergedSelection ├───┐       1) Merges overlapping nested objects
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
public func generateCode(document rawDocument: Document, schema: GraphQLSchema) -> Syntax {
    let document = attachCacheableFields(schema: schema, document: rawDocument)
    var decls = [Decl]()
    
    let fragmentDefs: [FragmentDefinition] = document.definitions.compactMap {
        if case let .executableDefinition(.fragment(fragmentDef)) = $0 {
            return fragmentDef
        } else {
            return nil
        }
    }
    let fragmentInfo = FragmentInfo(fragmentDefinitions: fragmentDefs, schema: schema)
    
    for def in document.definitions {
        switch def {
        case let .executableDefinition(.operation(def)):
            let objectDecl = gen(operation: def, schema: schema, fragments: fragmentDefs, fragmentInfo: fragmentInfo)
            let operationDecl = attach(operation: def, to: objectDecl, schema: schema, fragmentDefinitions: fragmentDefs)
            decls.append(operationDecl)
        case let .executableDefinition(.fragment(def)):
            decls += gen(fragment: fragmentInfo.selections[def.name.value]!, named: def.name.value, fragmentInfo: fragmentInfo)
        default:
            break
        }
    }
    
    let swiftGen = SwiftGen()
    
    let sourceFile = SourceFileSyntax {
        $0.addStatement(CodeBlockItemSyntax {
            $0.useItem(Syntax(
                ImportDeclSyntax {
                    $0.useImportTok(SyntaxFactory.makeImportKeyword().withTrailingTrivia(.spaces(1)))
                    $0.addPathComponent(AccessPathComponentSyntax {
                        $0.useName(SyntaxFactory.makeIdentifier("Foundation"))
                    })
                }.withTrailingTrivia(.newlines(1))
            ))
        })
        $0.addStatement(CodeBlockItemSyntax {
            $0.useItem(Syntax(
                ImportDeclSyntax {
                    $0.useImportTok(SyntaxFactory.makeImportKeyword().withTrailingTrivia(.spaces(1)))
                    $0.addPathComponent(AccessPathComponentSyntax {
                        $0.useName(SyntaxFactory.makeIdentifier("SwiftUIGraphQL"))
                    })
                }.withTrailingTrivia(.newlines(1))
            ))
        })
        for decl in decls.map(swiftGen.gen) {
            $0.addStatement(CodeBlockItemSyntax {
                $0.useItem(Syntax(decl))
            })
        }
    }
    
    return Syntax(sourceFile)
}

private func gen(operation def: OperationDefinition, schema: GraphQLSchema, fragments: [FragmentDefinition], fragmentInfo: FragmentInfo) -> Decl {
    let parentType = operationRootType(for: def.operation, schema: schema)
    let unresolvedSelections = makeUnmergedSelections(selectionSet: def.selectionSet, parentType: parentType, schema: schema, fragments: fragments)
    let mergedSelection = merge(unmergedSelections: unresolvedSelections, type: parentType, schema: schema)
    
    let name = (def.name?.value.firstUppercased ?? "Anonymous") + operationSuffix(for: def.operation)
    
    return gen(object: mergedSelection, named: name, typename: parentType.name, fragmentInfo: fragmentInfo)
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
