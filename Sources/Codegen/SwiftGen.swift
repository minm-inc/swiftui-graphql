//
//  SwiftGen.swift
//  
//
//  Created by Luke Lau on 23/12/2021.
//

import SwiftSyntax
import OrderedCollections

class SwiftGen {
    private var indentationLevel = 0
    
    func gen(decl: Decl) -> DeclSyntax {
        switch decl {
        case let .let(name, type, initializer, accessor, isStatic):
            return DeclSyntax(
                genVariableDecl(
                    identifier: name,
                    type: type.map(gen(type:)),
                    initializer: initializer.map(gen),
                    accessor: accessor,
                    isStatic: isStatic
                )
            ).withTrailingTrivia(.newlines(1))
        case let .struct(name, decls, conforms):
            return DeclSyntax(genStruct(name: name, decls: decls, conforms: conforms))
                        .withTrailingTrivia(.newlines(1))
        case let .extension(type, conforms, decls):
            return DeclSyntax(
                genExtension(
                    type: gen(type: type),
                    conforms: conforms,
                    decls: decls
                )
            ).withTrailingTrivia(.newlines(1))
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
        case let .protocol(name, conforms, whereClauses, decls):
            return DeclSyntax(genProtocol(name: name, conforms: conforms, whereClauses: whereClauses, decls: decls))
        case let .associatedtype(name, inherits):
            return DeclSyntax(genAssociatedType(name: name, inherits: inherits))
        case let .func(name, parameters, `throws`, returnType, body, access):
            return DeclSyntax(
                genFunc(
                    name: name,
                    parameters: parameters,
                    throws: `throws`,
                    returnType: returnType.map(gen(type:)),
                    body: body.mapThunk { $0.map(self.gen(syntax:)) },
                    access: access
                )
            )
        case let .`init`(parameters, `throws`, body):
            return DeclSyntax(genInit(parameters: parameters, throws: `throws`, body: body.mapThunk { $0.map(self.gen(syntax:)) }))
        case let .`typealias`(name, type):
            return DeclSyntax(genTypealias(name: name, type: gen(type: type)))
        }
    }
    
