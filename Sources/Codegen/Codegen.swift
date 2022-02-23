import GraphQL
import SwiftSyntax
import SwiftSyntaxBuilder

struct StructList: DeclListBuildable {
    var structs: [DeclSyntax]
    func buildSyntaxList(format: Format, leadingTrivia: Trivia) -> [Syntax] {
        structs.map { Syntax($0) }
    }
    func buildDeclList(format: Format, leadingTrivia: Trivia) -> [DeclSyntax] {
        structs
    }
}

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
    let generated = SourceFile {
        Import("SwiftUIGraphQL")
        StructList(structs: decls.map(swiftGen.gen))
    }
    return generated.buildSyntax(format: Format(), leadingTrivia: .zero)
}
