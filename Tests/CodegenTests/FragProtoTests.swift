import XCTest
@testable import Codegen
import SwiftUIGraphQL
import GraphQL

class FragProtoTests: XCTestCase {
    func testGeneratesWhereClauses() throws {
        let fooType = try GraphQLObjectType(name: "Foo", fields: [
            "bar": GraphQLField(type: GraphQLInt),
            "baz": GraphQLField(type: GraphQLInt)
        ])
        let queryType = try GraphQLObjectType(name: "Query", fields: [
            "foo": GraphQLField(type: fooType)
        ])
        let schema = try GraphQLSchema(query: queryType)
        let mergedSelection = MergedObject(
            unconditional: .init(fields: [
                "foo": .init(
                    name: "foo",
                    arguments: [:],
                    type: fooType,
                    nested: MergedObject(
                        unconditional: .init(fields: [
                            "bar": .init(
                                name: "bar",
                                arguments: [:],
                                type: GraphQLInt,
                                nested: nil
                            )
                        ]),
                        conditional: [:],
                        type: fooType,
                        fragmentConformances: [:]
                    )
                )
            ]),
            conditional: [:],
            type: queryType,
            fragmentConformances: ["StuffOnFoo": .unconditional]
        )
        let stuffOnFooObj = MergedObject(
            unconditional: .init(fields: [
                "foo": .init(
                    name: "foo",
                    arguments: [:],
                    type: fooType,
                    nested: MergedObject(
                        unconditional: .init(fields: [
                            "baz": .init(
                                name: "baz",
                                arguments: [:],
                                type: GraphQLInt,
                                nested: nil
                            )
                        ]),
                        conditional: [:],
                        type: fooType,
                        fragmentConformances: [:]
                    )
                )
            ]),
            conditional: [:],
            type: queryType,
            fragmentConformances: [:]
        )
        let fragmentObjMap = ["StuffOnFoo": stuffOnFooObj]
        let fragProtoGenerator = FragProtoGenerator(fragmentObjectMap: fragmentObjMap,
                                                    fragmentConformanceGraph: ProtocolConformance.buildConformanceGraph(fragmentObjects: fragmentObjMap, schema: schema))
        let fragProto = fragProtoGenerator.gen(fragProtoFor: mergedSelection,
                                               following: [],
                                               currentPath: FragmentProtocolPath(fragmentName: "StuffOnFoo",
                                                                                 fragmentObject: stuffOnFooObj))
        guard case .proto(let proto) = fragProto else {
            XCTFail()
            return
        }
        XCTAssertEqual(proto.conformance.name, "StuffOnFooFragment")
        guard case .whereClause(let nestedFragProto) = proto.fields["foo"] else {
            XCTFail()
            return
        }
        guard case .proto = nestedFragProto else {
            XCTFail()
            return
        }
    }
}
