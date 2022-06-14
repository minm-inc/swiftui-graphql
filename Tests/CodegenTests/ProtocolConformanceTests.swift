@testable import Codegen
import GraphQL
import XCTest

final class ProtocolConformanceTests: XCTestCase {
    func testBuildConformanceGraph() throws {
        let typeA = try GraphQLObjectType(name: "A", fields: [
            "x": GraphQLField(type: GraphQLInt)
        ])
        let typeB = try GraphQLObjectType(name: "B", fields: [
            "y": GraphQLField(type: GraphQLInt)
        ])
        
        let fragmentObjects: [String: MergedObject] = [
            "Foo": MergedObject(
                unconditional: .empty,
                conditional: [
                    AnyGraphQLCompositeType(typeA): .init(fields: ["x": MergedObject.Selection.Field(
                        name: "x",
                        arguments: [:],
                        type: GraphQLInt,
                        nested: nil
                    )]),
                    AnyGraphQLCompositeType(typeB): .init(fields: ["y": MergedObject.Selection.Field(
                        name: "y",
                        arguments: [:],
                        type: GraphQLInt,
                        nested: nil
                    )])
                ],
                type: try! GraphQLInterfaceType(name: "Foo", fields: [:]),
                fragmentConformances: [:]
            )
        ]
        
        let schema = try GraphQLSchema(
            query: GraphQLObjectType(
                name: "Query",fields: ["foo": GraphQLField(type: GraphQLInt)]
            ),
            types: [typeA, typeB]
        )
        
        let graph = ProtocolConformance.buildConformanceGraph(fragmentObjects: fragmentObjects, schema: schema)
        
        let basePath = FragmentProtocolPath(fragmentName: "Foo", fragmentObject: fragmentObjects["Foo"]!)
        
        XCTAssertEqual(Set(graph.keys), [
            basePath,
            basePath.appendingTypeDiscrimination(type: typeA),
            basePath.appendingTypeDiscrimination(type: typeB)
        ])
    }
    
    func testFragmentTypeDiscriminationsDontConformToUnconditionalFragmentsProtocol() throws {
        let typeA = try GraphQLObjectType(name: "A", fields: [
            "x": GraphQLField(type: GraphQLInt)
        ])
        
        let fragmentObjects: [String: MergedObject] = [
            "Foo": MergedObject(
                unconditional: .empty,
                conditional: [
                    AnyGraphQLCompositeType(typeA): .init(fields: ["x": MergedObject.Selection.Field(
                        name: "x",
                        arguments: [:],
                        type: GraphQLInt,
                        nested: nil
                    )])
                ],
                type: try! GraphQLInterfaceType(name: "Foo", fields: [:]),
                fragmentConformances: ["Bar": .unconditional]
            ),
            "Bar": MergedObject(
                unconditional: .empty,
                conditional: [
                    AnyGraphQLCompositeType(typeA): .init(fields: ["x": MergedObject.Selection.Field(
                        name: "x",
                        arguments: [:],
                        type: GraphQLInt,
                        nested: nil
                    )])
                ],
                type: try! GraphQLInterfaceType(name: "Foo", fields: [:]),
                fragmentConformances: [:]
            )
        ]
        
        let schema = try GraphQLSchema(
            query: GraphQLObjectType(
                name: "Query", fields: ["foo": GraphQLField(type: GraphQLInt)]
            ),
            types: [typeA]
        )
        
        let graph = ProtocolConformance.buildConformanceGraph(fragmentObjects: fragmentObjects, schema: schema)
        
        let path = FragmentProtocolPath(fragmentName: "Foo", fragmentObject: fragmentObjects["Foo"]!)
            .appendingTypeDiscrimination(type: typeA)
        let barPath = FragmentProtocolPath(fragmentName: "Bar", fragmentObject: fragmentObjects["Bar"]!)
        
        XCTAssertFalse(graph[path]!.inherits.map(\.name).contains(barPath.protocolName))
    }
    
