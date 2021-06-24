//
//  SwiftGen.swift
//  
//
//  Created by Luke Lau on 23/12/2021.
//

import SwiftSyntax

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
        case let .let(name, type, defaultValue, isVar, getter):
            return DeclSyntax(
                genVariableDecl(
                    identifier: name,
                    type: typeSyntax(for: type),
                    defaultValue: defaultValue,
                    isVar: isVar,
                    getter: getter.mapThunk(gen(syntax:))
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
        case let .protocol(name, conforms, decls):
            return DeclSyntax(genProtocol(name: name, conforms: conforms, decls: decls))
        case let .protocolVar(name, type):
            return DeclSyntax(genProtocolVar(name: name, type: typeSyntax(for: type)))
        case let .associatedtype(name, inherits):
            return DeclSyntax(genAssociatedType(name: name, inherits: inherits))
        case let .func(name, returnType, body):
            return DeclSyntax(
                genFunc(
                    name: name,
                    returnType: typeSyntax(for: returnType),
                    body: body.mapThunk(gen(syntax:))
                )
            )
        }
    }
    
    private func gen(syntax: Decl.Syntax) -> Syntax {
        switch syntax {
        case let .returnSwitch(expr, cases):
            return Syntax(
                genSwitch(
                    expr: expr,
                    cases: cases.map { genReturnEnumMemberSwitchCase(caseName: $0.key, memberName: $0.value) }
                )
            )
        }
    }
    
    private func genInheritanceClause(conforms: [String]) -> TypeInheritanceClauseSyntax {
        TypeInheritanceClauseSyntax {
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
                }.withTrailingTrivia(.spaces(1)))
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
                        })
                    }
                    
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
                                                forKey: SyntaxFactory.makeIdentifier("__typename")
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
    private func genDecode(container: String, type: TypeSyntax, forKey: TokenSyntax) -> ExprSyntax {
        ExprSyntax(TryExprSyntax {
            $0.useTryKeyword(SyntaxFactory.makeTryKeyword().withTrailingTrivia(.spaces(1)))
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
            ))
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
    
//    private func genEnumEncodeSwitch(cases: [String]) -> SwitchStmtSyntax {
//        gensw
//        SwitchStmtSyntax {
//            $0.useSwitchKeyword(
//                SyntaxFactory.makeSwitchKeyword(
//                    leadingTrivia: .spaces(indentationLevel),
//                    trailingTrivia: .spaces(1)
//                )
//            )
//            $0.useExpression(ExprSyntax(
//                IdentifierExprSyntax {
//                    $0.useIdentifier(
//                        SyntaxFactory.makeSelfKeyword().withTrailingTrivia(.spaces(1))
//                    )
//                }
//            ))
//            $0.useLeftBrace(
//                SyntaxFactory.makeLeftBraceToken().withTrailingTrivia(.newlines(1))
//            )
//            $0.useRightBrace(
//                SyntaxFactory.makeRightBraceToken().withLeadingTrivia(.spaces(indentationLevel))
//            )
//            for caseName in cases {
//                $0.addCase(Syntax(
//                    genEnumEncodeSwitchCase(caseName: caseName)
//                ))
//            }
//        }
//    }
    
    private func genEnumEncodeSwitchCase(caseName: String) -> SwitchCaseSyntax {
        SwitchCaseSyntax { builder in
            builder.useLabel(Syntax(
                SwitchCaseLabelSyntax {
                    $0.useCaseKeyword(
                        SyntaxFactory.makeCaseKeyword().withTrailingTrivia(.spaces(1))
                    )
                    $0.addCaseItem(genSingleAssociatedValBindingCaseItemSyntax(caseName: caseName, bindingName: caseName))
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
    
    /// Generates a case item binding for an enum with a single associated value, binding the value
    ///
    /// Generates
    /// ```swift
    /// .caseName(let bindingName)
    /// ```
    private func genSingleAssociatedValBindingCaseItemSyntax(caseName: String, bindingName: String) -> CaseItemSyntax {
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
                            $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
                            $0.addArgument(TupleExprElementSyntax {
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
                                                        $0.useIdentifier(SyntaxFactory.makeIdentifier(bindingName))
                                                    }
                                                ))
                                            }
                                        ))
                                    }
                                ))
                            })
                            $0.useRightParen(SyntaxFactory.makeRightParenToken())
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
    
    private func genProtocol(name: String, conforms: [String], decls: [Decl]) -> ProtocolDeclSyntax {
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
                }.withTrailingTrivia(.spaces(1)))
            }
            $0.useMembers(MemberDeclBlockSyntax { builder in
                builder.useLeftBrace(SyntaxFactory.makeLeftBraceToken().withTrailingTrivia(.newlines(1)))
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
    
//    func generate(def: OperationDefinition) -> [DeclSyntax] {
//        let structName = (def.name?.value.capitalized ?? "Anonymous") + "Query"
//        let structDecl = StructDeclSyntax { builder in
//            builder.useStructKeyword(SyntaxFactory.makeStructKeyword().withTrailingTrivia(.spaces(1)))
//            builder.useIdentifier(SyntaxFactory.makeIdentifier(structName))
//            builder.useInheritanceClause(
//                TypeInheritanceClauseSyntax {
//                    $0.useColon(SyntaxFactory.makeColonToken(leadingTrivia: .zero, trailingTrivia: .spaces(1)))
//                    $0.addInheritedType(InheritedTypeSyntax {
//                        $0.useTypeName(TypeSyntax(
//                            SyntaxFactory.makeSimpleTypeIdentifier(
//                                name: SyntaxFactory.makeIdentifier("Decodable"),
//                                genericArgumentClause: nil
//                            )
//                        ))
//                        $0.useTrailingComma(SyntaxFactory.makeCommaToken(leadingTrivia: .zero, trailingTrivia: .spaces(1)))
//                    })
//                    $0.addInheritedType(InheritedTypeSyntax {
//                        $0.useTypeName(TypeSyntax(
//                            SyntaxFactory.makeSimpleTypeIdentifier(
//                                name: SyntaxFactory.makeIdentifier("Queryable"),
//                                genericArgumentClause: nil
//                            )
//                        ))
//                    })
//                }
//            )
//            indent {
//                builder.useMembers(MemberDeclBlockSyntax {
//                    $0.useLeftBrace(SyntaxFactory.makeLeftBraceToken().withLeadingTrivia(.spaces(1)).withTrailingTrivia(.newlines(1)))
//                    $0.useRightBrace(SyntaxFactory.makeRightBraceToken())
//                    for item in genSelectionSet(parentType: schema.queryType, selectionSet: def.selectionSet) {
//                        $0.addMember(item)
//                    }
//                    $0.addMember(MemberDeclListItemSyntax {
//                        $0.useDecl(DeclSyntax(genDecoderInit(type: schema.queryType, selectionSet: def.selectionSet)))
//                    })
//                })
//            }
//        }
//        return [DeclSyntax(structDecl)] + topLevelDecls
//    }
    
    private func genVariableDecl(identifier: String, type: TypeSyntax, defaultValue: ExprSyntax?, isVar: Bool, getter: (() -> Syntax)?) -> DeclSyntax {
        DeclSyntax(
            VariableDeclSyntax {
                $0.useLetOrVarKeyword(
                    (isVar ? SyntaxFactory.makeVarKeyword() : SyntaxFactory.makeLetKeyword())
                        .withTrailingTrivia(.spaces(1))
                )
                $0.addBinding(PatternBindingSyntax {
                    $0.usePattern(PatternSyntax(IdentifierPatternSyntax {
                        $0.useIdentifier(SyntaxFactory.makeIdentifier(identifier))
                    }))
                    $0.useTypeAnnotation(TypeAnnotationSyntax {
                        $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                        $0.useType(type)
                    })
                    if let defaultValue = defaultValue {
                        $0.useInitializer(InitializerClauseSyntax {
                            $0.useEqual(
                                SyntaxFactory.makeEqualToken(
                                    leadingTrivia: .spaces(1),
                                    trailingTrivia: .spaces(1)
                                )
                            )
                            $0.useValue(defaultValue)
                        })
                    }
                    if let getter = getter {
                        $0.useAccessor(Syntax(
                            CodeBlockSyntax { builder in
                                builder.useLeftBrace(SyntaxFactory.makeLeftBraceToken(
                                    leadingTrivia: .spaces(1),
                                    trailingTrivia: .newlines(1)
                                ))
                                indent {
                                    builder.addStatement(CodeBlockItemSyntax {
                                        $0.useItem(getter().withTrailingTrivia(.newlines(1)))
                                    })
                                }
                                builder.useRightBrace(SyntaxFactory.makeRightBraceToken(
                                    leadingTrivia: .spaces(indentationLevel),
                                    trailingTrivia: .newlines(1)
                                ))
                            }.withTrailingTrivia(.newlines(1))
                        ))
                    }
                })
            }.withLeadingTrivia(.spaces(indentationLevel))
        )
    }
    
    private func genReturnEnumMemberSwitchCase(caseName: String, memberName: String) -> SwitchCaseSyntax {
        SwitchCaseSyntax { builder in
            builder.useLabel(Syntax(
                SwitchCaseLabelSyntax {
                    $0.useCaseKeyword(
                        SyntaxFactory.makeCaseKeyword().withTrailingTrivia(.spaces(1))
                    )
                    $0.addCaseItem(genSingleAssociatedValBindingCaseItemSyntax(caseName: caseName, bindingName: caseName))
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
                            $0.useExpression(ExprSyntax(
                                MemberAccessExprSyntax {
                                    $0.useBase(ExprSyntax(
                                        IdentifierExprSyntax {
                                            $0.useIdentifier(SyntaxFactory.makeIdentifier(caseName))
                                        }
                                    ))
                                    $0.useDot(SyntaxFactory.makePeriodToken())
                                    $0.useName(SyntaxFactory.makeIdentifier(memberName))
                                }
                            ))
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
    
    private func genFunc(name: String, returnType: TypeSyntax, body: (() -> Syntax)?) -> FunctionDeclSyntax {
        FunctionDeclSyntax {
            $0.useFuncKeyword(SyntaxFactory.makeFuncKeyword(
                leadingTrivia: .spaces(indentationLevel),
                trailingTrivia: .spaces(1)
            ))
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
        }
    }
    
//    private func genSelectionSet(parentType: GraphQLType, selectionSet: SelectionSet) -> [MemberDeclListItemSyntax] {
//        selectionSet.selections.flatMap { (selection: Selection) -> [MemberDeclListItemSyntax] in
//            var declListItems = [MemberDeclListItemSyntax]()
//            switch selection {
//            case let .field(field):
//                let x = getFieldDef(schema: schema, parentType: parentType, fieldAST: field)!
//                declListItems.append(MemberDeclListItemSyntax {
//                    $0.useDecl(DeclSyntax(
//                        VariableDeclSyntax {
//                            $0.useLetOrVarKeyword(SyntaxFactory.makeLetKeyword().withTrailingTrivia(.spaces(1)))
//                            $0.addBinding(PatternBindingSyntax {
//                                $0.usePattern(PatternSyntax(IdentifierPatternSyntax {
//                                    $0.useIdentifier(fieldToIdentifier(field))
//                                }))
//                                $0.useTypeAnnotation(TypeAnnotationSyntax {
//                                    $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
//                                    $0.useType(typeSyntax(for: x.type))
//                                })
//                            })
//                        }.withLeadingTrivia(.spaces(indentationLevel))
//                    ))
//                }.withTrailingTrivia(.newlines(1)))
//
//                let nestedTypes = genNestedType(schema: schema, type: x.type, selectionSet: field.selectionSet)
//                declListItems.append(contentsOf: nestedTypes)
//            default:
//                break
////                fatalError()
//            }
//            return declListItems
//        }
//    }
//
//    private func genNestedType(schema: GraphQLSchema, type: GraphQLOutputType, selectionSet: SelectionSet?) -> [MemberDeclListItemSyntax] {
//        switch type {
//        case is GraphQLScalarType:
//            return []
//        case let type as GraphQLObjectType:
//            return [MemberDeclListItemSyntax {
//                $0.useDecl(
//                    DeclSyntax(
//                        genObjectStruct(type: type, selectionSet: selectionSet!)
//                    )
//                )
//            }]
//        case let type as GraphQLInterfaceType:
//            self.topLevelDecls.append(
//                DeclSyntax(
//                    genInterfaceProtocol(type: type, selectionSet: selectionSet!)
//                )
//            )
//            return selectionSet!.selections.compactMap {
//                switch $0 {
//                case let .inlineFragment(inlineFragment):
//                    return MemberDeclListItemSyntax {
//                        $0.useDecl(
//                            DeclSyntax(
//                                genInterfaceFragmentStruct(interfaceType: type, interfaceSelectionSet: selectionSet!, inlineFragment: inlineFragment)
//                            )
//                        )
//                    }
//                default:
//                    return nil
//                }
//            }
//        case let type as GraphQLEnumType:
//            fatalError()
//        case let type as GraphQLUnionType:
//            fatalError()
//        case let type as GraphQLList:
//            return genNestedType(schema: schema, type: type.ofType as! GraphQLOutputType, selectionSet: selectionSet)
//        case let type as GraphQLNonNull:
//            return genNestedType(schema: schema, type: type.ofType as! GraphQLOutputType, selectionSet: selectionSet)
//        default:
//            fatalError()
//        }
//    }
//
//    private func genInterfaceProtocol(type: GraphQLInterfaceType, selectionSet: SelectionSet) -> ProtocolDeclSyntax {
//        ProtocolDeclSyntax {
//            $0.useProtocolKeyword(SyntaxFactory.makeProtocolKeyword().withTrailingTrivia(.spaces(1)))
//            $0.useIdentifier(SyntaxFactory.makeIdentifier(type.name))
//            $0.inheritFromDecodable()
//            $0.useMembers(MemberDeclBlockSyntax {
//                $0.useLeftBrace(SyntaxFactory.makeLeftBraceToken().withLeadingTrivia(.spaces(1)).withTrailingTrivia(.newlines(1)))
//                $0.useRightBrace(SyntaxFactory.makeRightBraceToken())
//
//                for selection in selectionSet.selections {
//                    for listItem in genInterfaceVars(parentType: type, selection: selection) {
//                        $0.addMember(listItem)
//                    }
//                }
//            })
//        }
//    }
//
//    private func genInterfaceVars(parentType: GraphQLType, selection: Selection) -> [MemberDeclListItemSyntax] {
//        switch selection {
//        case let .field(field):
//            let fieldDef = getFieldDef(schema: schema, parentType: parentType, fieldAST: field)!
//            return [
//                MemberDeclListItemSyntax {
//                    $0.useDecl(DeclSyntax(
//                        VariableDeclSyntax {
//                            $0.useLetOrVarKeyword(SyntaxFactory.makeVarKeyword().withTrailingTrivia(.spaces(1)))
//                            $0.addBinding(PatternBindingSyntax {
//                                $0.usePattern(PatternSyntax(IdentifierPatternSyntax {
//                                    $0.useIdentifier(fieldToIdentifier(field))
//                                }))
//                                $0.useTypeAnnotation(TypeAnnotationSyntax {
//                                    $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
//                                    $0.useType(typeSyntax(for: fieldDef.type).withTrailingTrivia(.spaces(1)))
//                                })
//                                $0.useAccessor(Syntax(
//                                    AccessorBlockSyntax {
//                                        $0.useLeftBrace(
//                                            SyntaxFactory.makeLeftBraceToken().withTrailingTrivia(.spaces(1))
//                                        )
//                                        $0.useRightBrace(SyntaxFactory.makeRightBraceToken())
//                                        $0.addAccessor(AccessorDeclSyntax {
//                                            $0.useAccessorKind(
//                                                SyntaxFactory.makeContextualKeyword("get").withTrailingTrivia(.spaces(1))
//                                            )
//                                        })
//                                    }
//                                ))
//                            })
//                        }
//                    ))
//                }.withTrailingTrivia(.newlines(1))
//            ]
//        case .inlineFragment:
//            return []
//        default:
//            fatalError()
//        }
//    }
//
//    private func genInterfaceFragmentStruct(interfaceType: GraphQLInterfaceType, interfaceSelectionSet: SelectionSet, inlineFragment: InlineFragment) -> StructDeclSyntax {
//        genStruct(
//            name: inlineFragment.typeCondition!.name.value,
//            conforms: ["Decodable", interfaceType.name],
//            listItems:
//                genSelectionSet(parentType: schema.getType(name: inlineFragment.typeCondition!.name.value)!, selectionSet: inlineFragment.selectionSet) +
//            genSelectionSet(parentType: interfaceType, selectionSet: interfaceSelectionSet)
//        )
//    }
//
//
//    private func genObjectStruct(type: GraphQLObjectType, selectionSet: SelectionSet) -> StructDeclSyntax {
//        return genStruct(
//            name: type.name,
//            conforms: ["Decodable"],
//            listItems: genSelectionSet(parentType: type, selectionSet: selectionSet)
//        )
//    }
    
    private func indent<T>(_ f: () -> T) -> T {
        indentationLevel = indentationLevel + 4
        defer {
            indentationLevel = indentationLevel - 4
        }
        return f()
    }
    
//
//    private func genStruct(name: String, conforms: [String], listItems: [MemberDeclListItemSyntax]) -> StructDeclSyntax {
//        StructDeclSyntax {
//            $0.useStructKeyword(SyntaxFactory.makeStructKeyword().withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.spaces(1)))
//            $0.useIdentifier(SyntaxFactory.makeIdentifier(name))
//
//            if !conforms.isEmpty {
//                $0.useInheritanceClause(
//                    TypeInheritanceClauseSyntax {
//                        $0.useColon(SyntaxFactory.makeColonToken(leadingTrivia: .zero, trailingTrivia: .spaces(1)))
//                        for (i, identifier) in conforms.enumerated() {
//                            $0.addInheritedType(InheritedTypeSyntax {
//                                $0.useTypeName(TypeSyntax(
//                                    SyntaxFactory.makeSimpleTypeIdentifier(
//                                        name: SyntaxFactory.makeIdentifier(identifier),
//                                        genericArgumentClause: nil
//                                    )
//                                ))
//                                if (i < conforms.endIndex - 1) {
//                                $0.useTrailingComma(SyntaxFactory.makeCommaToken(leadingTrivia: .zero, trailingTrivia: .spaces(1)))
//                                }
//                            })
//                        }
//                    }
//                )
//            }
//
//
//            $0.useMembers(MemberDeclBlockSyntax { builder in
//                builder.useLeftBrace(SyntaxFactory.makeLeftBraceToken().withLeadingTrivia(.spaces(1)).withTrailingTrivia(.newlines(1)))
//
//                indent {
//                    listItems.forEach { builder.addMember($0) }
//                }
//
//                builder.useRightBrace(SyntaxFactory.makeRightBraceToken().withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.newlines(1)))
//
//            })
//        }
//    }
//
//    private func genDecoderInit(type: GraphQLObjectType, selectionSet: SelectionSet) -> InitializerDeclSyntax {
//
//
//        func genDecodeInterface(_ interfaceType: GraphQLOutputType, inlineFragments: [InlineFragment], variableIdentifier: TokenSyntax) -> [CodeBlockItemSyntax] {
//
//            let interfaceContainerName = "\(variableIdentifier.text)Container"
//            let interfaceContainerDecl = genContainer(name: interfaceContainerName, keyedBy: "TypeCodingKeys")
//            let typenameDecl = VariableDeclSyntax {
//                $0.useLetOrVarKeyword(SyntaxFactory.makeLetKeyword().withTrailingTrivia(.spaces(1)))
//                $0.addBinding(PatternBindingSyntax {
//                    $0.usePattern(PatternSyntax(
//                        IdentifierPatternSyntax {
//                            $0.useIdentifier(SyntaxFactory.makeIdentifier("typename"))
//                        }
//                    ))
//                    $0.useInitializer(InitializerClauseSyntax {
//                        $0.useEqual(SyntaxFactory.makeEqualToken(leadingTrivia: .spaces(1), trailingTrivia: .spaces(1)))
//                        $0.useValue(
//                            genDecode(container: interfaceContainerName, type: GraphQLString, forKey: SyntaxFactory.makeIdentifier("__typename"))
//                        )
//                    })
//                })
//            }.withLeadingTrivia(.spaces(indentationLevel))
//            let switchDecl = SwitchStmtSyntax {
//                $0.useSwitchKeyword(SyntaxFactory.makeSwitchKeyword().withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.spaces(1)))
//                $0.useExpression(ExprSyntax(
//                    IdentifierExprSyntax {
//                        $0.useIdentifier(SyntaxFactory.makeIdentifier("typename"))
//                    }
//                ).withTrailingTrivia(.spaces(1)))
//                $0.useLeftBrace(SyntaxFactory.makeLeftBraceToken().withTrailingTrivia(.newlines(1)))
//                $0.useRightBrace(SyntaxFactory.makeRightBraceToken().withLeadingTrivia(.spaces(indentationLevel)))
//                for fragment in inlineFragments {
//                    $0.addCase(Syntax(
//                        SwitchCaseSyntax { builder in
//                            builder.useLabel(Syntax(
//                                SwitchCaseLabelSyntax {
//                                    $0.useCaseKeyword(SyntaxFactory.makeCaseKeyword().withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.spaces(1)))
//                                    $0.addCaseItem(CaseItemSyntax {
//                                        $0.usePattern(
//                                            PatternSyntax(
//                                                ExpressionPatternSyntax {
//                                                    $0.useExpression(
//                                                        genStringLiteral(string: fragment.typeCondition!.name.value)
//                                                    )
//                                                }
//                                            )
//                                        )
//                                    })
//                                    $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.newlines(1)))
//                                }
//                            ))
//                            indent {
//                                let type = schema.getType(name: fragment.typeCondition!.name.value) as! GraphQLOutputType
//                                builder.addStatement(
//                                    genSelfAssignment(
//                                        variableIdentifier: variableIdentifier,
//                                        expr: genDecode(container: "container", type: type, forKey: variableIdentifier)
//                                    )
//                                )
//                            }
//                        }
//                    ))
//                }
//            }
//            return [Syntax(interfaceContainerDecl), Syntax(typenameDecl), Syntax(switchDecl)].map { $0.withTrailingTrivia(.newlines(1)) }.map { syntax in
//                CodeBlockItemSyntax {
//                    $0.useItem(syntax)
//                }
//            }
//        }
//
//        return InitializerDeclSyntax {
//            $0.useInitKeyword(SyntaxFactory.makeInitKeyword().withLeadingTrivia(.spaces(indentationLevel)))
//            $0.useParameters(ParameterClauseSyntax {
//                $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
//                $0.useRightParen(SyntaxFactory.makeRightParenToken())
//                $0.addParameter(FunctionParameterSyntax {
//                    $0.useFirstName(SyntaxFactory.makeIdentifier("from").withTrailingTrivia(.spaces(1)))
//                    $0.useSecondName(SyntaxFactory.makeIdentifier("decoder"))
//                    $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
//                    $0.useType(TypeSyntax(
//                        SimpleTypeIdentifierSyntax {
//                            $0.useName(SyntaxFactory.makeIdentifier("Decoder"))
//                        }
//                    ))
//                })
//            }.withTrailingTrivia(.spaces(1)))
//            $0.useThrowsOrRethrowsKeyword(SyntaxFactory.makeThrowsKeyword().withTrailingTrivia(.spaces(1)))
//            $0.useBody(CodeBlockSyntax { builder in
//                builder.useLeftBrace(SyntaxFactory.makeLeftBraceToken().withTrailingTrivia(.newlines(1)))
//                builder.useRightBrace(SyntaxFactory.makeRightBraceToken().withLeadingTrivia(.newlines(1).appending(.spaces(indentationLevel))).withTrailingTrivia(.newlines(1)))
//                indent {
//                    builder.addStatement(CodeBlockItemSyntax{
//                        $0.useItem(
//                            Syntax(genContainer(name: "container", keyedBy: "CodingKeys"))
//                        )
//                    })
//                    selectionSet.selections.flatMap(genInitAssignment).forEach { builder.addStatement($0) }
//                }
//            })
//        }
//    }
    
    
//    private func genSelfAssignment(variableIdentifier: TokenSyntax, expr: ExprSyntax) -> CodeBlockItemSyntax {
//        CodeBlockItemSyntax {
//            $0.useItem(
//                Syntax(
//                    SequenceExprSyntax {
//                        $0.addElement(ExprSyntax(
//                            MemberAccessExprSyntax {
//                                $0.useName(variableIdentifier)
//                                $0.useDot(SyntaxFactory.makePeriodToken())
//                                $0.useBase(ExprSyntax(
//                                    IdentifierExprSyntax {
//                                        $0.useIdentifier(SyntaxFactory.makeSelfKeyword())
//                                    }
//                                ))
//                            }
//                        ))
//                        $0.addElement(ExprSyntax(
//                            AssignmentExprSyntax {
//                                $0.useAssignToken(SyntaxFactory.makeEqualToken(leadingTrivia: .spaces(1), trailingTrivia: .spaces(1)))
//                            }
//                        ))
//                        $0.addElement(expr)
//                    }
//                )
//            )
//        }.withLeadingTrivia(.spaces(indentationLevel)).withTrailingTrivia(.newlines(1))
//    }
    
//    private func fieldToIdentifier(_ field: Field) -> TokenSyntax {
//        let name: String
//        if let alias = field.alias {
//            name = alias.value
//        } else {
//            name = field.name.value
//        }
//        return SyntaxFactory.makeIdentifier(name)
//    }
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
