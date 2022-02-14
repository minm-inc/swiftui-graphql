import XCTest
@testable import Codegen
@testable import GraphQL

final class CodegenTests: XCTestCase {
    
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
        
        let someInterfaceType = try! GraphQLInterfaceType(
            name: "SomeInterface",
            fields: [
                "z": GraphQLField(type: GraphQLInt)
            ]
        )
        
        let someInterfaceXType = try! GraphQLObjectType(
            name: "SomeInterfaceX",
            description: nil,
            fields: ["x": GraphQLField(type: GraphQLInt), "z": GraphQLField(type: GraphQLInt)],
            interfaces: [someInterfaceType],
            isTypeOf: nil
        )
        
        let someInterfaceYType = try! GraphQLObjectType(
            name: "SomeInterfaceY",
            description: nil,
            fields: ["y": GraphQLField(type: GraphQLInt), "z": GraphQLField(type: GraphQLInt)],
            interfaces: [someInterfaceType],
            isTypeOf: nil
        )
        
        return try! GraphQLSchema(query: GraphQLObjectType(
            name: "query",
            description: nil,
            fields: [
                "foo": GraphQLField(type: fooType),
                "someInterface": GraphQLField(type: someInterfaceType),
                "aOwners": GraphQLField(type: GraphQLList(hasAInterface))
            ],
            interfaces: [],
            isTypeOf: nil
        ), types: [hasAInterface, someInterfaceXType, someInterfaceYType])
    }()
  
   
    func testGenerateQueryStruct() {
        let document = try! GraphQL.parse(source: """
            query getThingies {
                foo {
                    e {
                        x
                    }
                }
            }
        """)
        
        let fragments: [FragmentDefinition] = document.definitions.compactMap {
            if case let .executableDefinition(.fragment(fragmentDef)) = $0 {
                return fragmentDef
            } else {
                return nil
            }
        }
        
        guard case let .executableDefinition(.operation(opDef)) = document.definitions.first else {
            XCTFail()
            return
        }
        
        
        let result: Decl = generateStruct(for: opDef, schema: schema, fragments: fragments, queryString: document.printed)
        XCTAssertEqual(result, .struct(name: "GetThingiesQuery", decls: [
            .let(name: "foo", type: .optional(.named("Foo"))),
            .struct(
                name: "Foo",
                decls: [
                    .let(name: "e", type: .optional(.named("E"))),
                    .struct(
                        name: "E",
                        decls: [
                            .let(name: "x", type: .optional(.named("Int")))
                        ],
                        conforms: ["Codable"]
                    )
                ],
                conforms: ["Codable"]
            ),
            .staticLetString(name: "query", literal: document.printed)
        ], conforms: ["Queryable", "Codable"]))
    }
    
    func testNestedObjectsOnFragment() {
        let document = try! GraphQL.parse(source: """
            query test {
                foo {
                    ...Blah
                }
            }
            fragment Blah on Foo {
                e {
                    baz {
                        j
                    }
                }
            }
        """)
        
        guard case let .executableDefinition(.fragment(fragDef)) = document.definitions[1] else {
            fatalError()
        }
        let parentType = schema.getType(name: "Foo")!
        let object = resolveFields(
            selectionSet: fragDef.selectionSet,
            parentType: parentType as! GraphQLOutputType,
            schema: schema,
            fragments: [fragDef]
        )
        let protocols = generateProtocols(
            object: object,
            named: "BlahFragment",
            parentType: parentType
        )
        
        XCTAssertEqual(protocols[0], Decl.protocol(
            name: "BlahFragment",
            conforms: [],
            whereClauses: [],
            decls: [
                Decl.associatedtype(
                    name: "E",
                    inherits: "BlahFragmentE"
                ),
                .protocolVar(name: "e", type: .optional(.named("E")))
            ]
        ))
        XCTAssertEqual(protocols[1], Decl.protocol(
            name: "BlahFragmentE",
            conforms: [],
            whereClauses: [],
            decls: [
                Decl.associatedtype(
                    name: "Baz",
                    inherits: "BlahFragmentEBaz"
                ),
                .protocolVar(name: "baz", type: .optional(.named("Baz")))
            ]
        ))
        XCTAssertEqual(protocols[2], Decl.protocol(
            name: "BlahFragmentEBaz",
            conforms: [],
            whereClauses: [],
            decls: [
                .protocolVar(name: "j", type: .optional(.named("Int")))
            ])
        )
        
        guard case let .executableDefinition(.operation(opDef)) = document.definitions[0] else {
            fatalError()
        }
        
        let `struct`: Decl = generateStruct(for: opDef, schema: schema, fragments: [fragDef], queryString: "")
        XCTAssertEqual(`struct`, Decl.struct(
            name: "TestQuery",
            decls: [
                .let(name: "foo", type: .optional(.named("Foo"))),
                .struct(
                    name: "Foo",
                    decls: [
                        .let(name: "e", type: .optional(.named("E"))),
                        .struct(
                            name: "E",
                            decls: [
                                .let(name: "baz", type: .optional(.named("Baz"))),
                                .struct(
                                    name: "Baz",
                                    decls: [
                                        .let(name: "j", type: .optional(.named("Int")))
                                    ],
                                    conforms: ["Codable", "BlahFragmentEBaz"]
                                )
                            ],
                            conforms: ["Codable", "BlahFragmentE"]
                        )
                    ],
                    conforms: ["Codable", "BlahFragment"]
                ),
                .staticLetString(name: "query", literal: " {\nfoo {\n...Blah\n}\n}\nfragment Blah on Foo {\ne {\nbaz {\nj\n}\n}\n}\n")
            ],
            conforms: ["Queryable", "Codable"])
        )
    }
    
    func testUnionsInsideFragment() {
        let unionAType = try! GraphQLObjectType(
            name: "MyUnionA",
            fields: [
                "a1": GraphQLField(type: GraphQLInt),
                "a2": GraphQLField(type: GraphQLInt)
            ]
        )
        let unionBType = try! GraphQLObjectType(
            name: "MyUnionB",
            fields: [
                "b1": GraphQLField(type: GraphQLInt)
            ]
        )
        let unionCType = try! GraphQLObjectType(
            name: "MyUnionC",
            fields: [
                "c1": GraphQLField(type: GraphQLInt)
            ]
        )
        let unionType = try! GraphQLUnionType(
            name: "MyUnion",
            description: nil,
            resolveType: nil,
            types: [unionAType, unionBType, unionCType]
        )
        
        let schema = try! GraphQLSchema(query: GraphQLObjectType(
            name: "query",
            description: nil,
            fields: [
                "myUnion": GraphQLField(type: unionType)
            ],
            interfaces: [],
            isTypeOf: nil
        ), types: [])
        
        
        let document = try! GraphQL.parse(source: """
            query test {
                myUnion {
                    ...MyUnion
                    ... on MyUnionA { a2 }
                    ... on MyUnionC { c1 }
                }
            }
            fragment MyUnion on MyUnion {
                ... on MyUnionA { a1 }
                ... on MyUnionB { b1 }
            }
        """)
        guard case let .executableDefinition(.fragment(fragDef)) = document.definitions[1] else {
            fatalError()
        }
        let object = resolveFields(
            selectionSet: fragDef.selectionSet,
            parentType: unionType,
            schema: schema,
            fragments: [fragDef]
        )
        let protocols = generateProtocols(
            object: object,
            named: "MyUnionFragment",
            parentType: unionType
        )
        if case let .`protocol`(name, conforms, whereClauses, decls) = protocols[0] {
            XCTAssertEqual(name, "ContainsMyUnionFragment")
            XCTAssertEqual(conforms, [])
            XCTAssertEqual(whereClauses, [])
            XCTAssertEqual(decls, [
                .protocolVar(
                    name: "__myUnionFragment",
                    type: .named("MyUnionFragment", genericArguments: [
                        .named("MyUnionA"),
                        .named("MyUnionB")
                    ])
                ),
                .associatedtype(name: "MyUnionA", inherits: "MyUnionFragmentMyUnionA"),
                .associatedtype(name: "MyUnionB", inherits: "MyUnionFragmentMyUnionB")
            ])
        } else {
            XCTFail()
        }
        if case let .`enum`(name, cases, decls, conforms, defaultCase, genericParameters) = protocols[1] {
            XCTAssertEqual(name, "MyUnionFragment")
            XCTAssertEqual(cases, [
                Codegen.Decl.Case(name: "myUnionA", nestedTypeName: "MyUnionA"),
                Codegen.Decl.Case(name: "myUnionB", nestedTypeName: "MyUnionB")
            ])
            XCTAssertEqual(decls, [])
            XCTAssertEqual(conforms, [])
            XCTAssertEqual(defaultCase, Codegen.Decl.Case(name: "__other", nestedTypeName: nil))
            XCTAssertEqual(genericParameters, [
                Codegen.Decl.GenericParameter(identifier: "MyUnionA", constraint: .named("MyUnionFragmentMyUnionA")),
                Codegen.Decl.GenericParameter(identifier: "MyUnionB", constraint: .named("MyUnionFragmentMyUnionB")),
            ])
        } else {
            XCTFail()
        }
        if case let .`protocol`(name, conforms, whereClauses, decls) = protocols[2] {
            XCTAssertEqual(name, "MyUnionFragmentMyUnionA")
            XCTAssertEqual(conforms, [])
            XCTAssertEqual(whereClauses, [])
            XCTAssertEqual(decls, [.protocolVar(name: "a1", type: .optional(.named("Int")))])
        } else {
            XCTFail()
        }
        if case let .`protocol`(name, conforms, whereClauses, decls) = protocols[3] {
            XCTAssertEqual(name, "MyUnionFragmentMyUnionB")
            XCTAssertEqual(conforms, [])
            XCTAssertEqual(whereClauses, [])
            XCTAssertEqual(decls, [.protocolVar(name: "b1", type: .optional(.named("Int")))])
        } else {
            XCTFail()
        }
    }
    
    func testNestedObjectsOnInterface() {
        let bType = try! GraphQLObjectType(
            name: "B",
            fields: [
                "b1": GraphQLField(type: GraphQLInt),
                "b2": GraphQLField(type: GraphQLInt)
            ]
        )
        let interfaceType = try! GraphQLInterfaceType(
            name: "A",
            fields: [
                "b": GraphQLField(type: bType)
            ]
        )
        let implType = try! GraphQLObjectType(
            name: "Impl",
            fields: ["b": GraphQLField(type: bType)],
            interfaces: [interfaceType]
        )
        let queryType = try! GraphQLObjectType(
            name: "Query",
            fields: [
                "a": GraphQLField(type: interfaceType)
            ]
        )
        let schema = try! GraphQLSchema(
            query: queryType,
            types: [implType]
        )
        let (query, fragments) = getFirstOperationAndFragments(source: """
        {
            a {
                b { b1 }
                ...Foo
            }
        }
        fragment Foo on Impl {
            b {
                b2
            }
        }
        """)
        let queryDecl: Decl = generateStruct(for: query, schema: schema, fragments: fragments, queryString: query.printed)
        guard case let .struct(_, queryDecls, _) = queryDecl else {
            XCTFail()
            return
        }
        
        guard case let .enum(_, cases, decls, _, _, _) = queryDecls[1] else {
            XCTFail()
            return
        }
        XCTAssertEqual(cases, [Codegen.Decl.Case(name: "impl", nestedTypeName: "Impl")])
        
        guard case let .struct("Impl", implDecls, _) = decls[0] else {
            XCTFail()
            return
        }
        XCTAssertEqual(implDecls[0], .`let`(
            name: "b",
            type: .optional(.named("B")),
            defaultValue: nil,
            isVar: false,
            getter: nil
        ))
        XCTAssertEqual(implDecls[1], .struct(
            name: "B",
            decls: [
                .let(name: "b1", type: .optional(.named("Int")), defaultValue: nil, isVar: false, getter: nil),
                .let(name: "b2", type: .optional(.named("Int")), defaultValue: nil, isVar: false, getter: nil)
            ],
            conforms: ["Codable"]
        ))
        guard case let .struct("__Other", otherDecls, otherConforms) = decls[1] else {
            XCTFail()
            return
        }
        XCTAssertEqual(otherDecls[0], .`let`(
            name: "b",
            type: .optional(.named("B")),
            defaultValue: nil,
            isVar: false,
            getter: nil
        ))
        XCTAssertEqual(otherDecls[1], .struct(
            name: "B",
            decls: [
                .let(name: "b1", type: .optional(.named("Int")), defaultValue: nil, isVar: false, getter: nil)
            ],
            conforms: ["Codable"]
        ))
    }
}

