//
//  ValueCodegen.swift
//  
//
//  Created by Luke Lau on 26/12/2021.
//

import GraphQL
import SwiftSyntax

func exprSyntax(for value: Value) -> ExprSyntax {
    switch value {
    case let .booleanValue(booleanValue):
        return ExprSyntax(
            BooleanLiteralExprSyntax {
                $0.useBooleanLiteral(
                    booleanValue.value ?
                        SyntaxFactory.makeTrueKeyword() :
                        SyntaxFactory.makeFalseKeyword()
                )
            }
        )
    case let .stringValue(stringValue):
        return genStringLiteral(string: stringValue.value)
    default:
        fatalError("TODO")
    }
}
