import XCTest
@testable import Codegen
@testable import GraphQL

final class ResolveFieldTests: XCTestCase {
    
    lazy var schema: GraphQLSchema = {
        let hasAInterface = try! GraphQLInterfaceType(
            name: "HasA", fields: ["a": GraphQLField(type: GraphQLInt)]
        )
        let fooType = try! GraphQLObjectType(name: "Foo", description: nil, fields: [
            "a": GraphQLField(type: GraphQLInt),
            "b": GraphQLField(type: GraphQLInt),
            "c": GraphQLField(type: GraphQLInt),
            "d": GraphQLField(type: GraphQLInt),
            "e": GraphQLField(type: GraphQLObjectType(name: "Bar", description: nil, fields: [
                "x": GraphQLField(type: GraphQLInt),
                "y": GraphQLField(type: GraphQLInt),
                "z": GraphQLField(type: GraphQLInt),
                "baz": GraphQLField(type: GraphQLObjectType(
                    name: "Baz", description: nil, fields: [
                        "j": GraphQLField(type: GraphQLInt)
                    ]))
            ], interfaces: [], isTypeOf: nil))
        ], interfaces: [hasAInterface], isTypeOf: nil)
        
        return try! GraphQLSchema(query: GraphQLObjectType(
            name: "query",
            description: nil,
            fields: [
                "foo": GraphQLField(type: fooType),
                "aOwners": GraphQLField(type: GraphQLList(hasAInterface))
            ],
            interfaces: [],
            isTypeOf: nil
        ), types: [hasAInterface])
    }()
    
    func testResolveFields() {
        let (fooField, fragments) = getFirstQueryFieldAndFragments(source: """
        {
            foo {
                a
                b
                ...FooStuff
                e {
                    x
                }
                alsoE: e {
                    y
                }
            }
        }
        fragment FooStuff on Foo {
            c
            ...MoreFooStuff
            e {
                z
            }
        }
        fragment MoreFooStuff on Foo {
            d
        }
    """)
        
        let object = resolveFields(
            selectionSet: fooField.selectionSet!,
            parentType: schema.getType(name: "Foo")! as! GraphQLOutputType,
            schema: schema,
            fragments: fragments
        )
        XCTAssertEqual(object.unconditional.keys, ["a", "b", "c", "d", "e", "alsoE"])
        XCTAssert(object.conditional.isEmpty)
    }
    
    func testResolveFragmentFields2() {
        let (aOwnersField, fragments) = getFirstQueryFieldAndFragments(source: """
            query explore {
                aOwners {
                    ... on Foo {
                        e {
                            x
                        }
                        ...EY
                    }
                }
            }
            
            fragment EY on Foo {
                e {
                    y
                }
            }
        """)
        
        let object = resolveFields(
            selectionSet: aOwnersField.selectionSet!,
            parentType: schema.getType(name: "HasA")! as! GraphQLOutputType,
            schema: schema,
            fragments: fragments
        )
        XCTAssertEqual(object.unconditional, [:])
        XCTAssertEqual(object.conditional, [
            "Foo": ResolvedField.Object(
                type: schema.getType(name: "Foo")! as! GraphQLOutputType,
                unconditional: [
                    "e": .nested(ResolvedField.Object(
                        type: schema.getType(name: "Bar")! as! GraphQLOutputType,
                        unconditional: [
                            "x": .leaf(GraphQLInt),
                            "y": .leaf(GraphQLInt)
                        ],
                        conditional: [:],
                        fragProtos: [:]
                    ))
                ],
                conditional: [:],
                fragProtos: [.base("EY"): ProtocolInfo(
                    declaredFields: ["e"],
                    alsoConformsTo: [:],
                    isConditional: false
                )]
            )
        ])
    }
    
    func testFragmentOnInterface() {
        let (iface, fragments) = getFirstQueryFieldAndFragments(source: readQuerySource(path: "Cases/FragmentOnInterface"))
        let schema = fragmentOnInterfaceSchema
        let object = resolveFields(
            selectionSet: iface.selectionSet!,
            parentType: schema.getType(name: "Interface")! as! GraphQLOutputType,
            schema: schema,
            fragments: fragments
        )
        
        XCTAssertEqual(
            object.fragProtos,
            [
                .base("Foo"): ProtocolInfo(
                    declaredFields: ["z"],
                    alsoConformsTo: [
                        .base("Bar"): ProtocolInfo(
                            declaredFields: [],
                            alsoConformsTo: [:],
                            isConditional: true
                        )
                    ],
                    isConditional: true
                )
            ]
        )
        
        XCTAssertEqual(object.unconditional["z"], .leaf(GraphQLInt))
        
        XCTAssertEqual(object.conditional["X"], ResolvedField.Object(
            type: schema.getType(name: "X")! as! GraphQLOutputType,
            unconditional: [
                "x1": .leaf(GraphQLInt),
                "x2": .nested(ResolvedField.Object(
                    type: schema.getType(name: "X2")! as! GraphQLOutputType,
                    unconditional: [
                        "b": .leaf(GraphQLInt),
                        "a": .leaf(GraphQLInt)
                    ],
                    conditional: [:],
                    fragProtos: [:]
                )),
                "z": .leaf(GraphQLInt)
            ],
            conditional: [:],
            fragProtos: [
                .base("Baz"): ProtocolInfo(
                    declaredFields: ["x2"],
                    alsoConformsTo: [:],
                    isConditional: false
                )
            ]
        ))
        XCTAssertEqual(object.conditional["Y"], ResolvedField.Object(
            type: schema.getType(name: "Y")! as! GraphQLOutputType,
            unconditional: [
                "y": .leaf(GraphQLInt),
                "z": .leaf(GraphQLInt)
            ],
            conditional: [:],
            fragProtos: [:]
        ))
    }
    
