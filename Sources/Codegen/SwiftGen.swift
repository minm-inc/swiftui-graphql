//
//  SwiftGen.swift
//  
//
//  Created by Luke Lau on 23/12/2021.
//

import SwiftSyntax
import OrderedCollections

extension Optional {
    func mapThunk<T>(_ f: @escaping (Wrapped) -> T) -> Optional<() -> T> {
        if let x = self {
            return { f(x) }
        } else {
            return nil
        }
    }
}

class SwiftGen {
    private var indentationLevel = 0
    
    func gen(decl: Decl) -> DeclSyntax {
        switch decl {
        case let .let(name, type, initializer, accessor, isStatic):
            return DeclSyntax(
                genVariableDecl(
                    identifier: name,
                    type: typeSyntax(for: type),
                    initializer: initializer.map(gen),
                    accessor: accessor,
                    isStatic: isStatic
                )
            ).withTrailingTrivia(.newlines(1))
        case let .struct(name, defs, conforms):
            return DeclSyntax(genStruct(name: name, defs: defs, conforms: conforms))
                        .withTrailingTrivia(.newlines(1))
        case let .enum(name, cases, decls, conforms, defaultCase, genericParameters):
            return DeclSyntax(
                genEnum(
                    name: name,
                    cases: cases,
                    decls: decls,
                    conforms: conforms,
                    defaultCase: defaultCase,
                    genericParameters: genericParameters
                )
            ).withTrailingTrivia(.newlines(1))
        case let .staticLetString(name, literal):
            return DeclSyntax(genStaticLetString(name: name, literal: literal))
        case let .protocol(name, conforms, whereClauses, decls):
            return DeclSyntax(genProtocol(name: name, conforms: conforms, whereClauses: whereClauses, decls: decls))
        case let .associatedtype(name, inherits):
            return DeclSyntax(genAssociatedType(name: name, inherits: inherits))
        case let .func(name, returnType, body, access):
            return DeclSyntax(
                genFunc(
                    name: name,
                    returnType: typeSyntax(for: returnType),
                    body: body.mapThunk(gen(syntax:)),
                    access: access
                )
            )
        }
    }
    
    private func gen(syntax: Decl.Syntax) -> Syntax {
        switch syntax {
        case let .returnSwitch(expr, cases):
            return Syntax(
                genSwitch(
                    expr: gen(expr: expr),
                    cases: cases.map(genReturnEnumMemberSwitchCase)
                )
            )
        case let .expr(expr):
            return Syntax(gen(expr: expr).withLeadingTrivia(.spaces(indentationLevel)))
        }
    }
    
    private func gen(expr: Expr) -> ExprSyntax {
        switch expr {
        case let .memberAccess(member, base):
            return ExprSyntax(genMemberAccess(base: base, member: member))
        case let .functionCall(called, args):
            return ExprSyntax(genFunctionCall(called: called, args: args))
        case let .identifier(identifier):
            return ExprSyntax(genIdentifier(identifier))
        case let .anonymousIdentifier(identifier):
            return gen(expr: .identifier("$\(identifier)"))
        case let .closure(expr):
            return ExprSyntax(genClosure(expr: expr))
        case let .stringLiteral(string):
            return genStringLiteral(string: string)
        case let .boolLiteral(bool):
            return ExprSyntax(genBoolLiteral(bool: bool))
        case let .intLiteral(int):
            return ExprSyntax(genIntLiteral(int: int))
        case let .floatLiteral(float):
            return ExprSyntax(genFloatLiteral(float: float))
        case let .array(array):
            return ExprSyntax(genArray(array: array))
        case let .dictionary(dictionary):
            return ExprSyntax(genDictionary(dictionary: dictionary))
        case .`self`:
            return ExprSyntax(IdentifierExprSyntax {
                $0.useIdentifier(SyntaxFactory.makeSelfKeyword())
            })
        }
    }
    
    private func genInheritanceClause(conforms: [String]) -> TypeInheritanceClauseSyntax {
        TypeInheritanceClauseSyntax {
            if conforms.isEmpty { return }
            $0.useColon(SyntaxFactory.makeColonToken(leadingTrivia: .zero, trailingTrivia: .spaces(1)))
            for (i, identifier) in conforms.enumerated() {
                
                $0.addInheritedType(InheritedTypeSyntax {
                    $0.useTypeName(TypeSyntax(
                        SyntaxFactory.makeSimpleTypeIdentifier(
                            name: SyntaxFactory.makeIdentifier(identifier),
                            genericArgumentClause: nil
                        )
                    ))
                    if i < conforms.endIndex - 1 {
                        $0.useTrailingComma(
                            SyntaxFactory.makeCommaToken(
                                leadingTrivia: .zero,
                                trailingTrivia: .spaces(1)
                            )
                        )
                    }
                })
            }
        }
    }
    
    private func genStruct(name: String, defs: [Decl], conforms: [String]) -> StructDeclSyntax {
        StructDeclSyntax { builder in
            builder.useStructKeyword(
                SyntaxFactory
                    .makeStructKeyword(
                        leadingTrivia: .spaces(indentationLevel),
                        trailingTrivia: .spaces(1)
                    )
            )
            builder.useIdentifier(SyntaxFactory.makeIdentifier(name))
            builder.useInheritanceClause(genInheritanceClause(conforms: conforms))
            builder.useMembers(MemberDeclBlockSyntax { builder in
                builder.useLeftBrace(SyntaxFactory.makeLeftBraceToken().withLeadingTrivia(.spaces(1)).withTrailingTrivia(.newlines(1)))
                builder.useRightBrace(
                    SyntaxFactory
                        .makeRightBraceToken()
                        .withLeadingTrivia(.spaces(indentationLevel))
                )
                indent {
                    for def in defs {
                        builder.addMember(MemberDeclListItemSyntax {
                            $0.useDecl(gen(decl: def))
                        })
                    }
                }
            })
        }
    }
    
