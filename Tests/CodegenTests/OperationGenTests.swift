import XCTest
@testable import Codegen
@testable import GraphQL

// TODO: Convert these to modern tests
//final class OperationGenTests: XCTestCase {
//    
//    lazy var schema: GraphQLSchema = {
//        let hasAInterface = try! GraphQLInterfaceType(
//            name: "HasA", fields: ["a": GraphQLField(type: GraphQLInt)]
//        )
//        let fooType = try! GraphQLObjectType(name: "Foo", description: nil, fields: [
//            "a": GraphQLField(type: GraphQLInt),
//            "b": GraphQLField(type: GraphQLInt),
//            "c": GraphQLField(type: GraphQLInt),
//            "d": GraphQLField(type: GraphQLInt),
//            "e": GraphQLField(type: GraphQLObjectType(name: "Bar", description: nil, fields: [
//                "x": GraphQLField(type: GraphQLInt),
//                "y": GraphQLField(type: GraphQLInt),
//                "z": GraphQLField(type: GraphQLInt),
//                "baz": GraphQLField(type: GraphQLObjectType(
//                    name: "Baz", description: nil, fields: [
//                        "j": GraphQLField(type: GraphQLInt)
//                    ]))
//            ], interfaces: [], isTypeOf: nil))
//        ], interfaces: [hasAInterface], isTypeOf: nil)
//        
//        let someInterfaceType = try! GraphQLInterfaceType(
//            name: "SomeInterface",
//            fields: [
//                "z": GraphQLField(type: GraphQLInt)
//            ]
//        )
//        
//        let someInterfaceXType = try! GraphQLObjectType(
//            name: "SomeInterfaceX",
//            description: nil,
//            fields: ["x": GraphQLField(type: GraphQLInt), "z": GraphQLField(type: GraphQLInt)],
//            interfaces: [someInterfaceType],
//            isTypeOf: nil
//        )
//        
//        let someInterfaceYType = try! GraphQLObjectType(
//            name: "SomeInterfaceY",
//            description: nil,
//            fields: ["y": GraphQLField(type: GraphQLInt), "z": GraphQLField(type: GraphQLInt)],
//            interfaces: [someInterfaceType],
//            isTypeOf: nil
//        )
//        
//        return try! GraphQLSchema(query: GraphQLObjectType(
//            name: "query",
//            description: nil,
//            fields: [
//                "foo": GraphQLField(type: fooType),
//                "someInterface": GraphQLField(type: someInterfaceType),
//                "aOwners": GraphQLField(type: GraphQLList(hasAInterface))
//            ],
//            interfaces: [],
//            isTypeOf: nil
//        ), types: [hasAInterface, someInterfaceXType, someInterfaceYType])
//    }()
//  
//   
//    func testGenerateQueryStruct() {
//        let document = try! GraphQL.parse(source: """
//            query getThingies {
//                foo {
//                    e {
//                        x
//                    }
//                }
//            }
//        """)
//        
//        let fragments: [FragmentDefinition] = document.definitions.compactMap {
//            if case let .executableDefinition(.fragment(fragmentDef)) = $0 {
//                return fragmentDef
//            } else {
//                return nil
//            }
//        }
//        
//        guard case let .executableDefinition(.operation(opDef)) = document.definitions.first else {
//            XCTFail()
//            return
//        }
//        
//        
//        let result: Decl = genOperation(opDef, schema: schema, fragmentDefinitions: fragments)
//        XCTAssertEqual(result, .struct(name: "GetThingiesQuery", decls: [
//            .let(name: "foo", type: .optional(.named("Foo"))),
//            .struct(
//                name: "Foo",
//                decls: [
//                    .let(name: "e", type: .optional(.named("E"))),
//                    .struct(
//                        name: "E",
//                        decls: [
//                            .let(name: "x", type: .optional(.named("Int")))
//                        ],
//                        conforms: ["Codable"]
//                    )
//                ],
//                conforms: ["Codable"]
//            ),
//            .staticLetString(name: "query", literal: document.printed)
//        ], conforms: ["Queryable", "Codable"]))
//    }
//    
//    func testNestedObjectsOnFragment() {
//        let document = try! GraphQL.parse(source: """
//            query test {
//                foo {
//                    ...Blah
//                }
//            }
//            fragment Blah on Foo {
//                e {
//                    baz {
//                        j
//                    }
//                }
//            }
//        """)
//        
//        guard case let .executableDefinition(.fragment(fragDef)) = document.definitions[1] else {
//            fatalError()
//        }
//        let parentType = schema.getType(name: "Foo")!
//        let object = resolveFields(
//            selectionSet: fragDef.selectionSet,
//            parentType: parentType as! GraphQLOutputType,
//            schema: schema,
//            fragments: [fragDef]
//        )
//        let protocols = generateProtocols(
//            object: object,
//            named: "BlahFragment",
//            parentType: parentType
//        )
//        
//        XCTAssertEqual(protocols[0], Decl.protocol(
//            name: "BlahFragment",
//            conforms: [],
//            whereClauses: [],
//            decls: [
//                Decl.associatedtype(
//                    name: "E",
//                    inherits: "BlahFragmentE"
//                ),
//                .let(name: "e", type: .optional(.named("E")), accessor: .get())
//            ]
//        ))
//        XCTAssertEqual(protocols[1], Decl.protocol(
//            name: "BlahFragmentE",
//            conforms: [],
//            whereClauses: [],
//            decls: [
//                Decl.associatedtype(
//                    name: "Baz",
//                    inherits: "BlahFragmentEBaz"
//                ),
//                .let(name: "baz", type: .optional(.named("Baz")), accessor: .get())
//            ]
//        ))
//        XCTAssertEqual(protocols[2], Decl.protocol(
//            name: "BlahFragmentEBaz",
//            conforms: [],
//            whereClauses: [],
//            decls: [
//                .let(name: "j", type: .optional(.named("Int")), accessor: .get())
//            ])
//        )
//        
//        guard case let .executableDefinition(.operation(opDef)) = document.definitions[0] else {
//            fatalError()
//        }
//        
//        let `struct`: Decl = genOperation(opDef, schema: schema, fragmentDefinitions: [fragDef])
//        XCTAssertEqual(`struct`, Decl.struct(
//            name: "TestQuery",
//            decls: [
//                .let(name: "foo", type: .optional(.named("Foo"))),
//                .struct(
//                    name: "Foo",
//                    decls: [
//                        .let(name: "e", type: .optional(.named("E"))),
//                        .struct(
//                            name: "E",
//                            decls: [
//                                .let(name: "baz", type: .optional(.named("Baz"))),
//                                .struct(
//                                    name: "Baz",
//                                    decls: [
//                                        .let(name: "j", type: .optional(.named("Int")))
//                                    ],
//                                    conforms: ["Codable", "BlahFragmentEBaz"]
//                                )
//                            ],
//                            conforms: ["Codable", "BlahFragmentE"]
//                        )
//                    ],
//                    conforms: ["Codable", "BlahFragment"]
//                ),
//                .staticLetString(name: "query", literal: " {\nfoo {\n...Blah\n}\n}\nfragment Blah on Foo {\ne {\nbaz {\nj\n}\n}\n}\n")
//            ],
//            conforms: ["Queryable", "Codable"])
//        )
//    }
//    
//    func testUnionsInsideFragment() {
//        let unionAType = try! GraphQLObjectType(
//            name: "MyUnionA",
//            fields: [
//                "a1": GraphQLField(type: GraphQLInt),
//                "a2": GraphQLField(type: GraphQLInt)
//            ]
//        )
//        let unionBType = try! GraphQLObjectType(
//            name: "MyUnionB",
//            fields: [
//                "b1": GraphQLField(type: GraphQLInt)
//            ]
//        )
//        let unionCType = try! GraphQLObjectType(
//            name: "MyUnionC",
//            fields: [
//                "c1": GraphQLField(type: GraphQLInt)
//            ]
//        )
//        let unionType = try! GraphQLUnionType(
//            name: "MyUnion",
//            description: nil,
//            resolveType: nil,
//            types: [unionAType, unionBType, unionCType]
//        )
//        
//        let schema = try! GraphQLSchema(query: GraphQLObjectType(
//            name: "query",
//            description: nil,
//            fields: [
//                "myUnion": GraphQLField(type: unionType)
//            ],
//            interfaces: [],
//            isTypeOf: nil
//        ), types: [])
//        
//        
//        let document = try! GraphQL.parse(source: """
//            query test {
//                myUnion {
//                    ...MyUnion
//                    ... on MyUnionA { a2 }
//                    ... on MyUnionC { c1 }
//                }
//            }
//            fragment MyUnion on MyUnion {
//                ... on MyUnionA { a1 }
//                ... on MyUnionB { b1 }
//            }
//        """)
//        guard case let .executableDefinition(.fragment(fragDef)) = document.definitions[1] else {
//            fatalError()
//        }
//        let object = resolveFields(
//            selectionSet: fragDef.selectionSet,
//            parentType: unionType,
//            schema: schema,
//            fragments: [fragDef]
//        )
//        let protocols = generateProtocols(
//            object: object,
//            named: "MyUnionFragment",
//            parentType: unionType
//        )
//        if case let .`protocol`(name, conforms, whereClauses, decls) = protocols[0] {
//            XCTAssertEqual(name, "ContainsMyUnionFragment")
//            XCTAssertEqual(conforms, [])
//            XCTAssertEqual(whereClauses, [])
//            XCTAssertEqual(decls, [
//                .let(
//                    name: "__myUnionFragment",
//                    type: .named("MyUnionFragment", genericArguments: [
//                        .named("MyUnionA"),
//                        .named("MyUnionB")
//                    ]),
//                    accessor: .get()
//                ),
//                .associatedtype(name: "MyUnionA", inherits: "MyUnionFragmentMyUnionA"),
//                .associatedtype(name: "MyUnionB", inherits: "MyUnionFragmentMyUnionB")
//            ])
//        } else {
//            XCTFail()
//        }
//        if case let .`enum`(name, cases, decls, conforms, defaultCase, genericParameters) = protocols[1] {
//            XCTAssertEqual(name, "MyUnionFragment")
//            XCTAssertEqual(cases, [
//                Codegen.Decl.Case(name: "myUnionA", nestedTypeName: "MyUnionA"),
//                Codegen.Decl.Case(name: "myUnionB", nestedTypeName: "MyUnionB")
//            ])
//            XCTAssertEqual(decls, [])
//            XCTAssertEqual(conforms, [])
//            XCTAssertEqual(defaultCase, Codegen.Decl.Case(name: "__other", nestedTypeName: nil))
//            XCTAssertEqual(genericParameters, [
//                Codegen.Decl.GenericParameter(identifier: "MyUnionA", constraint: .named("MyUnionFragmentMyUnionA")),
//                Codegen.Decl.GenericParameter(identifier: "MyUnionB", constraint: .named("MyUnionFragmentMyUnionB")),
//            ])
//        } else {
//            XCTFail()
//        }
//        if case let .`protocol`(name, conforms, whereClauses, decls) = protocols[2] {
//            XCTAssertEqual(name, "MyUnionFragmentMyUnionA")
//            XCTAssertEqual(conforms, [])
//            XCTAssertEqual(whereClauses, [])
//            XCTAssertEqual(decls, [.let(
//                name: "a1",
//                type: .optional(.named("Int")),
//                accessor: .get()
//            )])
//        } else {
//            XCTFail()
//        }
//        if case let .`protocol`(name, conforms, whereClauses, decls) = protocols[3] {
//            XCTAssertEqual(name, "MyUnionFragmentMyUnionB")
//            XCTAssertEqual(conforms, [])
//            XCTAssertEqual(whereClauses, [])
//            XCTAssertEqual(decls, [.let(
//                name: "b1",
//                type: .optional(.named("Int")),
//                accessor: .get()
//            )])
//        } else {
//            XCTFail()
//        }
//    }
//    
//    func testNestedObjectsOnInterface() {
//        let bType = try! GraphQLObjectType(
//            name: "B",
//            fields: [
//                "b1": GraphQLField(type: GraphQLInt),
//                "b2": GraphQLField(type: GraphQLInt)
//            ]
//        )
//        let interfaceType = try! GraphQLInterfaceType(
//            name: "A",
//            fields: [
//                "b": GraphQLField(type: bType)
//            ]
//        )
//        let implType = try! GraphQLObjectType(
//            name: "Impl",
//            fields: ["b": GraphQLField(type: bType)],
//            interfaces: [interfaceType]
//        )
//        let queryType = try! GraphQLObjectType(
//            name: "Query",
//            fields: [
//                "a": GraphQLField(type: interfaceType)
//            ]
//        )
//        let schema = try! GraphQLSchema(
//            query: queryType,
//            types: [implType]
//        )
//        let (query, fragments) = getFirstOperationAndFragments(source: """
//        {
//            a {
//                b { b1 }
//                ...Foo
//            }
//        }
//        fragment Foo on Impl {
//            b {
//                b2
//            }
//        }
//        """)
//        let queryDecl: Decl = genOperation(query, schema: schema, fragmentDefinitions: fragments)
//        guard case let .struct(_, queryDecls, _) = queryDecl else {
//            XCTFail()
//            return
//        }
//        
//        guard case let .enum(_, cases, decls, _, _, _) = queryDecls[1] else {
//            XCTFail()
//            return
//        }
//        XCTAssertEqual(cases, [Codegen.Decl.Case(name: "impl", nestedTypeName: "Impl")])
//        
//        guard case let .struct("Impl", implDecls, _) = decls[0] else {
//            XCTFail()
//            return
//        }
//        XCTAssertEqual(implDecls[0], .`let`(
//            name: "b",
//            type: .optional(.named("B"))
//        ))
//        XCTAssertEqual(implDecls[1], .struct(
//            name: "B",
//            decls: [
//                .let(name: "b2", type: .optional(.named("Int"))),
//                .let(name: "b1", type: .optional(.named("Int"))),
//                .func(
//                    name: "convert",
//                    returnType: .memberType("B", .memberType("A", .named("AnonymousQuery"))),
//                    body: .expr(
//                        .functionCall(
//                            called: .memberAccess(member: "B", base: .memberAccess(member: "A", base: .identifier("AnonymousQuery"))),
//                            args: [.named("b1", .identifier("b1"))]
//                        )
//                    ),
//                    access: .fileprivate
//                )
//            ],
//            conforms: ["Codable", "FooFragmentB"]
//        ))
//        guard case let .struct("__Other", otherDecls, _) = decls[3] else {
//            XCTFail()
//            return
//        }
//        XCTAssertEqual(otherDecls[0], .`let`(
//            name: "b",
//            type: .optional(.named("B"))
//        ))
//        XCTAssertEqual(decls[2], .struct(
//            name: "B",
//            decls: [
//                .let(name: "b1", type: .optional(.named("Int")))
//            ],
//            conforms: ["Codable"]
//        ))
//    }
//    
//    func testLiftProtocols() {
//        let decl = Decl.struct(
//            name: "Foo",
//            decls: [
//                .protocol(
//                    name: "Proto1",
//                    conforms: [],
//                    whereClauses: [],
//                    decls: []
//                ),
//                .struct(
//                    name: "Bar",
//                    decls: [
//                        .protocol(
//                            name: "Proto2",
//                            conforms: [],
//                            whereClauses: [],
//                            decls: []
//                        ),
//                        .enum(
//                            name: "Baz",
//                            cases: [],
//                            decls: [],
//                            conforms: ["Proto2"],
//                            defaultCase: nil,
//                            genericParameters: []
//                        )
//                    ],
//                    conforms: ["Proto1"]
//                )
//            ],
//            conforms: []
//        )
//        let expected = [
//            Decl.struct(
//                name: "Foo",
//                decls: [
//                    .struct(
//                        name: "Bar",
//                        decls: [
//                            .enum(
//                                name: "Baz",
//                                cases: [],
//                                decls: [],
//                                conforms: ["FooBarProto2"],
//                                defaultCase: nil,
//                                genericParameters: []
//                            )
//                        ],
//                        conforms: ["FooProto1"]
//                    )
//                ],
//                conforms: []
//            ),
//            .protocol(
//                name: "FooProto1",
//                conforms: [],
//                whereClauses: [],
//                decls: []
//            ),
//            .protocol(
//                name: "FooBarProto2",
//                conforms: [],
//                whereClauses: [],
//                decls: []
//            )
//        ]
//        XCTAssertEqual(
//            liftProtocols(outOf: decl),
//            expected
//        )
//    }
//}
//
