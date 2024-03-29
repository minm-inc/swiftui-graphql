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
    public init(variable: String, type: `Type`, defaultValue: Value? = nil, directives: [String]? = nil) {
        self.variable = variable
        self.type = type
        self.defaultValue = defaultValue
        self.directives = directives
    }
    
    let variable: String
    let type: `Type`
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

public indirect enum `Type`: QueryPrintable {
    case named(String)
    case list(`Type`)
    case nonNull(NonNullType)
    
    var printed: String {
        switch self {
        case .named(let s):
            return s
        case .list(let t):
            return "[\(t.printed)]"
        case .nonNull(let t):
            return t.printed
        }
    }
}

public indirect enum NonNullType: QueryPrintable {
    case named(String)
    case nonNull(`Type`)
    var printed: String {
        switch self {
        case .named(let s):
            return s + "!"
        case .nonNull(let t):
            return t.printed + "!"
        }
    }
}

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

public protocol Value1Param: Hashable, Encodable, Sendable {
    var variableString: String { get }
}

extension Never: Value1Param {
    public func encode(to encoder: Encoder) throws {
    }
    public var variableString: String { fatalError() }
}

extension String: Value1Param {
    public var variableString: String { self }
}

/// The key used for  objects in ``Value1``.
///
/// This is equivalent to a ``String``, but is wrapped in a type to prevent confusion with ``FieldName``:
/// An ``ObjectKey`` is the key of the field as returned in the object, and can be affected by field aliases.
public struct ObjectKey: Hashable, ExpressibleByStringLiteral, CodingKey, Codable, Sendable {
    private let key: String
    public init(stringLiteral value: String) {
        self.key = value
    }
    
    public var stringValue: String { key }
    public var intValue: Int? { nil }
    public init?(stringValue: String) {
        self.key = stringValue
    }
    public init?(intValue: Int) {
        return nil
    }
    
    public init(_ key: String) { self.key = key }
    public var description: String { key }
    
    static func convert<T>(object: [ObjectKey: Value1<T>]) -> [String: Value1<T>] {
        object.reduce(into: [:]) { $0[$1.key.key] = $1.value }
    }
}

public enum Value1<T: Value1Param>: Hashable, Sendable, QueryPrintable {
    public typealias Object = [ObjectKey: Value1<T>]
    case variable(T)
    case boolean(Bool)
    case string(String)
    case int(Int)
    case float(Double)
    case `enum`(String)
    case list([Value1<T>])
    case object(Object)
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
            return "{" + obj.map { $0.key.description + ": " + $0.value.printed }.joined(separator: ",") + "}"
        case .null:
            return "null"
        case .`enum`(let x):
            return "\"" + x + "\""
        case .variable(let x):
            return "$\(x.variableString)"
        }
    }
    
    public subscript(_ key: ObjectKey) -> Value1? {
        switch self {
        case .object(let obj):
            return obj[key]
        default:
            return nil
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
            var container = encoder.container(keyedBy: ObjectKey.self)
            for (key, val) in obj {
                try container.encode(val, forKey: key)
            }
//            try obj.encode(to: encoder)
        case .variable(let x):
            try x.encode(to: encoder)
        case .`enum`(let x):
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
            let container = try decoder.container(keyedBy: ObjectKey.self)
            var res: [ObjectKey: Value1<T>] = [:]
            for key in container.allKeys {
                res[key] = try container.decode(Value1<T>.self, forKey: key)
            }
            self = .object(res)
//            self = .object(try [ObjectKey: Value1<T>].init(from: decoder))
        }
    }
}

extension Value1: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (ObjectKey, Value1)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension Value1: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Value1...) {
        self = .list(elements)
    }
}

extension Value1: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self = .string(value)
    }
}

extension Value1: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: IntegerLiteralType) {
        self = .int(value)
    }
}

extension Value1: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: BooleanLiteralType) {
        self = .boolean(value)
    }
}

extension Value1: ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) {
        self = .float(value)
    }
}

extension Value1: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

public typealias Value = Value1<Never>
public typealias NonConstValue = Value1<String>
