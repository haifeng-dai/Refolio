import Foundation

struct CrossrefWorkEnvelope: Decodable {
    let message: CrossrefWorkMessage
}

struct CrossrefWorkMessage: Decodable {
    let DOI: String?
    let title: [String]?
    let author: [CrossrefAuthor]?
    let containerTitle: [String]?
    let type: String?
    let issued: CrossrefDate?
    let volume: String?
    let issue: String?
    let page: String?
    let URL: String?
    let abstract: String?

    enum CodingKeys: String, CodingKey {
        case DOI, title, author, type, issued, volume, issue, page, URL, abstract
        case containerTitle = "container-title"
    }
}

struct CrossrefAuthor: Decodable {
    let given: String?
    let family: String?
    let name: String?
}

struct CrossrefDate: Decodable {
    let dateParts: [[Int]]?

    enum CodingKeys: String, CodingKey {
        case dateParts = "date-parts"
    }
}
