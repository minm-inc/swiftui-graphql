//
//  TypeCodegen.swift
//  
//
//  Created by Luke Lau on 26/12/2021.
//

import GraphQL
import SwiftSyntax

func declType(for graphqlType: GraphQLType) -> DeclType {
    func go(type: GraphQLType, addOptional: Bool) -> DeclType {
        func wrapOptional(_ x: DeclType) -> DeclType {
            if addOptional {
                return .optional(x)
            } else {
                return x
            }
        }
        
        switch type {
        case let type as GraphQLList:
            return wrapOptional(
                .array(go(type: type.ofType, addOptional: true))
            )
        case let type as GraphQLNonNull:
            return go(type: type.ofType, addOptional: false)
        case let type as GraphQLNamedType:
            let name: String
            if type.name == "Boolean" {
                name = "Bool"
            } else {
                name = type.name
            }
            return wrapOptional(.named(name))
        default:
            fatalError("Don't know how to handle this type")
        }
    }
    return go(type: graphqlType, addOptional: true)
}

func typeSyntax(for type: DeclType) -> TypeSyntax {
    switch type {
    case .named(let name, let genericArgs):
        return TypeSyntax(SimpleTypeIdentifierSyntax {
            $0.useName(SyntaxFactory.makeIdentifier(name))
            if !genericArgs.isEmpty {
                $0.useGenericArgumentClause(GenericArgumentClauseSyntax {
                    $0.useLeftAngleBracket(SyntaxFactory.makeLeftAngleToken())
                    for (i, arg) in genericArgs.enumerated() {
                        $0.addArgument(GenericArgumentSyntax {
                            $0.useArgumentType(typeSyntax(for: arg))
                            if i < genericArgs.index(before: genericArgs.endIndex) {
                                $0.useTrailingComma(
                                    SyntaxFactory.makeCommaToken()
                                        .withTrailingTrivia(.spaces(1))
                                )
                            }
                        })
                    }
                    $0.useRightAngleBracket(SyntaxFactory.makeRightAngleToken())
                })
            }
        })
    case .optional(let type):
        return TypeSyntax(OptionalTypeSyntax {
            $0.useWrappedType(typeSyntax(for: type))
            $0.useQuestionMark(SyntaxFactory.makePostfixQuestionMarkToken())
        })
    case .array(let type):
        return TypeSyntax(ArrayTypeSyntax {
            $0.useLeftSquareBracket(SyntaxFactory.makeLeftSquareBracketToken())
            $0.useRightSquareBracket(SyntaxFactory.makeRightSquareBracketToken())
            $0.useElementType(typeSyntax(for: type))
        })
    }
}
