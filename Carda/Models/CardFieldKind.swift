//
//  CardFieldKind.swift
//  Cardi
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

enum PhoneNumberFormatter {
    static func format(_ value: String) -> String {
        let digits = digits(in: value)
        guard digits.count > 3 else { return digits }

        let firstBreak = digits.index(digits.startIndex, offsetBy: 3)
        let firstGroup = digits[..<firstBreak]
        let remaining = digits[firstBreak...]
        guard remaining.count > 4 else {
            return "\(firstGroup) \(remaining)"
        }

        let secondBreak = remaining.index(remaining.startIndex, offsetBy: 4)
        return "\(firstGroup) \(remaining[..<secondBreak]) \(remaining[secondBreak...])"
    }

    static func digits(in value: String) -> String {
        String(value.filter(\.isNumber))
    }
}
