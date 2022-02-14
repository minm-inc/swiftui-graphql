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

public func generateCode(document rawDocument: Document, schema: GraphQLSchema) -> Syntax  {
    let document = attachCachableFields(schema: schema, document: rawDocument)
    var decls = [DeclSyntax]()
    
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
            decls.append(generateStruct(for: def, schema: schema, fragments: fragments, queryString: document.printed))
        case let .executableDefinition(.fragment(def)):
            decls += generateProtocols(for: def, schema: schema, fragmentDefinitions: fragments)
        default:
            break
        }
    }
    
    let generated = SourceFile {
        Import("SwiftUIGraphQL")
        StructList(structs: decls)
    }
    return generated.buildSyntax(format: Format(), leadingTrivia: .zero)
}
