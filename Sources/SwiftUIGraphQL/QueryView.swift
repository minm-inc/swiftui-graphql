//
//  QueryView.swift
//  
//
//  Created by Luke Lau on 26/06/2021.
//

import SwiftUI

//public struct QueryV<T: Queryable, Content: View>: View {
//    @Environment(\.graphqlClient) var graphqlClient: GraphQLClient!
//    @ObservedObject var query: Query<T>
//    
//    let closure: (Query<T>.State) -> Content
//    
//    public init(variables: T.Variables, closure: @escaping (QueryBlah<T>.State) -> Content) {
//        self.closure = closure
//        query = Query(graphqlClient: graphqlClient, variables: variables)
//    }
//    
//    public var body: some View {
//        closure(query.state)
//    }
//}
