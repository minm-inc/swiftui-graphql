//
//  AST.swift
//  Minm
//
//  Created by Luke Lau on 22/06/2021.
//

import Foundation

protocol QueryPrintable: CustomStringConvertible {
    var printed: String { get }
    
}
extension QueryPrintable {
    public var description: String {
        printed
    }
}

struct Document: QueryPrintable {
    let definitions: [Definition]
    
    var printed: String {
        definitions.map { $0.description }.joined(separator: "\n")
    }
}

public struct ExecutableDocument: QueryPrintable {
    public init(definitions: [ExecutableDefinition]) {
        self.definitions = definitions
    }
    
    let definitions: [ExecutableDefinition]
    
    var printed: String {
        definitions.map { $0.description }.joined(separator: "\n")
    }
}

extension String {
    func indented(by numSpaces: Int) -> Self {
        var newStr = ""
        self.enumerateLines { line, stop in
            newStr += Array(repeating: " ", count: numSpaces) + line
        }
        return newStr
    }
}

public enum Definition: QueryPrintable {
    var printed: String {
        switch self {
        case .executableDefinition(let x):
            return x.description
        case .typeSystemDefinitionOrExtension:
            fatalError("not implemented yet")
        }
    }
    
    case executableDefinition(ExecutableDefinition)
    case typeSystemDefinitionOrExtension
}

public enum ExecutableDefinition: QueryPrintable {
    var printed: String {
        switch self {
        case .operationDefinition(let x):
            return x.description
        case .fragmentDefinition(let fragmentName, let typeCondition, _, let selectionSet):
            return """
fragment \(fragmentName) on \(typeCondition) {
\(selectionSet.printed.indented(by: 2))
}
"""
        }
    }
    case operationDefinition(OperationDefinition)
    case fragmentDefinition(fragmentName: String, typeCondition: String, directives: [String]?, selectionSet: Set<Selection>)
}

public enum OperationType: QueryPrintable {
    case query, mutation, subscription
    
    var printed: String {
        switch self {
        case .query: return "query"
        case .mutation: return "mutation"
        case .subscription: return "subscription"
        }
    }
}

public enum OperationDefinition: QueryPrintable {
    var printed: String {
        switch self {
        case .operationDefinition(let type, let name, let variableDefinitions, _, let selectionSet):
            let variableDefString: String
            if let variableDefinitions = variableDefinitions {
                variableDefString = "(" + variableDefinitions.map { $0.printed }.joined(separator: ", ") + ")"
            } else {
                variableDefString = ""
            }
            return """
\(type) \(name ?? "")\(variableDefString) {
\(selectionSet.printed.indented(by: 2))
}
"""
        case .anonymousQuery(let selectionSet):
            return """
{
\(selectionSet.printed.indented(by: 2))
}
"""
        }
    }
    case operationDefinition(type: OperationType, name: String? = nil, variableDefinitions: [VariableDefinition]? = nil, directives: [String]? = nil, selectionSet: Set<Selection>)
    case anonymousQuery(Set<Selection>)
}

public struct VariableDefinition: QueryPrintable {
    public init(variable: String, type: Typ, defaultValue: Value? = nil, directives: [String]? = nil) {
        self.variable = variable
        self.type = type
        self.defaultValue = defaultValue
        self.directives = directives
    }
    
    let variable: String
    let type: Typ
    let defaultValue: Value?
    let directives: [String]?
    
    var printed: String {
        var s = "$" + variable + " : " + type.printed
        if let defaultValue = defaultValue {
            s += " = \(defaultValue.printed)"
        }
        if directives != nil {
            fatalError("Need to implement")
        }
        return s
    }
    
    
}

public indirect enum Typ: QueryPrintable {
    case namedType(NamedType)
    case listType(ListType)
    case nonNullType(NonNullType)
    
    var printed: String {
        switch self {
        case .namedType(let s):
            return s
        case .listType(let t):
            return "[\(t.printed)]"
        case .nonNullType(let t):
            return t.printed
        }
    }
}

