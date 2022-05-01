//
//  ValueDecoder.swift
//  Minm
//
//  Created by Luke Lau on 23/06/2021.
//

import Foundation

struct ValueDecoder {
    let scalarDecoder: ScalarDecoder
    func decode<T: Decodable>(_ type: T.Type, from value: Value) throws -> T {
        let decoder = ValueDecoderImpl(scalarDecoder: scalarDecoder, value: value)
        return try T.self.init(from: decoder)
    }
}

fileprivate struct ValueDecoderImpl: Decoder {
    var codingPath: [CodingKey] = []
    
    var userInfo: [CodingUserInfoKey : Any] = [:]
    let scalarDecoder: ScalarDecoder
    let value: Value
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        switch value {
        case .object(let obj):
            return KeyedDecodingContainer(KeyedContainer(scalarDecoder: scalarDecoder, object: obj, decoder: self))
        default:
            throw DecodingError.typeMismatch([String: Value].self, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
        }
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        switch value {
        case .list(let xs):
            return UnkeyedContainer(scalarDecoder: scalarDecoder, list: xs, codingPath: codingPath)
        default:
            throw DecodingError.typeMismatch([Value].self, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
        }
    }
    
    struct UnkeyedContainer: UnkeyedDecodingContainer {
        let scalarDecoder: ScalarDecoder
        let list: [Value]
        var codingPath: [CodingKey]

        var count: Int? { list.count }

        var isAtEnd: Bool { currentIndex >= count! }

        var currentIndex = 0

        mutating func decodeNil() throws -> Bool {
            let val = list[currentIndex]
            currentIndex += 1
            return val == .null
        }

        mutating func decode(_ type: Bool.Type) throws -> Bool {
            guard case .boolean(let x) = list[currentIndex] else {
                throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
            }
            currentIndex += 1
            return x
        }
        
        mutating func decode(_ type: String.Type) throws -> String {
            guard case .string(let x) = list[currentIndex] else {
                throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
            }
            currentIndex += 1
            return x
        }
        
        private mutating func decodeDouble() throws -> Double {
            guard case .float(let x) = list[currentIndex] else {
                throw DecodingError.typeMismatch(Double.self, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
            }
            currentIndex += 1
            return x
        }
        
        mutating func decode(_ type: Double.Type) throws -> Double {
            return try decodeDouble()
        }
        
        mutating func decode(_ type: Float.Type) throws -> Float {
            return Float(try decodeDouble())
        }
        
        private mutating func decodeFixedWidthInteger<T: FixedWidthInteger>() throws -> T {
            guard case .int(let x) = list[currentIndex] else {
                throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
            }
            currentIndex += 1
            return T(x)
        }
        
        mutating func decode(_ type: Int.Type) throws -> Int { try decodeFixedWidthInteger() }
        
        mutating func decode(_ type: Int8.Type) throws -> Int8 { try decodeFixedWidthInteger() }
        
        mutating func decode(_ type: Int16.Type) throws -> Int16 { try decodeFixedWidthInteger() }
        
        mutating func decode(_ type: Int32.Type) throws -> Int32 { try decodeFixedWidthInteger() }
        
        mutating func decode(_ type: Int64.Type) throws -> Int64 { try decodeFixedWidthInteger() }
        
        mutating func decode(_ type: UInt.Type) throws -> UInt { try decodeFixedWidthInteger() }
        
        mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeFixedWidthInteger() }
        
        mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeFixedWidthInteger() }
        
        mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeFixedWidthInteger() }
        
        mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeFixedWidthInteger() }
        
        mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
            if let scalarDecoded = try decodeScalarWrappingError(ofType: type, value: list[currentIndex], codingPath: codingPath, scalarDecoder: scalarDecoder) {
                currentIndex += 1
                return scalarDecoded
            } else {
                let decoder = ValueDecoderImpl(codingPath: codingPath, scalarDecoder: scalarDecoder, value: list[currentIndex])
                currentIndex += 1
                return try T.init(from: decoder)
            }
        }
        

        mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
            let decoder = ValueDecoderImpl(codingPath: codingPath, scalarDecoder: scalarDecoder, value: list[currentIndex])
            currentIndex += 1
            return try decoder.container(keyedBy: type)
        }

        mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            let decoder = ValueDecoderImpl(codingPath: codingPath, scalarDecoder: scalarDecoder, value: list[currentIndex])
            currentIndex += 1
            return try decoder.unkeyedContainer()
        }

        mutating func superDecoder() throws -> Decoder {
            let decoder = ValueDecoderImpl(codingPath: codingPath, scalarDecoder: scalarDecoder, value: list[currentIndex])
            currentIndex += 1
            return decoder
        }
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return SingleValueContainer(scalarDecoder: scalarDecoder, value: value, codingPath: codingPath)
    }
    
    struct SingleValueContainer: SingleValueDecodingContainer {
        let scalarDecoder: ScalarDecoder
        let value: Value
        var codingPath: [CodingKey]
        
        func decodeNil() -> Bool {
            switch value {
            case .null:
                return true
            default:
                return false
            }
        }
        
        func decode(_ type: Bool.Type) throws -> Bool {
            switch value {
            case .boolean(let x):
                return x
            default:
                throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
            }
        }
        
        func decode(_ type: String.Type) throws -> String {
            switch value {
            case .string(let x):
                return x
            default:
                throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
            }
        }
        
        private func decodeFloatingPoint<T: LosslessStringConvertible & BinaryFloatingPoint>() throws -> T {
            guard case .float(let x) = value else {
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
            }
            return T(x)
        }
        
        func decode(_ type: Double.Type) throws -> Double { try decodeFloatingPoint() }

        func decode(_ type: Float.Type) throws -> Float { try decodeFloatingPoint() }
        
        private func decodeFixedWidthInteger<T: FixedWidthInteger>() throws -> T {
            guard case .int(let x) = value else {
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
            }
            return T(x)
        }

        func decode(_ type: Int.Type) throws -> Int { try decodeFixedWidthInteger() }

        func decode(_ type: Int8.Type) throws -> Int8 { try decodeFixedWidthInteger() }

        func decode(_ type: Int16.Type) throws -> Int16 { try decodeFixedWidthInteger() }

        func decode(_ type: Int32.Type) throws -> Int32 { try decodeFixedWidthInteger() }

        func decode(_ type: Int64.Type) throws -> Int64 { try decodeFixedWidthInteger() }

        func decode(_ type: UInt.Type) throws -> UInt { try decodeFixedWidthInteger() }

        func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeFixedWidthInteger() }

        func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeFixedWidthInteger() }

        func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeFixedWidthInteger() }

        func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeFixedWidthInteger() }
        
        func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
            if let scalarDecoded = try decodeScalarWrappingError(ofType: type, value: value, codingPath: codingPath, scalarDecoder: scalarDecoder) {
                return scalarDecoded
            } else {
                let decoder = ValueDecoderImpl(codingPath: codingPath, scalarDecoder: scalarDecoder, value: value)
                return try T.init(from: decoder)
            }
        }
        
        
    }
    
    struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
        let scalarDecoder: ScalarDecoder
        var codingPath: [CodingKey] = []
        var allKeys: [Key] = []
        
        let object: [ObjectKey: Value]
        let decoder: Decoder
        
        func contains(_ key: Key) -> Bool {
            object.keys.contains(ObjectKey(key.stringValue))
        }
        
        func decodeNil(forKey key: Key) throws -> Bool {
            guard case .null = try lookup(key) else {
                return false
            }
            return true
        }
        
        func lookup(_ key: Key) throws -> Value {
            guard let x = object[ObjectKey(key.stringValue)] else {
                throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
            }
            return x
        }
        
        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
            guard case .boolean(let x) = try lookup(key) else {
                throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
            }
            return x
        }
        
        func decode(_ type: String.Type, forKey key: Key) throws -> String {
            guard case .string(let s) = try lookup(key) else {
                throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
            }
            return s
        }
        
        private func decodeFloatingPoint<T: LosslessStringConvertible & BinaryFloatingPoint>(key: Key) throws -> T {
            guard case .float(let x) = try lookup(key) else {
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
            }
            return T(x)
        }
        
        private func decodeFixedWidthInteger<T: FixedWidthInteger>(key: Key) throws -> T {
            guard case .int(let x) = try lookup(key) else {
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: codingPath, debugDescription: "TODO"))
            }
            return T(x)
        }
        func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try decodeFloatingPoint(key: key) }

        func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try decodeFloatingPoint(key: key) }

        func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try decodeFixedWidthInteger(key: key) }

        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try decodeFixedWidthInteger(key: key) }

        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try decodeFixedWidthInteger(key: key) }

        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try decodeFixedWidthInteger(key: key) }

        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try decodeFixedWidthInteger(key: key) }

        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try decodeFixedWidthInteger(key: key) }

        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try decodeFixedWidthInteger(key: key) }

        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try decodeFixedWidthInteger(key: key) }

        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try decodeFixedWidthInteger(key: key) }

        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try decodeFixedWidthInteger(key: key) }
        
        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
            let value = try lookup(key)
            if let scalarDecoded = try decodeScalarWrappingError(ofType: type, value: value, codingPath: codingPath, scalarDecoder: scalarDecoder) {
                return scalarDecoded
            } else {
                return try T.init(from: ValueDecoderImpl(scalarDecoder: scalarDecoder, value: value))
            }
        }
        
        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
            try ValueDecoderImpl(codingPath: codingPath + [key], scalarDecoder: scalarDecoder, value: try lookup(key)).container(keyedBy: type)
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            try ValueDecoderImpl(codingPath: codingPath + [key], scalarDecoder: scalarDecoder, value: try lookup(key)).unkeyedContainer()
        }
        func superDecoder() throws -> Decoder {
            return try superDecoder(forKey: Key(stringValue: "super")!)
        }

        func superDecoder(forKey key: Key) throws -> Decoder {
            return ValueDecoderImpl(codingPath: codingPath, scalarDecoder: scalarDecoder, value: try lookup(key))
        }
        
    }
}

private func decodeScalarWrappingError<T>(ofType type: T.Type, value: Value, codingPath: [CodingKey], scalarDecoder: ScalarDecoder) throws -> T? {
    let scalarDecoded: Any?
    do {
        scalarDecoded = try scalarDecoder.decodeScalar(ofType: type, value: value)
    } catch {
        throw DecodingError.typeMismatch(type, .init(
            codingPath: codingPath,
            debugDescription: "Error ocurred whilst decoding a scalar type of type \(type): \(value)",
            underlyingError: error
        ))
    }
    if let scalarDecoded = scalarDecoded {
        return (scalarDecoded as! T)
    } else {
        return nil
    }
}
