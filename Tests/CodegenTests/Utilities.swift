//
//  File.swift
//  
//
//  Created by Luke Lau on 09/02/2022.
//

import Foundation
@testable import GraphQL

func getFirstOperationAndFragments(source: String) -> (OperationDefinition, [FragmentDefinition]) {
    let document = try! GraphQL.parse(source: source)
    
    let fragments: [FragmentDefinition] = document.definitions.compactMap {
        if case let .executableDefinition(.fragment(fragmentDef)) = $0 {
            return fragmentDef
        } else {
            return nil
        }
    }
    
    guard let opDef = document.definitions.compactMap({ def -> OperationDefinition? in
        if case let .executableDefinition(.operation(opDef)) = def {
            return opDef
        } else {
            return nil
        }
    }).first else {
        fatalError("Couldn't find operation definition")
    }
    
    return (opDef, fragments)
}

func getFirstQueryFieldAndFragments(source: String) -> (Field, [FragmentDefinition]) {
    let (opDef, fragments) = getFirstOperationAndFragments(source: source)
    
    guard case let .field(field) = opDef.selectionSet.selections.first else {
        fatalError("Couldn't find field")
    }
    
    return (field, fragments)
}

func readQuerySource(path: String) -> String {
    let inputUrl = Bundle.module.url(forResource: path, withExtension: "graphql")!
    return String(data: try! Data(contentsOf: inputUrl), encoding: .utf8)!
}
