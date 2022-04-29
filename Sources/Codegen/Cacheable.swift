//
//  Cacheable.swift
//  
//
//  Created by Luke Lau on 10/12/2021.
//

import GraphQL
import Foundation

/**
 In order to cache objects that are returned from any queries, we need to know the `id` and `__typename` fields to any object that has an `id`.
 `attachCacheableFields` appends these fields to any selection sets for any object that contains these fields
 */
public func attachCacheableFields(schema: GraphQLSchema, document: Document) -> Document {
    let typeInfo = TypeInfo(schema: schema)
    
    struct AttachCacheableFieldsVisitor: Visitor {
        let typeInfo: TypeInfo
        func enter(selectionSet: SelectionSet, key: AnyKeyPath?, parent: VisitorParent?, ancestors: [VisitorParent]) -> VisitResult<SelectionSet> {
            guard let type = typeInfo.type else {
                return .continue
            }
            
            var newSelections = selectionSet.selections
            
            func appendFieldIfNeeded(named: String) {
                let exists = newSelections.contains { selection in
                    if case let .field(field) = selection {
                        return field.name.value == named
                    } else {
                        return false
                    }
                }
                if !exists {
                    newSelections.append(.field(Field(name: Name(value: named))))
                }
            }
            
            if isCacheable(type: type) {
                appendFieldIfNeeded(named: "id")
                appendFieldIfNeeded(named: "__typename")
            }
            // These will be generated as enums so we need to be able to discriminate between them
            if type is GraphQLUnionType || type is GraphQLInterfaceType {
                appendFieldIfNeeded(named: "__typename")
            }
            
            return .node(
                SelectionSet(
                    loc: selectionSet.loc,
                    selections: newSelections
                )
            )
        }
    }
    
    let visitor = VisitorWithTypeInfo(visitor: AttachCacheableFieldsVisitor(typeInfo: typeInfo), typeInfo: typeInfo)
    
    return visit(root: document, visitor: visitor)
}


func isCacheable(type: GraphQLType) -> Bool {
    let fields: GraphQLFieldDefinitionMap
    if let type = type as? GraphQLObjectType {
        fields = type.fields
    } else if let type = type as? GraphQLInterfaceType {
        fields = type.fields
    } else if let type = type as? GraphQLList {
        return isCacheable(type: type.ofType)
    } else if let type = type as? GraphQLNonNull {
        return isCacheable(type: type.ofType)
    } else {
        return false
    }
    if let idField = fields["id"],
       getNamedType(type: idField.type)?.name == GraphQLID.name {
        return true
    }
    return false
}
