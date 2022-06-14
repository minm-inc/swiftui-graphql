//
//  File.swift
//  
//
//  Created by Luke Lau on 09/02/2022.
//

import Foundation
@testable import GraphQL

func readQuerySource(path: String) -> String {
    let inputUrl = Bundle.module.url(forResource: path, withExtension: "graphql")!
    return String(data: try! Data(contentsOf: inputUrl), encoding: .utf8)!
}
