import Foundation

public protocol ScalarDecoder: Sendable {
    func decodeScalar(ofType type: Any.Type, value: Value) throws -> Any?
}

public enum ScalarDecoderError: Error {
    case invalidScalar
}

/// Decodes scalars into foundation types
public struct FoundationScalarDecoder: ScalarDecoder {
    let markdownParsingOptions: AttributedString.MarkdownParsingOptions
    public init(markdownParsingOptions: AttributedString.MarkdownParsingOptions = .init()) {
        self.markdownParsingOptions = markdownParsingOptions
    }
    public func decodeScalar(ofType type: Any.Type, value: Value) throws -> Any? {
        if type == Date.self {
                switch value {
                case .string(let s):
                    return try Date(s, strategy: .iso8601)
                default:
                    throw ScalarDecoderError.invalidScalar
                }
        } else if type == URL.self {
            switch value {
            case .string(let s):
                guard let url = URL(string: s) else {
                    throw ScalarDecoderError.invalidScalar
                }
                return url
            default:
                throw ScalarDecoderError.invalidScalar
            }
        } else if type == AttributedString.self {
            switch value {
            case .string(let s):
                return try AttributedString(markdown: s, options: markdownParsingOptions)
            default:
                throw ScalarDecoderError.invalidScalar
            }
        }
        return nil
    }
}