    func testMultipleFragments() {
        let (query, fragments) = getFirstOperationAndFragments(source: readQuerySource(path: "Cases/MultipleFragments"))
        let schema = multipleFragmentsSchema
        
        let object = resolveFields(
            selectionSet: query.selectionSet,
            parentType: schema.queryType,
            schema: schema,
            fragments: fragments
        )
        
        XCTAssertEqual(
            object.fragProtos.keys,
            [.base("Foo"), .base("Bar"), .base("Baz")]
        )
        
        XCTAssertEqual(
            object.unconditional,
            [
                "a": .nested(ResolvedField.Object(
                    type: schema.getType(name: "A")! as! GraphQLObjectType,
                    unconditional: [
                        "b1": .leaf(GraphQLInt),
                        "b2": .leaf(GraphQLInt)
                    ],
                    conditional: [:],
                    fragProtos: [:]
                )),
                "b": .nested(ResolvedField.Object(
                    type: schema.getType(name: "A")! as! GraphQLObjectType,
                    unconditional: [
                        "b1": .leaf(GraphQLInt)
                    ],
                    conditional: [:],
                    fragProtos: [:]
                ))
            ]
        )
        
        XCTAssertEqual(object.conditional, [:])
    }
    
    func testResolvesNonNull() {
        let schema = try! GraphQLSchema(query: GraphQLObjectType(
            name: "Query",
            fields: [
                "a": GraphQLField(type: GraphQLNonNull(GraphQLObjectType(
                    name: "A",
                    fields: ["b": GraphQLField(type: GraphQLNonNull(GraphQLInt))]
                )))
            ])
        )
        let (query, fragments) = getFirstOperationAndFragments(source: "{ a { b } }")
        let object = resolveFields(
            selectionSet: query.selectionSet,
            parentType: schema.queryType,
            schema: schema,
            fragments: fragments
        )
        XCTAssertEqual(object.unconditional["a"], .nested(ResolvedField.Object(
            type: GraphQLNonNull(schema.getType(name: "A")!),
            unconditional: ["b": .leaf(GraphQLNonNull(GraphQLInt))],
            conditional: [:],
            fragProtos: [:]
        )))
    }
    
    func testFragmentAndNonFragmentNestedConditional() {
        let aType = try! GraphQLInterfaceType(
            name: "A",
            fields: [
                "x": GraphQLField(type: GraphQLInt)
            ]
        )
        let bType = try! GraphQLObjectType(
            name: "B",
            fields: [
                "x": GraphQLField(type: GraphQLInt),
                "y": GraphQLField(type: GraphQLInt)
            ],
            interfaces: [aType]
        )
        let schema = try! GraphQLSchema(
            query: GraphQLObjectType(
                name: "Query",
                fields: ["a": GraphQLField(type: aType)]
            ),
            types: [bType]
        )
        
        let (a, fragments) = getFirstQueryFieldAndFragments(source: """
        {
            a { ...F x }
        }
        fragment F on A {
            ... on B {
                y
            }
        }
        """)
        let object = resolveFields(
            selectionSet: a.selectionSet!,
            parentType: aType,
            schema: schema,
            fragments: fragments
        )
        XCTAssertEqual(
            object.conditional["B"]?.unconditional,
            [
                "y": .leaf(GraphQLInt),
                "x": .leaf(GraphQLInt)
            ]
        )
    }
    
    func testFragmentAndNonFragmentNestedObjectConditional() {
        let dType = try! GraphQLObjectType(
            name: "D",
            fields: [
                "x": GraphQLField(type: GraphQLInt),
                "y": GraphQLField(type: GraphQLInt)
            ]
        )
        let bType = try! GraphQLInterfaceType(
            name: "B",
            fields: [
                "d": GraphQLField(type: dType)
            ]
        )
        let cType = try! GraphQLObjectType(
            name: "C",
            fields: [
                "d": GraphQLField(type: dType),
            ],
            interfaces: [bType]
        )
        let schema = try! GraphQLSchema(
            query: GraphQLObjectType(
                name: "Query",
                fields: ["b": GraphQLField(type: bType)]
            ),
            types: [cType]
        )
        
        let (b, fragments) = getFirstQueryFieldAndFragments(source: """
        {
            b {
                ...F
                d { y }
            }
        }
        fragment F on B {
            ... on C {
                d { x }
            }
        }
        """)
        let object = resolveFields(
            selectionSet: b.selectionSet!,
            parentType: bType,
            schema: schema,
            fragments: fragments
        )
        guard case let .nested(dObj) = object.conditional["C"]?.unconditional["d"] else {
            XCTFail()
            return
        }
        XCTAssertEqual(dObj.unconditional.keys, ["x", "y"])
        guard case let .nested(dObj) = object.unconditional["d"] else {
            XCTFail()
            return
        }
        XCTAssertEqual(dObj.unconditional.keys, ["y"])
    }
    
