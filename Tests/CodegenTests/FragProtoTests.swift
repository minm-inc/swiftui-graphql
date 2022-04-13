import XCTest
@testable import Codegen

class FragProtoTests: XCTestCase {
    func testGeneratesWhereClauses() throws {
        let mergedSelection = MergedSelection.Object(
            selections: [
                .field(key: "foo", .init(
                    name: "foo",
                    arguments: [:],
                    type: .named("Foo"),
                    nested: MergedSelection.Object(
                        selections: [
                            .field(key: "bar", .init(
                                name: "bar",
                                arguments: [:],
                                type: .named("Int"),
                                nested: nil
                            ))
                        ],
                        fragmentConformances: []
                    )
                ))
            ],
            fragmentConformances: ["StuffOnFoo"]
        )
        let fragmentObjMap = [
            "StuffOnFoo": MergedSelection.Object(
                selections: [
                    .field(key: "foo", .init(
                        name: "foo",
                        arguments: [:],
                        type: .named("Foo"),
                        nested: MergedSelection.Object(
                            selections: [
                                .field(key: "baz", .init(
                                    name: "baz",
                                    arguments: [:],
                                    type: .named("Int"),
                                    nested: nil
                                ))
                            ],
                            fragmentConformances: []
                        )
                    ))
                ],
                fragmentConformances: []
            )
        ]
        let fragProto = gen(fragProtoFor: mergedSelection, following: [], fragmentObjMap: fragmentObjMap)
        guard case .monomorphic(let fields, let conforms) = fragProto else {
            XCTFail()
            return
        }
        XCTAssertEqual(conforms, [FragmentPath(fragmentName: "StuffOnFoo")])
        guard case .whereClause(let nestedFragProto) = fields["foo"] else {
            XCTFail()
            return
        }
        guard case .monomorphic(let fields, _) = nestedFragProto else {
            XCTFail()
            return
        }
    }
}