    private func genEnum(name: String, cases: [Decl.Case], decls: [Decl], conforms: [String], defaultCase: Decl.Case?, genericParameters: [Decl.GenericParameter]) -> EnumDeclSyntax {
        EnumDeclSyntax {
            $0.useEnumKeyword(
                SyntaxFactory.makeEnumKeyword(
                    leadingTrivia: .spaces(indentationLevel),
                    trailingTrivia: .spaces(1)
                )
            )
            $0.useIdentifier(SyntaxFactory.makeIdentifier(name))
            if !genericParameters.isEmpty {
                $0.useGenericParameters(GenericParameterClauseSyntax {
                    $0.useLeftAngleBracket(SyntaxFactory.makeLeftAngleToken())
                    for (i, param) in genericParameters.enumerated() {
                        $0.addGenericParameter(GenericParameterSyntax {
                            $0.useName(SyntaxFactory.makeIdentifier(param.identifier))
                            $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                            $0.useInheritedType(typeSyntax(for: param.constraint))
                            if i < genericParameters.index(before: genericParameters.endIndex) {
                                $0.useTrailingComma(SyntaxFactory.makeCommaToken().withTrailingTrivia(.spaces(1)))
                            }
                        })
                    }
                    $0.useRightAngleBracket(SyntaxFactory.makeRightAngleToken())
                })
            }
            $0.useInheritanceClause(genInheritanceClause(conforms: conforms))
            $0.useMembers(MemberDeclBlockSyntax { builder in
                builder.useLeftBrace(SyntaxFactory.makeLeftBraceToken().withLeadingTrivia(.spaces(1)).withTrailingTrivia(.newlines(1)))
                builder.useRightBrace(
                    SyntaxFactory
                        .makeRightBraceToken()
                        .withLeadingTrivia(.spaces(indentationLevel))
                )
                indent {
                    let allCases = cases + [defaultCase].compactMap { $0 }
                    for `case` in allCases {
                        builder.addMember(MemberDeclListItemSyntax {
                            $0.useDecl(DeclSyntax(gen(`case`)))
                        })
                    }
                    for def in decls {
                        builder.addMember(MemberDeclListItemSyntax {
                            $0.useDecl(gen(decl: def))
                        }.withTrailingTrivia(.newlines(1)))
                    }
                    
                    if (conforms.contains("Codable")) {
                        builder.addMember(MemberDeclListItemSyntax {
                            $0.useDecl(DeclSyntax(
                                genEnumDecoderInit(
                                    cases: cases,
                                    enumName: name,
                                    defaultCase: defaultCase
                                )
                            ))
                        })
                        
                        builder.addMember(MemberDeclListItemSyntax {
                            $0.useDecl(DeclSyntax(
                                genEnumEncodeFunc(
                                    cases: allCases
                                )
                            ))
                        })
                    }
                }
            })
        }
    }
    
    private func gen(_ `case`: Decl.Case) -> EnumCaseDeclSyntax {
        EnumCaseDeclSyntax {
            $0.useCaseKeyword(
                SyntaxFactory
                    .makeCaseKeyword(
                        leadingTrivia: .spaces(indentationLevel),
                        trailingTrivia: .spaces(1)
                    )
            )
            $0.addElement(EnumCaseElementSyntax {
                $0.useIdentifier(SyntaxFactory.makeIdentifier(`case`.name))
                if let nestedTypeName = `case`.nestedTypeName {
                    $0.useAssociatedValue(
                        ParameterClauseSyntax {
                            $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
                            $0.useRightParen(SyntaxFactory.makeRightParenToken())
                            $0.addParameter(
                                FunctionParameterSyntax {
                                    $0.useType(TypeSyntax(
                                        SimpleTypeIdentifierSyntax {
                                            $0.useName(SyntaxFactory.makeIdentifier(nestedTypeName))
                                        }
                                    ))
                                }
                            )
                        }
                    )
                }
            })
        }.withTrailingTrivia(.newlines(1))
    }
    
