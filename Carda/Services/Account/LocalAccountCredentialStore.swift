//
//  LocalAccountCredentialStore.swift
//  Cardi
//

import Foundation
import Security

enum LocalAccountCredentialStoreError: LocalizedError, Equatable {
    case invalidPhoneNumber
    case emptyPassword
    case credentialAlreadyExists
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidPhoneNumber:
            "请输入有效的手机号。"
        case .emptyPassword:
            "密码不能为空。"
        case .credentialAlreadyExists:
            "该手机号已注册。"
        case .keychainFailure:
            "无法访问本机账户凭据。"
        }
    }
}

struct LocalAccountCredentialStore {
    private let service: String

    init(
        service: String = "\(Bundle.main.bundleIdentifier ?? "Carda").local-account"
    ) {
        self.service = service
    }

    func register(phoneNumber: String, password: String) throws {
        let phoneNumber = try requiredPhoneNumber(phoneNumber)
        guard !password.isEmpty else {
            throw LocalAccountCredentialStoreError.emptyPassword
        }

        var query = baseQuery(for: phoneNumber)
        query[kSecValueData as String] = Data(password.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw LocalAccountCredentialStoreError.credentialAlreadyExists
        default:
            throw LocalAccountCredentialStoreError.keychainFailure(status)
        }
    }

    func authenticate(phoneNumber: String, password: String) throws -> Bool {
        let phoneNumber = try requiredPhoneNumber(phoneNumber)
        guard !password.isEmpty else { return false }

        var query = baseQuery(for: phoneNumber)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let storedData = result as? Data else {
                throw LocalAccountCredentialStoreError.keychainFailure(errSecDecode)
            }
            return storedData == Data(password.utf8)
        case errSecItemNotFound:
            return false
        default:
            throw LocalAccountCredentialStoreError.keychainFailure(status)
        }
    }

    func credentialExists(for phoneNumber: String) throws -> Bool {
        let phoneNumber = try requiredPhoneNumber(phoneNumber)
        var query = baseQuery(for: phoneNumber)
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw LocalAccountCredentialStoreError.keychainFailure(status)
        }
    }

    func removeCredential(for phoneNumber: String) throws {
        let phoneNumber = try requiredPhoneNumber(phoneNumber)
        let status = SecItemDelete(baseQuery(for: phoneNumber) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LocalAccountCredentialStoreError.keychainFailure(status)
        }
    }

    func removeAllCredentials() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LocalAccountCredentialStoreError.keychainFailure(status)
        }
    }

    private func baseQuery(for phoneNumber: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: phoneNumber
        ]
    }

    private func requiredPhoneNumber(_ rawValue: String) throws -> String {
        guard let phoneNumber = LocalAccountCardStore.canonicalPhoneNumber(rawValue) else {
            throw LocalAccountCredentialStoreError.invalidPhoneNumber
        }
        return phoneNumber
    }
}
