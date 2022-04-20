public struct FieldName: Hashable, ExpressibleByStringLiteral {
    public let name: String
    public init(stringLiteral value: String) {
        self.name = value
    }
    public init(_ name: String) { self.name = name }
}

public struct SelectionField<Arguments, Nested> {
    /// This is the actual name of the field *as it appears on the type* – i.e. without the alias
    public let name: FieldName
    // This will be implementation dependent:
    // At runtime we want a regular, unordered dictionary
    public let arguments: Arguments
    public let type: `Type`
    public var nested: Nested?
    public init(name: FieldName, arguments: Arguments, type: `Type`, nested: Nested?) {
        self.name = name
        self.arguments = arguments
        self.type = type
        self.nested = nested
    }
}

/// Represents the fields that were selected for a particular object that was code generated.
public struct ResolvedSelection<Variables: Value1Param> {
    
    public typealias Field = SelectionField<[String: Value1<Variables>], ResolvedSelection>
    /// Map from the key of the field as it will appear in the result payload, to the field
    public let fields: [ObjectKey: Field]
    
    public typealias TypeCondition = String
    /// Fields that may be conditionally included on certain types
    let conditional: [TypeCondition: [ObjectKey: Field]]
    public init(fields: [ObjectKey: Field], conditional: [TypeCondition: [ObjectKey: Field]]) {
        self.fields = fields
        self.conditional = conditional
    }
}

func findField<T>(key: ObjectKey, onType typename: String?, in selection: ResolvedSelection<T>) -> ResolvedSelection<T>.Field? {
    if let typename = typename, let field = selection.conditional[typename]?[key] {
        return field
    } else {
        return selection.fields[key]
    }
}

func substituteVariables(in selection: ResolvedSelection<String>, variableDefs: [String: Value]) -> ResolvedSelection<Never> {
    ResolvedSelection(
        fields: selection.fields.mapValues { substituteVariables(in: $0, variableDefs: variableDefs) },
        conditional: selection.conditional.mapValues {
            $0.mapValues {
                substituteVariables(in: $0, variableDefs: variableDefs)
            }
        }
    )
}

private func substituteVariables(in field: ResolvedSelection<String>.Field, variableDefs: [String: Value]) -> ResolvedSelection<Never>.Field {
    ResolvedSelection.Field(
        name: field.name,
        arguments: field.arguments.mapValues { substituteVariables(in: $0, variableDefs: variableDefs)},
        type: field.type,
        nested: field.nested.map { substituteVariables(in: $0, variableDefs: variableDefs) }
    )
}

private func substituteVariables(in value: NonConstValue, variableDefs: [String: Value]) -> Value {
    switch value {
    case let .variable(varName):
        if let variable = variableDefs[varName] {
            return variable
        } else {
            return .null
        }
    case let .int(x):
        return .int(x)
    case let .string(x):
        return .string(x)
    case let .boolean(x):
        return .boolean(x)
    case let .enum(x):
        return .enum(x)
    case let .float(x):
        return .float(x)
    case let .object(xs):
        return .object(xs.mapValues { substituteVariables(in: $0, variableDefs: variableDefs ) })
    case let .list(xs):
        return .list(xs.map { substituteVariables(in: $0, variableDefs: variableDefs) })
    case .null:
        return .null
    }
}