    /// Generates the decoder initializer for an enum
    /// ```swift
    /// init(from decoder: Decoder) throws { ... }
    /// ```
    private func genEnumDecoderInit(cases: [Decl.Case], enumName: String, defaultCase: Decl.Case?) -> InitializerDeclSyntax {
        InitializerDeclSyntax {
            $0.useInitKeyword(
                SyntaxFactory
                    .makeInitKeyword()
                    .withLeadingTrivia(.spaces(indentationLevel))
            )
            $0.useParameters(ParameterClauseSyntax {
                $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
                $0.useRightParen(SyntaxFactory.makeRightParenToken())
                $0.addParameter(FunctionParameterSyntax {
                    $0.useFirstName(SyntaxFactory.makeIdentifier("from").withTrailingTrivia(.spaces(1)))
                    $0.useSecondName(SyntaxFactory.makeIdentifier("decoder"))
                    $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                    $0.useType(TypeSyntax(
                        SimpleTypeIdentifierSyntax {
                            $0.useName(SyntaxFactory.makeIdentifier("Decoder"))
                        }
                    ))
                })
            }.withTrailingTrivia(.spaces(1)))
            
            $0.useThrowsOrRethrowsKeyword(SyntaxFactory.makeThrowsKeyword().withTrailingTrivia(.spaces(1)))
            
            $0.useBody(CodeBlockSyntax { builder in
                builder.useLeftBrace(SyntaxFactory.makeLeftBraceToken().withTrailingTrivia(.newlines(1)))
                builder.useRightBrace(SyntaxFactory.makeRightBraceToken().withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.newlines(1)))
                indent {
                    builder.addStatement(CodeBlockItemSyntax {
                        $0.useItem(Syntax(
                            genContainerVarDecl(name: "container", keyedBy: "TypenameCodingKeys")
                                .withTrailingTrivia(.newlines(1))
                        ))
                    })
                    
                    let typenameIdentifier = "typename"
                    
                    builder.addStatement(CodeBlockItemSyntax {
                        $0.useItem(Syntax(
                            VariableDeclSyntax {
                                $0.useLetOrVarKeyword(
                                    SyntaxFactory.makeLetKeyword(
                                        leadingTrivia: .spaces(indentationLevel),
                                        trailingTrivia: .spaces(1)
                                    )
                                )
                                $0.addBinding(PatternBindingSyntax {
                                    $0.usePattern(PatternSyntax(
                                        IdentifierPatternSyntax {
                                            $0.useIdentifier(SyntaxFactory.makeIdentifier(typenameIdentifier))
                                        }
                                    ).withTrailingTrivia(.spaces(1)))
                                    $0.useInitializer(InitializerClauseSyntax {
                                        $0.useEqual(SyntaxFactory.makeEqualToken().withTrailingTrivia(.spaces(1)))
                                        $0.useValue(
                                            genDecode(
                                                container: "container",
                                                type: SyntaxFactory.makeTypeIdentifier("String"),
                                                forKey: SyntaxFactory.makeIdentifier("__typename"),
                                                optionalTry: false
                                            )
                                        )
                                    })
                                }.withTrailingTrivia(.newlines(1)))
                            }
                        ))
                    })
                    
                    builder.addStatement(CodeBlockItemSyntax {
                        $0.useItem(Syntax(
                            SwitchStmtSyntax {
                                $0.useSwitchKeyword(SyntaxFactory.makeSwitchKeyword().withTrailingTrivia(.spaces(1)))
                                $0.useExpression(ExprSyntax(
                                    IdentifierExprSyntax {
                                        $0.useIdentifier(SyntaxFactory.makeIdentifier(typenameIdentifier))
                                    }
                                ))
                                $0.useLeftBrace(
                                    SyntaxFactory
                                        .makeLeftBraceToken()
                                        .withLeadingTrivia(.spaces(1))
                                        .withTrailingTrivia(.newlines(1))
                                )
                                $0.useRightBrace(
                                    SyntaxFactory
                                        .makeRightBraceToken()
                                        .withLeadingTrivia(.spaces(indentationLevel))
                                        .withTrailingTrivia(.newlines(1))
                                )
                                for `case` in cases {
                                    $0.addCase(Syntax(
                                        genEnumDecoderInitSwitchCase(
                                            matchOn: `case`.nestedTypeName,
                                            codeBlockItem: {
                                                Syntax(
                                                    genEnumDecoderInitAssignment(case: `case`)
                                                )
                                            }
                                        )
                                    ))
                                }
                                if let defaultCase = defaultCase {
                                    $0.addCase(Syntax(
                                        genEnumDecoderInitSwitchCase(
                                            matchOn: nil,
                                            codeBlockItem: {
                                                Syntax(
                                                    genEnumDecoderInitAssignment(case: defaultCase)
                                                )
                                            }
                                        )
                                    ))
                                } else {
                                    $0.addCase(Syntax(
                                        genEnumDecoderInitSwitchCase(
                                            matchOn: nil,
                                            codeBlockItem: {
                                                    genEnumDecodingErrorThrow(
                                                    typenameIdentifier: typenameIdentifier,
                                                    enumName: enumName
                                                )
                                            }
                                        )
                                    ))
                                }
                            }.withLeadingTrivia(.spaces(indentationLevel))
                        ))
                    })
                }
            })
        }
    }
    
    private func genEnumDecodingErrorThrow(typenameIdentifier: String, enumName: String) -> Syntax {
        Syntax(
            ThrowStmtSyntax {
                $0.useThrowKeyword(SyntaxFactory.makeThrowKeyword().withTrailingTrivia(.spaces(1)))
                $0.useExpression(ExprSyntax(
                    FunctionCallExprSyntax { builder in
                        builder.useCalledExpression(ExprSyntax(
                            MemberAccessExprSyntax {
                                $0.useBase(ExprSyntax(
                                    IdentifierExprSyntax {
                                        $0.useIdentifier(SyntaxFactory.makeIdentifier("DecodingError"))
                                    }
                                ))
                                $0.useDot(SyntaxFactory.makePeriodToken())
                                $0.useName(SyntaxFactory.makeIdentifier("typeMismatch"))
                            }
                        ))
                        builder.useLeftParen(SyntaxFactory.makeLeftParenToken().withTrailingTrivia(.newlines(1)))
                        indent {
                            builder.addArgument(TupleExprElementSyntax {
                                $0.useExpression(ExprSyntax(
                                    MemberAccessExprSyntax {
                                        $0.useBase(ExprSyntax(
                                            IdentifierExprSyntax {
                                                $0.useIdentifier(SyntaxFactory.makeIdentifier("Self"))
                                            }
                                        ))
                                        $0.useDot(SyntaxFactory.makePeriodToken())
                                        $0.useName(SyntaxFactory.makeSelfKeyword())
                                    }
                                ))
                                $0.useTrailingComma(SyntaxFactory.makeCommaToken())
                            }.withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.newlines(1)))
                            builder.addArgument(TupleExprElementSyntax {
                                $0.useExpression(genEnumDecodingErrorContext(
                                    typenameIdentifier: typenameIdentifier,
                                    enumName: enumName
                                ))
                            }.withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.newlines(1)))
                        }
                        builder.useRightParen(SyntaxFactory.makeRightParenToken(
                            leadingTrivia: .spaces(indentationLevel),
                            trailingTrivia: .newlines(1)
                        ))
                    }
                ))
            }
        )
    }
    
    private func genEnumDecodingErrorContext(typenameIdentifier: String, enumName: String) -> ExprSyntax {
        ExprSyntax(
            FunctionCallExprSyntax { builder in
                builder.useCalledExpression(ExprSyntax(
                    MemberAccessExprSyntax {
                        $0.useBase(ExprSyntax(
                            IdentifierExprSyntax {
                                $0.useIdentifier(SyntaxFactory.makeIdentifier("DecodingError"))
                            }
                        ))
                        $0.useDot(SyntaxFactory.makePeriodToken())
                        $0.useName(SyntaxFactory.makeIdentifier("Context"))
                    }
                ))
                builder.useLeftParen(SyntaxFactory.makeLeftParenToken().withTrailingTrivia(.newlines(1)))
                indent {
                    builder.addArgument(TupleExprElementSyntax {
                        $0.useLabel(SyntaxFactory.makeIdentifier("codingPath"))
                        $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                        $0.useExpression(ExprSyntax(
                            MemberAccessExprSyntax {
                                $0.useBase(ExprSyntax(
                                    IdentifierExprSyntax {
                                        $0.useIdentifier(SyntaxFactory.makeIdentifier("decoder"))
                                    }
                                ))
                                $0.useDot(SyntaxFactory.makePeriodToken())
                                $0.useName(SyntaxFactory.makeIdentifier("codingPath"))
                            }
                        ))
                        $0.useTrailingComma(SyntaxFactory.makeCommaToken())
                    }.withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.newlines(1)))
                    builder.addArgument(TupleExprElementSyntax {
                        
                        $0.useLabel(SyntaxFactory.makeIdentifier("debugDescription"))
                        $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                        $0.useExpression(ExprSyntax(
                            StringLiteralExprSyntax {
                                $0.useOpenQuote(SyntaxFactory.makeStringQuoteToken())
                                
                                $0.addSegment(Syntax(
                                    StringSegmentSyntax {
                                        $0.useContent(SyntaxFactory.makeStringLiteral(
                                            "Unexpected object type "
                                        ))
                                    }
                                ))
                                
                                $0.addSegment(Syntax(
                                    ExpressionSegmentSyntax {
                                        $0.useBackslash(SyntaxFactory.makeBackslashToken())
                                        $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
                                        $0.addExpression(TupleExprElementSyntax {
                                            $0.useExpression(ExprSyntax(
                                                IdentifierExprSyntax {
                                                    $0.useIdentifier(SyntaxFactory.makeIdentifier(typenameIdentifier))
                                                }
                                            ))
                                        })
                                        $0.useRightParen(SyntaxFactory.makeRightParenToken())
                                    }
                                ))
                                
                                $0.addSegment(Syntax(
                                    StringSegmentSyntax {
                                        $0.useContent(SyntaxFactory.makeStringLiteral(
                                            " for enum \(enumName)"
                                        ))
                                    }
                                ))
                                
                                $0.useCloseQuote(SyntaxFactory.makeStringQuoteToken())
                            }
                        ))
                    }.withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.newlines(1)))
                }
                builder.useRightParen(SyntaxFactory.makeRightParenToken(
                    leadingTrivia: .spaces(indentationLevel),
                    trailingTrivia: .newlines(1)
                ))
            }
        )
    }
    
    /**
     Generates the `let container = try decoder.container...` part
     */
    private func genContainerVarDecl(name: String, keyedBy: String) -> VariableDeclSyntax {
        VariableDeclSyntax {
            $0.useLetOrVarKeyword(SyntaxFactory.makeLetKeyword().withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.spaces(1)))
            $0.addBinding(PatternBindingSyntax {
                $0.usePattern(PatternSyntax(
                    IdentifierPatternSyntax {
                        $0.useIdentifier(SyntaxFactory.makeIdentifier(name))
                    })
                )
                $0.useInitializer(InitializerClauseSyntax {
                    $0.useEqual(SyntaxFactory.makeEqualToken(leadingTrivia: .spaces(1), trailingTrivia: .spaces(1)))
                    $0.useValue(ExprSyntax(
                        TryExprSyntax {
                        $0.useTryKeyword(SyntaxFactory.makeTryKeyword().withTrailingTrivia(.spaces(1)))
                        $0.useExpression(ExprSyntax(
                            FunctionCallExprSyntax {
                                $0.useCalledExpression(ExprSyntax(
                                    MemberAccessExprSyntax {
                                        $0.useName(SyntaxFactory.makeIdentifier("container"))
                                        $0.useDot(SyntaxFactory.makePeriodToken())
                                        $0.useBase(ExprSyntax(
                                            IdentifierExprSyntax {
                                                $0.useIdentifier(SyntaxFactory.makeIdentifier("decoder"))
                                            }
                                        ))
                                    }
                                ))
                                $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
                                $0.useRightParen(SyntaxFactory.makeRightParenToken())
                                $0.addArgument(TupleExprElementSyntax {
                                    $0.useLabel(SyntaxFactory.makeIdentifier("keyedBy"))
                                    $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                                    $0.useExpression(ExprSyntax(
                                        MemberAccessExprSyntax {
                                            $0.useName(SyntaxFactory.makeIdentifier("self"))
                                            $0.useDot(SyntaxFactory.makePeriodToken())
                                            $0.useBase(ExprSyntax(
                                                IdentifierExprSyntax {
                                                    $0.useIdentifier(SyntaxFactory.makeIdentifier(keyedBy))
                                                }
                                            ))
                                        }
                                    ))
                                })
                            }
                        ))
                    }
                    ))
                })
            })
        }
    }
    
    /**
     Generates the `try container.decode(Type.self, forKey: .blah)` part
     */
    private func genDecode(container: String, type: TypeSyntax, forKey: TokenSyntax, optionalTry: Bool) -> ExprSyntax {
        ExprSyntax(TryExprSyntax {
            $0.useTryKeyword(SyntaxFactory.makeTryKeyword())
            if optionalTry {
                $0.useQuestionOrExclamationMark(SyntaxFactory.makePostfixQuestionMarkToken())
            }
            $0.useExpression(ExprSyntax(
                FunctionCallExprSyntax {
                    $0.useCalledExpression(ExprSyntax(
                        MemberAccessExprSyntax {
                            $0.useName(SyntaxFactory.makeIdentifier("decode"))
                            $0.useDot(SyntaxFactory.makePeriodToken())
                            $0.useBase(ExprSyntax(
                                IdentifierExprSyntax {
                                    $0.useIdentifier(SyntaxFactory.makeIdentifier("container"))
                                }
                            ))
                        }
                    ))
                    $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
                    $0.useRightParen(SyntaxFactory.makeRightParenToken())
                    $0.addArgument(TupleExprElementSyntax {
                        $0.useExpression(ExprSyntax(
                            MemberAccessExprSyntax {
                                $0.useName(SyntaxFactory.makeIdentifier("self"))
                                $0.useDot(SyntaxFactory.makePeriodToken())
                                $0.useBase(ExprSyntax(
                                    TypeExprSyntax {
                                        $0.useType(type)
                                    }
                                ))
                            }
                        ))
                        $0.useTrailingComma(SyntaxFactory.makeCommaToken(leadingTrivia: .zero, trailingTrivia: .spaces(1)))
                    })
                    $0.addArgument(TupleExprElementSyntax {
                        $0.useLabel(SyntaxFactory.makeIdentifier("forKey"))
                        $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                        $0.useExpression(ExprSyntax(
                            MemberAccessExprSyntax {
                                $0.useName(forKey)
                                $0.useDot(SyntaxFactory.makePeriodToken())
                            }
                        ))
                    })
                }
            ).withLeadingTrivia(.spaces(1)))
        })
    }
    
    private enum SwitchCaseLabel {
        case `default`, `case`(String)
    }
    
    /**
     Generates the
     ```
     case "Foo":
         self = .foo(try Foo(from: decoder))
     ```
     part
     */
    private func genEnumDecoderInitSwitchCase(matchOn typeName: String?, codeBlockItem: () -> Syntax) -> SwitchCaseSyntax {
        SwitchCaseSyntax { builder in
            if let typeName = typeName {
                builder.useLabel(Syntax(
                    SwitchCaseLabelSyntax {
                        $0.useCaseKeyword(
                            SyntaxFactory.makeCaseKeyword(
                                leadingTrivia: .spaces(indentationLevel),
                                trailingTrivia: .spaces(1)
                            )
                        )
                        $0.addCaseItem(
                            CaseItemSyntax {
                                $0.usePattern(
                                    PatternSyntax(
                                        ExpressionPatternSyntax {
                                            $0.useExpression(genStringLiteral(string: typeName))
                                        }
                                    )
                                )
                            }
                        )
                        $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.newlines(1)))
                    }
                ))
            } else {
                builder.useLabel(Syntax(
                    SwitchDefaultLabelSyntax {
                        $0.useDefaultKeyword(
                            SyntaxFactory.makeDefaultKeyword()
                                .withLeadingTrivia(.spaces(indentationLevel))
                        )
                        $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.newlines(1)))
                    })
                )
            }
            indent {
                builder.addStatement(
                    CodeBlockItemSyntax {
                        $0.useItem(codeBlockItem().withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.newlines(1)))
                    }
                )
            }
        }
    }
    
    
    /**
        Generates the `self = .foo(try Foo(from: decoder))` part
     */
    private func genEnumDecoderInitAssignment(case: Decl.Case) -> SequenceExprSyntax {
        SequenceExprSyntax {
            $0.addElement(ExprSyntax(
                IdentifierExprSyntax { $0.useIdentifier(SyntaxFactory.makeSelfKeyword().withTrailingTrivia(.spaces(1)))
                }
            ))
            $0.addElement(ExprSyntax(
                AssignmentExprSyntax {
                    $0.useAssignToken(SyntaxFactory.makeEqualToken().withTrailingTrivia(.spaces(1)))
                }
            ))
            let accessExpr = ExprSyntax(
                MemberAccessExprSyntax {
                    $0.useDot(SyntaxFactory.makePeriodToken())
                    $0.useName(SyntaxFactory.makeIdentifier(`case`.name))
                }
            )
            guard let nestedTypeName = `case`.nestedTypeName else {
                $0.addElement(accessExpr)
                return
            }
            $0.addElement(ExprSyntax(
                FunctionCallExprSyntax {
                    $0.useCalledExpression(accessExpr)
                    $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
                    $0.useRightParen(SyntaxFactory.makeRightParenToken())
                    $0.addArgument(TupleExprElementSyntax {
                        $0.useExpression(ExprSyntax(
                            TryExprSyntax {
                                $0.useTryKeyword(SyntaxFactory.makeTryKeyword().withTrailingTrivia(.spaces(1)))
                                $0.useExpression(ExprSyntax(
                                    FunctionCallExprSyntax {
                                        $0.useCalledExpression(ExprSyntax(
                                            IdentifierExprSyntax {
                                                $0.useIdentifier(SyntaxFactory.makeIdentifier(nestedTypeName))
                                            }
                                        ))
                                        $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
                                        $0.useRightParen(SyntaxFactory.makeRightParenToken())
                                        $0.addArgument(TupleExprElementSyntax {
                                            $0.useLabel(SyntaxFactory.makeIdentifier("from"))
                                            $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                                            $0.useExpression(ExprSyntax(
                                                IdentifierExprSyntax {
                                                    $0.useIdentifier(SyntaxFactory.makeIdentifier("decoder"))
                                                }
                                            ))
                                        })

                                    }
                                ))
                            }
                        ))
                    })
                }
            ))
        }
    }
    
    private func genEnumEncodeFunc(cases: [Decl.Case]) -> FunctionDeclSyntax {
        FunctionDeclSyntax {
            $0.useFuncKeyword(SyntaxFactory.makeFuncKeyword().withTrailingTrivia(.spaces(1)))
            $0.useIdentifier(SyntaxFactory.makeIdentifier("encode"))
            $0.useSignature(FunctionSignatureSyntax {
                $0.useInput(ParameterClauseSyntax {
                    $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
                    $0.useRightParen(SyntaxFactory.makeRightParenToken())
                    $0.addParameter(FunctionParameterSyntax {
                        $0.useFirstName(SyntaxFactory.makeIdentifier("to").withTrailingTrivia(.spaces(1)))
                        $0.useSecondName(SyntaxFactory.makeIdentifier("encoder"))
                        $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                        $0.useType(TypeSyntax(
                            SimpleTypeIdentifierSyntax {
                                $0.useName(SyntaxFactory.makeIdentifier("Encoder"))
                            }
                        ))
                    })
                }.withTrailingTrivia(.spaces(1)))
                $0.useThrowsOrRethrowsKeyword(SyntaxFactory.makeThrowsKeyword().withTrailingTrivia(.spaces(1)))
            })
            $0.useBody(CodeBlockSyntax { builder in
                builder.useLeftBrace(SyntaxFactory.makeLeftBraceToken().withTrailingTrivia(.newlines(1)))
                builder.useRightBrace(SyntaxFactory.makeRightBraceToken().withLeadingTrivia(.spaces(indentationLevel)))
                indent {
                    builder.addStatement(CodeBlockItemSyntax {
                        $0.useItem(Syntax(
                            genSwitch(
                                expr: ExprSyntax(IdentifierExprSyntax {
                                    $0.useIdentifier(
                                        SyntaxFactory.makeSelfKeyword()
                                    )
                                }),
                                cases: cases.map { genEnumEncodeSwitchCase(caseName: $0.name) }
                            ).withTrailingTrivia(.newlines(1))
                        ))
                    })
                }
            })
        }.withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.newlines(1))
    }
    
    private func genEnumEncodeSwitchCase(caseName: String) -> SwitchCaseSyntax {
        SwitchCaseSyntax { builder in
            builder.useLabel(Syntax(
                SwitchCaseLabelSyntax {
                    $0.useCaseKeyword(
                        SyntaxFactory.makeCaseKeyword().withTrailingTrivia(.spaces(1))
                    )
                    $0.addCaseItem(genSingleAssociatedValBindingCaseItemSyntax(caseName: caseName, bindings: [.named(caseName)]))
                    $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.newlines(1)))
                }
            ).withLeadingTrivia(.spaces(indentationLevel)))
            indent {
                builder.addStatement(CodeBlockItemSyntax {
                    $0.useItem(Syntax(
                        TryExprSyntax {
                            $0.useTryKeyword(SyntaxFactory.makeTryKeyword().withTrailingTrivia(.spaces(1)))
                            $0.useExpression(ExprSyntax(
                                FunctionCallExprSyntax {
                                    $0.useCalledExpression(ExprSyntax(
                                        MemberAccessExprSyntax {
                                            $0.useBase(ExprSyntax(
                                                IdentifierExprSyntax {
                                                    $0.useIdentifier(SyntaxFactory.makeIdentifier(caseName))
                                                }
                                            ))
                                            $0.useDot(SyntaxFactory.makePeriodToken())
                                            $0.useName(SyntaxFactory.makeIdentifier("encode"))
                                        }
                                    ))
                                    $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
                                    $0.addArgument(TupleExprElementSyntax {
                                        $0.useLabel(SyntaxFactory.makeIdentifier("to"))
                                        $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                                        $0.useExpression(ExprSyntax(
                                            IdentifierExprSyntax {
                                                $0.useIdentifier(SyntaxFactory.makeIdentifier("encoder"))
                                            }
                                        ))
                                    })
                                    $0.useRightParen(SyntaxFactory.makeRightParenToken())
                                }
                            ))
                        }
                    ).withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.newlines(1)))
                })
            }
        }
    }
    
    /// Generates a case item binding for an enum, optionally binding its associated values
    ///
    /// Generates
    /// ```swift
    /// .caseName(let bindingName)
    /// ```
    private func genSingleAssociatedValBindingCaseItemSyntax(caseName: String, bindings: [Decl.Syntax.SwitchCase.Bind]) -> CaseItemSyntax {
        CaseItemSyntax {
            $0.usePattern(PatternSyntax(
                ExpressionPatternSyntax {
                    $0.useExpression(ExprSyntax(
                        FunctionCallExprSyntax {
                            $0.useCalledExpression(ExprSyntax(
                                MemberAccessExprSyntax {
                                    $0.useDot(SyntaxFactory.makePeriodToken())
                                    $0.useName(SyntaxFactory.makeIdentifier(caseName))
                                }
                            ))
                            if !bindings.isEmpty {
                                $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
                                for (i, binding) in bindings.enumerated() {
                                    $0.addArgument(TupleExprElementSyntax {
                                        switch binding {
                                        case .discard:
                                            $0.useExpression(ExprSyntax(DiscardAssignmentExprSyntax {
                                                $0.useWildcard(SyntaxFactory.makeWildcardKeyword())
                                            }))
                                        case .named(let name):
                                            $0.useExpression(ExprSyntax(
                                                UnresolvedPatternExprSyntax {
                                                    $0.usePattern(PatternSyntax(
                                                        ValueBindingPatternSyntax {
                                                            $0.useLetOrVarKeyword(
                                                                SyntaxFactory
                                                                    .makeLetKeyword()
                                                                    .withTrailingTrivia(.spaces(1))
                                                            )
                                                            $0.useValuePattern(PatternSyntax(
                                                                IdentifierPatternSyntax {
                                                                    $0.useIdentifier(SyntaxFactory.makeIdentifier(name))
                                                                }
                                                            ))
                                                        }
                                                    ))
                                                }
                                            ))
                                        }
                                        if i < bindings.index(before: bindings.endIndex) {
                                            $0.useTrailingComma(SyntaxFactory.makeCommaToken().withTrailingTrivia(.spaces(1)))
                                        }
                                    })
                                }
                                $0.useRightParen(SyntaxFactory.makeRightParenToken())
                            }
                        }
                    ))
                }
            ))
        }
    }
    
    private func genStaticLetString(name: String, literal: String) -> VariableDeclSyntax {
        VariableDeclSyntax {
            $0.addModifier(DeclModifierSyntax {
                $0.useName(
                    SyntaxFactory.makeStaticKeyword(
                        leadingTrivia: .spaces(indentationLevel),
                        trailingTrivia: .spaces(1)
                    )
                )
            })
            $0.useLetOrVarKeyword(
                SyntaxFactory.makeLetKeyword().withTrailingTrivia(.spaces(1))
            )
            $0.addBinding(PatternBindingSyntax {
                $0.usePattern(PatternSyntax(
                    IdentifierPatternSyntax {
                        $0.useIdentifier(SyntaxFactory.makeIdentifier(name))
                    }.withTrailingTrivia(.spaces(1))
                ))
                $0.useInitializer(InitializerClauseSyntax {
                    $0.useEqual(
                        SyntaxFactory.makeEqualToken().withTrailingTrivia(.spaces(1))
                    )
                    $0.useValue(
                        genStringLiteral(string: literal, multiline: true)
                            .withTrailingTrivia(.newlines(1))
                    )
                })
            })
        }
    }
    
    private func genProtocol(name: String, conforms: [String], whereClauses: [Decl.WhereClause], decls: [Decl]) -> ProtocolDeclSyntax {
        ProtocolDeclSyntax {
            $0.useProtocolKeyword(
                SyntaxFactory.makeProtocolKeyword(
                    leadingTrivia: .spaces(indentationLevel),
                    trailingTrivia: .spaces(1)
                )
            )
            $0.useIdentifier(SyntaxFactory.makeIdentifier(name))
            if !conforms.isEmpty {
                $0.useInheritanceClause(TypeInheritanceClauseSyntax {
                    $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                    for (i, conformance) in conforms.enumerated() {
                        $0.addInheritedType(InheritedTypeSyntax {
                            $0.useTypeName(TypeSyntax(
                                SimpleTypeIdentifierSyntax {
                                    $0.useName(SyntaxFactory.makeIdentifier(conformance))
                                }
                            ))
                            if i < conforms.index(before: conforms.endIndex) {
                                $0.useTrailingComma(SyntaxFactory.makeCommaToken().withTrailingTrivia(.spaces(1)))
                            }
                        })
                    }
                })
            }
            if !whereClauses.isEmpty {
                $0.useGenericWhereClause(GenericWhereClauseSyntax {
                    $0.useWhereKeyword(SyntaxFactory.makeWhereKeyword(
                        leadingTrivia: .spaces(1),
                        trailingTrivia: .spaces(1)
                    ))
                    for (i, whereClause) in whereClauses.enumerated() {
                        $0.addRequirement(GenericRequirementSyntax {
                            $0.useBody(Syntax(genConformanceRequirement(whereClause: whereClause)))
                            if i < whereClauses.index(before: conforms.endIndex) {
                                $0.useTrailingComma(SyntaxFactory.makeCommaToken().withTrailingTrivia(.spaces(1)))
                            }
                        })
                    }
                })
            }
            $0.useMembers(MemberDeclBlockSyntax { builder in
                builder.useLeftBrace(SyntaxFactory.makeLeftBraceToken(
                    leadingTrivia: .spaces(1),
                    trailingTrivia: .newlines(1)
                ))
                indent {
                    for decl in decls {
                        builder.addMember(MemberDeclListItemSyntax {
                            $0.useDecl(gen(decl: decl).withTrailingTrivia(.newlines(1)))
                        })
                    }
                }
                builder.useRightBrace(SyntaxFactory.makeRightBraceToken(leadingTrivia: .spaces(indentationLevel), trailingTrivia: .newlines(1)))
            })
        }
    }
    
    private func genConformanceRequirement(whereClause: Decl.WhereClause) -> ConformanceRequirementSyntax {
        ConformanceRequirementSyntax {
            $0.useLeftTypeIdentifier(TypeSyntax(
                SimpleTypeIdentifierSyntax {
                    $0.useName(SyntaxFactory.makeIdentifier(whereClause.associatedType))
                }
            ))
            $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
            $0.useRightTypeIdentifier(TypeSyntax(
                SimpleTypeIdentifierSyntax {
                    $0.useName(SyntaxFactory.makeIdentifier(whereClause.constraint))
                }
            ))
        }
    }
    
    private func genProtocolVar(name: String, type: TypeSyntax) -> VariableDeclSyntax {
        VariableDeclSyntax {
            $0.useLetOrVarKeyword(
                SyntaxFactory.makeVarKeyword(
                    leadingTrivia: .spaces(indentationLevel),
                    trailingTrivia: .spaces(1)
                )
            )
            $0.addBinding(PatternBindingSyntax {
                $0.usePattern(PatternSyntax(
                    IdentifierPatternSyntax {
                        $0.useIdentifier(SyntaxFactory.makeIdentifier(name))
                    }
                ))
                $0.useTypeAnnotation(TypeAnnotationSyntax {
                    $0.useColon(
                        SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1))
                    )
                    $0.useType(type.withTrailingTrivia(.spaces(1)))
                })
                $0.useAccessor(Syntax(
                    AccessorBlockSyntax {
                        $0.useLeftBrace(SyntaxFactory.makeLeftBraceToken().withTrailingTrivia(.spaces(1)))
                        $0.addAccessor(AccessorDeclSyntax {
                            $0.useAccessorKind(SyntaxFactory.makeContextualKeyword("get").withTrailingTrivia(.spaces(1)))
                        })
                        $0.useRightBrace(
                            SyntaxFactory.makeRightBraceToken()
                        )
                    }
                ))
            })
        }.withTrailingTrivia(.newlines(1))
    }
    
    private func genAssociatedType(name: String, inherits: String) -> AssociatedtypeDeclSyntax {
        AssociatedtypeDeclSyntax {
            $0.useAssociatedtypeKeyword(
                SyntaxFactory.makeAssociatedtypeKeyword(
                    leadingTrivia: .spaces(indentationLevel),
                    trailingTrivia: .spaces(1)
                )
            )
            $0.useIdentifier(
                SyntaxFactory
                    .makeIdentifier(name)
            )
            $0.useInheritanceClause(TypeInheritanceClauseSyntax {
                $0.useColon(
                    SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1))
                )
                $0.addInheritedType(InheritedTypeSyntax {
                    $0.useTypeName(TypeSyntax(
                        SimpleTypeIdentifierSyntax {
                            $0.useName(SyntaxFactory.makeIdentifier(inherits))
                        }
                    ))
                })
            })
        }.withTrailingTrivia(.newlines(1))
    }
    
    private func genVariableDecl(identifier: String, type: TypeSyntax, initializer: ExprSyntax?, accessor: Decl.LetAccessor, isStatic: Bool) -> DeclSyntax {
        DeclSyntax(
            VariableDeclSyntax {
                let letOrVarKeyword: TokenSyntax
                switch accessor {
                case .let:
                    letOrVarKeyword = SyntaxFactory.makeLetKeyword()
                case .var, .get:
                    letOrVarKeyword = SyntaxFactory.makeVarKeyword()
                }
                $0.useLetOrVarKeyword(
                    letOrVarKeyword.withTrailingTrivia(.spaces(1))
                )
                if isStatic {
                    $0.addModifier(DeclModifierSyntax {
                        $0.useName(SyntaxFactory.makeStaticKeyword().withTrailingTrivia(.spaces(1)))
                    })
                }
                $0.addBinding(PatternBindingSyntax {
                    $0.usePattern(PatternSyntax(IdentifierPatternSyntax {
                        $0.useIdentifier(SyntaxFactory.makeIdentifier(identifier))
                    }))
                    $0.useTypeAnnotation(TypeAnnotationSyntax {
                        $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                        $0.useType(type)
                    })
                    if let initializer = initializer {
                        $0.useInitializer(InitializerClauseSyntax {
                            $0.useEqual(
                                SyntaxFactory.makeEqualToken(
                                    leadingTrivia: .spaces(1),
                                    trailingTrivia: .spaces(1)
                                )
                            )
                            $0.useValue(initializer)
                        })
                    }
                    if case .get(let body) = accessor {
                        if let body = body {
                            $0.useAccessor(Syntax(
                                CodeBlockSyntax { builder in
                                    builder.useLeftBrace(SyntaxFactory.makeLeftBraceToken(
                                        leadingTrivia: .spaces(1),
                                        trailingTrivia: .newlines(1)
                                    ))
                                    indent {
                                        builder.addStatement(CodeBlockItemSyntax {
                                            $0.useItem(gen(syntax: body).withTrailingTrivia(.newlines(1)))
                                        })
                                    }
                                    builder.useRightBrace(SyntaxFactory.makeRightBraceToken(
                                        leadingTrivia: .spaces(indentationLevel),
                                        trailingTrivia: .newlines(1)
                                    ))
                                }.withTrailingTrivia(.newlines(1))
                            ))
                        } else {
                            $0.useAccessor(Syntax(
                                AccessorBlockSyntax {
                                    $0.useLeftBrace(SyntaxFactory.makeLeftBraceToken(
                                        leadingTrivia: .spaces(1),
                                        trailingTrivia: .spaces(1)
                                    ))
                                    $0.addAccessor(AccessorDeclSyntax {
                                        $0.useAccessorKind(SyntaxFactory.makeContextualKeyword("get").withTrailingTrivia(.spaces(1)))
                                    })
                                    $0.useRightBrace(
                                        SyntaxFactory.makeRightBraceToken()
                                    )
                                }
                            ))
                        }
                    }
                })
            }.withLeadingTrivia(.spaces(indentationLevel))
        )
    }
    
    private func genReturnEnumMemberSwitchCase(`case`: Decl.Syntax.SwitchCase) -> SwitchCaseSyntax {
        SwitchCaseSyntax { builder in
            builder.useLabel(Syntax(
                SwitchCaseLabelSyntax {
                    $0.useCaseKeyword(
                        SyntaxFactory.makeCaseKeyword().withTrailingTrivia(.spaces(1))
                    )
                    $0.addCaseItem(genSingleAssociatedValBindingCaseItemSyntax(caseName: `case`.enumName, bindings: `case`.binds))
                    $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.newlines(1)))
                }
            ).withLeadingTrivia(.spaces(indentationLevel)))
            indent {
                builder.addStatement(CodeBlockItemSyntax {
                    $0.useItem(Syntax(
                        ReturnStmtSyntax {
                            $0.useReturnKeyword(SyntaxFactory.makeReturnKeyword(
                                leadingTrivia: .spaces(indentationLevel),
                                trailingTrivia: .spaces(1)
                            ))
                            $0.useExpression(gen(expr: `case`.returns))
                        }
                    ))
                })
            }
        }
    }
    
    private func genSwitch(expr: ExprSyntax, cases: [SwitchCaseSyntax]) -> SwitchStmtSyntax {
        SwitchStmtSyntax {
            $0.useSwitchKeyword(
                SyntaxFactory.makeSwitchKeyword(
                    leadingTrivia: .spaces(indentationLevel),
                    trailingTrivia: .spaces(1)
                )
            )
            $0.useExpression(expr.withTrailingTrivia(.spaces(1)))
            $0.useLeftBrace(
                SyntaxFactory.makeLeftBraceToken().withTrailingTrivia(.newlines(1))
            )
            $0.useRightBrace(
                SyntaxFactory.makeRightBraceToken().withLeadingTrivia(.spaces(indentationLevel))
            )
            for `case` in cases {
                $0.addCase(Syntax(`case`).withTrailingTrivia(.newlines(1)))
            }
        }
    }
    
    private func genFunc(name: String, returnType: TypeSyntax, body: (() -> Syntax)?, access: Decl.FuncAccess?) -> FunctionDeclSyntax {
        FunctionDeclSyntax {
            if let access = access {
                $0.addModifier(DeclModifierSyntax {
                    switch access {
                    case .fileprivate:
                        $0.useName(SyntaxFactory.makeFileprivateKeyword())
                    }
                }.withTrailingTrivia(.spaces(1)))
            }
            $0.useFuncKeyword(
                SyntaxFactory.makeFuncKeyword()
                    .withTrailingTrivia(.spaces(1))
            )
            $0.useIdentifier(SyntaxFactory.makeIdentifier(name))
            $0.useSignature(FunctionSignatureSyntax {
                $0.useInput(ParameterClauseSyntax {
                    $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
                    $0.useRightParen(SyntaxFactory.makeRightParenToken())
                }.withTrailingTrivia(.spaces(1)))
                $0.useOutput(ReturnClauseSyntax {
                    $0.useArrow(SyntaxFactory.makeArrowToken().withTrailingTrivia(.spaces(1)))
                    $0.useReturnType(returnType)
                })
            })
            if let body = body {
                $0.useBody(CodeBlockSyntax { builder in
                    builder.useLeftBrace(SyntaxFactory.makeLeftBraceToken(leadingTrivia: .spaces(1), trailingTrivia: .newlines(1)))
                    indent {
                        builder.addStatement(CodeBlockItemSyntax {
                            $0.useItem(body().withTrailingTrivia(.newlines(1)))
                        })
                    }
                    builder.useRightBrace(SyntaxFactory.makeRightBraceToken(leadingTrivia: .spaces(indentationLevel), trailingTrivia: .newlines(1)))
                })
            }
        }.withLeadingTrivia(.spaces(indentationLevel))
    }
    
    private func genMemberAccess(base: Expr?, member: String) -> MemberAccessExprSyntax {
        MemberAccessExprSyntax {
            if let base = base {
                $0.useBase(gen(expr: base))
            }
            $0.useDot(SyntaxFactory.makePeriodToken())
            $0.useName(SyntaxFactory.makeIdentifier(member))
        }
    }
    
    private func genFunctionCall(called: Expr, args: [Expr.Arg]) -> FunctionCallExprSyntax {
        FunctionCallExprSyntax {
            $0.useCalledExpression(gen(expr: called))
            $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
            
            for (i, arg) in args.enumerated() {
                $0.addArgument(TupleExprElementSyntax {
                    switch arg {
                    case let .named(name, expr):
                        $0.useLabel(SyntaxFactory.makeIdentifier(name))
                        $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                        $0.useExpression(gen(expr: expr))
                    case let .unnamed(expr):
                        $0.useExpression(gen(expr: expr))
                    }
                    if i < args.index(before: args.endIndex) {
                        $0.useTrailingComma(
                            SyntaxFactory.makeCommaToken()
                                .withTrailingTrivia(.spaces(1))
                        )
                    }
                })
            }
            
            $0.useRightParen(SyntaxFactory.makeRightParenToken())
        }
    }
    
    private func genIdentifier(_ identifier: String) -> IdentifierExprSyntax {
        IdentifierExprSyntax {
            $0.useIdentifier(SyntaxFactory.makeIdentifier(identifier))
        }
    }

    private func genClosure(expr: Expr) -> ClosureExprSyntax {
        ClosureExprSyntax {
            $0.useLeftBrace(SyntaxFactory.makeLeftBraceToken().withTrailingTrivia(.spaces(1)))
            $0.addStatement(CodeBlockItemSyntax {
                $0.useItem(Syntax(gen(expr: expr)))
            }.withTrailingTrivia(.spaces(1)))
            $0.useRightBrace(SyntaxFactory.makeRightBraceToken())
        }
    }
    
    private func genBoolLiteral(bool: Bool) -> BooleanLiteralExprSyntax {
        BooleanLiteralExprSyntax {
            $0.useBooleanLiteral(
                bool ?
                SyntaxFactory.makeTrueKeyword() :
                    SyntaxFactory.makeFalseKeyword()
            )
        }
    }
    
    private func genIntLiteral(int: Int) -> IntegerLiteralExprSyntax {
        SyntaxFactory.makeIntegerLiteralExpr(digits: SyntaxFactory.makeIntegerLiteral("\(int)"))
    }
    
    private func genFloatLiteral(float: Double) -> FloatLiteralExprSyntax {
        SyntaxFactory.makeFloatLiteralExpr(floatingDigits: SyntaxFactory.makeFloatingLiteral("\(float)"))
    }
    
    private func genArray(array: [Expr]) -> ArrayExprSyntax {
        ArrayExprSyntax { builder in
            builder.useLeftSquare(
                SyntaxFactory.makeLeftSquareBracketToken()
            )
            indent {
                for (i, x) in array.enumerated() {
                    builder.addElement(ArrayElementSyntax {
                        $0.useExpression(gen(expr: x))
                        if i < array.index(before: array.endIndex) {
                            $0.useTrailingComma(
                                SyntaxFactory.makeCommaToken()
                                    .withTrailingTrivia(.spaces(1))
                            )
                        }
                    }.withLeadingTrivia(.spaces(indentationLevel)))
                }
            }
            builder.useRightSquare(
                SyntaxFactory.makeRightSquareBracketToken()
            )
        }
    }
    
    private func genDictionary(dictionary: OrderedDictionary<Expr, Expr>) -> DictionaryExprSyntax {
        DictionaryExprSyntax { builder in
            builder.useLeftSquare(
                SyntaxFactory.makeLeftSquareBracketToken()
            )
            
            if dictionary.isEmpty {
                builder.useContent(Syntax(SyntaxFactory.makeColonToken()))
            } else {
                let keyVals = dictionary.map { ($0, $1) }
                let elements = keyVals.enumerated().map { i, x in
                    indent {
                        DictionaryElementSyntax {
                            $0.useKeyExpression(gen(expr: x.0))
                            $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                            $0.useValueExpression(gen(expr: x.1))
                            if i < keyVals.index(before: keyVals.endIndex) {
                                $0.useTrailingComma(
                                    SyntaxFactory.makeCommaToken()
                                )
                            }
                        }.withLeadingTrivia(.newlines(1).appending(.spaces(indentationLevel)))
                    }
                }
                builder.useContent(Syntax(SyntaxFactory.makeDictionaryElementList(elements)))
            }
            builder.useRightSquare(
                SyntaxFactory.makeRightSquareBracketToken()
            )
        }
    }
    
    private func indent<T>(_ f: () -> T) -> T {
        indentationLevel = indentationLevel + 4
        defer {
            indentationLevel = indentationLevel - 4
        }
        return f()
    }
    
    private func typeSyntax(for type: DeclType) -> TypeSyntax {
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
        case .memberType(let name, let base):
            return TypeSyntax(MemberTypeIdentifierSyntax {
                $0.useBaseType(typeSyntax(for: base))
                $0.usePeriod(SyntaxFactory.makePeriodToken())
                $0.useName(SyntaxFactory.makeIdentifier(name))
            })
        }
    }

}


func genStringLiteral(string: String, multiline: Bool = false) -> ExprSyntax {
    let quote = multiline ?
        SyntaxFactory
            .makeMultilineStringQuoteToken()
            .withTrailingTrivia(.newlines(1))
        :
        SyntaxFactory.makeStringQuoteToken()
    return ExprSyntax(
        StringLiteralExprSyntax {
            $0.useOpenQuote(quote)
            $0.useCloseQuote(quote)
            $0.addSegment(Syntax(
                StringSegmentSyntax {
                    $0.useContent(SyntaxFactory.makeStringLiteral(string))
                }
            ))
        }
   )
}
