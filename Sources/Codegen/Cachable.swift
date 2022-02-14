//
//  Cachable.swift
//  
//
//  Created by Luke Lau on 10/12/2021.
//

import GraphQL
import Foundation

/**
 In order to cache objects that are returned from any queries, we need to know the `id` and `__typename` fields to any object that has an `id`.
 `attachCachableFields` appends these fields to any selection sets for any object that contains these fields
 */
public func attachCachableFields(schema: GraphQLSchema, document: Document) -> Document {

    
    let typeInfo = TypeInfo(schema: schema)
    
    struct AttachCachableFieldsVisitor: Visitor {
        let typeInfo: TypeInfo
        func enter(selectionSet: SelectionSet, key: AnyKeyPath?, parent: VisitorParent?, ancestors: [VisitorParent]) -> VisitResult<SelectionSet> {
            guard let type = typeInfo.type, isCachable(type: type) else {
                return .continue
            }
            func makeFieldIfNeeded(named: String) -> [Selection] {
                let exists = selectionSet.selections.contains { selection in
                    if case let .field(field) = selection {
                        return field.name.value == named
                    } else {
                        return false
                    }
                }
                if !exists {
                    return [.field(Field(name: Name(value: named)))]
                } else {
                    return []
                }
            }
            return .node(
                SelectionSet(
                    loc: selectionSet.loc,
                    selections: selectionSet.selections +
                    makeFieldIfNeeded(named: "id") + makeFieldIfNeeded(named: "__typename")
                )
            )
        }
    }
    
    let visitor = VisitorWithTypeInfo(visitor: AttachCachableFieldsVisitor(typeInfo: typeInfo), typeInfo: typeInfo)
    
    return visit(root: document, visitor: visitor)
}


func isCachable(type: GraphQLType) -> Bool {
    let fields: GraphQLFieldDefinitionMap
    if let type = type as? GraphQLObjectType {
        fields = type.fields
    } else if let type = type as? GraphQLInterfaceType {
        fields = type.fields
    } else if let type = type as? GraphQLList {
        return isCachable(type: type.ofType)
    } else if let type = type as? GraphQLNonNull {
        return isCachable(type: type.ofType)
    } else {
        return false
    }
    if let idField = fields["id"],
       getNamedType(type: idField.type)?.name == GraphQLID.name {
        return true
    }
    return false
}
