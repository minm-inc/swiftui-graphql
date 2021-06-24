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
    
    func getFirstQueryFieldAndFragments(source: String) -> (Field, [FragmentDefinition]) {
        let document = try! GraphQL.parse(source: source)
        
        let fragments: [FragmentDefinition] = document.definitions.compactMap {
            if case let .executableDefinition(.fragment(fragmentDef)) = $0 {
                return fragmentDef
            } else {
                return nil
            }
        }
        
        guard case let .executableDefinition(.operation(opDef)) = document.definitions.first else {
            fatalError("Couldn't find operation definition")
        }
        
        guard case let .field(field) = opDef.selectionSet.selections.first else {
            fatalError("Couldn't find field")
        }
        
        return (field, fragments)
    }
    
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
        
        let (unconditional, conditional, _) = resolveFields(
            selectionSet: fooField.selectionSet!,
            parentType: schema.getType(name: "Foo")!,
            schema: schema,
            fragments: fragments
        )
        XCTAssertEqual(unconditional.keys, ["a", "b", "c", "d", "e", "alsoE"])
        XCTAssert(conditional.isEmpty)
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
        
        let (unconditional, conditional, _) = resolveFields(
            selectionSet: aOwnersField.selectionSet!,
            parentType: schema.getType(name: "HasA")!,
            schema: schema,
            fragments: fragments
        )
        XCTAssertEqual(unconditional, [:])
        XCTAssertEqual(conditional, [
            "Foo": [
                "e": .nested(
                    schema.getType(name: "Bar")! as! GraphQLOutputType,
                    unconditional: [
                        "x": .leaf(GraphQLInt),
                        "y": .leaf(GraphQLInt)
                    ],
                    conditional: [:],
                    fragmentConformances: ["EYFragmentE"]
                )
            ]
        ])
    }
    
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
        
        XCTAssertTrue(GraphQLTypeReference("Bar") == GraphQLTypeReference("Bar"))
        
        
        let result: Decl = generateStruct(for: opDef, schema: schema, fragments: fragments, queryString: document.printed)
        XCTAssertEqual(result, .struct(name: "GetThingiesQuery", defs: [
            .let(name: "foo", type: .named("Foo")),
            .struct(
                name: "Foo",
                defs: [
                    .let(name: "e", type: .named("Bar")),
                    .struct(
                        name: "Bar",
                        defs: [
                            .let(name: "x", type: .named("Int"))
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
        let (unconditional, conditional, _) = resolveFields(
            selectionSet: fragDef.selectionSet,
            parentType: parentType,
            schema: schema,
            fragments: [fragDef]
        )
        let protocols = generateProtocols(
            unconditional: unconditional,
            conditional: conditional,
            named: "BlahFragment",
            parentType: parentType
        )
        
        XCTAssertEqual(protocols[0], Decl.protocol(
            name: "BlahFragment",
            decls: [
                Decl.associatedtype(
                    name: "E",
                    inherits: "BlahFragmentE"
                ),
                .protocolVar(name: "e", type: .named("E"))
            ])
        )
        XCTAssertEqual(protocols[1], Decl.protocol(
            name: "BlahFragmentE",
            decls: [
                Decl.associatedtype(
                    name: "Baz",
                    inherits: "BlahFragmentEBaz"
                ),
                .protocolVar(name: "baz", type: .named("Baz"))
            ])
        )
        XCTAssertEqual(protocols[2], Decl.protocol(
            name: "BlahFragmentEBaz",
            decls: [
                .protocolVar(name: "j", type: .named("Int"))
            ])
        )
        
        guard case let .executableDefinition(.operation(opDef)) = document.definitions[0] else {
            fatalError()
        }
        
        let `struct`: Decl = generateStruct(for: opDef, schema: schema, fragments: [fragDef], queryString: "")
        XCTAssertEqual(`struct`, Decl.struct(
            name: "TestQuery",
            defs: [
                .let(name: "foo", type: .named("Foo")),
                .struct(
                    name: "Foo",
                    defs: [
                        .let(name: "e", type: .named("Bar")),
                        .struct(
                            name: "Bar",
                            defs: [
                                .let(name: "baz", type: .named("Baz")),
                                .struct(
                                    name: "Baz",
                                    defs: [
                                        .let(name: "j", type: .named("Int"))
                                    ],
                                    conforms: ["Codable", "BlahFragmentEBaz"]
                                )
                            ],
                            conforms: ["Codable", "BlahFragmentE"]
                        )
                    ],
                    conforms: ["Codable", "BlahFragment"]
                ),
                .staticLetString(name: "query", literal: "")
            ],
            conforms: ["Queryable", "Codable"])
        )
    }
}

extension ResolvedField: Equatable {
    public static func == (lhs: ResolvedField, rhs: ResolvedField) -> Bool {
        switch (lhs, rhs) {
        case let (.leaf(ltype), .leaf(rtype)):
            return isEqualType(ltype, rtype)
        case let (.nested(ltype, lunconditional, lconditional, lfragmentConformances), .nested(rtype, runconditional, rconditional, rfragmentConformances)):
            return isEqualType(ltype, rtype) && lunconditional == runconditional && lconditional == rconditional && lfragmentConformances == rfragmentConformances
        default:
            return false
        }
    }
}
//
//extension Decl: Equatable where TypeRep == GraphQLType {
//    public static func == (lhs: Self, rhs: Self) -> Bool {
//        switch (lhs, rhs) {
//        case let (.struct(lhsname, lhsdefs, lhsconforms), .struct(rhsname, rhsdefs, rhsconforms)):
//            return lhsname == rhsname && lhsdefs == rhsdefs && lhsconforms == rhsconforms
//        case let (.enum(lhsname, lhscases, lhsdefs, lhsdefaultCaseName), .enum(rhsname, rhscases, rhsdefs, rhsdefaultCaseName)):
//            return lhsname == rhsname && lhscases == rhscases && lhsdefs == rhsdefs && lhsdefaultCaseName == rhsdefaultCaseName
//        case let (.let(lhsname, lhstype, lhsdefaultValue, lhsisVar), .let(rhsname, rhstype, rhsdefaultValue, rhsisVar)):
//            return lhsname == rhsname && lhstype == rhstype && lhsdefaultValue == rhsdefaultValue && lhsisVar == rhsisVar
//        case let (.staticLetString(lhsname, lhsliteral), .staticLetString(rhsname, rhsliteral)):
//            return lhsname == rhsname && lhsliteral == rhsliteral
//        case let (.protocol(lhsname, lhsdecls), .protocol(rhsname, rhsdecls)):
//            return lhsname == rhsname && lhsdecls == rhsdecls
//        case let (.protocolVar(lhsname, lhstype), .protocolVar(rhsname, rhstype)):
//            return lhsname == rhsname && lhstype == rhstype
//        case let (.associatedtype(lhsname, lhsinherits), .associatedtype(rhsname, rhsinherits)):
//            return lhsname == rhsname && lhsinherits == rhsinherits
//        default:
//            return false
//        }
//    }
//}
