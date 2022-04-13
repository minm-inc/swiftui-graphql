import OrderedCollections
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
        type: DeclType? = nil,
        initializer: Expr? = nil,
        accessor: LetAccessor = .let,
        isStatic: Bool = false
    )
    enum LetAccessor: Equatable {
        case `let`
        case `var`
        case `get`(Syntax? = nil)
    }
    case staticLetString(name: String, literal: String)
    case `protocol`(name: String, conforms: [String], whereClauses: [WhereClause], decls: [Decl])
    case `associatedtype`(name: String, inherits: String)
    case `func`(name: String, parameters: [Parameter] = [], `throws`: Throws? = nil, returnType: DeclType? = nil, body: [Syntax]?, access: FuncAccess? = nil)
    
    enum FuncAccess: Equatable {
        case `fileprivate`
    }
    
    case `init`(parameters: [Parameter] = [], `throws`: Throws? = nil, body: [Syntax]?)
    struct Parameter: Equatable {
        let firstName: String
        let secondName: String?
        let type: DeclType
        init(_ firstName: String, _ secondName: String? = nil, type: DeclType) {
            self.firstName = firstName
            self.secondName = secondName
            self.type = type
        }
    }
    
    enum Throws: Equatable {
        case `throws`, `rethrows`
    }
    
    indirect enum Syntax: Equatable {
        case expr(Expr)
        case decl(Decl)
        case `switch`(Expr, cases: [Case])
        enum Case: Equatable {
            case `case`(Expr, [Syntax])
            case `default`([Syntax])
        }
        case `return`(Expr)
        case assignment(lhs: Expr, rhs: Expr)
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

indirect enum Expr: Hashable, ExpressibleByStringLiteral {
    /** `Base.member` */
    case memberAccess(member: String, base: Expr? = nil)
    /** `called(args)` */
    case functionCall(called: Expr, args: [Arg] = [])
    enum Arg: Hashable {
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
    case intLiteral(Int)
    case floatLiteral(Double)
    case nilLiteral
    case array([Expr])
    case dictionary(OrderedDictionary<Expr, Expr>)
    case `try`(Expr)
    /// `_`
    case discardPattern
    /// `let foo`
    case letPattern(String)
    
    init(stringLiteral value: StringLiteralType) {
        self = .identifier(value)
    }
    
    func access(_ member: String) -> Expr {
        .memberAccess(member: member, base: self)
    }
    
    func call(_ args: Arg...) -> Expr {
        call(args)
    }
    
    func call(_ args: [Arg]) -> Expr {
        .functionCall(called: self, args: args)
    }
    
    static func dot(_ member: String) -> Expr {
        .memberAccess(member: member)
    }
}


indirect enum DeclType: Equatable {
    case named(String, genericArguments: [DeclType] = [])
    case array(DeclType)
    case optional(DeclType)
    case memberType(String, DeclType)
}