    private func gen(syntax: Decl.Syntax) -> Syntax {
        switch syntax {
        case let .expr(expr):
            return Syntax(gen(expr: expr).withLeadingTrivia(.spaces(indentationLevel)))
        case let .return(expr):
            return Syntax(ReturnStmtSyntax {
                $0.useReturnKeyword(SyntaxFactory.makeReturnKeyword(
                    leadingTrivia: .spaces(indentationLevel),
                    trailingTrivia: .spaces(1)
                ))
                $0.useExpression(gen(expr: expr))
            })
        case let .decl(decl):
            return Syntax(gen(decl: decl))
        case let .switch(expr, cases):
            return Syntax(genSwitch(expr: gen(expr: expr), cases: cases.map(gen(case:))))
        case let .assignment(lhs, rhs):
            return Syntax(SequenceExprSyntax {
                $0.addElement(gen(expr: lhs))
                $0.addElement(ExprSyntax(AssignmentExprSyntax {
                    $0.useAssignToken(SyntaxFactory.makeEqualToken(
                        leadingTrivia: .spaces(1), trailingTrivia: .spaces(1)
                    ))
                }))
                $0.addElement(gen(expr: rhs))
            }.withLeadingTrivia(.spaces(indentationLevel)))
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
        case let .stringLiteral(string, multiline):
            return genStringLiteral(string: string, multiline: multiline)
        case let .boolLiteral(bool):
            return ExprSyntax(genBoolLiteral(bool: bool))
        case let .intLiteral(int):
            return ExprSyntax(genIntLiteral(int: int))
        case let .floatLiteral(float):
            return ExprSyntax(genFloatLiteral(float: float))
        case .nilLiteral:
            return ExprSyntax(genNilLiteral())
        case let .array(array):
            return ExprSyntax(genArray(array: array))
        case let .dictionary(dictionary):
            return ExprSyntax(genDictionary(dictionary: dictionary))
        case .`self`:
            return ExprSyntax(IdentifierExprSyntax {
                $0.useIdentifier(SyntaxFactory.makeSelfKeyword())
            })
        case let .try(expr):
            return ExprSyntax(genTry(expr: expr))
        case .discardPattern:
            return ExprSyntax(DiscardAssignmentExprSyntax {
                $0.useWildcard(SyntaxFactory.makeWildcardKeyword())
            })
        case let .letPattern(identifier):
            return ExprSyntax(genLetPattern(identifier: identifier))
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
                                trailingTrivia: .spaces(1)
                            )
                        )
                    }
                })
            }
        }
    }
    
    private func genStruct(name: String, decls: [Decl], conforms: [String]) -> StructDeclSyntax {
        StructDeclSyntax {
            $0.addModifier(publicModifier.withLeadingTrivia(.spaces(indentationLevel)))
            $0.useStructKeyword(
                SyntaxFactory.makeStructKeyword(trailingTrivia: .spaces(1))
            )
            $0.useIdentifier(SyntaxFactory.makeIdentifier(name))
            $0.useInheritanceClause(genInheritanceClause(conforms: conforms))
            $0.useMembers(genMemberDeclBlockSyntax(decls: decls))
        }
    }
    
    private func genEnum(name: String, cases: [Decl.Case], decls: [Decl], conforms: [String], defaultCase: Decl.Case?, genericParameters: [Decl.GenericParameter]) -> EnumDeclSyntax {
        EnumDeclSyntax {
            $0.addModifier(publicModifier.withLeadingTrivia(.spaces(indentationLevel)))
            $0.useEnumKeyword(
                SyntaxFactory.makeEnumKeyword(trailingTrivia: .spaces(1))
            )
            $0.useIdentifier(SyntaxFactory.makeIdentifier(name))
            if !genericParameters.isEmpty {
                $0.useGenericParameters(GenericParameterClauseSyntax {
                    $0.useLeftAngleBracket(SyntaxFactory.makeLeftAngleToken())
                    for (i, param) in genericParameters.enumerated() {
                        $0.addGenericParameter(GenericParameterSyntax {
                            $0.useName(SyntaxFactory.makeIdentifier(param.identifier))
                            $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                            $0.useInheritedType(gen(type: param.constraint))
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
    
    private func genExtension(type: TypeSyntax, conforms: [String], decls: [Decl]) -> ExtensionDeclSyntax {
        ExtensionDeclSyntax {
            $0.useExtensionKeyword(SyntaxFactory.makeExtensionKeyword(
                leadingTrivia: .spaces(indentationLevel),
                trailingTrivia: .spaces(1)
            ))
            $0.useExtendedType(type)
            if !conforms.isEmpty {
                $0.useInheritanceClause(genInheritanceClause(conforms: conforms))
            }
            $0.useMembers(genMemberDeclBlockSyntax(decls: decls))
        }
    }
    
    private func genProtocol(name: String, conforms: [String], whereClauses: [Decl.WhereClause], decls: [Decl]) -> ProtocolDeclSyntax {
        ProtocolDeclSyntax {
            $0.addModifier(publicModifier.withLeadingTrivia(.spaces(indentationLevel)))
            $0.useProtocolKeyword(
                SyntaxFactory.makeProtocolKeyword(trailingTrivia: .spaces(1))
            )
            $0.useIdentifier(SyntaxFactory.makeIdentifier(name))
            if !conforms.isEmpty {
                $0.useInheritanceClause(genInheritanceClause(conforms: conforms))
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
                            if i < whereClauses.index(before: whereClauses.endIndex) {
                                $0.useTrailingComma(SyntaxFactory.makeCommaToken().withTrailingTrivia(.spaces(1)))
                            }
                        })
                    }
                })
            }
            $0.useMembers(genMemberDeclBlockSyntax(decls: decls))
        }
    }
    
    private func genMemberDeclBlockSyntax(decls: [Decl]) -> MemberDeclBlockSyntax {
        MemberDeclBlockSyntax { builder in
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
    
    private func genVariableDecl(identifier: String, type: TypeSyntax?, initializer: ExprSyntax?, accessor: Decl.LetAccessor, isStatic: Bool) -> DeclSyntax {
        DeclSyntax(
            VariableDeclSyntax {
                $0.addModifier(publicModifier)
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
                    if let type = type {
                        $0.useTypeAnnotation(TypeAnnotationSyntax {
                            $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                            $0.useType(type)
                        })
                    }
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
    
    private func gen(`case`: Decl.Syntax.Case) -> SwitchCaseSyntax {
        SwitchCaseSyntax { builder in
            builder.useLabel(Syntax(
                SwitchCaseLabelSyntax {
                    switch `case` {
                    case .`case`(let expr, _):
                        $0.useCaseKeyword(
                            SyntaxFactory.makeCaseKeyword().withTrailingTrivia(.spaces(1))
                        )
                        $0.addCaseItem(CaseItemSyntax {
                            $0.usePattern(PatternSyntax(
                                ExpressionPatternSyntax {
                                    $0.useExpression(gen(expr: expr))
                                }
                            ))
                        })
                    case .`default`:
                        $0.useCaseKeyword(SyntaxFactory.makeDefaultKeyword())
                    }
                    $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.newlines(1)))
                }
            ).withLeadingTrivia(.spaces(indentationLevel)))
            indent {
                let syntax: [Decl.Syntax]
                switch `case` {
                case .`case`(_, let xs):
                    syntax = xs
                case .`default`(let xs):
                    syntax = xs
                }
                for syntax in syntax.map(gen(syntax:)) {
                    builder.addStatement(CodeBlockItemSyntax {
                        $0.useItem(syntax)
                    }.withTrailingTrivia(.newlines(1)))
                }
            }
        }
    }
    
    private func gen(parameters: [Decl.Parameter]) -> ParameterClauseSyntax {
        ParameterClauseSyntax {
            $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
            
            for (i, parameter) in parameters.enumerated() {
                $0.addParameter(FunctionParameterSyntax {
                    $0.useFirstName(SyntaxFactory.makeIdentifier(parameter.firstName))
                    if let secondName = parameter.secondName {
                        $0.useSecondName(SyntaxFactory.makeIdentifier(secondName).withLeadingTrivia(.spaces(1)))
                    }
                    $0.useColon(SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1)))
                    $0.useType(gen(type: parameter.type))
                    if i < parameters.index(before: parameters.endIndex) {
                        $0.useTrailingComma(SyntaxFactory.makeCommaToken().withTrailingTrivia(.spaces(1)))
                    }
                })
            }
            
            $0.useRightParen(SyntaxFactory.makeRightParenToken())
        }
    }
    
    private func gen(throws: Decl.Throws) -> TokenSyntax {
        switch `throws` {
        case .throws:
            return SyntaxFactory.makeThrowsKeyword()
        case .rethrows:
            return SyntaxFactory.makeRethrowsKeyword()
        }
    }
    
    private func genCodeBlockSyntax(_ f:() -> [Syntax]) -> CodeBlockSyntax {
        CodeBlockSyntax { builder in
            builder.useLeftBrace(SyntaxFactory.makeLeftBraceToken(leadingTrivia: .spaces(1), trailingTrivia: .newlines(1)))
            indent {
                for syntax in f() {
                    builder.addStatement(CodeBlockItemSyntax {
                        $0.useItem(syntax.withTrailingTrivia(.newlines(1)))
                    })
                }
            }
            builder.useRightBrace(SyntaxFactory.makeRightBraceToken(leadingTrivia: .spaces(indentationLevel), trailingTrivia: .newlines(1)))
        }
    }
    
    private func genFunc(name: String, parameters: [Decl.Parameter], throws: Decl.Throws?, returnType: TypeSyntax?, body: (() -> [Syntax])?, access: Decl.FuncAccess?) -> FunctionDeclSyntax {
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
                $0.useInput(gen(parameters: parameters).withTrailingTrivia(.spaces(1)))
                if let returnType = returnType {
                    $0.useOutput(ReturnClauseSyntax {
                        $0.useArrow(SyntaxFactory.makeArrowToken().withTrailingTrivia(.spaces(1)))
                        $0.useReturnType(returnType)
                    })
                }
                if let `throws` = `throws` {
                    $0.useThrowsOrRethrowsKeyword(gen(throws: `throws`).withTrailingTrivia(.spaces(1)))
                }
            })
            if let body = body {
                $0.useBody(genCodeBlockSyntax(body))
            }
        }.withLeadingTrivia(.spaces(indentationLevel))
    }
    
    private func genInit(parameters: [Decl.Parameter], throws: Decl.Throws?, body: (() -> [Syntax])?) -> InitializerDeclSyntax {
        InitializerDeclSyntax {
            $0.addModifier(publicModifier)
            $0.useInitKeyword(SyntaxFactory.makeInitKeyword())
            $0.useParameters(gen(parameters: parameters).withTrailingTrivia(.spaces(1)))
            if let `throws` = `throws` {
                $0.useThrowsOrRethrowsKeyword(gen(throws: `throws`).withTrailingTrivia(.spaces(1)))
            }
            if let body = body {
                $0.useBody(genCodeBlockSyntax(body))
            }
        }.withLeadingTrivia(.spaces(indentationLevel))
    }
    
    private func genTypealias(name: String, type: TypeSyntax) -> TypealiasDeclSyntax {
        TypealiasDeclSyntax {
            $0.useTypealiasKeyword(SyntaxFactory.makeTypealiasKeyword(
                leadingTrivia: .spaces(indentationLevel),
                trailingTrivia: .spaces(1)
            ))
            $0.useIdentifier(SyntaxFactory.makeIdentifier(name).withTrailingTrivia(.spaces(1)))
            $0.useInitializer(TypeInitializerClauseSyntax {
                $0.useEqual(SyntaxFactory.makeEqualToken().withTrailingTrivia(.spaces(1)))
                $0.useValue(type)
            })
        }.withTrailingTrivia(.newlines(1))
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
    
    private func genNilLiteral() -> NilLiteralExprSyntax {
        SyntaxFactory.makeNilLiteralExpr(nilKeyword: SyntaxFactory.makeNilKeyword())
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
    
    private func genTry(expr: Expr) -> TryExprSyntax {
        TryExprSyntax {
            $0.useTryKeyword(SyntaxFactory.makeTryKeyword().withTrailingTrivia(.spaces(1)))
            $0.useExpression(gen(expr: expr))
        }
    }
    
    private func genLetPattern(identifier: String) -> UnresolvedPatternExprSyntax {
        UnresolvedPatternExprSyntax {
            $0.usePattern(PatternSyntax(ValueBindingPatternSyntax {
                $0.useLetOrVarKeyword(SyntaxFactory.makeLetKeyword().withTrailingTrivia(.spaces(1)))
                $0.useValuePattern(PatternSyntax(IdentifierPatternSyntax {
                    $0.useIdentifier(SyntaxFactory.makeIdentifier(identifier))
                }))
            }))
        }
    }
    
    private var publicModifier: DeclModifierSyntax {
        DeclModifierSyntax {
            $0.useName(SyntaxFactory.makePublicKeyword(trailingTrivia: .spaces(1)))
        }
    }
    
    private func indent<T>(_ f: () -> T) -> T {
        indentationLevel = indentationLevel + 4
        defer {
            indentationLevel = indentationLevel - 4
        }
        return f()
    }
    
    private func gen(type: DeclType) -> TypeSyntax {
        switch type {
        case .named(let name, let genericArgs):
            return TypeSyntax(SimpleTypeIdentifierSyntax {
                $0.useName(SyntaxFactory.makeIdentifier(name))
                if !genericArgs.isEmpty {
                    $0.useGenericArgumentClause(GenericArgumentClauseSyntax {
                        $0.useLeftAngleBracket(SyntaxFactory.makeLeftAngleToken())
                        for (i, arg) in genericArgs.enumerated() {
                            $0.addArgument(GenericArgumentSyntax {
                                $0.useArgumentType(gen(type: arg))
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
                $0.useWrappedType(gen(type: type))
                $0.useQuestionMark(SyntaxFactory.makePostfixQuestionMarkToken())
            })
        case .array(let type):
            return TypeSyntax(ArrayTypeSyntax {
                $0.useLeftSquareBracket(SyntaxFactory.makeLeftSquareBracketToken())
                $0.useRightSquareBracket(SyntaxFactory.makeRightSquareBracketToken())
                $0.useElementType(gen(type: type))
            })
        case .memberType(let name, let base):
            return TypeSyntax(MemberTypeIdentifierSyntax {
                $0.useBaseType(gen(type: base))
                $0.usePeriod(SyntaxFactory.makePeriodToken())
                $0.useName(SyntaxFactory.makeIdentifier(name))
            })
        }
    }

}


func genStringLiteral(string: String, multiline: Bool) -> ExprSyntax {
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

fileprivate extension Optional {
    func mapThunk<T>(_ f: @escaping (Wrapped) -> T) -> Optional<() -> T> {
        if let x = self {
            return { f(x) }
        } else {
            return nil
        }
    }
}
