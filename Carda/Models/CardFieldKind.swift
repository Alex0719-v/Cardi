//
//  CardFieldKind.swift
//  Carda
//

import Foundation

enum CardOwnerKind: String, CaseIterable, Codable, Identifiable {
    case mine
    case received

    var id: String { rawValue }
}

enum CardFieldKind: String, CaseIterable, Codable, Identifiable {
    case phone
    case email
    case address
    case link
    case companyLogo

    static let allCases: [CardFieldKind] = [.phone, .email, .address, .link]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phone:
            "手机"
        case .email:
            "邮箱"
        case .address:
            "地址"
        case .link:
            "链接"
        case .companyLogo:
            "公司logo"
        }
    }

    var isRenderedInfoField: Bool {
        self != .companyLogo
    }
}