public indirect enum NonNullType: QueryPrintable {
    case nonNullNamedType(NamedType)
    case nonNullListType(ListType)
    var printed: String {
        switch self {
        case .nonNullNamedType(let s):
            return s + "!"
        case .nonNullListType(let t):
            return t.printed + "!"
        }
    }
}
        
public typealias NamedType = String
public typealias ListType = Typ

public enum Selection: QueryPrintable, Hashable {
    case field(alias: String? = nil, name: String, arguments: [String: NonConstValue]? = nil, directives: [String]? = nil, selectionSet: Set<Selection>? = nil)
    case fragmentSpread(fragmentName: String, directives: [String]?)
    case inlineFragment(typeCondition: String?, directives: [String]?, selectionSet: Set<Selection>)
    
    var printed: String {
        switch self {
        case .field(let alias, let name, let arguments, _, let selectionSet):
            var firstLine = ""
            if let alias = alias {
                firstLine += "\(alias): "
            }
            firstLine += name + " "
            if let arguments = arguments {
                firstLine += "(" + arguments.map { $0.key + ": " + $0.value.printed }.joined(separator: ", ") + ")"
            }
            if let selectionSet = selectionSet {
                firstLine += " {\n" + selectionSet.printed.indented(by: 2) + "\n}"
            }
            return firstLine
        case .fragmentSpread(_, _):
            fatalError("Not implemented")
        case .inlineFragment(_, _, _):
            fatalError("Not implemented")
        }
    }
}

extension Set: QueryPrintable where Element == Selection {
    var printed: String {
        self.reduce("") { $0 + "\n" + $1.printed}
    }
}

public protocol Value1Param: Hashable, Encodable {
    var variableString: String { get }
}

public enum Const: Hashable, Value1Param {
    public var variableString: String { "" }
}

extension String: Value1Param {
    public var variableString: String { self }
}

public enum Value1<T>: Equatable, Hashable, QueryPrintable where T: Value1Param {
    
    
    case variable(T)
    case boolean(Bool)
    case string(String)
    case int(Int)
    case float(Double)
    case enumm(String)
    case list([Value1<T>])
    case object([String: Value1<T>])
    case null
    
    var printed: String {
        switch self {
        case .boolean(let x):
            return x ? "true" : "false"
        case .string(let x):
            return "\"" + x + "\""
        case .int(let x):
            return String(x)
        case .float(let x):
            return String(x)
        case .list(let xs):
            return "[\(xs.map { $0.printed }.joined(separator: ", ") )]"
        case .object(let obj):
            return "{" + obj.map { $0.key + ": " + $0.value.printed }.joined(separator: ",") + "}"
        case .null:
            return "null"
        case .enumm(let x):
            return "\"" + x + "\""
        case .variable(let x):
            return "$\(x.variableString)"
        }
    }
}

extension Value1: Codable {
        
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .int(let x):
            try x.encode(to: encoder)
        case .float(let x):
            try x.encode(to: encoder)
        case .boolean(let x):
            try x.encode(to: encoder)
        case .string(let x):
            try x.encode(to: encoder)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .list(let xs):
            try xs.encode(to: encoder)
        case .object(let obj):
            try obj.encode(to: encoder)
        case .variable(let x):
            try x.encode(to: encoder)
        case .enumm(let x):
            try x.encode(to: encoder)
        }
    }
    
    // TODO: Decode enums?
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() == true {
            self = .null
        } else if let x = try? container.decode(Int.self) {
            self = .int(x)
        } else if let x = try? container.decode(Double.self) {
            self = .float(x)
        } else if let x = try? container.decode(String.self) {
            self = .string(x)
        } else if let x = try? container.decode(Bool.self) {
            self = .boolean(x)
        } else if let arr = try? [Value1<T>].init(from: decoder) {
            self = .list(arr)
        } else {
            self = .object(try [String: Value1<T>].init(from: decoder))
        }
    }
}

public typealias Value = Value1<Const>
public typealias NonConstValue = Value1<String>

