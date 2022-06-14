//
//  IntegrationTests.swift
//  
//
//  Created by Luke Lau on 13/02/2022.
//

import XCTest
@testable import GraphQL
import Codegen

class IntegrationTests: XCTestCase {

    func testChainedFragments() {
        assertCodegenMatches(path: "Cases/ChainedFragments", schema: chainedFragmentsSchema)
    }
    
    func testFragmentOnInterface() {
        assertCodegenMatches(path: "Cases/FragmentOnInterface", schema: fragmentOnInterfaceSchema)
    }
    
    func testMultipleFragments() {
        assertCodegenMatches(path: "Cases/MultipleFragments", schema: multipleFragmentsSchema)
    }
    
    func testNestedObjectsOnInterface() {
        assertCodegenMatches(path: "Cases/NestedObjectsOnInterface", schema: nestedObjectsOnInterfaceSchema)
    }
    
    private func assertCodegenMatches(path: String, schema: GraphQLSchema) {
        let document = try! parse(source: readQuerySource(path: path))
        let errors = GraphQL.validate(schema: schema, ast: document)
        if !errors.isEmpty {
            errors.forEach { XCTFail($0.localizedDescription) }
        }
        var actualOutput = ""
        generateCode(document: document, schema: schema, globalFragments: [])
            .write(to: &actualOutput)
        let outputUrl = Bundle.module.url(forResource: path, withExtension: "swift")!
        let expectedOutput = String(data: try! Data(contentsOf: outputUrl), encoding: .utf8)!
        XCTAssertEqual(actualOutput, expectedOutput)
    }

}

let chainedFragmentsSchema = try! GraphQLSchema(
    query: try! GraphQLObjectType(
        name: "Query",
        fields: [
            "a": GraphQLField(type: try! GraphQLObjectType(
                name: "A",
                fields: [
                    "a1": GraphQLField(type: GraphQLInt),
                    "a2": GraphQLField(type: GraphQLInt)
                ]
            )),
            "b": GraphQLField(type: GraphQLInt)
        ]
    )
)

var fragmentOnInterfaceSchema: GraphQLSchema = {
    let interface = try! GraphQLInterfaceType(
        name: "Interface",
        fields: [
            "z": GraphQLField(type: GraphQLInt)
        ]
    )
    
    let x = try! GraphQLObjectType(
        name: "X",
        description: nil,
        fields: [
            "x1": GraphQLField(type: GraphQLInt),
            "x2": GraphQLField(type: try! GraphQLObjectType(
                name: "X2",
                fields: [
                    "a": GraphQLField(type: GraphQLInt),
                    "b": GraphQLField(type: GraphQLInt)
                ]
            )),
            "z": GraphQLField(type: GraphQLInt)
        ],
        interfaces: [interface],
        isTypeOf: nil
    )
    
    let y = try! GraphQLObjectType(
        name: "Y",
        description: nil,
        fields: [
            "y": GraphQLField(type: GraphQLInt),
            "z": GraphQLField(type: GraphQLInt)
        ],
        interfaces: [interface],
        isTypeOf: nil
    )
    
    return try! GraphQLSchema(
        query: try! GraphQLObjectType(
            name: "Query",
            fields: [
                "iface": GraphQLField(type: interface)
            ]
        ),
        types: [x, y]
    )
}()

let multipleFragmentsSchema = try! GraphQLSchema(
    query: try! GraphQLObjectType(
        name: "Query",
        fields: [
            "a": GraphQLField(type: try! GraphQLObjectType(
                name: "A",
                fields: [
                    "b1": GraphQLField(type: GraphQLInt),
                    "b2": GraphQLField(type: GraphQLInt)
                ]
            ))
        ]
    )
)

var nestedObjectsOnInterfaceSchema: GraphQLSchema = {
    let dType = try! GraphQLObjectType(
        name: "D",
        fields: [
            "d1": GraphQLField(type: GraphQLInt),
            "d2": GraphQLField(type: GraphQLInt)
        ]
    )
    let interfaceType2 = try! GraphQLInterfaceType(
        name: "Iface2",
        fields: ["d": GraphQLField(type: dType)]
    )
    let bType = try! GraphQLObjectType(
        name: "B",
        fields: [
            "b1": GraphQLField(type: GraphQLInt),
            "b2": GraphQLField(type: GraphQLInt),
            "b3": GraphQLField(type: GraphQLList(
                GraphQLObjectType(
                    name: "C",
                    fields: [
                        "c1": GraphQLField(type: GraphQLInt),
                        "c2": GraphQLField(type: GraphQLInt)
                    ]
                )
            )),
            "b4": GraphQLField(type: interfaceType2)
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
    let implType2 = try! GraphQLObjectType(
        name: "Impl2",
        fields: [
            "d": GraphQLField(type: dType)
        ],
        interfaces: [interfaceType2]
    )
    let queryType = try! GraphQLObjectType(
        name: "Query",
        fields: [
            "a": GraphQLField(type: interfaceType)
        ]
    )
    return try! GraphQLSchema(
        query: queryType,
        types: [implType, implType2]
    )
}()
