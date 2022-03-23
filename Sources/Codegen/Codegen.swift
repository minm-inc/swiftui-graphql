import GraphQL
import SwiftSyntax

/// Ties together the field resolution stage, the IR gen stage and the Swift gen stage together into one pass
public func generateCode(document rawDocument: Document, schema: GraphQLSchema) -> Syntax {
    let document = attachCacheableFields(schema: schema, document: rawDocument)
    var decls = [Decl]()
    
    let fragments: [FragmentDefinition] = document.definitions.compactMap {
        if case let .executableDefinition(.fragment(fragmentDef)) = $0 {
            return fragmentDef
        } else {
            return nil
        }
    }
    
    for def in document.definitions {
        switch def {
        case let .executableDefinition(.operation(def)):
            decls.append(genOperation(def, schema: schema, fragmentDefinitions: fragments))
        case let .executableDefinition(.fragment(def)):
            decls += generateProtocols(for: def, schema: schema, fragmentDefinitions: fragments)
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