    func testConditionalOnConditional() {
        let cType = try! GraphQLObjectType(
            name: "C",
            fields: [
                "x": GraphQLField(type: GraphQLInt),
                "y": GraphQLField(type: GraphQLInt)
            ]
        )
        let bType = try! GraphQLInterfaceType(
            name: "B",
            fields: [
                "c": GraphQLField(type: cType)
            ]
        )
        let bImplType = try! GraphQLObjectType(
            name: "BImpl",
            fields: [
                "c": GraphQLField(type: cType)
            ],
            interfaces: [bType]
        )
        let aType = try! GraphQLInterfaceType(
            name: "A",
            fields: [
                "b": GraphQLField(type: bType)
            ]
        )
        let aImplType = try! GraphQLObjectType(
            name: "AImpl",
            fields: [
                "b": GraphQLField(type: bType)
            ],
            interfaces: [aType]
        )
        let schema = try! GraphQLSchema(
            query: GraphQLObjectType(
                name: "Query",
                fields: ["a": GraphQLField(type: aType)]
            ),
            types: [aImplType, bImplType]
        )
        
        let (a, fragments) = getFirstQueryFieldAndFragments(source: """
        {
            a {
                b {
                    c {
                        x
                    }
                }
                ...F
            }
        }
        fragment F on A {
            ... on AImpl {
                b {
                    ... on BImpl {
                        c { y }
                    }
                }
            }
        }
        """)
        let object = resolveFields(
            selectionSet: a.selectionSet!,
            parentType: aType,
            schema: schema,
            fragments: fragments
        )
        guard case let .nested(bObj) = object.conditional["AImpl"]?.unconditional["b"] else {
            XCTFail()
            return
        }
        guard case let .nested(cObj) = bObj.conditional["BImpl"]?.unconditional["c"] else {
            XCTFail()
            return
        }
        XCTAssertEqual(cObj.unconditional.keys, ["y", "x"])
    }
    
    
//    func testCommunalFieldsOnConditional() {
//        let aType = try! GraphQLObjectType(
//            name: "A",
//            fields: [
//                "a1": GraphQLField(type: GraphQLInt),
//                "a2": GraphQLField(type: GraphQLInt)
//            ]
//        )
//        let ifaceType = try! GraphQLInterfaceType(
//            name: "Iface",
//            fields: ["a": GraphQLField(type: aType)]
//        )
//        let implType = try! GraphQLObjectType(
//            name: "Impl",
//            fields: ["a": GraphQLField(type: aType)],
//            interfaces: [ifaceType]
//        )
//        let schema = try! GraphQLSchema(
//            query: GraphQLObjectType(
//                name: "Query",
//                fields: ["iface": GraphQLField(type: ifaceType)]
//            ),
//            types: [implType]
//        )
//        let (iface, fragments) = getFirstQueryFieldAndFragments(source: """
//        {
//            iface {
//                ... on Impl { a { a1 } }
//                a { a2 }
//            }
//        }
//        """)
//        let object = resolveFields(
//            selectionSet: iface.selectionSet!,
//            parentType: ifaceType,
//            schema: schema,
//            fragments: fragments
//        )
//        XCTAssertEqual(object.conditional, [:])
//        XCTAssertEqual(object.unconditional, [
//            "a": .nested(ResolvedField.Object(
//                type: aType,
//                unconditional: [
//                    "a1": .leaf(GraphQLInt),
//                    "a2": .leaf(GraphQLInt)
//                ],
//                conditional: [:],
//                fragProtos: [:]
//            ))
//        ])
//    }
}

extension ResolvedField: Equatable {
    public static func == (lhs: ResolvedField, rhs: ResolvedField) -> Bool {
        switch (lhs, rhs) {
        case let (.leaf(ltype), .leaf(rtype)):
            return isEqualType(ltype, rtype)
        case let (.nested(l), .nested(r)):
            return l == r
        default:
            return false
        }
    }
}

extension ResolvedField.Object: Equatable {
    public static func == (lhs: ResolvedField.Object, rhs: ResolvedField.Object) -> Bool {
        return isEqualType(lhs.type, rhs.type) && lhs.unconditional == rhs.unconditional && lhs.conditional == rhs.conditional && lhs.fragProtos == rhs.fragProtos
    }
}