    /// The nested FooYFragment protocol should conform to BarYFragment here
    ///
    /// ```
    /// fragment Foo on X {
    ///    y { a }
    ///    ...Bar
    /// }
    /// fragment Bar on X {
    ///    y { b }
    /// }
    /// ```
    func testFragmentsInheritFragmentsThroughoutNestedObjects() throws {
        let yType = try GraphQLObjectType(name: "Y", fields: [
            "a": GraphQLField(type: GraphQLInt),
            "b": GraphQLField(type: GraphQLInt)
        ])
        let xType = try GraphQLObjectType(name: "X", fields: [
            "y": GraphQLField(type: yType)
        ])
        
        let fragmentObjects: [String: MergedObject] = [
            "Foo": MergedObject(
                unconditional: .init(fields: [
                    "y": .init(
                        name: "y",
                        arguments: [:],
                        type: yType,
                        nested: MergedObject(
                            unconditional: .init(fields: [
                                "a": .init(name: "a", arguments: [:], type: GraphQLInt, nested: nil),
                            ]),
                            conditional: [:],
                            type: yType,
                            fragmentConformances: [:]
                        )
                    )
                ]),
                conditional: [:],
                type: xType,
                fragmentConformances: ["Bar": .unconditional]
            ),
            "Bar": MergedObject(
                unconditional: .init(fields: [
                    "y": .init(
                        name: "y",
                        arguments: [:],
                        type: yType,
                        nested: MergedObject(
                            unconditional: .init(fields: [
                                "b": .init(name: "b", arguments: [:], type: GraphQLInt, nested: nil)
                            ]),
                            conditional: [:],
                            type: yType,
                            fragmentConformances: [:]
                        )
                    )
                ]),
                conditional: [:],
                type: xType,
                fragmentConformances: [:]
            )
        ]
        let schema = try GraphQLSchema(
            query: xType,
            types: [yType]
        )
        
        let graph = ProtocolConformance.buildConformanceGraph(fragmentObjects: fragmentObjects, schema: schema)
        
        let fooYPath = FragmentProtocolPath(fragmentName: "Foo", fragmentObject: fragmentObjects["Foo"]!)
            .appendingNestedObject(fragmentObjects["Foo"]!.unconditional.fields["y"]!.nested!, withKey: "y")
        
        let barYPath = FragmentProtocolPath(fragmentName: "Bar", fragmentObject: fragmentObjects["Bar"]!)
            .appendingNestedObject(fragmentObjects["Bar"]!.unconditional.fields["y"]!.nested!, withKey: "y")
        
        XCTAssert(graph[fooYPath]!.inherits.map(\.name).contains(barYPath.protocolName))
        
    }
    
    /// The nested FooYFragment protocol should conform to BarYFragment here
    ///
    /// ```
    /// fragment Foo on X {
    ///    ...Bar
    /// }
    /// fragment Bar on X {
    ///    ... on Y { a }
    /// }
    /// ```
    func testFragmentsInheritFragmentsThroughoutTypeDiscriminations() throws {
        let yType = try GraphQLObjectType(name: "Y", fields: [
            "a": GraphQLField(type: GraphQLInt),
            "b": GraphQLField(type: GraphQLInt)
        ])
        let xType = try GraphQLInterfaceType(name: "X", fields: [
            "b": GraphQLField(type: GraphQLInt)
        ])
        
        let fragmentObjects: [String: MergedObject] = [
            "Foo": MergedObject(
                unconditional: .empty,
                conditional: [AnyGraphQLCompositeType(yType): .init(fields: [
                    "a": .init(name: "a", arguments: [:], type: GraphQLInt, nested: nil)
                ])],
                type: xType,
                fragmentConformances: ["Bar": .unconditional]
            ),
            "Bar": MergedObject(
                unconditional: .empty,
                conditional: [AnyGraphQLCompositeType(yType): .init(fields: [
                    "a": .init(name: "a", arguments: [:], type: GraphQLInt, nested: nil)
                ])],
                type: xType,
                fragmentConformances: [:]
            )
        ]
        let schema = try GraphQLSchema(
            query: yType,
            types: [xType, yType]
        )
        
        let graph = ProtocolConformance.buildConformanceGraph(fragmentObjects: fragmentObjects, schema: schema)
        
        let fooYPath = FragmentProtocolPath(fragmentName: "Foo", fragmentObject: fragmentObjects["Foo"]!)
            .appendingTypeDiscrimination(type: yType)
        let barYPath = FragmentProtocolPath(fragmentName: "Bar", fragmentObject: fragmentObjects["Bar"]!)
            .appendingTypeDiscrimination(type: yType)
        
        let conformance = graph[fooYPath]!
        
        XCTAssertEqual(conformance.inherits.map(\.name), [barYPath.protocolName])
        
    }
    
    func testInheritingRemovesRedundantInheritances() {
        let a = ProtocolConformance(type: .plain("A"))
        let b = ProtocolConformance(type: .plain("B"))
        let c = ProtocolConformance(type: .plain("C"))
        a.inherit(b)
        a.inherit(c)
        b.inherit(c)
        XCTAssertEqual(a.inherits, [b])
    }
    
    func testInheritingSomethingThatInheritsRemovesRedundantInheritances() {
        let a = ProtocolConformance(type: .plain("A"))
        let b = ProtocolConformance(type: .plain("B"))
        let c = ProtocolConformance(type: .plain("C"))
        a.inherit(b)
        c.inherit(b)
        a.inherit(c)
        XCTAssertEqual(a.inherits, [c])
    }
}
