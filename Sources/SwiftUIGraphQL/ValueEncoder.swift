//
//  ValueEncoder.swift
//  
//
//  Created by Luke Lau on 24/06/2021.
//

import Foundation

struct ValueEncoder {
    func encode<Const: Value1Param, T: Encodable>(_ x: T) throws -> Value1<Const> {
        let encoder = ValueEncoderImpl<Const>(codingPath: [])
        try x.encode(to: encoder)
        return encoder.value!.value
    }
}

fileprivate class ValueEncoderImpl<Const: Value1Param>: Encoder {
    
    fileprivate indirect enum ValueRef {
        case regular(Value1<Const>)
        case object(ObjectRef)
        case list(ListRef)
        case encoder(ValueEncoderImpl<Const>)
        case any(AnyRef)
        
        class AnyRef {
            var value: Value1<Const>? = nil
        }
        class ObjectRef {
            var object: [ObjectKey: ValueRef] = [:]
        }
        class ListRef {
            var list: [ValueRef] = []
        }
        
        var value: Value1<Const> {
            switch self {
            case .regular(let v): return v
            case .object(let objRef): return .object(objRef.object.mapValues { $0.value })
            case .list(let arrRef): return .list(arrRef.list.map { $0.value })
            case .encoder(let encoder): return encoder.value!.value
            case .any(let anyRef): return anyRef.value!
            }
        }
    }
    
    var codingPath: [CodingKey]
    
    init(codingPath: [CodingKey]) {
        self.codingPath = codingPath
    }
    
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    var value: ValueRef? = nil
    
    struct ObjectContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
        var codingPath: [CodingKey]
        
        let objRef: ValueRef.ObjectRef

        var obj: [ObjectKey: ValueRef] {
            get {
                objRef.object
            }
            set {
                objRef.object = newValue
            }
        }
        
        mutating func encodeNil(forKey key: Key) throws {
            obj[key.stringValue] = .regular(.null)
        }
        
        mutating func encode(_ value: Bool, forKey key: Key) throws {
            obj[key.stringValue] = .regular(.boolean(value))
        }
        
        mutating func encode(_ value: String, forKey key: Key) throws {
            obj[key.stringValue] = .regular(.string(value))
        }
        
        mutating func encode(_ value: Double, forKey key: Key) throws {
            obj[key.stringValue] = .regular(.float(value))
        }
        
        mutating func encode(_ value: Float, forKey key: Key) throws {
            obj[key.stringValue] = .regular(.float(Double(value)))
        }
        
        private mutating func encodeFixedWidthInteger<T: FixedWidthInteger>(_ value: T, forKey key: Key) {
            obj[key.stringValue] = .regular(.int(Int(value)))
        }
        
        mutating func encode(_ value: Int, forKey key: Key) throws {
            encodeFixedWidthInteger(value, forKey: key)
        }
        
        mutating func encode(_ value: Int8, forKey key: Key) throws {
            encodeFixedWidthInteger(value, forKey: key)
        }
        
        mutating func encode(_ value: Int16, forKey key: Key) throws {
            encodeFixedWidthInteger(value, forKey: key)
        }
        
        mutating func encode(_ value: Int32, forKey key: Key) throws {
            encodeFixedWidthInteger(value, forKey: key)
        }
        
        mutating func encode(_ value: Int64, forKey key: Key) throws {
            encodeFixedWidthInteger(value, forKey: key)
        }
        
        mutating func encode(_ value: UInt, forKey key: Key) throws {
            encodeFixedWidthInteger(value, forKey: key)
        }
        
        mutating func encode(_ value: UInt8, forKey key: Key) throws {
            encodeFixedWidthInteger(value, forKey: key)
        }
        
        mutating func encode(_ value: UInt16, forKey key: Key) throws {
            encodeFixedWidthInteger(value, forKey: key)
        }
        
        mutating func encode(_ value: UInt32, forKey key: Key) throws {
            encodeFixedWidthInteger(value, forKey: key)
        }
        
        mutating func encode(_ value: UInt64, forKey key: Key) throws {
            encodeFixedWidthInteger(value, forKey: key)
        }
        
        mutating func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
            if let date = value as? Date {
                return try encode(date.formatted(.iso8601), forKey: key)
            }
            let encoder = ValueEncoderImpl(codingPath: codingPath + [key])
            try value.encode(to: encoder)
            obj[key.stringValue] = encoder.value!
        }
        
        mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            let objRef = ValueRef.ObjectRef()
            obj[key.stringValue] = .object(objRef)
            return KeyedEncodingContainer(ObjectContainer<NestedKey>(codingPath: codingPath + [key], objRef: objRef))
        }
        
        mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
            let listRef = ValueRef.ListRef()
            obj[key.stringValue] = .list(listRef)
            return ListContainer(codingPath: codingPath + [key], listRef: listRef)
        }
        
        mutating func superEncoder() -> Encoder {
            superEncoder(forKey: Key(stringValue: "super")!)
        }
        
        mutating func superEncoder(forKey key: Key) -> Encoder {
            let encoder = ValueEncoderImpl(codingPath: codingPath + [key])
            obj[key.stringValue] = .encoder(encoder)
            return encoder
        }
         
    }
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        let objRef = ValueRef.ObjectRef()
        value = .object(objRef)
        return KeyedEncodingContainer(ObjectContainer(codingPath: codingPath, objRef: objRef))
    }
    
    struct ListContainer: UnkeyedEncodingContainer {

        
        var codingPath: [CodingKey]
        
        var count: Int { list.count }
        
        let listRef: ValueRef.ListRef
        
        var list: [ValueRef] {
            get { listRef.list }
            set { listRef.list = newValue }
        }
        
        mutating func encodeNil() throws {
            list.append(.regular(.null))
        }

        mutating func encode(_ value: Bool) throws {
            list.append(.regular(.boolean(value)))
        }
        
        mutating func encode(_ value: String) throws {
            list.append(.regular(.string(value)))
        }
        
        mutating func encode(_ value: Double) throws {
            list.append(.regular(.float(value)))
        }
        
        mutating func encode(_ value: Float) throws {
            list.append(.regular(.float(Double(value))))
        }
        
        mutating func encodeFixedWidthInteger<T: FixedWidthInteger>(_ value: T) {
            list.append(.regular(.int(Int(value))))
        }
        
        mutating func encode(_ value: Int) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: Int8) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: Int16) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: Int32) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: Int64) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: UInt) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: UInt8) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: UInt16) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: UInt32) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: UInt64) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode<T>(_ value: T) throws where T : Encodable {
            if let date = value as? Date {
                return try encode(date.formatted(.iso8601))
            }
            let encoder = ValueEncoderImpl<Const>(codingPath: codingPath)
            try value.encode(to: encoder)
            list.append(encoder.value!)
        }
        
        
        mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            let objRef = ValueRef.ObjectRef()
            list.append(.object(objRef))
            return KeyedEncodingContainer(ObjectContainer<NestedKey>(codingPath: codingPath, objRef: objRef))
        }
        
        mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            let listRef = ValueRef.ListRef()
            list.append(.list(listRef))
            return ListContainer(codingPath: codingPath, listRef: listRef)
        }
        
        mutating func superEncoder() -> Encoder {
            let encoder = ValueEncoderImpl(codingPath: codingPath)
            list.append(.encoder(encoder))
            return encoder
        }
        
        
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let listRef = ValueRef.ListRef()
        value = .list(listRef)
        return ListContainer(codingPath: codingPath, listRef: listRef)
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        let anyRef = ValueRef.AnyRef()
        self.value = .any(anyRef)
        return ValueContainer(codingPath: codingPath, anyRef: anyRef)
    }
    
    
    struct ValueContainer: SingleValueEncodingContainer {
        var codingPath: [CodingKey]
        
        let anyRef: ValueRef.AnyRef
        var val: Value1<Const> {
            get { anyRef.value! }
            set { anyRef.value = newValue }
        }
        
        mutating func encodeNil() throws {
            val = .null
        }
        
        mutating func encode(_ value: Bool) throws {
            val = .boolean(value)
        }
        
        mutating func encode(_ value: String) throws {
            val = .string(value)
        }
        
        mutating func encode(_ value: Double) throws {
            val = .float(value)
        }
        
        mutating func encode(_ value: Float) throws {
            val = .float(Double(value))
        }
        
        mutating func encodeFixedWidthInteger<T: FixedWidthInteger>(_ value: T) {
            val = .int(Int(value))
        }
        
        mutating func encode(_ value: Int) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: Int8) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: Int16) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: Int32) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: Int64) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: UInt) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: UInt8) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: UInt16) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: UInt32) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode(_ value: UInt64) throws {
            encodeFixedWidthInteger(value)
        }
        
        mutating func encode<T>(_ value: T) throws where T : Encodable {
            if let date = value as? Date {
                return try encode(date.formatted(.iso8601))
            }
            let encoder = ValueEncoderImpl(codingPath: codingPath)
            try value.encode(to: encoder)
            val = encoder.value!.value
        }
        
        
    }
    
}

fileprivate extension Dictionary where Key == ObjectKey {
    subscript(_ key: String) -> Value? {
        get {
            self[ObjectKey(key)]
        }
        set(newValue) {
            self[ObjectKey(key)] = newValue
        }
    }
}
