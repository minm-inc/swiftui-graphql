public enum ResolvedSelection<Variables: Value1Param> {
    case field(Field)
    public struct Field {
        /// This is the **resolved name**, i.e. the alias if it has one, falling back to the field name otherwise.
        public let name: String
        public let arguments: [String: Value1<Variables>]
        public let type: `Type`
        public let selections: [ResolvedSelection]
        public init(name: String, arguments: [String: Value1<Variables>] = [:], type: `Type`, selections: [ResolvedSelection] = []) {
            self.name = name
            self.arguments = arguments
            self.type = type
            self.selections = selections
        }
    }
    /// A fragment whose selections are *only included on a type condition*.
    ///
    /// Plain old fragments get resovled into regular ``Field``s.
    case fragment(typeCondition: String, selections: [ResolvedSelection])
}

func findSelection<T>(name: String, in selections: [ResolvedSelection<T>]) -> ResolvedSelection<T>.Field? {
    for selection in selections {
        switch selection {
        case .field(let field):
            if field.name == name {
                return field
            } else {
                continue
            }
        case .fragment(_, let selections):
            if let selection = findSelection(name: name, in: selections) {
                return selection
            } else {
                continue
            }
        }
    }
    return nil
}


func substituteVariables(in selections: [ResolvedSelection<String>], variableDefs: [String: Value]) -> [ResolvedSelection<Never>] {
    selections.map { selection in
        switch selection {
        case let .field(field):
            return .field(ResolvedSelection.Field(
                name: field.name,
                arguments: field.arguments.mapValues { substituteVariables(in: $0, variableDefs: variableDefs)},
                type: field.type,
                selections: substituteVariables(in: field.selections, variableDefs: variableDefs)
            ))
        case let .fragment(typeCondition, selections):
            return .fragment(
                typeCondition: typeCondition,
                selections: substituteVariables(in: selections, variableDefs: variableDefs)
            )
        }
    }
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
