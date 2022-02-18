/// Because SwiftSyntax's AST is quite hefty, we use a mini AST that more succintly represents what we're trying to generate
enum Decl: Equatable {
    case `struct`(name: String, decls: [Decl], conforms: [String])
    case `enum`(
        name: String,
        cases: [Case],
        decls: [Decl],
        conforms: [String],
        defaultCase: Case?,
        genericParameters: [GenericParameter]
    )
    case `let`(
        name: String,
        type: DeclType,
        initializer: Expr? = nil,
        accessor: LetAccessor = .let
    )
    enum LetAccessor: Equatable {
        case `let`
        case `var`
        case `get`(Syntax? = nil)
    }
    case staticLetString(name: String, literal: String)
    case `protocol`(name: String, conforms: [String], whereClauses: [WhereClause], decls: [Decl])
    case `associatedtype`(name: String, inherits: String)
    case `func`(name: String, returnType: DeclType, body: Syntax?, access: FuncAccess? = nil)
    
    enum FuncAccess: Equatable {
        case `fileprivate`
    }
    
    enum Syntax: Equatable {
        case expr(Expr)
        case returnSwitch(expr: Expr, cases: [SwitchCase])
        /** A case statement like `case .enumName(let binds...)`*/
        struct SwitchCase: Equatable {
            let enumName: String
            let binds: [String]
            let returns: Expr
        }
    }
    
    struct WhereClause: Equatable {
        let associatedType: String
        let constraint: String
    }
    
    struct GenericParameter: Equatable {
        let identifier: String
        let constraint: DeclType
    }
    
    struct Case: Equatable {
        let name: String
        let nestedTypeName: String?
    }
}

indirect enum Expr: Equatable, ExpressibleByStringLiteral {
    /** `Base.member` */
    case memberAccess(member: String, base: Expr? = nil)
    /** `called(args)` */
    case functionCall(called: Expr, args: [Arg] = [])
    enum Arg: Equatable {
        case named(String, Expr)
        case unnamed(Expr)
    }
    /** `identifier` */
    case identifier(String)
    /** `$i` */
    case anonymousIdentifier(Int)
    /** `{ expr }` */
    case closure(Expr)
    case `self`
    case stringLiteral(String)
    case boolLiteral(Bool)
    
    init(stringLiteral value: StringLiteralType) {
        self = .identifier(value)
    }
}


indirect enum DeclType: Equatable {
    case named(String, genericArguments: [DeclType] = [])
    case array(DeclType)
    case optional(DeclType)
    case memberType(String, DeclType)
}
