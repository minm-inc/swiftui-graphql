//let query = """
//{
//    o { a }
//    ... on X {
//        o { b }
//    }
//    ... on Y {
//        o { c }
//    }
//}
//"""
//
//o will always be present, because o needs to be the same type on X and Y
//
//let query2 = """
//{
//    ... on User {
//        name # string
//    }
//    ... on Artist {
//        name # bool
//    }
//}
//"""
//// This is possible! da fuq happens here?
//
///*
// When storing selections, there are two lemmas:
// 2) Conditional fields can share the same key as other conditional keys, and they can be of different types
// */
//
//let query3 = """
//{
//    ... on LibraryItem {
//        artist { url }
//        ... on Track {
//            artist { name }
//        }
//        ... on Album {
//            artist { picture }
//        }
//    }
//}
//"""
//
//let x = ObjectDecl.polymorphic(
//    fields: ["artist":]
//)
//
//ResolvedSelection(fields: [
//    "artist": .conditional(
//])
//]

//import Foundation
//import SwiftUIGraphQL
//struct AnonymousQuery: Queryable, Codable {
//  let hasArtist: HasArtist
//  enum HasArtist: Codable {
//      case track(Track)
//      case album(Album)
//      case __other(__Other)
//      struct Track: Codable, Cacheable {
//          let artist: Artist
//          struct Artist: Codable, Cacheable {
//              let name: String
//              let id: ID
//              var __typename: String = "Artist"
//              let url: URL
//              fileprivate func convert() -> AnonymousQuery.HasArtist.Artist {
//                  AnonymousQuery.HasArtist.Artist(url: url, id: id, __typename: __typename)
//              }
//          }
//          let id: ID
//          var __typename: String = "Track"
//      }
//      struct Album: Codable, Cacheable {
//          let artist: Artist
//          struct Artist: Codable, Cacheable {
//              let pictureUrl: URL
//              let id: ID
//              var __typename: String = "Artist"
//              let url: URL
//              fileprivate func convert() -> AnonymousQuery.HasArtist.Artist {
//                  AnonymousQuery.HasArtist.Artist(url: url, id: id, __typename: __typename)
//              }
//          }
//          let id: ID
//          var __typename: String = "Album"
//      }
//      var artist: Artist {
//          switch self {
//          case .track(let track):
//              return track.artist.convert()
//          case .album(let album):
//              return album.artist.convert()
//          case .__other(let __other):
//              return __other.artist
//          }
//      }
//      struct Artist: Codable, Cacheable {
//          let url: URL
//          let id: ID
//          var __typename: String = "Artist"
//      }
//      struct __Other: Codable {
//          let artist: Artist
//      }
//      init(from decoder: Decoder) throws {
//          let container = try decoder.container(keyedBy: TypenameCodingKeys.self)
//          let typename = try container.decode(String.self, forKey: .__typename)
//          switch typename {
//          case "Track":
//              self = .track(try Track(from: decoder))
//          case "Album":
//              self = .album(try Album(from: decoder))
//          default:
//              self = .__other(try __Other(from: decoder))
//          }
//      }
//      func encode(to encoder: Encoder) throws {
//          switch self {
//          case .track(let track):
//              try track.encode(to: encoder)
//          case .album(let album):
//              try album.encode(to: encoder)
//          case .__other(let __other):
//              try __other.encode(to: encoder)
//          }
//      }
//  }
//  static let query = """
//{
//hasArtist {
//artist {
//url
//id
//__typename
//}
//... on Track {
//artist {
//name
//id
//__typename
//}
//id
//__typename
//}
//... on Album {
//artist {
//pictureUrl
//id
//__typename
//}
//id
//__typename
//}
//}
//}
//
//"""
